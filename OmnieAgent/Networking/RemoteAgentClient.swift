import Foundation

/// What "remote mode" needs from any Hermes-style agent server. Both
/// `HermesClient` and `OpenCodeClient` conform to this, so `AppModel` and
/// the chat UI don't need to know which one is active.
protocol RemoteAgentClient: Actor {
    /// A cheap liveness/capability check, used by the "Test Connection"
    /// button. `modelName` may return `nil` if the backend has no concept
    /// of a single advertised model (or no cheap way to ask).
    func health() async throws -> Bool
    func modelName() async throws -> String?

    func listSessions() async throws -> [ChatSession]
    func createSession() async throws -> ChatSession
    func deleteSession(id: String) async throws
    func messages(sessionId: String) async throws -> [ChatMessage]

    /// Streams one turn. Backends that can't stream token-by-token (see
    /// `OpenCodeClient`) are expected to yield the full reply as a single
    /// `.delta` followed by `.completed` — the chat UI doesn't distinguish
    /// "arrived all at once" from "arrived in pieces."
    nonisolated func streamChat(sessionId: String, text: String) -> AsyncThrowingStream<StreamEvent, Error>
}

extension ServerConfig {
    /// Builds the right client type for this config's `kind` — the one
    /// place that needs to know both backends exist.
    func makeClient() -> any RemoteAgentClient {
        switch kind {
        case .hermes:
            return HermesClient(config: self)
        case .opencode:
            return OpenCodeClient(config: self)
        }
    }
}
