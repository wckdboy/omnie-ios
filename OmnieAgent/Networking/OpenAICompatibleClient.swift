import Foundation

/// A generic client for OpenAI-compatible providers (DeepSeek, OpenAI,
/// OpenRouter, Groq, Mistral, and most others that advertise "just change
/// base_url" compatibility with the OpenAI SDK) — one implementation covers
/// all of them rather than bespoke code per provider. Each request sends
/// the full message history, since these endpoints are stateless per call.
actor OpenAICompatibleClient {
    let config: CloudProviderConfig
    private let session: URLSession

    init(config: CloudProviderConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: configuration)
    }

    /// A minimal non-streaming call used to validate a key/model/base URL
    /// combination from Settings before saving it.
    func testConnection() async throws {
        var request = try makeRequest()
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": "Say \"ok\"."]],
            "max_tokens": 8,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    /// Streams one turn given the full conversation so far (the caller's
    /// `messages` should already include the new user message).
    nonisolated func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.runChatStream(messages: messages, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runChatStream(
        messages: [ChatMessage],
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async {
        do {
            var request = try makeRequest()
            let payload: [String: Any] = [
                "model": config.model,
                "messages": [systemMessage] + messages.map { ["role": $0.role.rawValue, "content": $0.text] },
                "stream": true
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw HermesError.server(status: status, message: nil)
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

    private var systemMessage: [String: String] {
        [
            "role": "system",
            "content": """
            You are Omnie Agent, a concise, helpful assistant. The user has connected their own \
            \(config.providerName) API key directly — you have no tools and no file or shell access.
            """
        ]
    }

    private func makeRequest() throws -> URLRequest {
        guard let url = URL(string: "chat/completions", relativeTo: config.baseURL) else {
            throw HermesError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw HermesError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let errorObject = object?["error"] as? [String: Any]
            let message = (errorObject?["message"] as? String) ?? (object?["error"] as? String)
            throw HermesError.server(status: http.statusCode, message: message)
        }
    }
}
