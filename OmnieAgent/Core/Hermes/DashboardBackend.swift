import Foundation

/// Hermes dashboard / `hermes serve` (port 9119) — the Hermes Desktop
/// protocol. The richest surface: clarify questions, sudo/secret prompts,
/// todos, slash commands, steering, logs.
nonisolated final class DashboardBackend: AgentBackend, @unchecked Sendable {
    let client: DashboardClient
    /// rpc id of an open server request, by prompt id.
    private let openRequests = Locked([String: JSONValue]())
    /// Runtime id per stored id for sessions live on this socket.
    private let live = Locked([String: String]())

    init(client: DashboardClient) {
        self.client = client
    }

    func probe() async throws -> BackendInfo {
        let status = try await client.status()
        try await client.connect()
        let version = status["version"]?.string ?? status["displayVersion"]?.string
        var features = BackendFeatures()
        features.serverSessions = true
        features.rename = true
        features.pin = true
        features.delete = true
        features.approvals = true
        features.prompts = true
        features.interrupt = true
        features.steer = true
        features.images = true
        features.modelSwitch = true
        features.reasoningControl = true
        features.skills = true
        features.toolsets = true
        features.jobs = true
        features.slashCommands = true
        features.todos = true
        features.logs = true
        var detail: String?
        if let gateway = status["gateway_state"]?.string ?? (status["gateway_running"]?.bool == true ? "running" : nil) {
            detail = "Messaging gateway: \(gateway)"
        }
        var model: String?
        if let info = try? await client.rest("/api/model/info", authenticate: false) {
            model = info["model"]?.string ?? info["current"]?["model"]?.string
        }
        return BackendInfo(name: "Hermes", version: version, model: model, detail: detail, features: features)
    }

    func sessions() async throws -> [AgentSession] {
        let result = try await client.call("session.list", ["limit": 200])
        return (result["sessions"]?.array ?? []).compactMap { raw in
            var session = AgentSession(json: raw)
            // `resolved_id` is the live compression tip of a chain.
            if let resolved = raw["resolved_id"]?.string, !resolved.isEmpty, session != nil {
                session?.id = resolved
            }
            return session
        }
    }

    func newSession(options: TurnOptions) async throws -> OpenedSession {
        var params: [String: JSONValue] = ["cols": 72]
        if let model = options.model { params["model"] = .string(model) }
        if let provider = options.provider { params["provider"] = .string(provider) }
        if options.reasoning != .auto { params["reasoning_effort"] = .string(options.reasoning.rawValue) }
        if options.fast { params["fast"] = true }
        let result = try await client.call("session.create", .object(params), timeout: 180)
        let opened = Self.opened(result, fallbackID: nil)
        live.update { $0[opened.storedID] = opened.id }
        return opened
    }

    func open(sessionID: String) async throws -> OpenedSession {
        let result = try await client.call("session.resume", ["session_id": .string(sessionID), "cols": 72], timeout: 180)
        let opened = Self.opened(result, fallbackID: sessionID)
        live.update { $0[opened.storedID] = opened.id }
        return opened
    }

    private static func opened(_ result: JSONValue, fallbackID: String?) -> OpenedSession {
        let runtimeID = result["session_id"]?.string ?? fallbackID ?? ""
        let stored = result["stored_session_id"]?.string ?? result["info"]?["stored_session_id"]?.string ?? fallbackID ?? runtimeID
        let rows = result["messages"]?.array ?? []
        var opened = OpenedSession(
            id: runtimeID,
            storedID: stored,
            title: result["info"]?["title"]?.string,
            messages: rows.enumerated().compactMap { StoredMessage(json: $1, index: $0) },
            running: result["running"]?.bool ?? result["info"]?["running"]?.bool ?? false,
            model: result["info"]?["model"]?.string
        )
        if let approval = result["pending_approval"], approval.object != nil {
            opened.pendingApproval = ApprovalRequest(json: approval, fallbackRunID: runtimeID)
        }
        return opened
    }

    func delete(sessionID: String) async throws {
        // A session open on this socket must be closed before it can go.
        if let runtime = live.update({ $0.removeValue(forKey: sessionID) }) {
            _ = try? await client.call("session.close", ["session_id": .string(runtime)])
        }
        _ = try await client.call("session.delete", ["session_id": .string(sessionID)])
    }

    func rename(sessionID: String, title: String) async throws {
        _ = try await client.rest("/api/sessions/\(HermesClient.escape(sessionID))", method: "PATCH", body: ["title": .string(title)])
    }

    func setPinned(sessionID: String, pinned: Bool) async throws {
        _ = try await client.rest("/api/sessions/\(HermesClient.escape(sessionID))", method: "PATCH", body: ["pinned": .bool(pinned)])
    }

    func send(_ turn: TurnRequest, in session: OpenedSession) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.runTurn(turn, session: session, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runTurn(
        _ turn: TurnRequest,
        session: OpenedSession,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async {
        let sid = session.id
        // Subscribe before submitting so no early frame is missed.
        let messages = await client.messages()
        do {
            for image in turn.images {
                guard let comma = image.firstIndex(of: ",") else { continue }
                let base64 = String(image[image.index(after: comma)...])
                let ext = image.contains("image/png") ? "png" : "jpg"
                _ = try await client.call("image.attach_bytes", [
                    "session_id": .string(sid), "content_base64": .string(base64),
                    "filename": .string("photo.\(ext)"), "ext": .string(ext),
                ], timeout: 120)
            }
            let submitted = try await client.call("prompt.submit", ["session_id": .string(sid), "text": .string(turn.text)], timeout: 60)
            continuation.yield(.runStarted(runID: nil, sessionID: nil))
            let status = submitted["status"]?.string ?? "streaming"
            if status == "steered" || status == "queued" {
                continuation.yield(.status(kind: status, text: status == "steered"
                    ? "Added to the running turn."
                    : "Queued until the current turn finishes."))
                if status == "steered" {
                    continuation.finish()
                    return
                }
            }
        } catch {
            continuation.finish(throwing: error)
            return
        }

        var sawReasoningDelta = false
        for await message in messages {
            if Task.isCancelled { break }
            switch message {
            case .connection(let state):
                if case .failed(let reason) = state {
                    continuation.yield(.status(kind: "connection", text: "Reconnecting… (\(reason))"))
                } else if case .connected = state {
                    continuation.yield(.status(kind: "connection", text: ""))
                }
            case .request(let request):
                guard request.params["session_id"]?.string == sid || request.params["session_id"] == nil else { continue }
                if let event = await handle(request, sessionID: sid) { continuation.yield(event) }
            case .event(let event):
                guard event.sessionID == sid else { continue }
                let payload = event.payload
                switch event.type {
                case "message.delta":
                    if let text = payload["text"]?.string { continuation.yield(.textDelta(text)) }
                case "thinking.delta":
                    // Mostly spinner phrases; surface only as a quiet status.
                    continue
                case "reasoning.delta":
                    if let text = payload["text"]?.string {
                        sawReasoningDelta = true
                        continuation.yield(.reasoningDelta(text))
                    }
                case "reasoning.available":
                    if !sawReasoningDelta, let text = payload["text"]?.string { continuation.yield(.reasoningDelta(text)) }
                case "message.interim":
                    if payload["already_streamed"]?.bool != true, let text = payload["text"]?.string {
                        continuation.yield(.commentary(text))
                    }
                case "tool.start":
                    let name = payload["name"]?.string ?? "tool"
                    let preview = payload["preview"]?.string ?? payload["context"]?.string
                    let args = payload["args_text"]?.string ?? HermesEventDecoder.argumentsText(payload["args"])
                    continuation.yield(.toolStarted(id: payload["tool_id"]?.string, name: name, preview: preview, arguments: args))
                case "tool.complete":
                    let name = payload["name"]?.string ?? "tool"
                    let preview = payload["summary"]?.string
                        ?? payload["inline_diff"]?.string
                        ?? payload["result_text"]?.string
                        ?? payload["result"]?.string
                    let failed = payload["error"]?.bool == true || payload["status"]?.string == "error"
                    continuation.yield(.toolFinished(id: payload["tool_id"]?.string, name: name, preview: preview,
                                                     failed: failed, duration: payload["duration_s"]?.double))
                case "todo.updated":
                    let todos = (payload["todos"]?.array ?? []).enumerated().compactMap { TodoItem(json: $1, index: $0) }
                    continuation.yield(.todos(todos))
                case "status.update":
                    if let text = payload["text"]?.string {
                        continuation.yield(.status(kind: payload["kind"]?.string ?? "status", text: text))
                    }
                case "notification.show", "notice":
                    if let text = payload["text"]?.string ?? payload["message"]?.string {
                        continuation.yield(.status(kind: "notice", text: text))
                    }
                case "session.usage":
                    continuation.yield(.usage(Self.usage(payload["usage"] ?? payload)))
                case "session.title":
                    if let title = payload["title"]?.string { continuation.yield(.title(title)) }
                case "subagent.start", "subagent.complete":
                    continuation.yield(.subagent(SubagentUpdate(json: payload, finished: event.type == "subagent.complete")))
                case "request.cancel":
                    if let id = payload["id"] {
                        let key = id.string ?? ""
                        openRequests.update { $0[key] = nil }
                        continuation.yield(.promptWithdrawn(id: key))
                    }
                case "error":
                    let text = payload["message"]?.string ?? "The agent reported an error."
                    continuation.yield(.failed(text))
                    continuation.finish()
                    return
                case "message.complete":
                    if let usage = payload["usage"], !usage.isNull {
                        continuation.yield(.usage(Self.usage(usage)))
                    }
                    let status = payload["status"]?.string ?? "complete"
                    if status == "error" {
                        continuation.yield(.failed(payload["error"]?.string ?? payload["error"]?["message"]?.string ?? "The turn failed."))
                    } else {
                        continuation.yield(.completed(finalText: payload["text"]?.string, interrupted: status == "interrupted"))
                    }
                    continuation.finish()
                    return
                default:
                    break
                }
            }
        }
        continuation.finish()
    }

    /// Turns a server request into an event the UI answers, or declines it.
    private func handle(_ request: ServerRequest, sessionID: String) async -> AgentEvent? {
        let key = request.id.string ?? UUID().uuidString
        switch request.method {
        case "approval":
            var approval = ApprovalRequest(json: request.params, fallbackRunID: sessionID)
            approval.runID = sessionID
            openRequests.update { $0[key] = request.id }
            return .approval(approval)
        case "clarify":
            let questions = (request.params["questions"]?.array ?? []).enumerated().map { ClarifyQuestion(json: $1, index: $0) }
            openRequests.update { $0[key] = request.id }
            return .prompt(AgentPrompt(id: key, sessionID: sessionID, kind: .clarify(questions)))
        case "sudo":
            openRequests.update { $0[key] = request.id }
            return .prompt(AgentPrompt(id: key, sessionID: sessionID, kind: .sudo(command: request.params["command"]?.string)))
        case "secret":
            openRequests.update { $0[key] = request.id }
            return .prompt(AgentPrompt(id: key, sessionID: sessionID, kind: .secret(
                envVar: request.params["env_var"]?.string ?? "SECRET",
                prompt: request.params["prompt"]?.string ?? "The agent needs a value.")))
        default:
            // Desktop-window tools (preview, terminal, window, tour…).
            try? await client.decline(request.id)
            return nil
        }
    }

    private static func usage(_ json: JSONValue) -> TurnUsage {
        var usage = TurnUsage(json: json)
        if usage.inputTokens == 0 { usage.inputTokens = json["input"]?.int ?? json["prompt"]?.int ?? 0 }
        if usage.outputTokens == 0 { usage.outputTokens = json["output"]?.int ?? json["completion"]?.int ?? 0 }
        if usage.totalTokens == 0 { usage.totalTokens = json["total"]?.int ?? usage.inputTokens + usage.outputTokens }
        usage.model = usage.model ?? json["model"]?.string
        return usage
    }

    func interrupt(session: OpenedSession, runID: String?) async throws {
        _ = try await client.call("session.interrupt", ["session_id": .string(session.id)])
    }

    func steer(session: OpenedSession, runID: String?, text: String) async throws {
        let result = try await client.call("session.steer", ["session_id": .string(session.id), "text": .string(text)])
        if result["status"]?.string == "rejected" {
            throw APIError.http(status: 409, code: "steer_rejected", message: "The agent couldn't take that guidance right now.")
        }
    }

    func approve(_ request: ApprovalRequest, choice: ApprovalChoice, session: OpenedSession) async throws {
        var params: [String: JSONValue] = ["session_id": .string(session.id), "choice": .string(choice.rawValue)]
        if let requestID = request.requestID { params["request_id"] = .string(requestID) }
        _ = try await client.call("approval.respond", .object(params), timeout: 300)
    }

    func answer(_ prompt: AgentPrompt, with answer: PromptAnswer) async throws {
        guard let rpcID = openRequests.update({ $0.removeValue(forKey: prompt.id) }) else {
            throw APIError.http(status: 410, code: "expired", message: "The agent stopped waiting for this answer.")
        }
        switch answer {
        case .clarify(let answers):
            try await client.reply(to: rpcID, result: ["answers": .object(answers.mapValues { .string($0) })])
        case .value(let value):
            try await client.reply(to: rpcID, result: ["value": .string(value)])
        case .decline:
            if case .clarify = prompt.kind {
                try await client.reply(to: rpcID, result: ["answers": .object([:])])
            } else {
                try await client.decline(rpcID, code: -32000, message: "Declined on iPhone")
            }
        }
    }

    func models(session: OpenedSession?) async throws -> [ModelOption] {
        var params: [String: JSONValue] = [:]
        if let session { params["session_id"] = .string(session.id) }
        let result = try await client.call("model.options", .object(params))
        var models: [ModelOption] = []
        let current = result["model"]?.string
        for provider in result["providers"]?.array ?? [] {
            let slug = provider["slug"]?.string ?? provider["id"]?.string
            let providerName = provider["name"]?.string ?? slug ?? ""
            for entry in provider["models"]?.array ?? [] {
                guard let id = entry.string ?? entry["id"]?.string ?? entry["model"]?.string else { continue }
                let label = entry["label"]?.string ?? entry["name"]?.string ?? id
                let isCurrent = id == current && (provider["is_current"]?.bool ?? true)
                models.append(ModelOption(id: id, provider: slug, label: providerName.isEmpty ? label : "\(label) · \(providerName)", isDefault: isCurrent))
            }
        }
        return models
    }

    func setModel(_ model: ModelOption, session: OpenedSession) async throws {
        var value = model.id
        if let provider = model.provider { value += " --provider \(provider)" }
        _ = try await client.call("config.set", ["session_id": .string(session.id), "key": "model", "value": .string(value)])
    }

    func setReasoning(_ effort: ReasoningEffort, fast: Bool, session: OpenedSession) async throws {
        if effort != .auto {
            _ = try await client.call("config.set", ["session_id": .string(session.id), "key": "reasoning", "value": .string(effort.rawValue)])
        }
        _ = try await client.call("config.set", ["session_id": .string(session.id), "key": "fast", "value": .string(fast ? "fast" : "normal")])
    }

    func skills() async throws -> [AgentSkill] {
        let json = try await client.rest("/api/skills")
        let list = json.array ?? json["skills"]?.array ?? json["data"]?.array ?? []
        return list.compactMap(AgentSkill.init(json:))
    }

    func toolsets() async throws -> [AgentToolset] {
        let result = try await client.call("toolsets.list", nil)
        let list = result["toolsets"]?.array ?? result.array ?? []
        return list.compactMap(AgentToolset.init(json:))
    }

    func jobs() async throws -> [AgentJob] {
        let json = try await client.rest("/api/cron/jobs")
        let list = json.array ?? json["jobs"]?.array ?? []
        return list.compactMap(AgentJob.init(json:))
    }

    func createJob(name: String, schedule: String, prompt: String) async throws {
        _ = try await client.rest("/api/cron/jobs", method: "POST", body: [
            "name": .string(name), "schedule": .string(schedule), "prompt": .string(prompt),
        ])
    }

    func job(_ id: String, _ action: JobAction) async throws {
        let path = "/api/cron/jobs/\(HermesClient.escape(id))"
        switch action {
        case .delete: _ = try await client.rest(path, method: "DELETE")
        case .pause: _ = try await client.rest(path + "/pause", method: "POST")
        case .resume: _ = try await client.rest(path + "/resume", method: "POST")
        case .run: _ = try await client.rest(path + "/trigger", method: "POST")
        }
    }

    func commands(session: OpenedSession?) async throws -> [SlashCommand] {
        var params: [String: JSONValue] = [:]
        if let session { params["session_id"] = .string(session.id) }
        let result = try await client.call("commands.catalog", .object(params))
        var commands: [SlashCommand] = []
        if let pairs = result["pairs"]?.array {
            for pair in pairs {
                if let items = pair.array, let name = items.first?.string {
                    commands.append(SlashCommand(name: name, summary: items.count > 1 ? items[1].string ?? "" : "", category: nil))
                } else if let name = pair["name"]?.string ?? pair["command"]?.string {
                    commands.append(SlashCommand(name: name, summary: pair["description"]?.string ?? "", category: pair["category"]?.string))
                }
            }
        }
        if commands.isEmpty, let object = result["commands"]?.object {
            commands = object.map { SlashCommand(name: $0.key, summary: $0.value.string ?? $0.value["description"]?.string ?? "", category: nil) }
        }
        return commands
            .map { var command = $0; if !command.name.hasPrefix("/") { command.name = "/" + command.name }; return command }
            .sorted { $0.name < $1.name }
    }

    func runCommand(_ command: String, session: OpenedSession) async throws -> String? {
        let result = try await client.call("slash.exec", ["session_id": .string(session.id), "command": .string(command)], timeout: 180)
        if result["type"]?.string == "skill", let message = result["message"]?.string {
            return "\u{1}skill:" + message
        }
        return result["output"]?.string ?? result["message"]?.string ?? result["notice"]?.string ?? result["warning"]?.string
    }

    func logs(file: String, lines: Int) async throws -> [String] {
        let json = try await client.rest("/api/logs", query: ["file": file, "lines": String(lines)])
        return (json["lines"]?.array ?? []).compactMap(\.string)
    }

    func foreground() async {
        await client.resume()
    }

    func close() async {
        await client.disconnect()
    }
}
