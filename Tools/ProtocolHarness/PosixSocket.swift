// Test-only RFC 6455 client over POSIX sockets (Linux libcurl lacks WebSockets).
import Foundation
#if canImport(Glibc)
import Glibc
#endif

final class PosixSocket: TextSocket, @unchecked Sendable {
    private var fd: Int32 = -1
    private let lock = NSLock()
    private var inbox: [Result<String, Error>] = []
    private var waiters: [CheckedContinuation<String, Error>] = []
    private var closed = false
    private var handshakeBuffer = [UInt8]()

    init(url: URL) {
        do { try open(url) } catch { push(.failure(error)); return }
        Thread { self.readLoop() }.start()
    }

    private func open(_ url: URL) throws {
        let host = url.host ?? "127.0.0.1"
        let port = UInt16(url.port ?? 80)
        fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host == "localhost" ? "127.0.0.1" : host, &addr.sin_addr)
        let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard rc == 0 else { throw APIError.transport("connect failed") }
        var path = url.path.isEmpty ? "/" : url.path
        if let q = url.query { path += "?" + q }
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let req = "GET \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        try writeAll(Array(req.utf8))
        var head = [UInt8]()
        while !head.ends(with: [13, 10, 13, 10]) {
            var b: UInt8 = 0
            guard read(fd, &b, 1) == 1 else { throw APIError.transport("handshake closed") }
            head.append(b)
        }
        let status = String(decoding: head, as: UTF8.self)
        guard status.hasPrefix("HTTP/1.1 101") else { throw APIError.transport("handshake: \(status.prefix(60))") }
    }

    private func writeAll(_ bytes: [UInt8]) throws {
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { throw APIError.transport("write failed") }
            off += n
        }
    }

    private func readExactly(_ count: Int) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: count)
        var off = 0
        while off < count {
            let n = out[off...].withUnsafeMutableBufferPointer { read(fd, $0.baseAddress, $0.count) }
            if n <= 0 { return nil }
            off += n
        }
        return out
    }

    private func readLoop() {
        var message = [UInt8]()
        while true {
            guard let h = readExactly(2) else { break }
            let opcode = h[0] & 0x0F
            var len = Int(h[1] & 0x7F)
            if len == 126 { guard let e = readExactly(2) else { break }; len = Int(e[0]) << 8 | Int(e[1]) }
            else if len == 127 { guard let e = readExactly(8) else { break }; len = e.reduce(0) { $0 << 8 | Int($1) } }
            guard let payload = len > 0 ? readExactly(len) : [] else { break }
            switch opcode {
            case 0x1, 0x0:
                message += payload
                if h[0] & 0x80 != 0 { push(.success(String(decoding: message, as: UTF8.self))); message = [] }
            case 0x9: try? frame(0xA, payload)
            case 0x8: push(.failure(APIError.transport("socket closed by server"))); return
            default: break
            }
        }
        push(.failure(APIError.transport("socket closed")))
    }

    private func push(_ r: Result<String, Error>) {
        lock.lock()
        if case .failure = r { if closed { lock.unlock(); return }; closed = true }
        if !waiters.isEmpty { let w = waiters.removeFirst(); lock.unlock(); w.resume(with: r); return }
        inbox.append(r)
        lock.unlock()
    }

    private func frame(_ opcode: UInt8, _ payload: [UInt8]) throws {
        var out: [UInt8] = [0x80 | opcode]
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        if payload.count < 126 { out.append(0x80 | UInt8(payload.count)) }
        else if payload.count < 65536 { out += [UInt8(0xFE), UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)] }
        else { out.append(UInt8(0xFF)); for i in (0..<8).reversed() { out.append(UInt8((payload.count >> (i * 8)) & 0xFF)) } }
        out += mask
        out += payload.enumerated().map { $1 ^ mask[$0 % 4] }
        lock.lock(); defer { lock.unlock() }
        try writeAll(out)
    }

    func send(_ text: String) async throws { try frame(0x1, Array(text.utf8)) }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { c in
            lock.lock()
            if !inbox.isEmpty { let r = inbox.removeFirst(); lock.unlock(); c.resume(with: r); return }
            waiters.append(c)
            lock.unlock()
        }
    }

    func close() { shutdown(fd, Int32(SHUT_RDWR)) }
}

extension Array where Element == UInt8 {
    func ends(with suffix: [UInt8]) -> Bool { count >= suffix.count && Array(self[(count - suffix.count)...]) == suffix }
}
