import Foundation

/// A conversation on the Hermes gateway, as returned by `/api/sessions`.
/// Marked `nonisolated`: this is a plain value type decoded off the main
/// actor (inside the `HermesClient` actor), and the project's default actor
/// isolation setting would otherwise pin it to `@MainActor`.
nonisolated struct ChatSession: Identifiable, Codable, Hashable {
    let id: String
    var title: String?
    var updatedAt: Date?
    var createdAt: Date?

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "New Chat"
    }
}

nonisolated enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

/// A single message in a conversation. Assistant messages accumulate text as
/// stream deltas arrive, plus any tool-use events reported alongside them.
nonisolated struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: ChatRole
    var text: String
    var toolEvents: [ToolEvent]
    var isStreaming: Bool

    init(id: UUID = UUID(), role: ChatRole, text: String = "", toolEvents: [ToolEvent] = [], isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.toolEvents = toolEvents
        self.isStreaming = isStreaming
    }
}

nonisolated enum ToolStatus: String, Codable {
    case started
    case completed
    case failed
}

/// A tool invocation reported by the agent mid-turn (e.g. `tool.started` / `tool.completed`).
nonisolated struct ToolEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var status: ToolStatus
    var preview: String?

    init(id: UUID = UUID(), name: String, status: ToolStatus, preview: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.preview = preview
    }
}
