import Foundation

/// One Server-Sent Event as framed by the WHATWG spec.
nonisolated struct SSEEvent: Sendable, Equatable {
    var event: String?
    var data: String
    var id: String?
}

/// Incremental SSE parser. Feed it raw bytes as they arrive; it returns the
/// events completed by those bytes. Handles `\n`, `\r\n` and `\r` line
/// endings, multi-line `data:`, comments (`: keepalive`) and events split
/// across chunk boundaries.
///
/// `URLSession.AsyncBytes.lines` is deliberately not used: it drops the
/// blank lines that delimit SSE events.
nonisolated struct SSEParser: Sendable {
    private var buffer: [UInt8] = []
    private var eventName: String?
    private var dataLines: [String] = []
    private var lastEventID: String?
    private var sawField = false
    private var pendingCR = false

    init() {}

    mutating func feed(_ data: Data) -> [SSEEvent] {
        var events: [SSEEvent] = []
        for byte in data {
            if pendingCR {
                pendingCR = false
                if byte == 0x0A { continue }
            }
            switch byte {
            case 0x0A:
                if let event = processLine() { events.append(event) }
            case 0x0D:
                pendingCR = true
                if let event = processLine() { events.append(event) }
            default:
                buffer.append(byte)
            }
        }
        return events
    }

    /// Flushes a trailing event that wasn't followed by a blank line.
    mutating func finish() -> SSEEvent? {
        if !buffer.isEmpty { _ = processLine() }
        return dispatch()
    }

    private mutating func processLine() -> SSEEvent? {
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)

        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "event": eventName = String(value); sawField = true
        case "data": dataLines.append(String(value)); sawField = true
        case "id": lastEventID = String(value); sawField = true
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            eventName = nil
            dataLines.removeAll()
            sawField = false
        }
        guard sawField, !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"), id: lastEventID)
    }
}
