import Foundation

/// What a connected agent can do. The UI shows a control only when the
/// backend reports the matching feature.
nonisolated struct BackendFeatures: Sendable, Hashable {
    var serverSessions = false
    var rename = false
    var pin = false
    var delete = false
    var fork = false
    var approvals = false
    var prompts = false
    var interrupt = false
    var steer = false
    var images = false
    var modelSwitch = false
    var reasoningControl = false
    var skills = false
    var toolsets = false
    var jobs = false
    var slashCommands = false
    var todos = false
    var logs = false
}

nonisolated struct BackendInfo: Sendable, Hashable {
    var name: String
    var version: String?
    var model: String?
    var detail: String?
    var features: BackendFeatures
}

/// An open conversation. `id` is what turns are sent to (the runtime id on
/// the dashboard); `storedID` is the durable state.db key.
nonisolated struct OpenedSession: Sendable, Hashable {
    var id: String
    var storedID: String
    var title: String?
    var messages: [StoredMessage]
    var running: Bool = false
    var model: String?
    var pendingApproval: ApprovalRequest?
}

nonisolated struct TurnRequest: Sendable {
    var text: String
    /// `data:image/...;base64,...` URLs.
    var images: [String] = []
    var options = TurnOptions()
}

nonisolated struct SlashCommand: Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var summary: String
    var category: String?
}

/// One Hermes surface the app can drive. Three exist: the gateway API
/// server, the dashboard / `hermes serve` JSON-RPC socket, and any
/// OpenAI-compatible endpoint.
nonisolated protocol AgentBackend: AnyObject, Sendable {
    func probe() async throws -> BackendInfo
    func sessions() async throws -> [AgentSession]
    func newSession(options: TurnOptions) async throws -> OpenedSession
    func open(sessionID: String) async throws -> OpenedSession
    func delete(sessionID: String) async throws
    func rename(sessionID: String, title: String) async throws
    func setPinned(sessionID: String, pinned: Bool) async throws
    func fork(sessionID: String) async throws -> OpenedSession
    func send(_ turn: TurnRequest, in session: OpenedSession) -> AsyncThrowingStream<AgentEvent, Error>
    func interrupt(session: OpenedSession, runID: String?) async throws
    func steer(session: OpenedSession, runID: String?, text: String) async throws
    func approve(_ request: ApprovalRequest, choice: ApprovalChoice, session: OpenedSession) async throws
    func answer(_ prompt: AgentPrompt, with answer: PromptAnswer) async throws
    func models(session: OpenedSession?) async throws -> [ModelOption]
    func setModel(_ model: ModelOption, session: OpenedSession) async throws
    func skills() async throws -> [AgentSkill]
    func toolsets() async throws -> [AgentToolset]
    func jobs() async throws -> [AgentJob]
    func createJob(name: String, schedule: String, prompt: String) async throws
    func job(_ id: String, _ action: JobAction) async throws
    func commands(session: OpenedSession?) async throws -> [SlashCommand]
    func runCommand(_ command: String, session: OpenedSession) async throws -> String?
    func logs(file: String, lines: Int) async throws -> [String]
    /// Live events of a turn already running when the session was opened.
    func follow(_ session: OpenedSession) -> AsyncThrowingStream<AgentEvent, Error>?
    func foreground() async
    func close() async
}

nonisolated extension AgentBackend {
    func rename(sessionID: String, title: String) async throws { throw APIError.unsupported("renaming conversations") }
    func setPinned(sessionID: String, pinned: Bool) async throws { throw APIError.unsupported("pinning") }
    func fork(sessionID: String) async throws -> OpenedSession { throw APIError.unsupported("branching conversations") }
    func steer(session: OpenedSession, runID: String?, text: String) async throws { throw APIError.unsupported("steering a running turn") }
    func approve(_ request: ApprovalRequest, choice: ApprovalChoice, session: OpenedSession) async throws { throw APIError.unsupported("approvals") }
    func answer(_ prompt: AgentPrompt, with answer: PromptAnswer) async throws { throw APIError.unsupported("questions from the agent") }
    func setModel(_ model: ModelOption, session: OpenedSession) async throws { throw APIError.unsupported("switching models") }
    func skills() async throws -> [AgentSkill] { [] }
    func toolsets() async throws -> [AgentToolset] { [] }
    func jobs() async throws -> [AgentJob] { [] }
    func createJob(name: String, schedule: String, prompt: String) async throws { throw APIError.unsupported("scheduled jobs") }
    func job(_ id: String, _ action: JobAction) async throws { throw APIError.unsupported("scheduled jobs") }
    func commands(session: OpenedSession?) async throws -> [SlashCommand] { [] }
    func runCommand(_ command: String, session: OpenedSession) async throws -> String? { throw APIError.unsupported("slash commands") }
    func logs(file: String, lines: Int) async throws -> [String] { throw APIError.unsupported("logs") }
    func follow(_ session: OpenedSession) -> AsyncThrowingStream<AgentEvent, Error>? { nil }
    func foreground() async {}
    func close() async {}
}
