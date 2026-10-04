import Foundation

/// Hermes gateway API server (`API_SERVER_KEY`, port 8642).
nonisolated final class GatewayBackend: AgentBackend, @unchecked Sendable {
    let client: HermesClient
    private let state = Locked(AgentCapabilities.none)

    init(client: HermesClient) {
        self.client = client
    }

    func probe() async throws -> BackendInfo {
        let health = try await client.health()
        let capabilities = try await client.capabilities()
        state.set(capabilities)
        guard capabilities.sessions else {
            throw APIError.unsupported("the session API (update Hermes, or connect it as an OpenAI-compatible endpoint)")
        }
        var features = BackendFeatures()
        features.serverSessions = true
        features.rename = true
        features.pin = true
        features.delete = true
        features.fork = capabilities.fork
        features.approvals = capabilities.approvals
        features.interrupt = true
        features.steer = capabilities.steer
        features.images = true
        features.modelSwitch = capabilities.modelLock
        features.reasoningControl = true
        features.skills = capabilities.skills
        features.toolsets = true
        features.jobs = true
        let platforms = health.platforms.keys.sorted().joined(separator: ", ")
        return BackendInfo(
            name: capabilities.model ?? health.platform ?? "Hermes",
            version: health.version,
            model: capabilities.model,
            detail: platforms.isEmpty ? nil : "Gateway platforms: \(platforms)",
            features: features
        )
    }

    func sessions() async throws -> [AgentSession] {
        var all: [AgentSession] = []
        var offset = 0
        while true {
            let page = try await client.sessions(limit: 200, offset: offset)
            all += page.sessions
            offset += page.sessions.count
            if !page.hasMore || page.sessions.isEmpty || all.count >= 1000 { break }
        }
        return all
    }

    func newSession(options: TurnOptions) async throws -> OpenedSession {
        let session = try await client.createSession(model: options.model, provider: options.provider)
        return OpenedSession(id: session.id, storedID: session.id, title: session.title, messages: [], model: session.model)
    }

    func open(sessionID: String) async throws -> OpenedSession {
        async let meta = try? client.session(id: sessionID)
        let (resolved, messages) = try await client.messages(sessionID: sessionID)
        let session = await meta
        return OpenedSession(id: resolved, storedID: sessionID, title: session?.title, messages: messages, model: session?.model)
    }

    func delete(sessionID: String) async throws {
        try await client.deleteSession(id: sessionID)
    }

    func rename(sessionID: String, title: String) async throws {
        try await client.updateSession(id: sessionID, title: title)
    }

    func setPinned(sessionID: String, pinned: Bool) async throws {
        try await client.updateSession(id: sessionID, pinned: pinned)
    }

    func fork(sessionID: String) async throws -> OpenedSession {
        let forked = try await client.forkSession(id: sessionID)
        return try await open(sessionID: forked.id)
    }

    func send(_ turn: TurnRequest, in session: OpenedSession) -> AsyncThrowingStream<AgentEvent, Error> {
        do {
            let content = HermesClient.messageContent(text: turn.text, imageDataURLs: turn.images)
            let upstream = try client.streamTurn(sessionID: session.id, message: content, options: turn.options)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    var text = ""
                    do {
                        for try await event in upstream {
                            switch event {
                            case .textDelta(let delta):
                                text += delta
                            case .reasoningDelta(let preview):
                                // The gateway re-sends the reply as a reasoning
                                // preview when the model gave no reasoning.
                                let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(trimmed) { continue }
                            default:
                                break
                            }
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    func interrupt(session: OpenedSession, runID: String?) async throws {
        guard let runID else { return }
        try await client.stop(runID: runID)
    }

    func steer(session: OpenedSession, runID: String?, text: String) async throws {
        guard let runID else { throw APIError.unsupported("steering before the run starts") }
        try await client.steer(runID: runID, text: text)
    }

    func approve(_ request: ApprovalRequest, choice: ApprovalChoice, session: OpenedSession) async throws {
        try await client.respond(runID: request.runID, choice: choice, requestID: request.requestID)
    }

    func models(session: OpenedSession?) async throws -> [ModelOption] {
        if state.get().modelOptions, let options = try? await client.modelOptions(), !options.isEmpty {
            return options
        }
        return try await client.models()
    }

    func setModel(_ model: ModelOption, session: OpenedSession) async throws {
        try await client.lockModel(sessionID: session.id, model: model.id, provider: model.provider)
    }

    func skills() async throws -> [AgentSkill] { try await client.skills() }
    func toolsets() async throws -> [AgentToolset] { try await client.toolsets() }
    func jobs() async throws -> [AgentJob] { try await client.jobs() }

    func createJob(name: String, schedule: String, prompt: String) async throws {
        _ = try await client.createJob(name: name, schedule: schedule, prompt: prompt)
    }

    func job(_ id: String, _ action: JobAction) async throws {
        try await client.setJob(id: id, action: action)
    }
}

/// A tiny lock-protected box for state shared across concurrency domains.
nonisolated final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }

    @discardableResult
    func update<R>(_ body: (inout Value) -> R) -> R { lock.withLock { body(&value) } }
}
