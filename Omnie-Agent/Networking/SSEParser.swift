import Foundation

/// The decoded shape of one Server-Sent Event from a Hermes session chat stream.
/// Marked `nonisolated`, along with `SSEParser` below: both are plain value
/// types used from inside the `HermesClient` actor, and the project's default
/// actor isolation setting would otherwise pin them to `@MainActor`.
nonisolated enum StreamEvent: Equatable {
    case delta(String)
    case commentary(String)
    case toolStarted(name: String, preview: String?)
    case toolCompleted(name: String, preview: String?, failed: Bool)
    case completed
    case failed(String?)
    case cancelled
    case unknown
}

/// Minimal, lenient Server-Sent Events parser for Hermes Agent's streaming endpoints.
/// The exact payload shape per event name isn't fully documented, so this favors
/// tolerance: it tries several common key names before giving up on a field, and
/// anything it can't place becomes `.unknown` rather than throwing.
nonisolated struct SSEParser {
    private var currentEvent: String?
    private var dataLines: [String] = []

    /// Feed one line at a time (as produced by `URLSession.AsyncBytes.lines`).
    /// Per the SSE spec, a record is terminated by a blank line; returns the
    /// decoded event at that point, or `nil` while a record is still accumulating.
    mutating func feed(_ line: String) -> StreamEvent? {
        if line.isEmpty {
            defer {
                currentEvent = nil
                dataLines = []
            }
            guard !dataLines.isEmpty else { return nil }
            return Self.decode(event: currentEvent, data: dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") {
            // Keepalive comment line; nothing to do.
            return nil
        }
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let field = line[line.startIndex..<colonIndex]
        var value = String(line[line.index(after: colonIndex)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "event":
            currentEvent = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    private static func decode(event: String?, data: String) -> StreamEvent {
        if data == "[DONE]" { return .completed }
        guard let jsonData = data.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] else {
            return .unknown
        }

        let kind = (event ?? object["type"] as? String ?? object["object"] as? String ?? "").lowercased()

        if kind.contains("delta") || kind.contains("chunk") {
            // OpenAI-style chat.completion.chunk shape.
            if let choices = object["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let text = delta["content"] as? String {
                return .delta(text)
            }
            if let text = firstString(["delta", "content", "text"], in: object) {
                return kind.contains("commentary") ? .commentary(text) : .delta(text)
            }
            return .unknown
        }

        if kind.contains("commentary") {
            return .commentary(firstString(["content", "text", "message"], in: object) ?? "")
        }

        if kind.contains("tool") {
            let name = firstString(["name", "tool", "tool_name"], in: object) ?? "tool"
            let preview = firstString(["preview", "result", "argument_preview", "arguments"], in: object)
            if kind.contains("failed") {
                return .toolCompleted(name: name, preview: preview, failed: true)
            }
            if kind.contains("completed") {
                return .toolCompleted(name: name, preview: preview, failed: false)
            }
            return .toolStarted(name: name, preview: preview)
        }

        if kind.contains("cancelled") { return .cancelled }
        if kind.contains("failed") { return .failed(firstString(["error", "message"], in: object)) }
        if kind.contains("completed") { return .completed }

        return .unknown
    }

    private static func firstString(_ keys: [String], in dict: [String: Any]) -> String? {
        for key in keys {
            if let value = dict[key] as? String { return value }
        }
        return nil
    }
}
