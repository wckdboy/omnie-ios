import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

var failures = 0
func check(_ ok: Bool, _ label: String) {
    print(ok ? "  PASS \(label)" : "  FAIL \(label)")
    if !ok { failures += 1 }
}

nonisolated(unsafe) var liveTranscript = Transcript()
struct TurnResult { var text = ""; var reasoning = ""; var tools: [String] = []; var finished: [String] = []; var completed = false; var failed: String?; var approvals = 0; var prompts = 0; var runID: String?; var events: [String] = [] }

func runTurn(_ backend: AgentBackend, _ session: OpenedSession, _ text: String, approve: ApprovalChoice? = nil, clarify: Bool = false) async -> TurnResult {
    var r = TurnResult()
    do {
        for try await event in backend.send(TurnRequest(text: text), in: session) {
            r.events.append(String(describing: event).prefix(90).description)
            liveTranscript.apply(event)
            switch event {
            case .runStarted(let run, _): if let run { r.runID = run }
            case .textDelta(let t): r.text += t
            case .reasoningDelta(let t): r.reasoning += t
            case .toolStarted(_, let name, _, _): r.tools.append(name)
            case .toolFinished(_, let name, _, _, _): r.finished.append(name)
            case .completed: r.completed = true
            case .failed(let m): r.failed = m
            case .approval(let req):
                r.approvals += 1
                if let approve {
                    var req = req
                    if req.runID.isEmpty, let run = r.runID { req.runID = run }
                    do { try await backend.approve(req, choice: approve, session: session) } catch { print("    approve error: \(error)") }
                }
            case .prompt(let prompt):
                r.prompts += 1
                if clarify, case .clarify(let qs) = prompt.kind {
                    var answers: [String: String] = [:]
                    for q in qs { answers[q.id] = q.choices.last ?? "blue" }
                    do { try await backend.answer(prompt, with: .clarify(answers)) } catch { print("    answer error: \(error)") }
                }
            default: break
            }
        }
    } catch {
        r.failed = "THROWN: \(error.localizedDescription)"
    }
    return r
}

