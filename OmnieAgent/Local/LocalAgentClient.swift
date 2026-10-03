import FoundationModels

/// Wraps Apple's on-device Foundation Model so Omnie Agent can run a real
/// agent entirely on the iPhone, offline, with no server involved. Tool
/// calling (see `CurrentDateTimeTool`) is what makes this a genuine agent
/// rather than a plain chatbot.
@MainActor
final class LocalAgentClient {
    enum Availability: Equatable {
        case available
        case unavailable(reason: String)
    }

    /// Checked fresh each time rather than cached: Apple Intelligence can be
    /// toggled, or finish downloading, while the app is running.
    static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Turn on Apple Intelligence in Settings to run an agent on this iPhone.")
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This iPhone doesn't support Apple Intelligence's on-device model.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The on-device model is still downloading. Try again shortly.")
        case .unavailable:
            return .unavailable(reason: "The on-device model isn't available right now.")
        }
    }

    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession(
            tools: [CurrentDateTimeTool()],
            instructions: """
            You are Omnie Agent, a concise, friendly assistant running entirely on-device on the \
            user's iPhone. You have no internet access and can't browse the web, run shell \
            commands, or read the user's files. Use the currentDateTime tool whenever you need to \
            know the current date or time. Keep answers short and clear.
            """
        )
    }

    /// Streams cumulative snapshots of the model's reply for one turn (each
    /// item is the full response so far, not a delta — unlike Hermes's SSE).
    func reply(to text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: text) {
                        continuation.yield(snapshot.content)
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
