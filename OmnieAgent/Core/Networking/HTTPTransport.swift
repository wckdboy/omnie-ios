import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Errors surfaced to the UI. Messages follow the brand voice: say what
/// happened, plainly.
nonisolated enum APIError: LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case unauthorized(String?)
    case http(status: Int, code: String?, message: String?)
    case decoding(String)
    case transport(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let raw):
            return "“\(raw)” isn't a valid server address."
        case .unauthorized(let message):
            return message ?? "The server rejected the API key."
        case .http(let status, let code, let message):
            if let message, !message.isEmpty { return message }
            if let code { return "The server answered \(status) (\(code))." }
            return "The server answered \(status)."
        case .decoding(let what):
            return "Couldn't read the server's \(what)."
        case .transport(let message):
            return message
        case .unsupported(let feature):
            return "This agent doesn't support \(feature)."
        }
    }

    var code: String? {
        if case .http(_, let code, _) = self { return code }
        return nil
    }

    var status: Int? {
        switch self {
        case .http(let status, _, _): return status
        case .unauthorized: return 401
        default: return nil
        }
    }

    /// Reads Hermes' `{"error":{"message","code"}}` envelope, the simpler
    /// `{"error":"..."}` form, and FastAPI's `{"detail": ...}`.
    static func from(status: Int, body: Data) -> APIError {
        let json = JSONValue.parse(body)
        var message: String?
        var code: String?
        if let error = json?["error"] {
            if let text = error.string {
                message = text
            } else {
                message = error["message"]?.string
                code = error["code"]?.string ?? error["type"]?.string
            }
        } else if let detail = json?["detail"] {
            message = detail.string ?? detail.array?.first?["msg"]?.string
        }
        if message == nil, json == nil, !body.isEmpty, body.count < 400 {
            message = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if status == 401 || status == 403 && code == "gateway_auth_failed" {
            return .unauthorized(message)
        }
        return .http(status: status, code: code, message: message)
    }
}

/// A chunk of a streaming response.
nonisolated enum StreamChunk: Sendable {
    case response(HTTPURLResponse)
    case data(Data)
}

/// Streams an HTTP response body as it arrives using a data delegate. This
/// works the same on iOS and on Linux (where the protocol layer is tested),
/// unlike `URLSession.bytes(for:)`.
nonisolated final class StreamingTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation
    private var errorBody = Data()
    private var failingStatus: Int?
    private let lock = NSLock()

    private init(continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation) {
        self.continuation = continuation
    }

    /// Starts `request` and yields the response head, then body chunks.
    /// Non-2xx responses finish the stream with an `APIError` built from the
    /// error body. Cancelling the consuming task cancels the request.
    static func stream(_ request: URLRequest, configuration: URLSessionConfiguration = .default) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let delegate = StreamingTransport(continuation: continuation)
            let configuration = configuration
            configuration.timeoutIntervalForRequest = 600
            configuration.timeoutIntervalForResource = 60 * 60 * 6
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            continuation.finish(throwing: APIError.transport("The server didn't answer over HTTP."))
            completionHandler(.cancel)
            return
        }
        if (200..<300).contains(http.statusCode) {
            continuation.yield(.response(http))
        } else {
            lock.withLock { failingStatus = http.statusCode }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let failing = lock.withLock { () -> Bool in
            if failingStatus != nil {
                errorBody.append(data)
                return true
            }
            return false
        }
        if !failing { continuation.yield(.data(data)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (status, body) = lock.withLock { (failingStatus, errorBody) }
        if let status {
            continuation.finish(throwing: APIError.from(status: status, body: body))
        } else if let error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                continuation.finish()
            } else {
                continuation.finish(throwing: APIError.transport(error.localizedDescription))
            }
        } else {
            continuation.finish()
        }
        session.finishTasksAndInvalidate()
    }
}

/// Minimal request builder + JSON round trip shared by every backend client.
nonisolated struct HTTPClient: Sendable {
    var baseURL: URL
    var headers: [String: String]
    var timeout: TimeInterval = 30

    func url(_ path: String, query: [String: String?] = [:]) throws -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + path) else {
            throw APIError.invalidURL(base + path)
        }
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
            .sorted { $0.name < $1.name }
        if !items.isEmpty { components.queryItems = (components.queryItems ?? []) + items }
        guard let url = components.url else { throw APIError.invalidURL(base + path) }
        return url
    }

    func request(
        _ path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: JSONValue? = nil,
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = method
        request.timeoutInterval = timeout
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        for (key, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    @discardableResult
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("The server didn't answer over HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.from(status: http.statusCode, body: data)
        }
        return (data, http)
    }

    func json(
        _ path: String,
        method: String = "GET",
        query: [String: String?] = [:],
        body: JSONValue? = nil
    ) async throws -> JSONValue {
        let (data, _) = try await send(request(path, method: method, query: query, body: body))
        if data.isEmpty { return .null }
        guard let value = JSONValue.parse(data) else { throw APIError.decoding("response to \(path)") }
        return value
    }

    /// Opens an SSE stream and yields parsed events.
    func events(_ request: URLRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                do {
                    for try await chunk in StreamingTransport.stream(request) {
                        if case .data(let data) = chunk {
                            for event in parser.feed(data) { continuation.yield(event) }
                        }
                    }
                    if let tail = parser.finish() { continuation.yield(tail) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
