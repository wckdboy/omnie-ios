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

    /// `tools` always includes `CurrentDateTimeTool`; pass additional tools
    /// (e.g. ones discovered from an MCP server) to extend what the model
    /// can call. Use `makeConfigured()` to build one with the user's
    /// configured MCP server already folded in.
    init(tools: [any Tool] = [CurrentDateTimeTool()]) {
        session = LanguageModelSession(
            tools: tools,
            instructions: """
            You are Omnie Agent, a concise, friendly assistant running entirely on-device on the \
            user's iPhone. You have no internet access and can't browse the web, run shell \
            commands, or read the user's files, beyond what your tools explicitly let you do. \
            Use the currentDateTime tool whenever you need to know the current date or time. \
            Keep answers short and clear.
            """
        )
    }

    /// Builds a client with the built-in tool plus any tools discovered from
    /// the configured MCP server. A server that's unreachable just means
    /// fewer tools, not a failed launch — this never throws.
    static func makeConfigured() async -> LocalAgentClient {
        var tools: [any Tool] = [CurrentDateTimeTool()]
        if let mcpConfig = MCPServerConfigStore.shared.current {
            let mcpClient = MCPClient(endpoint: mcpConfig.endpoint, bearerToken: mcpConfig.bearerToken)
            if let discovered = try? await mcpClient.listTools() {
                tools += discovered.map { MCPDynamicTool(definition: $0, client: mcpClient) }
            }
        }
        return LocalAgentClient(tools: tools)
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
