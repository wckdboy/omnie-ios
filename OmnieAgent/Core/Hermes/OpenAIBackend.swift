import Foundation

/// Any OpenAI-compatible `/v1/chat/completions` endpoint: a Hermes gateway
/// used as a plain model, or another agent server. History lives on the
/// device; when the server is Hermes, `X-Hermes-Session-Id` keeps its own
/// memory in step and its tool-progress events still show.
nonisolated final class OpenAIBackend: AgentBackend, @unchecked Sendable {
    let http: HTTPClient
    let defaultModel: String?
    let store: LocalTranscriptStore
    private let running = Locked([String: Task<Void, Never>]())

    init(baseURL: URL, apiKey: String, model: String?, store: LocalTranscriptStore) {
        var headers = ["Accept": "application/json"]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        var url = baseURL
        // Accept both "https://host" and "https://host/v1".
        if url.path.hasSuffix("/v1") || url.path.hasSuffix("/v1/") {
            url = url.deletingLastPathComponent()
        }
        http = HTTPClient(baseURL: url, headers: headers)
        defaultModel = (model?.isEmpty ?? true) ? nil : model
        self.store = store
    }

    func probe() async throws -> BackendInfo {
        let models = try await self.models(session: nil)
        var features = BackendFeatures()
        features.delete = true
        features.rename = true
        features.pin = true
        features.images = true
        features.modelSwitch = true
        features.reasoningControl = true
        features.approvals = true
        features.interrupt = true
        let model = defaultModel ?? models.first?.id
        return BackendInfo(name: model ?? "Endpoint", version: nil, model: model,
                           detail: "\(models.count) model\(models.count == 1 ? "" : "s") available", features: features)
    }

    func sessions() async throws -> [AgentSession] {
        store.list()
    }

    func newSession(options: TurnOptions) async throws -> OpenedSession {
        let id = "omnie-" + UUID().uuidString.lowercased()
        store.save(LocalTranscript(id: id, title: nil, model: options.model ?? defaultModel, messages: [], updatedAt: Date(), pinned: false))
        return OpenedSession(id: id, storedID: id, title: nil, messages: [], model: options.model ?? defaultModel)
    }

    func open(sessionID: String) async throws -> OpenedSession {
        guard let transcript = store.load(sessionID) else {
            throw APIError.http(status: 404, code: "session_not_found", message: "That conversation is no longer on this iPhone.")
        }
        return OpenedSession(id: transcript.id, storedID: transcript.id, title: transcript.title,
                             messages: transcript.storedMessages, model: transcript.model)
    }

    func delete(sessionID: String) async throws { store.delete(sessionID) }

    func rename(sessionID: String, title: String) async throws {
        store.update(sessionID) { $0.title = title }
    }

    func setPinned(sessionID: String, pinned: Bool) async throws {
        store.update(sessionID) { $0.pinned = pinned }
    }

    func setModel(_ model: ModelOption, session: OpenedSession) async throws {
        store.update(session.id) { $0.model = model.id }
    }

    func send(_ turn: TurnRequest, in session: OpenedSession) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(turn, session: session, continuation: continuation) }
            self.running.update { $0[session.id] = task }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ turn: TurnRequest, session: OpenedSession, continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation) async {
        var transcript = store.load(session.id)
            ?? LocalTranscript(id: session.id, title: nil, model: session.model, messages: [], updatedAt: Date(), pinned: false)
        let userContent = HermesClient.messageContent(text: turn.text, imageDataURLs: turn.images)
        transcript.messages.append(LocalMessage(role: "user", content: userContent))
        if transcript.title == nil {
            transcript.title = String(turn.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        }
        store.save(transcript)

        var messages: [JSONValue] = []
        if let instructions = turn.options.instructions, !instructions.isEmpty {
            messages.append(["role": "system", "content": .string(instructions)])
        }
        messages += transcript.messages.map { ["role": .string($0.role), "content": $0.content] }

        var body: [String: JSONValue] = ["messages": .array(messages), "stream": true,
                                         "stream_options": ["include_usage": true]]
        let model = turn.options.model ?? transcript.model ?? defaultModel
        if let model { body["model"] = .string(model) }
        if let options = turn.options.modelOptions { body["model_options"] = options }
        if turn.options.reasoning != .auto, turn.options.reasoning != .none {
            body["reasoning_effort"] = .string(turn.options.reasoning == .xhigh ? "high" : turn.options.reasoning.rawValue)
        }

        var state = ChatCompletionState()
        var reply = ""
        var failure: String?
        do {
            let request = try http.request("/v1/chat/completions", method: "POST", body: .object(body), extraHeaders: [
                "Accept": "text/event-stream",
                "X-Hermes-Session-Id": session.id,
            ])
            continuation.yield(.runStarted(runID: nil, sessionID: nil))
            for try await sse in http.events(request) {
                for event in HermesEventDecoder.chatCompletions(sse, state: &state) {
                    switch event {
                    case .textDelta(let text): reply += text
                    case .failed(let message): failure = message
                    case .approval:
                        // The completion id doubles as the run id for approvals.
                        break
                    default: break
                    }
                    continuation.yield(event)
                }
            }
        } catch {
            running.update { $0[session.id] = nil }
            if !reply.isEmpty {
                transcript.messages.append(LocalMessage(role: "assistant", content: .string(reply)))
                store.save(transcript)
            }
            if Task.isCancelled {
                continuation.yield(.completed(finalText: reply, interrupted: true))
                continuation.finish()
            } else {
                continuation.finish(throwing: error)
            }
            return
        }
        if !reply.isEmpty {
            transcript.messages.append(LocalMessage(role: "assistant", content: .string(reply)))
        }
        transcript.updatedAt = Date()
        store.save(transcript)
        running.update { $0[session.id] = nil }
        if let failure, reply.isEmpty {
            continuation.yield(.failed(failure))
        } else {
            continuation.yield(.completed(finalText: reply, interrupted: Task.isCancelled || state.finishReason == "length"))
        }
        continuation.finish()
    }

    /// Dropping the stream is the interrupt; Hermes also stops its agent
    /// when the client disconnects.
    func interrupt(session: OpenedSession, runID: String?) async throws {
        running.update { $0.removeValue(forKey: session.id) }?.cancel()
    }

    func approve(_ request: ApprovalRequest, choice: ApprovalChoice, session: OpenedSession) async throws {
        var body: [String: JSONValue] = ["choice": .string(choice.rawValue)]
        if let requestID = request.requestID { body["request_id"] = .string(requestID) }
        _ = try await http.json("/v1/runs/\(HermesClient.escape(request.runID))/approval", method: "POST", body: .object(body))
    }

    func models(session: OpenedSession?) async throws -> [ModelOption] {
        let json = try await http.json("/v1/models")
        let list = json["data"]?.array ?? json["models"]?.array ?? []
        let models = list.compactMap { item -> ModelOption? in
            guard let id = item["id"]?.string ?? item.string else { return nil }
            return ModelOption(id: id, provider: item["owned_by"]?.string, label: id, isDefault: id == defaultModel)
        }
        return models.sorted { ($0.isDefault ? 0 : 1, $0.id) < ($1.isDefault ? 0 : 1, $1.id) }
    }
}

