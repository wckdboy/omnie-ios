import Foundation

nonisolated struct ToolCall: Sendable, Hashable {
    enum Status: Sendable, Hashable { case running, done, failed }

    var callID: String?
    var name: String
    var preview: String?
    var arguments: String?
    var result: String?
    var status: Status = .running
    var duration: Double?
    var startedAt = Date()

    /// "terminal" → "Terminal", "web_search" → "Web search".
    var title: String {
        let words = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

nonisolated struct ChatItem: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case user(text: String, images: [String])
        case assistant(String)
        case reasoning(String)
        case commentary(String)
        case tool(ToolCall)
        case approval(ApprovalRequest, resolved: ApprovalChoice?)
        case prompt(AgentPrompt, answered: Bool)
        case subagent(SubagentUpdate)
        case notice(String, isError: Bool)
    }

    var id: String
    var kind: Kind
    var date: Date = Date()
}

/// The chat timeline. Folds `AgentEvent`s from a live turn and rebuilds
/// itself from stored history; the view only renders `items`.
nonisolated struct Transcript: Sendable {
    private(set) var items: [ChatItem] = []
    private(set) var todos: [TodoItem] = []
    private var counter = 0
    /// Whether streaming text should extend the last assistant item.
    private var assistantOpen = false
    private var reasoningOpen = false

    init() {}

    init(history: [StoredMessage]) {
        for message in history where !message.hidden {
            appendStored(message)
        }
        closeStreams()
    }

    private mutating func nextID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }

    private mutating func append(_ kind: ChatItem.Kind, date: Date = Date()) {
        items.append(ChatItem(id: nextID("item"), kind: kind, date: date))
    }

    mutating func closeStreams() {
        assistantOpen = false
        reasoningOpen = false
    }

    // MARK: History

    private mutating func appendStored(_ message: StoredMessage) {
        let date = message.timestamp ?? Date()
        switch message.role {
        case "user":
            closeStreams()
            let (text, images) = Self.splitImages(message.content)
            append(.user(text: text, images: images), date: date)
        case "assistant":
            closeStreams()
            if let reasoning = message.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines), !reasoning.isEmpty {
                append(.reasoning(reasoning), date: date)
            }
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                append(message.toolCalls.isEmpty ? .assistant(text) : .commentary(text), date: date)
            }
            for call in message.toolCalls {
                var tool = ToolCall(callID: call.id, name: call.name)
                tool.arguments = HermesEventDecoder.argumentsText(.string(call.arguments))
                tool.status = .done
                tool.startedAt = date
                append(.tool(tool), date: date)
            }
        case "tool":
            let result = message.content
            if let index = matchingTool(callID: message.toolCallID, name: message.toolName, preferRunning: false, requireNoResult: true),
               case .tool(var tool) = items[index].kind {
                tool.result = result
                tool.status = Self.looksFailed(result) ? .failed : .done
                if tool.arguments == nil { tool.arguments = message.toolArguments }
                items[index].kind = .tool(tool)
            } else {
                // Dashboard transcripts carry the call and result in one row.
                var tool = ToolCall(callID: message.toolCallID, name: message.toolName ?? "tool")
                tool.arguments = message.toolArguments
                tool.result = result
                tool.status = Self.looksFailed(result) ? .failed : .done
                tool.startedAt = date
                append(.tool(tool), date: date)
            }
        case "system":
            break
        default:
            if !message.content.isEmpty { append(.notice(message.content, isError: false), date: date) }
        }
    }

    static func looksFailed(_ result: String) -> Bool {
        guard let json = JSONValue.parse(result) else { return false }
        if let error = json["error"], !error.isNull, error.string?.isEmpty != true { return true }
        if let code = json["exit_code"]?.int, code != 0 { return true }
        return json["success"]?.bool == false
    }

    /// Pulls `![image](data:...)` / image URLs out of user text.
    static func splitImages(_ text: String) -> (String, [String]) {
        var images: [String] = []
        var kept: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("![") , let open = trimmed.range(of: "]("), trimmed.hasSuffix(")") {
                images.append(String(trimmed[open.upperBound..<trimmed.index(before: trimmed.endIndex)]))
            } else {
                kept.append(line)
            }
        }
        return (kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), images)
    }

    // MARK: Live turns

    mutating func addUser(_ text: String, images: [String]) {
        closeStreams()
        append(.user(text: text, images: images))
    }

    mutating func addNotice(_ text: String, isError: Bool) {
        closeStreams()
        append(.notice(text, isError: isError))
    }

    mutating func apply(_ event: AgentEvent) {
        switch event {
        case .textDelta(let delta):
            reasoningOpen = false
            if assistantOpen, let last = items.indices.last, case .assistant(let text) = items[last].kind {
                items[last].kind = .assistant(text + delta)
            } else {
                // Leading whitespace of a fresh block reads as a gap.
                let trimmed = delta.drop { $0 == "\n" }
                guard !trimmed.isEmpty || assistantOpen else { return }
                append(.assistant(String(trimmed)))
                assistantOpen = true
            }
        case .reasoningDelta(let delta):
            if reasoningOpen, let index = items.lastIndex(where: { if case .reasoning = $0.kind { return true }; return false }),
               case .reasoning(let text) = items[index].kind {
                items[index].kind = .reasoning(text + delta)
            } else {
                assistantOpen = false
                append(.reasoning(delta))
                reasoningOpen = true
            }
        case .commentary(let text):
            closeStreams()
            append(.commentary(text))
        case .toolStarted(let id, let name, let preview, let arguments):
            closeStreams()
            var tool = ToolCall(callID: id, name: name)
            tool.preview = preview
            tool.arguments = arguments
            append(.tool(tool))
        case .toolFinished(let id, let name, let preview, let failed, let duration):
            closeStreams()
            if let index = matchingTool(callID: id, name: name, preferRunning: true, requireNoResult: false),
               case .tool(var tool) = items[index].kind {
                tool.status = failed ? .failed : .done
                tool.duration = duration ?? Date().timeIntervalSince(tool.startedAt)
                if let preview, !preview.isEmpty { tool.result = preview }
                items[index].kind = .tool(tool)
            } else {
                var tool = ToolCall(callID: id, name: name)
                tool.result = preview
                tool.status = failed ? .failed : .done
                tool.duration = duration
                append(.tool(tool))
            }
        case .approval(let request):
            closeStreams()
            if items.contains(where: { if case .approval(let other, nil) = $0.kind { return other.id == request.id }; return false }) { return }
            append(.approval(request, resolved: nil))
        case .approvalResolved(let requestID):
            for index in items.indices {
                if case .approval(let request, nil) = items[index].kind, requestID == nil || request.requestID == requestID {
                    items[index].kind = .approval(request, resolved: .once)
                }
            }
        case .prompt(let prompt):
            closeStreams()
            append(.prompt(prompt, answered: false))
        case .promptWithdrawn(let id):
            for index in items.indices {
                if case .prompt(let prompt, false) = items[index].kind, prompt.id == id {
                    items[index].kind = .prompt(prompt, answered: true)
                }
            }
        case .subagent(let update):
            if let index = items.lastIndex(where: { if case .subagent(let other) = $0.kind { return other.id == update.id }; return false }) {
                items[index].kind = .subagent(update)
            } else {
                closeStreams()
                append(.subagent(update))
            }
        case .todos(let todos):
            self.todos = todos
        case .failed(let message):
            addNotice(message, isError: true)
            finishRunningTools(failed: true)
        case .cancelled:
            addNotice("Stopped.", isError: false)
            finishRunningTools(failed: true)
        case .completed(let finalText, let interrupted):
            // Some backends only send the reply at the end.
            let hasReply = items.last.map { if case .assistant = $0.kind { return true }; return false } ?? false
            if !hasReply, let finalText = finalText?.trimmingCharacters(in: .whitespacesAndNewlines), !finalText.isEmpty,
               !items.contains(where: { if case .assistant(let text) = $0.kind { return text.trimmingCharacters(in: .whitespacesAndNewlines) == finalText }; return false }) {
                append(.assistant(finalText))
            }
            if interrupted { addNotice("Stopped.", isError: false) }
            finishRunningTools(failed: interrupted)
            closeStreams()
        case .runStarted, .status, .usage, .sessionChanged, .title:
            break
        }
    }

    mutating func resolveApproval(_ request: ApprovalRequest, choice: ApprovalChoice) {
        for index in items.indices {
            if case .approval(let other, nil) = items[index].kind, other.id == request.id {
                items[index].kind = .approval(other, resolved: choice)
            }
        }
    }

    mutating func markAnswered(_ prompt: AgentPrompt) {
        for index in items.indices {
            if case .prompt(let other, false) = items[index].kind, other.id == prompt.id {
                items[index].kind = .prompt(other, answered: true)
            }
        }
    }

    private mutating func finishRunningTools(failed: Bool) {
        for index in items.indices {
            if case .tool(var tool) = items[index].kind, tool.status == .running {
                tool.status = failed ? .failed : .done
                items[index].kind = .tool(tool)
            }
        }
    }

    private func matchingTool(callID: String?, name: String?, preferRunning: Bool, requireNoResult: Bool) -> Int? {
        let tools = items.indices.reversed().filter { if case .tool = items[$0].kind { return true }; return false }
        func tool(_ index: Int) -> ToolCall? { if case .tool(let call) = items[index].kind { return call }; return nil }
        if let callID {
            if let match = tools.first(where: { tool($0)?.callID == callID }) { return match }
        }
        let candidates = tools.filter { index in
            guard let call = tool(index) else { return false }
            if requireNoResult, call.result != nil { return false }
            if preferRunning, call.status != .running { return false }
            return true
        }
        // Oldest unmatched call with this name first: results arrive in order.
        if let name, let match = candidates.reversed().first(where: { tool($0)?.name == name }) { return match }
        return candidates.last
    }

    /// The text of the latest reply, for copy/share/notifications.
    var lastReply: String? {
        for item in items.reversed() {
            if case .assistant(let text) = item.kind { return text }
        }
        return nil
    }
}
