import Foundation
import Observation

/// A saved agent, live: its backend, status and conversation list.
@Observable
final class AgentConnection: Identifiable {
    enum Status: Equatable {
        case idle
        case connecting
        case online
        case failed(String)

        var dot: StatusDot.State {
            switch self {
            case .idle: .unknown
            case .connecting: .connecting
            case .online: .online
            case .failed: .offline
            }
        }
    }

    let connection: Connection
    let backend: AgentBackend
    var id: UUID { connection.id }

    var status: Status = .idle
    var info: BackendInfo?
    var features: BackendFeatures { info?.features ?? BackendFeatures() }
    var sessions: [AgentSession] = []
    var sessionsError: String?
    var isLoadingSessions = false
    var models: [ModelOption] = []

    init(connection: Connection, secret: String) {
        self.connection = connection
        backend = Self.makeBackend(connection, secret: secret)
    }

    static func makeBackend(_ connection: Connection, secret: String) -> AgentBackend {
        let url = connection.url ?? URL(string: "http://localhost")!
        switch connection.kind {
        case .gateway:
            return GatewayBackend(client: HermesClient(
                baseURL: url,
                apiKey: secret,
                profile: connection.profile,
                sessionKey: "omnie-\(DeviceIdentity.id)"
            ))
        case .dashboard:
            let credential: DashboardClient.Credential = connection.username.isEmpty
                ? .token(secret)
                : .password(username: connection.username, password: secret, provider: connection.authProvider)
            return DashboardBackend(client: DashboardClient(baseURL: url, credential: credential, profile: connection.profile))
        case .openAI:
            return OpenAIBackend(baseURL: url, apiKey: secret, model: connection.model,
                                 store: LocalTranscriptStore(scope: connection.id.uuidString))
        }
    }

    var isOnline: Bool { status == .online }

    func connect() async {
        if status == .connecting { return }
        status = .connecting
        do {
            info = try await backend.probe()
            status = .online
            await refreshSessions()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func refreshSessions() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            sessions = try await backend.sessions().sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned }
                return lhs.sortDate > rhs.sortDate
            }
            sessionsError = nil
            if case .failed = status { status = .online }
        } catch {
            sessionsError = error.localizedDescription
        }
    }

    func loadModels(for session: OpenedSession?) async {
        if let models = try? await backend.models(session: session), !models.isEmpty {
            self.models = models
        }
    }

    func delete(_ session: AgentSession) async throws {
        try await backend.delete(sessionID: session.id)
        sessions.removeAll { $0.id == session.id }
    }

    func rename(_ session: AgentSession, to title: String) async throws {
        try await backend.rename(sessionID: session.id, title: title)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index].title = title }
    }

    func togglePin(_ session: AgentSession) async throws {
        try await backend.setPinned(sessionID: session.id, pinned: !session.pinned)
        await refreshSessions()
    }

    func close() async {
        await backend.close()
    }
}

/// A stable per-install id, used as the Hermes memory scope
/// (`X-Hermes-Session-Key`) so the agent knows this iPhone across chats.
enum DeviceIdentity {
    static var id: String {
        let key = "omnie.device.id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