func suite(_ name: String, _ backend: AgentBackend, approvals: Bool, clarify: Bool) async {
    print("== \(name)")
    do {
        let info = try await backend.probe()
        check(true, "probe: \(info.name) v\(info.version ?? "?") model=\(info.model ?? "-")")
        let session = try await backend.newSession(options: TurnOptions())
        check(!session.id.isEmpty, "new session \(session.id)")

        let hello = await runTurn(backend, session, "hello there")
        check(hello.completed && hello.text.contains("fake model"), "plain turn streams text: \(hello.text.prefix(60))")
        if hello.failed != nil { print("    \(hello.failed!)"); print(hello.events) }
        print("    reasoning: \(hello.reasoning.prefix(40))")

        let tool = await runTurn(backend, session, "use a tool please")
        check(tool.tools.contains("terminal") && tool.finished.contains("terminal"), "tool events: started=\(tool.tools) finished=\(tool.finished)")
        check(tool.completed && tool.text.contains("hello-from-tool"), "tool result reaches reply: \(tool.text.prefix(70))")
        if !tool.completed { print(tool.events) }

        if approvals {
            let danger = await runTurn(backend, session, "do something danger", approve: .once)
            check(danger.approvals == 1, "approval requested (\(danger.approvals))")
            check(danger.completed, "turn completes after approval: \(danger.text.prefix(60)) \(danger.failed ?? "")")
            if !danger.completed { print(danger.events.suffix(8)) }
        }
        if clarify {
            let ask = await runTurn(backend, session, "ask me something", clarify: true)
            check(ask.prompts == 1, "clarify prompt surfaced (\(ask.prompts))")
            check(ask.completed && ask.text.lowercased().contains("blue"), "clarify answer reaches agent: \(ask.text.prefix(80))")
            if !ask.completed { print(ask.events.suffix(8)) }
        }

        // Interrupt mid-stream.
        var runID: String?
        var deltas = 0
        var ended = "none"
        let started = Date()
        do {
            for try await event in backend.send(TurnRequest(text: "go slow please"), in: session) {
                switch event {
                case .runStarted(let run, _): runID = run ?? runID
                case .textDelta:
                    deltas += 1
                    if deltas == 3 {
                        if name.hasPrefix("Dashboard") {
                            try? await backend.steer(session: session, runID: runID, text: "wrap up")
                        }
                        try await backend.interrupt(session: session, runID: runID)
                    }
                case .completed(_, let interrupted): ended = interrupted ? "interrupted" : "completed"
                case .cancelled: ended = "cancelled"
                case .failed(let m): ended = "failed: \(m)"
                default: break
                }
            }
        } catch { ended = "threw \(error)" }
        let elapsed = Date().timeIntervalSince(started)
        check(elapsed < 5.5, "interrupt stops a slow turn (\(String(format: "%.1f", elapsed))s, deltas=\(deltas), end=\(ended), run=\(runID ?? "-"))")

        let list = try await backend.sessions()
        check(list.contains { $0.id == session.storedID || $0.id == session.id }, "session listed among \(list.count)")
        let reopened = try await backend.open(sessionID: session.storedID)
        let rebuilt = Transcript(history: reopened.messages)
        let kinds = rebuilt.items.map { item -> String in
            switch item.kind {
            case .user: return "U"
            case .assistant: return "A"
            case .reasoning: return "R"
            case .commentary: return "C"
            case .tool(let t): return "T(\(t.name):\(t.result == nil ? "nores" : "res"))"
            default: return "?"
            }
        }
        print("    transcript: \(kinds.joined(separator: " "))")
        if !name.hasPrefix("OpenAI") { check(rebuilt.items.contains { if case .tool(let t) = $0.kind { return t.name == "terminal" && t.result != nil }; return false }, "history rebuilds tool calls with results") }
        let roles = reopened.messages.map(\.role)
        check(roles.filter { $0 == "user" }.count >= 2, "history reloads (\(reopened.messages.count) rows: \(roles.prefix(8)))")
        do {
            try await backend.rename(sessionID: session.storedID, title: "Omnie test \(UUID().uuidString.prefix(6))")
            check(true, "rename")
        } catch { check(false, "rename: \(error)") }
        let models = (try? await backend.models(session: reopened)) ?? []
        check(!models.isEmpty, "models: \(models.prefix(3).map(\.id))")
        let jobs = try? await backend.jobs()
        print("    jobs: \(jobs.map { "\($0.count)" } ?? "error")")
        let skills = try? await backend.skills()
        print("    skills: \(skills.map { "\($0.count)" } ?? "error")")
        if let commands = try? await backend.commands(session: reopened), !commands.isEmpty {
            check(true, "slash commands: \(commands.count) e.g. \(commands.prefix(4).map(\.name))")
        }
        try await backend.delete(sessionID: session.storedID)
        check(true, "delete")
    } catch {
        check(false, "\(name) threw: \(error.localizedDescription) \(error)")
    }
    await backend.close()
}

let key = "omnie-test-key-0123456789abcdef"
let gateway = GatewayBackend(client: HermesClient(baseURL: URL(string: "http://127.0.0.1:8642")!, apiKey: key))
let dash = DashboardBackend(client: DashboardClient(baseURL: URL(string: "http://127.0.0.1:9119")!,
    credential: .password(username: "omnie", password: "omnie-password-123", provider: "basic"), makeSocket: { url, _ in PosixSocket(url: url) }))
let store = LocalTranscriptStore(scope: "test-\(UUID().uuidString)")
let openai = OpenAIBackend(baseURL: URL(string: "http://127.0.0.1:8642/v1")!, apiKey: key, model: nil, store: store)

