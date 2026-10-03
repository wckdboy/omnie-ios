import Foundation
import Observation

/// Top-level app state: which mode is active (on-device vs remote), the
/// configured server, the session list, the active conversation, and the
/// in-flight streaming turn. Injected into the environment once by
/// `OmnieAgentApp`.
@MainActor
@Observable
final class AppModel {
    private(set) var config: ServerConfig?
    private(set) var client: HermesClient?
    private(set) var mode: AppMode?

    var sessions: [ChatSession] = []
    var messages: [ChatMessage] = []
    var activeSessionId: String?

    var isLoadingSessions = false
    var isStreaming = false
    var errorMessage: String?

    // On-device agent
    var localMessages: [ChatMessage] = []
    var isLocalStreaming = false
    private(set) var localAvailability: LocalAgentClient.Availability = .unavailable(reason: "Checking…")
    private var localClient: LocalAgentClient?

    private var streamTask: Task<Void, Never>?
    private var localStreamTask: Task<Void, Never>?
    private let localTranscriptKey = "omnie.local.transcript"

    init() {
        config = ServerConfigStore.shared.current
        if let config {
            client = HermesClient(config: config)
        }
        localAvailability = LocalAgentClient.availability
        mode = AppModeStore.shared.current
        if mode == .local {
            prepareLocalAgent()
        }
    }

    var isConfigured: Bool { config != nil }

    var localAvailabilityMessage: String? {
        if case .unavailable(let reason) = localAvailability { return reason }
        return nil
    }

    // MARK: - Mode

    /// Attempts to switch into on-device mode. Returns `false` (without
    /// changing anything) if Apple Intelligence's on-device model isn't
    /// available right now.
    func enterLocalMode() -> Bool {
        localAvailability = LocalAgentClient.availability
        guard localAvailability == .available else { return false }
        prepareLocalAgent()
        mode = .local
        AppModeStore.shared.save(.local)
        return true
    }

    /// Returns to the mode picker. Remote config and the local transcript are
    /// left untouched, so switching back later picks up where it left off.
    func changeMode() {
        mode = nil
        AppModeStore.shared.save(nil)
    }

    private func prepareLocalAgent() {
        guard localClient == nil else { return }
        localClient = LocalAgentClient()
        loadLocalTranscript()
    }

    // MARK: - Configuration (remote)

    func testConnection(_ config: ServerConfig) async -> Result<String?, Error> {
        let testClient = HermesClient(config: config)
        do {
            guard try await testClient.health() else {
                return .failure(HermesError.server(status: -1, message: "The server didn't report a healthy status."))
            }
            let name = try? await testClient.modelName()
            return .success(name)
        } catch {
            return .failure(error)
        }
    }

    func apply(_ config: ServerConfig) {
        ServerConfigStore.shared.save(config)
        self.config = config
        client = HermesClient(config: config)
        sessions = []
        messages = []
        activeSessionId = nil
        mode = .remote
        AppModeStore.shared.save(.remote)
    }

    func signOut() {
        ServerConfigStore.shared.clear()
        config = nil
        client = nil
        sessions = []
        messages = []
        activeSessionId = nil
        mode = nil
        AppModeStore.shared.save(nil)
    }

    // MARK: - Sessions (remote)

    func refreshSessions() async {
        guard let client else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        do {
            sessions = try await client.listSessions()
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSession() async -> ChatSession? {
        guard let client else { return nil }
        do {
            let session = try await client.createSession()
            sessions.insert(session, at: 0)
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteSession(_ session: ChatSession) async {
        guard let client else { return }
        do {
            try await client.deleteSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
            if activeSessionId == session.id {
                activeSessionId = nil
                messages = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Chat (remote)

    func openSession(_ session: ChatSession) async {
        activeSessionId = session.id
        guard let client else { return }
        do {
            messages = try await client.messages(sessionId: session.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(_ text: String) {
        guard let client, let sessionId = activeSessionId, !text.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: text))
        let assistantMessage = ChatMessage(role: .assistant, text: "", isStreaming: true)
        messages.append(assistantMessage)
        isStreaming = true

        streamTask = Task {
            do {
                for try await event in client.streamChat(sessionId: sessionId, text: text) {
                    self.apply(event, to: assistantMessage.id)
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.finishStreaming(assistantMessage.id)
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        finishStreaming(messages.last?.id)
        isStreaming = false
    }

    private func apply(_ event: StreamEvent, to messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        switch event {
        case .delta(let chunk), .commentary(let chunk):
            messages[index].text += chunk
        case .toolStarted(let name, let preview):
            messages[index].toolEvents.append(ToolEvent(name: name, status: .started, preview: preview))
        case .toolCompleted(let name, let preview, let failed):
            if let toolIndex = messages[index].toolEvents.lastIndex(where: { $0.name == name && $0.status == .started }) {
                messages[index].toolEvents[toolIndex].status = failed ? .failed : .completed
                messages[index].toolEvents[toolIndex].preview = preview
            } else {
                messages[index].toolEvents.append(ToolEvent(name: name, status: failed ? .failed : .completed, preview: preview))
            }
        case .failed(let message):
            errorMessage = message
        case .completed, .cancelled, .unknown:
            break
        }
    }

    private func finishStreaming(_ messageId: UUID?) {
        isStreaming = false
        guard let messageId, let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index].isStreaming = false
    }

    // MARK: - Chat (on-device)

    func sendLocal(_ text: String) {
        guard let localClient, !text.isEmpty else { return }

        localMessages.append(ChatMessage(role: .user, text: text))
        let assistantMessage = ChatMessage(role: .assistant, text: "", isStreaming: true)
        localMessages.append(assistantMessage)
        isLocalStreaming = true

        localStreamTask = Task {
            do {
                // Foundation Models streams cumulative snapshots, not deltas,
                // so each update replaces the text rather than appending.
                for try await snapshot in localClient.reply(to: text) {
                    if let index = self.localMessages.firstIndex(where: { $0.id == assistantMessage.id }) {
                        self.localMessages[index].text = snapshot
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            if let index = self.localMessages.firstIndex(where: { $0.id == assistantMessage.id }) {
                self.localMessages[index].isStreaming = false
            }
            self.isLocalStreaming = false
            self.saveLocalTranscript()
        }
    }

    func stopLocalStreaming() {
        localStreamTask?.cancel()
        localStreamTask = nil
        isLocalStreaming = false
        if let last = localMessages.indices.last {
            localMessages[last].isStreaming = false
        }
        saveLocalTranscript()
    }

    func clearLocalConversation() {
        localStreamTask?.cancel()
        localStreamTask = nil
        localMessages = []
        isLocalStreaming = false
        localClient = LocalAgentClient()
        UserDefaults.standard.removeObject(forKey: localTranscriptKey)
    }

    private func loadLocalTranscript() {
        guard let data = UserDefaults.standard.data(forKey: localTranscriptKey),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return }
        localMessages = saved
    }

    private func saveLocalTranscript() {
        guard let data = try? JSONEncoder().encode(localMessages) else { return }
        UserDefaults.standard.set(data, forKey: localTranscriptKey)
    }
}
