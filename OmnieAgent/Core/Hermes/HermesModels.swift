import Foundation

/// A conversation stored in the agent's state.db.
nonisolated struct AgentSession: Identifiable, Hashable, Sendable {
    var id: String
    var title: String?
    var source: String?
    var model: String?
    var preview: String?
    var startedAt: Date?
    var lastActive: Date?
    var endedAt: Date?
    var endReason: String?
    var messageCount: Int
    var toolCallCount: Int
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var estimatedCostUSD: Double?
    var parentSessionID: String?
    var pinned: Bool
    var archived: Bool
    var unread: Bool

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let preview, !preview.isEmpty { return String(preview.prefix(80)) }
        return "Untitled"
    }

    var sortDate: Date { lastActive ?? startedAt ?? .distantPast }

    init(id: String, title: String? = nil) {
        self.id = id
        self.title = title
        messageCount = 0
        toolCallCount = 0
        inputTokens = 0
        outputTokens = 0
        reasoningTokens = 0
        pinned = false
        archived = false
        unread = false
    }

    init?(json: JSONValue) {
        guard let id = json["id"]?.string else { return nil }
        self.init(id: id, title: json["title"]?.string)
        source = json["source"]?.string
        model = json["model"]?.string
        preview = json["preview"]?.string
        startedAt = HermesDate.parse(json["started_at"])
        lastActive = HermesDate.parse(json["last_active"])
        endedAt = HermesDate.parse(json["ended_at"])
        endReason = json["end_reason"]?.string
        messageCount = json["message_count"]?.int ?? 0
        toolCallCount = json["tool_call_count"]?.int ?? 0
        inputTokens = json["input_tokens"]?.int ?? 0
        outputTokens = json["output_tokens"]?.int ?? 0
        reasoningTokens = json["reasoning_tokens"]?.int ?? 0
        estimatedCostUSD = json["actual_cost_usd"]?.double ?? json["estimated_cost_usd"]?.double
        parentSessionID = json["parent_session_id"]?.string
        pinned = json["pinned"]?.bool ?? false
        archived = json["archived"]?.bool ?? false
        unread = json["unread"]?.bool ?? false
    }
}

/// Hermes timestamps arrive as epoch seconds (float) or ISO-8601 strings.
nonisolated enum HermesDate {
    static func parse(_ value: JSONValue?) -> Date? {
        guard let value, !value.isNull else { return nil }
        if case .number(let seconds) = value {
            return Date(timeIntervalSince1970: seconds > 1e12 ? seconds / 1000 : seconds)
        }
        guard let text = value.string else { return nil }
        if let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        // Python's isoformat() without a zone: "2026-10-04T12:00:00.123456"
        let python = DateFormatter()
        python.locale = Locale(identifier: "en_US_POSIX")
        python.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            python.dateFormat = format
            if let date = python.date(from: text) { return date }
        }
        return nil
    }
}

/// A stored transcript row from `/api/sessions/{id}/messages`.
nonisolated struct StoredMessage: Identifiable, Hashable, Sendable {
    var id: String
    var role: String
    var content: String
    var reasoning: String?
    var toolName: String?
    var toolCallID: String?
    var toolCalls: [StoredToolCall]
    var timestamp: Date?
    var hidden: Bool
    var toolArguments: String?

    init?(json: JSONValue, index: Int) {
        guard let role = json["role"]?.string else { return nil }
        self.role = role
        id = json["id"]?.string ?? json["row_id"]?.string ?? "row-\(index)"
        let content = Self.text(from: json["content"])
        self.content = content.isEmpty ? (json["text"]?.string ?? "") : content
        reasoning = json["reasoning"]?.string ?? json["reasoning_content"]?.string
        toolName = json["tool_name"]?.string ?? json["name"]?.string
        toolCallID = json["tool_call_id"]?.string
        timestamp = HermesDate.parse(json["timestamp"])
        hidden = json["display_kind"]?.string == "hidden"
        toolArguments = HermesEventDecoder.argumentsText(json["args"])
        toolCalls = (Self.decodeToolCalls(json["tool_calls"]) ?? []).map(StoredToolCall.init(json:))
    }

    /// `content` may be a string or OpenAI-style content parts.
    static func text(from value: JSONValue?) -> String {
        guard let value else { return "" }
        if let text = value.string { return text }
        if let parts = value.array {
            return parts.compactMap { part -> String? in
                if let text = part["text"]?.string { return text }
                if let url = part["image_url"]?["url"]?.string ?? part["image_url"]?.string {
                    return url.hasPrefix("data:") ? "![image](\(url))" : "![image](\(url))"
                }
                return nil
            }.joined(separator: "\n")
        }
        return ""
    }

    private static func decodeToolCalls(_ value: JSONValue?) -> [JSONValue]? {
        if let array = value?.array { return array }
        // state.db stores tool_calls as a JSON string.
        if let text = value?.string, let parsed = JSONValue.parse(text) { return parsed.array }
        return nil
    }
}