// MARK: - On-device transcripts

nonisolated struct LocalMessage: Codable, Sendable, Hashable {
    var role: String
    var content: JSONValue
    var date = Date()
}

nonisolated struct LocalTranscript: Codable, Sendable, Hashable {
    var id: String
    var title: String?
    var model: String?
    var messages: [LocalMessage]
    var updatedAt: Date
    var pinned: Bool

    var storedMessages: [StoredMessage] {
        messages.enumerated().compactMap { index, message in
            StoredMessage(json: ["role": .string(message.role), "content": message.content, "id": .string("\(id)-\(index)")], index: index)
        }
    }

    var session: AgentSession {
        var session = AgentSession(id: id, title: title)
        session.lastActive = updatedAt
        session.model = model
        session.messageCount = messages.count
        session.pinned = pinned
        session.preview = messages.last.map { StoredMessage.text(from: $0.content) }
        return session
    }
}

/// One JSON file per conversation under Application Support, scoped per
/// connection so endpoints never see each other's history.
nonisolated final class LocalTranscriptStore: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()

    init(scope: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("Transcripts").appendingPathComponent(scope)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(_ id: String) -> URL {
        directory.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    func list() -> [AgentSession] {
        lock.withLock {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return files.compactMap { url -> AgentSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return (try? Self.decoder.decode(LocalTranscript.self, from: data))?.session
            }.sorted { $0.sortDate > $1.sortDate }
        }
    }

    func load(_ id: String) -> LocalTranscript? {
        lock.withLock {
            guard let data = try? Data(contentsOf: file(id)) else { return nil }
            return try? Self.decoder.decode(LocalTranscript.self, from: data)
        }
    }

    func save(_ transcript: LocalTranscript) {
        lock.withLock {
            guard let data = try? Self.encoder.encode(transcript) else { return }
            try? data.write(to: file(transcript.id), options: [.atomic])
        }
    }

    func update(_ id: String, _ change: (inout LocalTranscript) -> Void) {
        guard var transcript = load(id) else { return }
        change(&transcript)
        save(transcript)
    }

    func delete(_ id: String) {
        _ = lock.withLock { try? FileManager.default.removeItem(at: file(id)) }
    }

    func deleteAll() {
        _ = lock.withLock { try? FileManager.default.removeItem(at: directory) }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
