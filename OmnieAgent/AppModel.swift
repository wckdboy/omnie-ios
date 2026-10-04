import Foundation
import Observation

/// Top-level app state: which mode is active (on-device vs. a configured
/// provider), the provider's config, the session list (for session-based
/// providers), the active conversation, and the in-flight streaming turn.
/// Injected into the environment once by `OmnieAgentApp`.
@MainActor
@Observable
final class AppModel {
    private(set) var providerConfig: ProviderConfig?
    private(set) var client: (any RemoteAgentClient)?
    private(set) var cloudClient: OpenAICompatibleClient?
    private(set) var mode: AppMode?

    // Session-based provider chat (Hermes, OpenCode)
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

    // Single-thread provider chat (OpenAI-compatible: DeepSeek, OpenAI, etc.)
    var providerMessages: [ChatMessage] = []
    var isProviderStreaming = false

    // Pending navigation target for a deep link that opened a new session;
    // SessionsView observes this to push into the conversation.
    var pendingRemoteSession: ChatSession?

    private var streamTask: Task<Void, Never>?
    private var localStreamTask: Task<Void, Never>?
    private var providerStreamTask: Task<Void, Never>?
    private let localTranscriptKey = "omnie.local.transcript"
    private let providerTranscriptKey = "omnie.provider.transcript"

    init() {
        providerConfig = ProviderConfigStore.shared.current
        if let providerConfig {
            setUpClients(for: providerConfig)
        }
        localAvailability = LocalAgentClient.availability
        mode = AppModeStore.shared.current
        if mode == .local {
            loadLocalTranscript()
            Task { localClient = await LocalAgentClient.makeConfigured() }
        } else if mode == .provider, providerConfig?.transport == .openAICompatible {
            loadProviderTranscript()
        }
    }

    var localAvailabilityMessage: String? {
        if case .unavailable(let reason) = localAvailability { return reason }
        return nil
    }

    private func setUpClients(for config: ProviderConfig) {
        if config.transport.isSessionBased {
            client = config.makeRemoteClient()
            cloudClient = nil
        } else {
            cloudClient = OpenAICompatibleClient(config: config)
            client = nil
        }
    }

    // MARK: - Mode

    /// Attempts to switch into on-device mode. Returns `false` (without
    /// changing anything) if Apple Intelligence's on-device model isn't
    /// available right now.
    func enterLocalMode() async -> Bool {
        localAvailability = LocalAgentClient.availability
        guard localAvailability == .available else { return false }
        loadLocalTranscript()
        localClient = await LocalAgentClient.makeConfigured()
        mode = .local
        AppModeStore.shared.save(.local)
        return true
    }

    /// Returns to the mode picker. The provider config and both
    /// transcripts are left untouched, so switching back later picks up
    /// where it left off.
    func changeMode() {
        mode = nil
        AppModeStore.shared.save(nil)
    }

    /// Rebuilds the on-device session against whatever MCP server is
    /// configured right now. Starts a fresh conversation turn-wise (tools are
    /// fixed at session construction) but keeps the visible transcript.
    func reloadLocalTools() async {
        guard mode == .local else { return }
        localClient = await LocalAgentClient.makeConfigured()
    }

    // MARK: - Configuration (provider)

    func testProviderConnection(_ config: ProviderConfig) async -> Result<String?, Error> {
        if config.transport.isSessionBased {
            guard let testClient = config.makeRemoteClient() else { return .failure(HermesError.decoding) }
            do {
                guard try await testClient.health() else {
                    return .failure(HermesError.server(status: -1, message: "The server didn't report a healthy status."))
                }
                let name = try? await testClient.modelName()
                return .success(name)
            } catch {
                return .failure(error)
            }
        } else {
            let testClient = OpenAICompatibleClient(config: config)
            do {
                try await testClient.testConnection()
                return .success(nil)
            } catch {
                return .failure(error)
            }
        }
    }