nonisolated struct StoredToolCall: Hashable, Sendable {
    var id: String?
    var name: String
    var arguments: String

    init(json: JSONValue) {
        id = json["id"]?.string ?? json["call_id"]?.string
        let function = json["function"] ?? json
        name = function["name"]?.string ?? "tool"
        if let args = function["arguments"]?.string {
            arguments = args
        } else if let args = function["arguments"], !args.isNull {
            arguments = args.prettyPrinted
        } else {
            arguments = ""
        }
    }
}

/// `GET /v1/capabilities`. Every flag defaults to off so older servers that
/// lack the route degrade to plain chat.
nonisolated struct AgentCapabilities: Hashable, Sendable {
    var model: String?
    var platform: String?
    var raw: JSONValue

    init(json: JSONValue) {
        raw = json
        model = json["model"]?.string
        platform = json["platform"]?.string
    }

    static let none = AgentCapabilities(json: .object([:]))

    func has(_ feature: String) -> Bool {
        raw["features"]?[feature]?.bool ?? false
    }

    var sessions: Bool { has("session_chat_streaming") || has("session_resources") }
    var runs: Bool { has("run_submission") }
    var approvals: Bool { has("run_approval_response") }
    var steer: Bool { has("run_steer") }
    var stop: Bool { has("run_stop") }
    var fork: Bool { has("session_fork") }
    var modelLock: Bool { has("session_model_lock") }
    var modelOptions: Bool { has("model_options") }
    var skills: Bool { has("skills_api") }
    var jobs: Bool { has("jobs_admin") }
}

nonisolated struct AgentHealth: Hashable, Sendable {
    var status: String
    var version: String?
    var platform: String?
    var activeRuns: Int?
    var activeAgents: Int?
    var gatewayState: String?
    var platforms: [String: String]
    var requestsToday: Int?
    var tokensToday: Int?
    var latencyP95: Double?
    var raw: JSONValue

    var isOK: Bool { ["ok", "healthy", "ready"].contains(status.lowercased()) }

    init(json: JSONValue) {
        raw = json
        status = json["status"]?.string ?? "unknown"
        version = json["version"]?.string
        platform = json["platform"]?.string
        gatewayState = json["gateway_state"]?.string
        activeRuns = json["api_server"]?["active_runs"]?.int
        activeAgents = json["active_agents"]?.int ?? json["active_agents"]?.array?.count
        let metrics = json["metrics_today"] ?? json["api_server"]?["metrics_today"]
        requestsToday = metrics?["requests"]?.int
        tokensToday = metrics?["tokens"]?.int
        latencyP95 = metrics?["latency_p95_ms"]?.double
        var platforms: [String: String] = [:]
        if let object = json["platforms"]?.object {
            for (name, value) in object {
                platforms[name] = value.string ?? value["state"]?.string ?? value["status"]?.string ?? "configured"
            }
        }
        self.platforms = platforms
    }
}

