import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A server→client request: the agent needs the user before it continues.
nonisolated struct ServerRequest: Sendable {
    var id: JSONValue
    var method: String
    var params: JSONValue
}

/// One `{"method":"event"}` notification from the gateway.
nonisolated struct GatewayEvent: Sendable {
    var type: String
    var sessionID: String
    var seq: Int?
    var payload: JSONValue
}

nonisolated enum GatewayMessage: Sendable {
    case event(GatewayEvent)
    case request(ServerRequest)
    case connection(DashboardClient.LinkState)
}

/// Client for the Hermes dashboard / `hermes serve` backend — the same
/// surface Hermes Desktop uses: tui_gateway JSON-RPC 2.0 over a WebSocket at
/// `/api/ws`, plus REST under `/api`.
///
/// Remote dashboards are always gated: sign in with a password provider
/// (`POST /auth/password-login`, cookies), then mint a 30-second
/// single-use ticket (`POST /api/auth/ws-ticket`) for every WebSocket dial.
/// A loopback-only session token is also accepted, for SSH-tunnelled setups.
actor DashboardClient {
    nonisolated enum Credential: Sendable {
        case password(username: String, password: String, provider: String)
        case token(String)
    }

    nonisolated enum LinkState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected(epoch: String?)
        case failed(String)
    }

    let baseURL: URL
    let credential: Credential
    let profile: String?

    private let session: URLSession
    private var socket: TextSocket?
    private let makeSocket: @Sendable (URL, URLSession) -> TextSocket
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var subscribers: [UUID: AsyncStream<GatewayMessage>.Continuation] = [:]
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var signedIn = false
    private(set) var epoch: String?
    private(set) var state: LinkState = .disconnected
    /// Highest seq seen per runtime session, for `session.events.since`.
    private var lastSeq: [String: Int] = [:]
    private var lastInbound = Date()
    private var wantsConnection = false
    private var reconnectAttempt = 0
    private var ready = false
    private var dialTask: Task<Void, Error>?
    private var reconnectTask: Task<Void, Never>?
    /// Session cookies from the dashboard's password login, managed by hand
    /// so refreshed cookies from any response replace the old ones.
    private var cookies: [String: String] = [:]

    init(
        baseURL: URL,
        credential: Credential,
        profile: String? = nil,
        makeSocket: @escaping @Sendable (URL, URLSession) -> TextSocket = { URLSessionTextSocket(url: $0, session: $1) }
    ) {
        self.makeSocket = makeSocket
        self.baseURL = baseURL
        self.credential = credential
        let trimmed = profile?.trimmingCharacters(in: .whitespaces)
        self.profile = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    // MARK: REST

    private var http: HTTPClient {
        var headers = ["Accept": "application/json"]
        if case .token(let token) = credential { headers["X-Hermes-Session-Token"] = token }
        if !cookies.isEmpty {
            headers["Cookie"] = cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        }
        return HTTPClient(baseURL: baseURL, headers: headers)
    }

    private func absorbCookies(from response: HTTPURLResponse) {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        guard let url = response.url else { return }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            if let expires = cookie.expiresDate, expires < Date() {
                cookies[cookie.name] = nil
            } else {
                cookies[cookie.name] = cookie.value
            }
        }
    }

    /// Public: version, auth mode and gateway state.
    func status() async throws -> JSONValue {
        try await rest("/api/status", authenticate: false)
    }

    func signIn() async throws {
        guard case .password(let username, let password, let provider) = credential else {
            signedIn = true
            return
        }
        let body: JSONValue = ["provider": .string(provider), "username": .string(username),
                               "password": .string(password), "next": ""]
        let request = try http.request("/auth/password-login", method: "POST", body: body)
        let (data, response) = try await data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let error = APIError.from(status: response.statusCode, body: data)
            if response.statusCode == 401 { throw APIError.unauthorized("Wrong username or password.") }
            if response.statusCode == 404 {
                throw APIError.http(status: 404, code: nil,
                                    message: "This dashboard has no “\(provider)” password sign-in. Check the auth provider in Hermes.")
            }
            throw error
        }
        guard !cookies.isEmpty else {
            throw APIError.transport("The dashboard signed in but returned no session. Hermes may be behind a proxy that strips cookies.")
        }
        signedIn = true
    }

    /// Authenticated REST call. Signs in lazily and once more on a 401.
    func rest(
        _ path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: JSONValue? = nil,
        authenticate: Bool = true
    ) async throws -> JSONValue {
        if authenticate, !signedIn { try await signIn() }
        var query = query
        if let profile, query["profile"] == nil { query["profile"] = profile }
        for attempt in 0..<2 {
            let request = try http.request(path, method: method, query: query, body: body)
            let (data, response) = try await data(for: request)
            if response.statusCode == 401, authenticate, attempt == 0, case .password = credential {
                signedIn = false
                cookies.removeAll()
                try await signIn()
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                throw APIError.from(status: response.statusCode, body: data)
            }
            return data.isEmpty ? .null : (JSONValue.parse(data) ?? .null)
        }
        throw APIError.unauthorized(nil)
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("The server didn't answer over HTTP.")
            }
            absorbCookies(from: http)
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    // MARK: Socket lifecycle

    /// Opens the socket (if needed) and waits for `gateway.ready`.
    func connect() async throws {
        wantsConnection = true
        if case .connected = state, socket != nil { return }
        if let dialTask {
            try await dialTask.value
            return
        }
        let task = Task { try await self.dial() }
        dialTask = task
        defer { dialTask = nil }
        try await task.value
    }

    func disconnect() {
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        tearDown(reason: nil)
        publish(.connection(.disconnected))
    }

    private func dial() async throws {
        tearDown(reason: nil)
        setState(.connecting)
        var components = URLComponents(url: try http.url("/api/ws"), resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        var items: [URLQueryItem] = []
        switch credential {
        case .token(let token):
            items.append(URLQueryItem(name: "token", value: token))
        case .password:
            items.append(URLQueryItem(name: "ticket", value: try await mintTicket()))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw APIError.invalidURL(baseURL.absoluteString) }

        let task = makeSocket(url, session)
        socket = task
        lastInbound = Date()
        receiveTask = Task { [weak self] in await self?.receiveLoop(task) }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.waitForReady() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw APIError.transport("The dashboard didn't finish the WebSocket handshake.")
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            tearDown(reason: error.localizedDescription)
            setState(.failed(error.localizedDescription))
            throw error
        }

        _ = try await rawCall("client.capabilities", ["server_requests": true], timeout: 20)
        reconnectAttempt = 0
        setState(.connected(epoch: epoch))
        startHeartbeat()
    }

    private func mintTicket() async throws -> String {
        let json = try await rest("/api/auth/ws-ticket", method: "POST", body: .object([:]))
        guard let ticket = json["ticket"]?.string else { throw APIError.decoding("WebSocket ticket") }
        return ticket
    }

    private func waitForReady() async throws {
        if ready { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
        }
    }

    private func tearDown(reason: String?) {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.close()
        socket = nil
        ready = false
        let error = APIError.transport(reason ?? "The connection to the dashboard closed.")
        for (_, continuation) in pending { continuation.resume(throwing: error) }
        pending.removeAll()
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        if case .connected = state { state = .disconnected }
    }

    private func setState(_ newState: LinkState) {
        state = newState
        publish(.connection(newState))
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.beat()
            }
        }
    }

    private func beat() async {
        if Date().timeIntervalSince(lastInbound) > 45 {
            linkLost("No response from the dashboard for 45 seconds.")
            return
        }
        _ = try? await rawCall("gateway.ping", nil, timeout: 20)
    }

    /// Tears the socket down and, if the app still wants the link, keeps
    /// redialing with backoff in a fresh task (the caller may be the receive
    /// task that `tearDown` cancels).
    private func linkLost(_ reason: String) {
        tearDown(reason: reason)
        setState(.failed(reason))
        guard wantsConnection, reconnectTask == nil else { return }
        reconnectTask = Task { await self.reconnectLoop() }
    }

    private func reconnectLoop() async {
        defer { reconnectTask = nil }
        while wantsConnection, !Task.isCancelled {
            reconnectAttempt += 1
            let delay = min(30.0, pow(2.0, Double(min(reconnectAttempt, 6))) * 0.25)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard wantsConnection, !Task.isCancelled else { return }
            let previousEpoch = epoch
            do {
                try await dial()
                await replayMissed(previousEpoch: previousEpoch)
                return
            } catch {
                setState(.failed(error.localizedDescription))
            }
        }
    }

    /// Call when the app returns to the foreground: iOS suspends sockets.
    func resume() async {
        guard wantsConnection else { return }
        if case .connected = state, socket != nil {
            do {
                _ = try await rawCall("gateway.ping", nil, timeout: 5)
                return
            } catch {
                linkLost("The connection went idle while the app was in the background.")
                return
            }
        }
        if reconnectTask == nil, dialTask == nil {
            reconnectAttempt = 0
            reconnectTask = Task { await self.reconnectLoop() }
        }
    }

    /// After a reconnect, replays events each live session missed. A changed
    /// epoch means the backend restarted and old watermarks are meaningless.
    private func replayMissed(previousEpoch: String?) async {
        if previousEpoch != nil, previousEpoch != epoch {
            lastSeq.removeAll()
            return
        }
        for (sessionID, seq) in lastSeq {
            guard let result = try? await rawCall("session.events.since", ["session_id": .string(sessionID), "last_seen": .number(Double(seq))], timeout: 30)
            else { continue }
            for raw in result["events"]?.array ?? [] {
                if let event = Self.decodeEvent(raw) { deliver(event) }
            }
            for open in result["open_requests"]?.array ?? [] {
                if let id = open["id"], let method = open["method"]?.string {
                    publish(.request(ServerRequest(id: id, method: method, params: open["params"] ?? .null)))
                }
            }
        }
    }

    // MARK: Receive

    private func receiveLoop(_ task: TextSocket) async {
        while !Task.isCancelled {
            do {
                let text = try await task.receive()
                handle(text)
            } catch {
                guard !Task.isCancelled, socket === task else { return }
                linkLost(error.localizedDescription)
                return
            }
        }
    }

    private func handle(_ text: String) {
        lastInbound = Date()
        // Frames are one object each; tolerate newline-joined batches.
        for line in text.split(whereSeparator: \.isNewline) {
            guard let frame = JSONValue.parse(String(line)) else { continue }
            route(frame)
        }
    }

    private func route(_ frame: JSONValue) {
        if let method = frame["method"]?.string {
            if method == "event" {
                guard let event = Self.decodeEvent(frame["params"] ?? .null) else { return }
                if event.type == "gateway.ready" {
                    epoch = event.payload["replay_epoch"]?.string
                    ready = true
                    readyContinuation?.resume()
                    readyContinuation = nil
                    return
                }
                deliver(event)
            } else if let id = frame["id"] {
                publish(.request(ServerRequest(id: id, method: method, params: frame["params"] ?? .null)))
            }
            return
        }
        guard let id = frame["id"]?.int, let continuation = pending.removeValue(forKey: id) else { return }
        if let error = frame["error"], !error.isNull {
            let code = error["code"]?.int ?? -32000
            let message = error["message"]?.string ?? "The agent reported error \(code)."
            continuation.resume(throwing: APIError.http(status: code, code: String(code), message: message))
        } else {
            continuation.resume(returning: frame["result"] ?? .null)
        }
    }

    private func deliver(_ event: GatewayEvent) {
        if let seq = event.seq, !event.sessionID.isEmpty {
            if let last = lastSeq[event.sessionID], seq <= last { return }
            lastSeq[event.sessionID] = seq
        }
        publish(.event(event))
    }

    static func decodeEvent(_ params: JSONValue) -> GatewayEvent? {
        guard let type = params["type"]?.string else { return nil }
        return GatewayEvent(
            type: type,
            sessionID: params["session_id"]?.string ?? "",
            seq: params["seq"]?.int,
            payload: params["payload"] ?? .null
        )
    }

    // MARK: Subscribe

    func messages() -> AsyncStream<GatewayMessage> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<GatewayMessage>.makeStream(bufferingPolicy: .bufferingNewest(2048))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.unsubscribe(id) }
        }
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private func publish(_ message: GatewayMessage) {
        for continuation in subscribers.values { continuation.yield(message) }
    }

    // MARK: RPC

    /// Calls `method`, connecting first if needed.
    func call(_ method: String, _ params: JSONValue? = nil, timeout: TimeInterval = 120) async throws -> JSONValue {
        if case .connected = state, socket != nil {} else { try await connect() }
        return try await rawCall(method, params, timeout: timeout)
    }

    private func rawCall(_ method: String, _ params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue {
        guard let socket else { throw APIError.transport("Not connected to the dashboard.") }
        let id = nextID
        nextID += 1
        var frame: [String: JSONValue] = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method)]
        var params = params ?? .object([:])
        if let profile, var object = params.object, object["profile"] == nil, Self.acceptsProfile(method) {
            object["profile"] = .string(profile)
            params = .object(object)
        }
        frame["params"] = params
        let text = String(decoding: try JSONEncoder().encode(JSONValue.object(frame)), as: UTF8.self)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await socket.send(text)
                } catch {
                    self.fail(id, error)
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.fail(id, APIError.transport("The agent didn't answer \(method) in time."))
            }
        }
    }

    private func fail(_ id: Int, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    /// Answers a server→client request.
    func reply(to id: JSONValue, result: JSONValue) async throws {
        try await sendFrame(["jsonrpc": "2.0", "id": id, "result": result])
    }

    /// Declines a request this client can't show (e.g. desktop-window tools).
    func decline(_ id: JSONValue, code: Int = 4404, message: String = "Not available on iPhone") async throws {
        try await sendFrame(["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]])
    }

    private func sendFrame(_ frame: JSONValue) async throws {
        guard let socket else { throw APIError.transport("Not connected to the dashboard.") }
        let text = String(decoding: try JSONEncoder().encode(frame), as: UTF8.self)
        try await socket.send(text)
    }

    private static func acceptsProfile(_ method: String) -> Bool {
        !["client.capabilities", "gateway.ping", "ping"].contains(method)
    }
}
