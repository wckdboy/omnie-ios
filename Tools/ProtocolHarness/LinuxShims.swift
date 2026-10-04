import Foundation
import FoundationNetworking
extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { c in
            dataTask(with: request) { d, r, e in
                if let e { c.resume(throwing: e) } else { c.resume(returning: (d ?? Data(), r!)) }
            }.resume()
        }
    }
}
extension NSLock {
    func withLock<R>(_ body: () throws -> R) rethrows -> R { lock(); defer { unlock() }; return try body() }
}
