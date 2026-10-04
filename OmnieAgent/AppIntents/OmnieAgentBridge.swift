import Foundation

/// Shared entry point for anything outside the main app UI — App Intents
/// today — that needs one-shot access to whichever agent is configured.
/// Intents run without the SwiftUI environment, so this talks to the same
/// stores (`AppModeStore`, `ProviderConfigStore`) directly rather than
/// reusing a live `AppModel`.
enum OmnieAgentBridge {
    enum BridgeError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            "Open Omnie Agent and finish setup first."
        }
    }

    @MainActor
    static func ask(_ prompt: String) async throws -> String {
        switch AppModeStore.shared.current {
        case .local:
            return try await askLocal(prompt)
        case .provider:
            return try await askProvider(prompt)
        case nil:
            if LocalAgentClient.availability == .available {
                return try await askLocal(prompt)
            }
            throw BridgeError.notConfigured
        }
    }

    @MainActor
    private static func askLocal(_ prompt: String) async throws -> String {
        let client = await LocalAgentClient.makeConfigured()
        var last = ""
        for try await snapshot in client.reply(to: prompt) {
            last = snapshot
        }
        return last.isEmpty ? "Done." : last
    }

    @MainActor
    private static func askProvider(_ prompt: String) async throws -> String {
        guard let config = ProviderConfigStore.shared.current else {
            throw BridgeError.notConfigured
        }
        if config.transport.isSessionBased {
            guard let client = config.makeRemoteClient() else { throw BridgeError.notConfigured }
            let session = try await client.createSession()
            var fullText = ""
            for try await event in client.streamChat(sessionId: session.id, text: prompt) {
                switch event {
                case .delta(let chunk), .commentary(let chunk):
                    fullText += chunk
                case .completed, .cancelled:
                    return fullText.isEmpty ? "Done." : fullText
                case .failed(let message):
                    throw HermesError.server(status: -1, message: message)
                case .toolStarted, .toolCompleted, .unknown:
                    break
                }
            }
            return fullText.isEmpty ? "Done." : fullText
        } else {
            let client = OpenAICompatibleClient(config: config)
            var fullText = ""
            for try await event in client.streamChat(messages: [ChatMessage(role: .user, text: prompt)]) {
                switch event {
                case .delta(let chunk), .commentary(let chunk):
                    fullText += chunk
                case .completed, .cancelled:
                    return fullText.isEmpty ? "Done." : fullText
                case .failed(let message):
                    throw HermesError.server(status: -1, message: message)
                case .toolStarted, .toolCompleted, .unknown:
                    break
                }
            }
            return fullText.isEmpty ? "Done." : fullText
        }
    }
}
