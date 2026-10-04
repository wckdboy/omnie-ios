import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A text-frame WebSocket. iOS uses `URLSessionWebSocketTask`; the Linux
/// protocol tests plug in their own implementation.
nonisolated protocol TextSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

nonisolated final class URLSessionTextSocket: TextSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(url: URL, session: URLSession) {
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = 64 * 1024 * 1024
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        while true {
            switch try await task.receive() {
            case .string(let text): return text
            case .data(let data): return String(decoding: data, as: UTF8.self)
            @unknown default: continue
            }
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}
