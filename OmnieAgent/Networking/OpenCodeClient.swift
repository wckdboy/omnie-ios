import Foundation

/// Talks to an OpenCode server (`opencode serve`): HTTP Basic auth, REST
/// session endpoints, and a synchronous message endpoint.
///
/// OpenCode's token-by-token streaming goes through a *global* SSE endpoint
/// (`/event`) shared across every session, with event shapes that aren't
/// fully documented publicly. Rather than guess at filtering/parsing that
/// correctly, this uses the documented synchronous endpoint
/// (`POST /session/:id/message`) instead: the reply arrives all at once
/// rather than token-by-token. `streamChat` still returns the same
/// `AsyncThrowingStream<StreamEvent, Error>` shape as `HermesClient` — it
/// just yields a single `.delta` with the full text. Revisit if/when the
/// `/event` payload shapes are confirmed against a live server.
actor OpenCodeClient: RemoteAgentClient {
    private let config: ProviderConfig
    private let session: URLSession

    init(config: ProviderConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration)
    }

    func health() async throws -> Bool {
        let (_, response) = try await send(request(path: "/session"))
        return (200..<300).contains(response.statusCode)
    }

    /// OpenCode has no single "advertised model" concept comparable to
    /// Hermes's `/v1/models` — the model is chosen per message.
    func modelName() async throws -> String? { nil }

    func listSessions() async throws -> [ChatSession] {
        let (data, _) = try await send(request(path: "/session"))
        let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return items.compactMap(Self.decodeSession)
    }

    func createSession() async throws -> ChatSession {
        let (data, _) = try await send(request(path: "/session", method: "POST", body: [:]))
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let session = Self.decodeSession(object) else {
            throw HermesError.decoding
        }
        return session
    }

    func deleteSession(id: String) async throws {
        _ = try await send(request(path: "/session/\(id)", method: "DELETE"))
    }

    func messages(sessionId: String) async throws -> [ChatMessage] {
        let (data, _) = try await send(request(path: "/session/\(sessionId)/message"))
        let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return items.compactMap(Self.decodeMessageEnvelope)
    }

    nonisolated func streamChat(sessionId: String, text: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.runChat(sessionId: sessionId, text: text, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runChat(
        sessionId: String,
        text: String,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async {
        do {
            let body: [String: Any] = ["parts": [["type": "text", "text": text]]]
            let (data, _) = try await send(request(path: "/session/\(sessionId)/message", method: "POST", body: body))
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw HermesError.decoding
            }
            let replyText = Self.extractText(fromEnvelope: object)
            if Task.isCancelled {
                continuation.finish()
                return
            }
            continuation.yield(.delta(replyText))
            continuation.yield(.completed)
            continuation.finish()
        } catch {
            if Task.isCancelled {
                continuation.finish()
            } else {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Request plumbing

    private func request(path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: config.baseURL) else {
            throw HermesError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let username = config.username.isEmpty ? "opencode" : config.username
        if let credentials = "\(username):\(config.apiKey)".data(using: .utf8) {
            request.setValue("Basic \(credentials.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HermesError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw HermesError.server(status: http.statusCode, message: nil)
        }
        return (data, http)
    }

    // MARK: - Decoding

    private static func decodeSession(_ object: [String: Any]) -> ChatSession? {
        guard let id = object["id"] as? String else { return nil }
        let title = object["title"] as? String
        let time = object["time"] as? [String: Any]
        let updatedAt = (time?["updated"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        let createdAt = (time?["created"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ChatSession(id: id, title: title, updatedAt: updatedAt, createdAt: createdAt)
    }

    /// Both `GET /session/:id/message` (an array of these) and
    /// `POST /session/:id/message` (a single one) use the same envelope:
    /// `{ info: Message, parts: Part[] }`.
    private static func decodeMessageEnvelope(_ object: [String: Any]) -> ChatMessage? {
        guard let info = object["info"] as? [String: Any],
              let roleRaw = info["role"] as? String,
              let role = ChatRole(rawValue: roleRaw) else { return nil }
        return ChatMessage(role: role, text: extractText(fromEnvelope: object))
    }

    private static func extractText(fromEnvelope object: [String: Any]) -> String {
        let parts = (object["parts"] as? [[String: Any]]) ?? []
        return parts
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }
}