// Markdown blocks
do {
    let md = "# Title\nSome **bold** text\nsecond line\n\n- one\n- two\n  continued\n1. first\n- [x] done\n\n```swift\nlet x = 1\n```\n> quote\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n![img](data:image/png;base64,AAA)\n---\n```py\nstreaming"
    let blocks = MarkdownParser.parse(md)
    let summary = blocks.map { b -> String in
        switch b { case .heading: return "H"; case .paragraph: return "P"; case .bullet(let i): return "L\(i.count)"; case .code(let l, _): return "C(\(l ?? ""))"; case .quote: return "Q"; case .table(_, let r): return "T\(r.count)"; case .image: return "I"; case .rule: return "R" }
    }.joined(separator: " ")
    check(summary == "H P L4 C(swift) Q T1 I R C(py)", "markdown blocks: \(summary)")
}
// Address normalization and links
do {
    func n(_ raw: String, _ port: Int) -> String { Connection.normalize(raw, defaultPort: port)?.absoluteString ?? "nil" }
    check(n("192.168.1.20", 9119) == "http://192.168.1.20:9119", "bare IP gets port: \(n("192.168.1.20", 9119))")
    check(n("studio.local", 8642) == "http://studio.local:8642", "mDNS host gets port")
    check(n("mac.tail1234.ts.net", 9119) == "http://mac.tail1234.ts.net:9119", "tailscale host gets port")
    check(n("https://hermes.example.com/", 9119) == "https://hermes.example.com", "https host untouched: \(n("https://hermes.example.com/", 9119))")
    check(n("http://10.0.0.2:9000/prefix/", 9119) == "http://10.0.0.2:9000/prefix", "explicit port + prefix kept: \(n("http://10.0.0.2:9000/prefix/", 9119))")
    check(n("   ", 9119) == "nil", "empty rejected")
    let link = ConnectionLink(url: URL(string: "omnie://connect?kind=gateway&url=http://h:8642&name=Box&key=abc&profile=work")!)
    check(link?.connection.kind == .gateway && link?.secret == "abc" && link?.connection.profile == "work" && link?.connection.name == "Box", "connection link parses")
    check(ConnectionLink(url: URL(string: "omnie://chat?text=hi")!) == nil, "non-connect link ignored")
    let profiled = HermesClient(baseURL: URL(string: "http://h:8642")!, apiKey: "k", profile: "work")
    check((try? profiled.http.url("/api/sessions").absoluteString) == "http://h:8642/p/work/api/sessions", "profile prefix: \((try? profiled.http.url("/api/sessions").absoluteString) ?? "")")
}
let only = CommandLine.arguments.dropFirst().first
if only == nil || only == "gateway" { await suite("Gateway API server", gateway, approvals: true, clarify: false) }
if only == nil || only == "dashboard" { await suite("Dashboard JSON-RPC", dash, approvals: true, clarify: true) }
if only == nil || only == "openai" { await suite("OpenAI-compatible (gateway /v1)", openai, approvals: true, clarify: false) }

// Bad credentials surface cleanly.
let bad = DashboardBackend(client: DashboardClient(baseURL: URL(string: "http://127.0.0.1:9119")!,
    credential: .password(username: "omnie", password: "wrong", provider: "basic")))
do { _ = try await bad.probe(); check(false, "bad password rejected") } catch { check(error.localizedDescription.contains("Wrong"), "bad password: \(error.localizedDescription)") }
let badKey = GatewayBackend(client: HermesClient(baseURL: URL(string: "http://127.0.0.1:8642")!, apiKey: "nope-nope-nope-nope"))
do { _ = try await badKey.sessions(); check(false, "bad key rejected") } catch { check(true, "bad key: \(error.localizedDescription)") }

print("live transcript items: \(liveTranscript.items.count), tools: \(liveTranscript.items.filter { if case .tool = $0.kind { return true }; return false }.count)")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