nonisolated struct ModelOption: Identifiable, Hashable, Sendable {
    var id: String
    var provider: String?
    var label: String
    var isDefault: Bool
}

nonisolated struct AgentSkill: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var description: String
    var category: String?
    var enabled: Bool

    init?(json: JSONValue) {
        guard let name = json["name"]?.string else { return nil }
        self.name = name
        description = json["description"]?.string ?? ""
        category = json["category"]?.string
        enabled = json["enabled"]?.bool ?? true
    }
}

nonisolated struct AgentToolset: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var label: String
    var description: String
    var enabled: Bool
    var configured: Bool
    var tools: [String]

    init?(json: JSONValue) {
        guard let name = json["name"]?.string else { return nil }
        self.name = name
        label = json["label"]?.string ?? name
        description = json["description"]?.string ?? ""
        enabled = json["enabled"]?.bool ?? false
        configured = json["configured"]?.bool ?? true
        tools = json["tools"]?.array?.compactMap { $0.string ?? $0["name"]?.string } ?? []
    }
}

/// A scheduled automation (`/api/jobs`).
nonisolated struct AgentJob: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var schedule: String
    var prompt: String
    var deliver: String?
    var enabled: Bool
    var paused: Bool
    var nextRun: Date?
    var lastRun: Date?
    var lastStatus: String?

    init?(json: JSONValue) {
        guard let id = json["id"]?.string ?? json["job_id"]?.string else { return nil }
        self.id = id
        name = json["name"]?.string ?? id
        schedule = json["schedule_display"]?.string
            ?? json["schedule"]?.string
            ?? json["schedule"]?["display"]?.string
            ?? json["schedule"]?["expr"]?.string
            ?? ""
        prompt = json["prompt"]?.string ?? ""
        deliver = json["deliver"]?.string
        enabled = json["enabled"]?.bool ?? true
        paused = json["paused"]?.bool ?? (json["state"]?.string == "paused")
        nextRun = HermesDate.parse(json["next_run_at"])
        lastRun = HermesDate.parse(json["last_run_at"])
        lastStatus = json["last_status"]?.string
    }
}

/// Dangerous-command approval request raised mid-turn.
nonisolated struct ApprovalRequest: Identifiable, Hashable, Sendable {
    var id: String { requestID ?? "\(runID)-\(command.hashValue)" }
    var requestID: String?
    var runID: String
    var command: String
    var description: String
    var choices: [ApprovalChoice]

    init(json: JSONValue, fallbackRunID: String?) {
        requestID = json["request_id"]?.string
        runID = json["run_id"]?.string ?? fallbackRunID ?? ""
        command = json["command"]?.string ?? ""
        description = json["description"]?.string ?? "This command needs your approval."
        let raw = json["choices"]?.array?.compactMap(\.string) ?? ["once", "session", "always", "deny"]
        choices = raw.compactMap(ApprovalChoice.init(rawValue:))
    }
}

nonisolated enum ApprovalChoice: String, CaseIterable, Hashable, Sendable {
    case once, session, always, deny

    var label: String {
        switch self {
        case .once: "Allow once"
        case .session: "Allow this session"
        case .always: "Always allow"
        case .deny: "Deny"
        }
    }
}

/// Reasoning effort accepted by `model_options.reasoning.effort`.
nonisolated enum ReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto, none, low, medium, high, xhigh

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "Default"
        case .none: "Off"
        case .xhigh: "Extra high"
        default: rawValue.capitalized
        }
    }
}

nonisolated struct TurnOptions: Sendable, Hashable {
    var model: String?
    var provider: String?
    var reasoning: ReasoningEffort = .auto
    var fast = false
    var instructions: String?

    var modelOptions: JSONValue? {
        var object: [String: JSONValue] = [:]
        switch reasoning {
        case .auto: break
        case .none: object["reasoning"] = ["enabled": false]
        default: object["reasoning"] = ["enabled": true, "effort": .string(reasoning.rawValue)]
        }
        if fast { object["fast"] = true }
        return object.isEmpty ? nil : .object(object)
    }
}
