import Foundation
import Observation
import UIKit

/// One open conversation: sends turns, folds the event stream into the
/// transcript, and routes the user's answers back to the agent.
@Observable
final class ChatModel {
    let agent: AgentConnection
    private(set) var session: OpenedSession?
    private(set) var transcript = Transcript()
    private(set) var isRunning = false
    private(set) var isLoading = false
    private(set) var runID: String?
    private(set) var statusLine: String?
    private(set) var usage: TurnUsage?
    var title: String?
    var error: String?
    var options: TurnOptions
    /// Bumped on every streamed change so the view can follow the tail.
    private(set) var revision = 0

    private var turnTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(agent: AgentConnection, options: TurnOptions = ChatDefaults.options) {
        self.agent = agent
        self.options = options
    }

    var backend: AgentBackend { agent.backend }
    var features: BackendFeatures { agent.features }
    var isEmpty: Bool { transcript.items.isEmpty }

    var pendingApproval: ApprovalRequest? {
        for item in transcript.items.reversed() {
            if case .approval(let request, nil) = item.kind { return request }
        }
        return nil
    }

    // MARK: Loading

    func open(_ sessionID: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let opened = try await backend.open(sessionID: sessionID)
            adopt(opened)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startNew() async {
        guard session == nil else { return }
        do {
            adopt(try await backend.newSession(options: options))
        } catch {
            self.error = error.localizedDescription
        }
    }

    func adopt(_ opened: OpenedSession) {
        session = opened
        title = opened.title
        transcript = Transcript(history: opened.messages)
        if let approval = opened.pendingApproval {
            transcript.apply(.approval(approval))
        }
        revision += 1
    }

    func reload() async {
        guard let session, !isRunning else { return }
        await open(session.storedID)
    }

    // MARK: Turns

    /// Sends `text`. While a turn runs it steers that turn when the agent
    /// supports it.
    func send(_ text: String, images: [String] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }
        if isRunning {
            steer(trimmed)
            return
        }
        if trimmed.hasPrefix("/"), features.slashCommands, images.isEmpty {
            runCommand(trimmed)
            return
        }
        transcript.addUser(trimmed, images: images)
        revision += 1
        error = nil
        isRunning = true
        statusLine = nil
        runID = nil
        beginBackgroundWork()
        Haptics.tap()

        turnTask = Task { [weak self] in
            guard let self else { return }
            await self.runTurn(TurnRequest(text: trimmed, images: images, options: self.options))
        }
    }

    private func runTurn(_ turn: TurnRequest) async {
        defer {
            isRunning = false
            statusLine = nil
            transcript.closeStreams()
            revision += 1
            endBackgroundWork()
        }
        do {
            if session == nil {
                session = try await backend.newSession(options: options)
            }
            guard let session else { return }
            var lastText = ""
            for try await event in backend.send(turn, in: session) {
                handle(event)
                if case .textDelta(let delta) = event { lastText += delta }
            }
            if UIApplication.shared.applicationState != .active {
                Notifier.turnFinished(agent: agent.connection.name, title: title, text: transcript.lastReply ?? lastText)
            }
            Haptics.success()
            Task { await agent.refreshSessions() }
        } catch is CancellationError {
            transcript.apply(.cancelled)
        } catch {
            if Task.isCancelled {
                transcript.apply(.cancelled)
            } else {
                transcript.apply(.failed(error.localizedDescription))
                Haptics.error()
            }
        }
    }

    private func handle(_ event: AgentEvent) {
        switch event {
        case .runStarted(let run, let sessionID):
            if let run { runID = run }
            if let sessionID, sessionID != session?.id { session?.id = sessionID }
        case .status(let kind, let text):
            statusLine = text.isEmpty ? nil : text
            if kind == "notice", !text.isEmpty { transcript.addNotice(text, isError: false) }
        case .usage(let usage):
            if !usage.isEmpty { self.usage = usage }
        case .sessionChanged(let id):
            // Context compression rotates the session id; follow it.
            if session?.id != id, agent.connection.kind == .gateway { session?.id = id }
        case .title(let title):
            self.title = title
        case .approval, .prompt:
            Haptics.attention()
            transcript.apply(event)
        default:
            transcript.apply(event)
        }
        revision += 1
    }

