import Foundation

/// The one event vocabulary the chat UI understands. Each backend decodes its
/// own wire format into this.
nonisolated enum AgentEvent: Sendable, Equatable {
    case runStarted(runID: String?, sessionID: String?)
    case textDelta(String)
    case reasoningDelta(String)
    case commentary(String)
    case toolStarted(id: String?, name: String, preview: String?, arguments: String?)
    case toolFinished(id: String?, name: String, preview: String?, failed: Bool, duration: Double?)
    case subagent(SubagentUpdate)
    case approval(ApprovalRequest)
    case approvalResolved(requestID: String?)
    /// The agent asks the user something (clarify questions, a sudo
    /// password, a secret). Answer through the backend's `answer` call.
    case prompt(AgentPrompt)
    case promptWithdrawn(id: String)
    case todos([TodoItem])
    case title(String)
    case status(kind: String, text: String)
    case usage(TurnUsage)
    case sessionChanged(String)
    case completed(finalText: String?, interrupted: Bool)
    case failed(String)
    case cancelled
}

nonisolated struct TurnUsage: Sendable, Equatable, Hashable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var totalTokens: Int = 0
    var model: String?
    var provider: String?

    init(json: JSONValue?, runtime: JSONValue? = nil) {
        inputTokens = json?["input_tokens"]?.int ?? json?["prompt_tokens"]?.int ?? 0
        outputTokens = json?["output_tokens"]?.int ?? json?["completion_tokens"]?.int ?? 0
        totalTokens = json?["total_tokens"]?.int ?? inputTokens + outputTokens
        let runtime = runtime ?? json?["runtime"]
        model = runtime?["model"]?.string
        provider = runtime?["provider"]?.string
    }

    var isEmpty: Bool { totalTokens == 0 && model == nil }
}

nonisolated struct TodoItem: Sendable, Equatable, Hashable, Identifiable {
    var id: String
    var content: String
    var status: String

    var isDone: Bool { ["completed", "done"].contains(status) }
    var isActive: Bool { status == "in_progress" }

    init?(json: JSONValue, index: Int) {
        guard let content = json["content"]?.string ?? json["text"]?.string ?? json["title"]?.string else { return nil }
        id = json["id"]?.string ?? "todo-\(index)"
        self.content = content
        status = json["status"]?.string ?? "pending"
    }
}

/// Something the agent needs from the user before it can continue.
nonisolated struct AgentPrompt: Sendable, Equatable, Hashable, Identifiable {
    enum Kind: Sendable, Equatable, Hashable {
        case clarify([ClarifyQuestion])
        case sudo(command: String?)
        case secret(envVar: String, prompt: String)
    }

    var id: String
    var sessionID: String?
    var kind: Kind
}

nonisolated struct ClarifyQuestion: Sendable, Equatable, Hashable, Identifiable {
    var id: String
    var question: String
    var choices: [String]
    var multiSelect: Bool

    init(json: JSONValue, index: Int) {
        id = json["qid"]?.string ?? "q\(index)"
        question = json["question"]?.string ?? ""
        choices = json["choices"]?.array?.compactMap { $0.string ?? $0["label"]?.string } ?? []
        multiSelect = json["multi_select"]?.bool ?? false
    }
}

nonisolated enum PromptAnswer: Sendable {
    case clarify([String: String])
    case value(String)
    case decline
}

nonisolated struct SubagentUpdate: Sendable, Equatable, Hashable {
    var id: String
    var goal: String
    var status: String
    var summary: String?
    var finished: Bool

    init(json: JSONValue, finished: Bool) {
        id = json["subagent_id"]?.string ?? json["delegation_id"]?.string ?? UUID().uuidString
        goal = json["goal"]?.string ?? json["preview"]?.string ?? "Subagent"
        status = json["status"]?.string ?? (finished ? "completed" : "running")
        summary = json["summary"]?.string
        self.finished = finished
    }
}