    func applyProvider(_ config: ProviderConfig) {
        ProviderConfigStore.shared.save(config)
        providerConfig = config
        setUpClients(for: config)
        sessions = []
        messages = []
        activeSessionId = nil
        providerMessages = []
        if config.transport == .openAICompatible {
            loadProviderTranscript()
        }
        mode = .provider
        AppModeStore.shared.save(.provider)
    }

    func signOutProvider() {
        ProviderConfigStore.shared.clear()
        providerConfig = nil
        client = nil
        cloudClient = nil
        sessions = []
        messages = []
        activeSessionId = nil
        providerMessages = []
        mode = nil
        AppModeStore.shared.save(nil)
    }

    // MARK: - Sessions (session-based providers)

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

    // MARK: - Chat (session-based providers)

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

    // MARK: - Chat (single-thread / OpenAI-compatible providers)

    func sendProvider(_ text: String) {
        guard let cloudClient, !text.isEmpty else { return }

        providerMessages.append(ChatMessage(role: .user, text: text))
        let assistantMessage = ChatMessage(role: .assistant, text: "", isStreaming: true)
        providerMessages.append(assistantMessage)
        isProviderStreaming = true

        // Stateless API: send the whole history so far, including the new
        // user message that was just appended above.
        let history = providerMessages.filter { $0.id != assistantMessage.id }

        providerStreamTask = Task {
            do {
                for try await event in cloudClient.streamChat(messages: history) {
                    self.applyProviderEvent(event, to: assistantMessage.id)
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            if let index = self.providerMessages.firstIndex(where: { $0.id == assistantMessage.id }) {
                self.providerMessages[index].isStreaming = false
            }
            self.isProviderStreaming = false
            self.saveProviderTranscript()
        }
    }

    func stopProviderStreaming() {
        providerStreamTask?.cancel()
        providerStreamTask = nil
        isProviderStreaming = false
        if let last = providerMessages.indices.last {
            providerMessages[last].isStreaming = false
        }
        saveProviderTranscript()
    }

    func clearProviderConversation() {
        providerStreamTask?.cancel()
        providerStreamTask = nil
        providerMessages = []
        isProviderStreaming = false
        UserDefaults.standard.removeObject(forKey: providerTranscriptKey)
    }

    private func applyProviderEvent(_ event: StreamEvent, to messageId: UUID) {
        guard let index = providerMessages.firstIndex(where: { $0.id == messageId }) else { return }
        switch event {
        case .delta(let chunk), .commentary(let chunk):
            providerMessages[index].text += chunk
        case .failed(let message):
            errorMessage = message
        case .toolStarted, .toolCompleted, .completed, .cancelled, .unknown:
            break
        }
    }

    private func loadProviderTranscript() {
        guard let data = UserDefaults.standard.data(forKey: providerTranscriptKey),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return }
        providerMessages = saved
    }

    private func saveProviderTranscript() {
        guard let data = try? JSONEncoder().encode(providerMessages) else { return }
        UserDefaults.standard.set(data, forKey: providerTranscriptKey)
    }

    // MARK: - Deep links

    /// Handles a `omnie://` URL opened by the system, a Shortcut, or another
    /// app. Unrecognized or incomplete links are silently ignored.
    func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .ask(let text, let requestedMode):
            switch requestedMode ?? mode {
            case .local:
                Task {
                    if mode != .local {
                        guard await enterLocalMode() else { return }
                    }
                    sendLocal(text)
                }
            case .provider:
                guard let providerConfig else { return }
                if mode != .provider {
                    mode = .provider
                    AppModeStore.shared.save(.provider)
                }
                if providerConfig.transport.isSessionBased {
                    guard client != nil else { return }
                    Task {
                        guard let session = await createSession() else { return }
                        pendingRemoteSession = session
                        await openSession(session)
                        send(text)
                    }
                } else {
                    guard cloudClient != nil else { return }
                    sendProvider(text)
                }
            case nil:
                break
            }
        }
    }
}
