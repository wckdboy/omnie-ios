import AppIntents
import Foundation

/// "Ask Omnie" — opens a new chat with the active agent, pre-sent.
struct AskOmnieIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Omnie"
    static let description = IntentDescription("Start a chat with your active Hermes agent.")
    static let openAppWhenRun = true

    @Parameter(title: "Message", requestValueDialog: "What should the agent do?")
    var message: String

    @Parameter(title: "Agent", description: "The saved agent's name. Leave empty for the active one.")
    var agentName: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        var components = URLComponents()
        components.scheme = "omnie"
        if let agentName, !agentName.isEmpty {
            components.host = "agent"
            components.queryItems = [URLQueryItem(name: "name", value: agentName)]
            if let url = components.url { IntentBridge.shared.pending.append(url) }
        }
        components.host = "chat"
        components.queryItems = [URLQueryItem(name: "text", value: message)]
        if let url = components.url { IntentBridge.shared.pending.append(url) }
        NotificationCenter.default.post(name: IntentBridge.didQueue, object: nil)
        return .result()
    }
}

struct OmnieShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskOmnieIntent(),
            phrases: ["Ask \(.applicationName)", "Start a chat in \(.applicationName)"],
            shortTitle: "Ask Omnie",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}

/// Hands intent results to the running app.
@MainActor
final class IntentBridge {
    static let shared = IntentBridge()
    static let didQueue = Notification.Name("omnie.intent.queued")
    var pending: [URL] = []

    func drain(into model: AppModel) {
        let urls = pending
        pending.removeAll()
        for url in urls { model.handle(url: url) }
    }
}