    func stop() {
        guard isRunning else { return }
        let session = session
        let runID = runID
        Task {
            if let session { try? await backend.interrupt(session: session, runID: runID) }
        }
        // The gateway's session stream also stops when the client hangs up.
        if agent.connection.kind != .dashboard {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                turnTask?.cancel()
            }
        }
        Haptics.tap()
    }

    private func steer(_ text: String) {
        guard features.steer, let session else {
            error = "The agent is still working. Stop it first, or wait for it to finish."
            return
        }
        transcript.addUser(text, images: [])
        revision += 1
        Task {
            do {
                try await backend.steer(session: session, runID: runID, text: text)
                transcript.addNotice("Sent to the running turn.", isError: false)
            } catch {
                transcript.addNotice(error.localizedDescription, isError: true)
            }
            revision += 1
        }
    }

    private func runCommand(_ command: String) {
        transcript.addUser(command, images: [])
        revision += 1
        isRunning = true
        Task {
            defer { isRunning = false; revision += 1 }
            do {
                if session == nil { session = try await backend.newSession(options: options) }
                guard let session else { return }
                let output = try await backend.runCommand(command, session: session)
                if let output, output.hasPrefix("\u{1}skill:") {
                    // A skill command expands into a prompt for the agent.
                    isRunning = false
                    let prompt = String(output.dropFirst("\u{1}skill:".count))
                    transcript.addNotice("Running \(command.split(separator: " ").first ?? "")…", isError: false)
                    await runTurn(TurnRequest(text: prompt, options: options))
                    return
                }
                transcript.addNotice(output?.isEmpty == false ? output! : "Done.", isError: false)
            } catch {
                transcript.addNotice(error.localizedDescription, isError: true)
            }
        }
    }

    // MARK: Answers

    func approve(_ request: ApprovalRequest, _ choice: ApprovalChoice) {
        guard let session else { return }
        transcript.resolveApproval(request, choice: choice)
        revision += 1
        Haptics.tap()
        Task {
            do {
                try await backend.approve(request, choice: choice, session: session)
            } catch {
                transcript.addNotice("Couldn't send your decision: \(error.localizedDescription)", isError: true)
                revision += 1
            }
        }
    }

    func answer(_ prompt: AgentPrompt, _ answer: PromptAnswer) {
        transcript.markAnswered(prompt)
        revision += 1
        Haptics.tap()
        Task {
            do {
                try await backend.answer(prompt, with: answer)
            } catch {
                transcript.addNotice(error.localizedDescription, isError: true)
                revision += 1
            }
        }
    }

    // MARK: Session actions

    func setModel(_ model: ModelOption) async {
        options.model = model.id
        options.provider = model.provider
        guard let session else { return }
        do {
            try await backend.setModel(model, session: session)
            transcript.addNotice("Model set to \(model.label).", isError: false)
        } catch let error as APIError where error.code == nil && error.status == nil {
            // Backends without a lock send the model with each turn instead.
        } catch {
            transcript.addNotice(error.localizedDescription, isError: true)
        }
        revision += 1
    }

    func setReasoning(_ effort: ReasoningEffort) async {
        options.reasoning = effort
        if let dashboard = backend as? DashboardBackend, let session {
            try? await dashboard.setReasoning(effort, fast: options.fast, session: session)
        }
    }

    func rename(_ title: String) async {
        guard let session else { return }
        do {
            try await backend.rename(sessionID: session.storedID, title: title)
            self.title = title
            await agent.refreshSessions()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fork() async -> OpenedSession? {
        guard let session else { return nil }
        do {
            return try await backend.fork(sessionID: session.storedID)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func exportText() -> String {
        var lines: [String] = []
        for item in transcript.items {
            switch item.kind {
            case .user(let text, _): lines.append("You: \(text)")
            case .assistant(let text): lines.append("\(agent.connection.name): \(text)")
            case .tool(let tool): lines.append("[\(tool.title)] \(tool.preview ?? "")")
            default: break
            }
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: Background

    /// Keeps the stream alive briefly after the app leaves the foreground so
    /// a finishing turn can still land and notify.
    private func beginBackgroundWork() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "omnie.turn") { [weak self] in
            self?.endBackgroundWork()
        }
    }

    private func endBackgroundWork() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

/// Defaults applied to new chats (Settings → Chat).
enum ChatDefaults {
    static var options: TurnOptions {
        var options = TurnOptions()
        let defaults = UserDefaults.standard
        options.reasoning = defaults.string(forKey: "omnie.chat.reasoning").flatMap(ReasoningEffort.init(rawValue:)) ?? .auto
        options.fast = defaults.bool(forKey: "omnie.chat.fast")
        let instructions = defaults.string(forKey: "omnie.chat.instructions") ?? ""
        options.instructions = instructions.isEmpty ? nil : instructions
        return options
    }
}
