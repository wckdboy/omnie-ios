import Foundation

nonisolated enum HermesError: LocalizedError {
    case invalidURL
    case server(status: Int, message: String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That server address isn't valid."
        case .server(let status, let message):
            return message ?? "The server responded with status \(status)."
        case .decoding:
            return "Couldn't understand the server's response."
        }
    }
}

/// Talks to a single Hermes Agent gateway's API server: the OpenAI-compatible
/// `/v1` routes for a quick health/name check, and the `/api/sessions` REST +
/// SSE routes that drive the chat UI.
actor HermesClient: RemoteAgentClient {
    private let config: ServerConfig
    private let session: URLSession

    init(config: ServerConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Health

    func health() async throws -> Bool {
        let (data, _) = try await send(request(path: "/health"))
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (object?["status"] as? String) == "ok"
    }

    func modelName() async throws -> String? {
        let (data, _) = try await send(request(path: "/v1/models"))
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let list = object?["data"] as? [[String: Any]]
        return list?.first?["id"] as? String
    }

    // MARK: - Sessions

    func listSessions() async throws -> [ChatSession] {
        let (data, _) = try await send(request(path: "/api/sessions"))
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let items = (object?["sessions"] as? [[String: Any]]) ?? (object?["data"] as? [[String: Any]]) ?? []
        return items.compactMap(Self.decodeSession)
    }

    func createSession() async throws -> ChatSession {
        let (data, _) = try await send(request(path: "/api/sessions", method: "POST", body: [:]))
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let session = Self.decodeSession(object) else {
            throw HermesError.decoding
        }
        return session
    }

    func deleteSession(id: String) async throws {
        _ = try await send(request(path: "/api/sessions/\(id)", method: "DELETE"))
    }

    func messages(sessionId: String) async throws -> [ChatMessage] {
        let (data, _) = try await send(request(path: "/api/sessions/\(sessionId)/messages"))
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let items = (object?["messages"] as? [[String: Any]]) ?? (object?["data"] as? [[String: Any]]) ?? []
        return items.compactMap(Self.decodeMessage)
    }

    // MARK: - Streaming chat

    /// Streams one turn of a conversation. The caller is expected to cancel the
    /// surrounding `Task` to stop early (mirrored by `AsyncThrowingStream`'s
    /// `onTermination`), which maps to the gateway simply dropping the connection.
    nonisolated func streamChat(sessionId: String, text: String) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.runChatStream(sessionId: sessionId, text: text, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runChatStream(
        sessionId: String,
        text: String,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async {
        do {
            let streamRequest = try request(path: "/api/sessions/\(sessionId)/chat/stream", method: "POST", body: ["message": text])
            let (bytes, response) = try await session.bytes(for: streamRequest)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw HermesError.server(status: (response as? HTTPURLResponse)?.statusCode ?? -1, message: nil)
            }

            var parser = SSEParser()
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let event = parser.feed(line) else { continue }
                continuation.yield(event)
                switch event {
                case .completed, .failed, .cancelled:
                    continuation.finish()
                    return
                default:
                    break
                }
            }
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
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesError.decoding
        }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (object?["error"] as? String) ?? ((object?["error"] as? [String: Any])?["message"] as? String)
            throw HermesError.server(status: http.statusCode, message: message)
        }
        return (data, http)
    }

    private static func decodeSession(_ object: [String: Any]) -> ChatSession? {
        guard let id = object["id"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        let title = object["title"] as? String
        let updatedAt = (object["updated_at"] as? String).flatMap(formatter.date(from:))
        let createdAt = (object["created_at"] as? String).flatMap(formatter.date(from:))
        return ChatSession(id: id, title: title, updatedAt: updatedAt, createdAt: createdAt)
    }

    private static func decodeMessage(_ object: [String: Any]) -> ChatMessage? {
        guard let roleRaw = object["role"] as? String, let role = ChatRole(rawValue: roleRaw) else { return nil }
        let text = (object["content"] as? String) ?? ""
        return ChatMessage(role: role, text: text)
    }
}