/// Decodes the Hermes API-server wire formats into `AgentEvent`s.
nonisolated enum HermesEventDecoder {
    /// `POST /api/sessions/{id}/chat/stream` — named SSE events.
    static func sessionStream(_ sse: SSEEvent) -> [AgentEvent] {
        guard let name = sse.event else { return [] }
        let json = JSONValue.parse(sse.data) ?? .null
        switch name {
        case "run.started":
            return [.runStarted(runID: json["run_id"]?.string, sessionID: json["session_id"]?.string)]
        case "assistant.delta":
            return (json["delta"]?.string).map { [.textDelta($0)] } ?? []
        case "tool.progress":
            // `_thinking` carries the reasoning preview.
            let tool = json["tool_name"]?.string ?? ""
            guard let delta = json["delta"]?.string, !delta.isEmpty else { return [] }
            return tool == "_thinking" || tool.isEmpty ? [.reasoningDelta(delta)] : []
        case "tool.started":
            let tool = json["tool_name"]?.string ?? "tool"
            if tool.hasPrefix("_") { return [] }
            return [.toolStarted(id: nil, name: tool, preview: json["preview"]?.string, arguments: argumentsText(json["args"]))]
        case "tool.completed", "tool.failed":
            let tool = json["tool_name"]?.string ?? "tool"
            if tool.hasPrefix("_") { return [] }
            return [.toolFinished(
                id: nil,
                name: tool,
                preview: json["preview"]?.string ?? json["result"]?.string,
                failed: name == "tool.failed" || json["is_error"]?.bool == true,
                duration: json["duration"]?.double
            )]
        case "assistant.commentary":
            if json["already_streamed"]?.bool == true { return [] }
            return (json["text"]?.string).map { [.commentary($0)] } ?? []
        case "approval.request":
            return [.approval(ApprovalRequest(json: json, fallbackRunID: json["run_id"]?.string))]
        case "approval.responded":
            return [.approvalResolved(requestID: json["request_id"]?.string)]
        case "subagent.start", "subagent.complete":
            return [.subagent(SubagentUpdate(json: json, finished: name == "subagent.complete"))]
        case "hermes.status", "status":
            return [.status(kind: json["kind"]?.string ?? "status", text: json["text"]?.string ?? "")]
        case "assistant.completed":
            var events: [AgentEvent] = []
            if let session = json["session_id"]?.string { events.append(.sessionChanged(session)) }
            return events
        case "run.completed":
            var events: [AgentEvent] = []
            if let session = json["session_id"]?.string { events.append(.sessionChanged(session)) }
            events.append(.usage(TurnUsage(json: json["usage"], runtime: json["runtime"])))
            events.append(.completed(finalText: json["content"]?.string ?? json["output"]?.string,
                                     interrupted: json["interrupted"]?.bool ?? false))
            return events
        case "run.failed":
            return [.failed(json["error"]?.string ?? json["message"]?.string ?? "The run failed.")]
        case "run.cancelled":
            return [.cancelled]
        case "error":
            return [.failed(json["message"]?.string ?? json["error"]?.string ?? "The agent reported an error.")]
        default:
            return []
        }
    }

    /// `GET /v1/runs/{id}/events` — unnamed frames, the name lives in `event`.
    static func runStream(_ sse: SSEEvent) -> [AgentEvent] {
        guard let json = JSONValue.parse(sse.data), let name = json["event"]?.string else { return [] }
        switch name {
        case "message.delta":
            return (json["delta"]?.string).map { [.textDelta($0)] } ?? []
        case "message.interim":
            if json["already_streamed"]?.bool == true { return [] }
            return (json["text"]?.string).map { [.commentary($0)] } ?? []
        case "reasoning.available":
            return (json["text"]?.string).map { [.reasoningDelta($0)] } ?? []
        case "tool.started":
            let tool = json["tool"]?.string ?? "tool"
            return tool.hasPrefix("_") ? [] : [.toolStarted(id: nil, name: tool, preview: json["preview"]?.string, arguments: nil)]
        case "tool.completed":
            let tool = json["tool"]?.string ?? "tool"
            return tool.hasPrefix("_") ? [] : [.toolFinished(id: nil, name: tool, preview: json["preview"]?.string,
                                                            failed: json["error"]?.bool ?? false,
                                                            duration: json["duration"]?.double)]
        case "subagent.start", "subagent.complete":
            return [.subagent(SubagentUpdate(json: json, finished: name == "subagent.complete"))]
        case "approval.request":
            return [.approval(ApprovalRequest(json: json, fallbackRunID: json["run_id"]?.string))]
        case "approval.responded":
            return [.approvalResolved(requestID: json["request_id"]?.string)]
        case "run.completed":
            return [.usage(TurnUsage(json: json["usage"], runtime: json["runtime"])),
                    .completed(finalText: json["output"]?.string, interrupted: json["interrupted"]?.bool ?? false)]
        case "run.failed", "run.interrupted":
            return [.failed(json["error"]?.string ?? "The run stopped before finishing.")]
        case "run.cancelled":
            return [.cancelled]
        default:
            return []
        }
    }

    /// `POST /v1/chat/completions` with `stream: true` — works against any
    /// OpenAI-compatible server, with Hermes' named extras when present.
    static func chatCompletions(_ sse: SSEEvent, state: inout ChatCompletionState) -> [AgentEvent] {
        if sse.data == "[DONE]" { return [] }
        guard let json = JSONValue.parse(sse.data) else { return [] }
        switch sse.event {
        case "hermes.tool.progress":
            let tool = json["tool"]?.string ?? "tool"
            if tool.hasPrefix("_") { return [] }
            if json["status"]?.string == "completed" {
                return [.toolFinished(id: json["toolCallId"]?.string, name: tool, preview: nil, failed: false, duration: nil)]
            }
            let label = [json["emoji"]?.string, json["label"]?.string].compactMap { $0 }.joined(separator: " ")
            return [.toolStarted(id: json["toolCallId"]?.string, name: tool, preview: label.isEmpty ? nil : label, arguments: nil)]
        case "hermes.status":
            return [.status(kind: json["kind"]?.string ?? "status", text: json["text"]?.string ?? "")]
        case "approval.request":
            return [.approval(ApprovalRequest(json: json, fallbackRunID: state.completionID))]
        default:
            break
        }
        if let error = json["error"], json["choices"] == nil {
            return [.failed(error["message"]?.string ?? error.string ?? "The server reported an error.")]
        }
        if state.completionID == nil, let id = json["id"]?.string {
            state.completionID = id
        }
        var events: [AgentEvent] = []
        if let choice = json["choices"]?.array?.first {
            let delta = choice["delta"] ?? .null
            if let reasoning = delta["reasoning_content"]?.string ?? delta["reasoning"]?.string, !reasoning.isEmpty {
                events.append(.reasoningDelta(reasoning))
            }
            if let text = delta["content"]?.string, !text.isEmpty {
                events.append(.textDelta(text))
            }
            if let reason = choice["finish_reason"]?.string {
                state.finishReason = reason
            }
        }
        if let usage = json["usage"], !usage.isNull {
            events.append(.usage(TurnUsage(json: usage)))
        }
        if let error = json["error"]?["message"]?.string {
            events.append(.failed(error))
        }
        return events
    }

    static func argumentsText(_ value: JSONValue?) -> String? {
        guard let value, !value.isNull else { return nil }
        if let text = value.string {
            return JSONValue.parse(text)?.prettyPrinted ?? text
        }
        return value.prettyPrinted
    }
}

nonisolated struct ChatCompletionState: Sendable {
    var completionID: String?
    var finishReason: String?
}
