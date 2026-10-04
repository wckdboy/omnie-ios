import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for a Hermes gateway's API server (`hermes gateway` with
/// `API_SERVER_KEY` set; default port 8642). Covers sessions, streaming
/// turns, approvals, steer/stop, models, skills, toolsets, jobs and health.
///
/// Every route is mounted under `/p/{profile}` too, so one gateway can
/// serve several profiles; `profile` selects one.
nonisolated struct HermesClient: Sendable {
    let http: HTTPClient
    /// Stable memory scope for this device (`X-Hermes-Session-Key`).
    var sessionKey: String?

    init(baseURL: URL, apiKey: String, profile: String? = nil, sessionKey: String? = nil) {
        var url = baseURL
        if let profile = profile?.trimmingCharacters(in: .whitespaces), !profile.isEmpty {
            url = baseURL.appendingPathComponent("p").appendingPathComponent(profile)
        }
        var headers = ["Accept": "application/json"]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        http = HTTPClient(baseURL: url, headers: headers)
        self.sessionKey = sessionKey
    }

    // MARK: Status

    func health() async throws -> AgentHealth {
        if let detailed = try? await http.json("/health/detailed") {
            return AgentHealth(json: detailed)
        }
        return AgentHealth(json: try await http.json("/health"))
    }

    func capabilities() async throws -> AgentCapabilities {
        do {
            return AgentCapabilities(json: try await http.json("/v1/capabilities"))
        } catch let error as APIError where error.status == 404 {
            return .none
        }
    }

    func models() async throws -> [ModelOption] {
        let json = try await http.json("/v1/models")
        let list = json["data"]?.array ?? []
        return list.enumerated().compactMap { index, item in
            guard let id = item["id"]?.string else { return nil }
            return ModelOption(id: id, provider: nil, label: id, isDefault: index == 0)
        }
    }

    /// The provider/model inventory the agent itself offers in `/model`.
    func modelOptions(refresh: Bool = false) async throws -> [ModelOption] {
        let json = try await http.json("/api/model/options", query: ["refresh": refresh ? "true" : nil])
        return Self.parseModelOptions(json)
    }

    static func parseModelOptions(_ json: JSONValue) -> [ModelOption] {
        var models: [ModelOption] = []
        let current = json["current"]?["model"]?.string ?? json["model"]?.string
        let providers = json["providers"]?.array ?? json["data"]?.array ?? []
        for provider in providers {
            let providerID = provider["id"]?.string ?? provider["slug"]?.string ?? provider["name"]?.string
            let entries = provider["models"]?.array ?? []
            for entry in entries {
                guard let id = entry.string ?? entry["id"]?.string ?? entry["model"]?.string else { continue }
                let label = entry["label"]?.string ?? entry["name"]?.string ?? id
                models.append(ModelOption(id: id, provider: providerID, label: label, isDefault: id == current))
            }
        }
        if models.isEmpty, let flat = json["models"]?.array {
            for entry in flat {
                guard let id = entry.string ?? entry["id"]?.string else { continue }
                models.append(ModelOption(id: id, provider: entry["provider"]?.string,
                                         label: entry["label"]?.string ?? id, isDefault: id == current))
            }
        }
        return models
    }

    func skills() async throws -> [AgentSkill] {
        (try await http.json("/v1/skills"))["data"]?.array?.compactMap(AgentSkill.init(json:)) ?? []
    }

    func toolsets() async throws -> [AgentToolset] {
        (try await http.json("/v1/toolsets"))["data"]?.array?.compactMap(AgentToolset.init(json:)) ?? []
    }

    // MARK: Sessions

    func sessions(limit: Int = 100, offset: Int = 0) async throws -> (sessions: [AgentSession], hasMore: Bool) {
        let json = try await http.json("/api/sessions", query: ["limit": String(limit), "offset": String(offset)])
        let items = json["data"]?.array ?? json["sessions"]?.array ?? []
        return (items.compactMap(AgentSession.init(json:)), json["has_more"]?.bool ?? false)
    }

    func createSession(title: String? = nil, model: String? = nil, provider: String? = nil) async throws -> AgentSession {
        var body: [String: JSONValue] = ["source": "api_server"]
        if let title { body["title"] = .string(title) }
        if let model { body["model"] = .string(model) }
        if let provider { body["provider"] = .string(provider) }
        let json = try await http.json("/api/sessions", method: "POST", body: .object(body))
        guard let session = AgentSession(json: json["session"] ?? json) else {
            throw APIError.decoding("new session")
        }
        return session
    }

    func session(id: String) async throws -> AgentSession {
        let json = try await http.json("/api/sessions/\(Self.escape(id))")
        guard let session = AgentSession(json: json["session"] ?? json) else { throw APIError.decoding("session") }
        return session
    }

    func updateSession(id: String, title: String? = nil, pinned: Bool? = nil, archived: Bool? = nil, unread: Bool? = nil) async throws {
        var body: [String: JSONValue] = [:]
        if let title { body["title"] = .string(title) }
        if let pinned { body["pinned"] = .bool(pinned) }
        if let archived { body["archived"] = .bool(archived) }
        if let unread { body["unread"] = .bool(unread) }
        _ = try await http.json("/api/sessions/\(Self.escape(id))", method: "PATCH", body: .object(body))
    }

    func deleteSession(id: String) async throws {
        _ = try await http.json("/api/sessions/\(Self.escape(id))", method: "DELETE")
    }

    func forkSession(id: String, title: String? = nil) async throws -> AgentSession {
        var body: [String: JSONValue] = [:]
        if let title { body["title"] = .string(title) }
        let json = try await http.json("/api/sessions/\(Self.escape(id))/fork", method: "POST", body: .object(body))
        guard let session = AgentSession(json: json["session"] ?? json) else { throw APIError.decoding("forked session") }
        return session
    }

    func lockModel(sessionID: String, model: String, provider: String?) async throws {
        var body: [String: JSONValue] = ["model": .string(model)]
        if let provider { body["provider"] = .string(provider) }
        _ = try await http.json("/api/sessions/\(Self.escape(sessionID))/model", method: "POST", body: .object(body))
    }

    /// Latest messages first-to-last, with the server-resolved session id
    /// (ids rotate when the agent compresses context).
    func messages(sessionID: String, limit: Int = 500) async throws -> (sessionID: String, messages: [StoredMessage]) {
        let json = try await http.json(
            "/api/sessions/\(Self.escape(sessionID))/messages",
            query: ["limit": String(limit), "order": "latest"]
        )
        let rows = json["data"]?.array ?? json["messages"]?.array ?? []
        var messages = rows.enumerated().compactMap { StoredMessage(json: $1, index: $0) }
        // `order=latest` pages from the end; keep chronological order.
        if messages.count > 1,
           let first = messages.first?.timestamp, let last = messages.last?.timestamp, first > last {
            messages.reverse()
        }
        return (json["session_id"]?.string ?? sessionID, messages)
    }

    // MARK: Turns

    /// Streams one turn of `sessionID`. History lives server-side. Cancelling
    /// the consuming task drops the connection, which interrupts the agent.
    func streamTurn(
        sessionID: String,
        message: JSONValue,
        options: TurnOptions = TurnOptions()
    ) throws -> AsyncThrowingStream<AgentEvent, Error> {
        var body: [String: JSONValue] = ["message": message]
        if let model = options.model { body["model"] = .string(model) }
        if let provider = options.provider { body["provider"] = .string(provider) }
        if let modelOptions = options.modelOptions { body["model_options"] = modelOptions }
        if let instructions = options.instructions, !instructions.isEmpty {
            body["system_message"] = .string(instructions)
        }
        var headers = ["Accept": "text/event-stream"]
        if let sessionKey { headers["X-Hermes-Session-Key"] = sessionKey }
        let request = try http.request(
            "/api/sessions/\(Self.escape(sessionID))/chat/stream",
            method: "POST",
            body: .object(body),
            extraHeaders: headers
        )
        return Self.map(http.events(request), HermesEventDecoder.sessionStream)
    }

    /// Message content: plain text, or text plus images as OpenAI-style parts.
    static func messageContent(text: String, imageDataURLs: [String]) -> JSONValue {
        guard !imageDataURLs.isEmpty else { return .string(text) }
        var parts: [JSONValue] = []
        if !text.isEmpty { parts.append(["type": "text", "text": .string(text)]) }
        for url in imageDataURLs {
            parts.append(["type": "image_url", "image_url": ["url": .string(url)]])
        }
        return .array(parts)
    }

    // MARK: Runs

    func respond(runID: String, choice: ApprovalChoice, requestID: String?) async throws {
        var body: [String: JSONValue] = ["choice": .string(choice.rawValue)]
        if let requestID { body["request_id"] = .string(requestID) }
        _ = try await http.json("/v1/runs/\(Self.escape(runID))/approval", method: "POST", body: .object(body))
    }

    func stop(runID: String) async throws {
        _ = try await http.json("/v1/runs/\(Self.escape(runID))/stop", method: "POST", body: .object([:]))
    }

    /// Adds guidance to a turn that's still running.
    func steer(runID: String, text: String) async throws {
        _ = try await http.json("/v1/runs/\(Self.escape(runID))/steer", method: "POST", body: ["input": .string(text)])
    }

    func runStatus(runID: String) async throws -> JSONValue {
        try await http.json("/v1/runs/\(Self.escape(runID))")
    }

    /// Starts a background run that survives the app closing. Pair with
    /// `runEvents` to watch it and `runStatus` to collect the result.
    func startRun(input: String, sessionID: String?, options: TurnOptions = TurnOptions(), idempotencyKey: String = UUID().uuidString) async throws -> String {
        var body: [String: JSONValue] = ["input": .string(input)]
        if let sessionID { body["session_id"] = .string(sessionID) }
        if let model = options.model { body["model"] = .string(model) }
        if let modelOptions = options.modelOptions { body["model_options"] = modelOptions }
        var headers = ["Idempotency-Key": idempotencyKey]
        if let sessionKey { headers["X-Hermes-Session-Key"] = sessionKey }
        let request = try http.request("/v1/runs", method: "POST", body: .object(body), extraHeaders: headers)
        let (data, _) = try await http.send(request)
        guard let runID = JSONValue.parse(data)?["run_id"]?.string else { throw APIError.decoding("run") }
        return runID
    }

    func runEvents(runID: String, after seq: Int? = nil) throws -> AsyncThrowingStream<AgentEvent, Error> {
        var headers = ["Accept": "text/event-stream"]
        if let seq { headers["Last-Event-ID"] = String(seq) }
        let request = try http.request("/v1/runs/\(Self.escape(runID))/events", extraHeaders: headers)
        return Self.map(http.events(request), HermesEventDecoder.runStream)
    }

    // MARK: Jobs

    func jobs() async throws -> [AgentJob] {
        let json = try await http.json("/api/jobs", query: ["include_disabled": "true"])
        return (json["jobs"]?.array ?? json["data"]?.array ?? []).compactMap(AgentJob.init(json:))
    }

    func createJob(name: String, schedule: String, prompt: String, deliver: String = "local") async throws -> AgentJob {
        let body: JSONValue = ["name": .string(name), "schedule": .string(schedule),
                               "prompt": .string(prompt), "deliver": .string(deliver)]
        let json = try await http.json("/api/jobs", method: "POST", body: body)
        guard let job = AgentJob(json: json["job"] ?? json) else { throw APIError.decoding("job") }
        return job
    }

    func setJob(id: String, action: JobAction) async throws {
        switch action {
        case .delete:
            _ = try await http.json("/api/jobs/\(Self.escape(id))", method: "DELETE")
        case .pause, .resume, .run:
            _ = try await http.json("/api/jobs/\(Self.escape(id))/\(action.rawValue)", method: "POST", body: .object([:]))
        }
    }

    // MARK: Helpers

    static func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? component
    }

    static func map(
        _ source: AsyncThrowingStream<SSEEvent, Error>,
        _ decode: @escaping @Sendable (SSEEvent) -> [AgentEvent]
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in source {
                        for decoded in decode(event) { continuation.yield(decoded) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

nonisolated enum JobAction: String, Sendable {
    case pause, resume, run, delete
}
