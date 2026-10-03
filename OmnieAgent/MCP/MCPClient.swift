import Foundation

/// A minimal MCP (Model Context Protocol) client over the Streamable HTTP
/// transport: JSON-RPC 2.0 requests posted to a single endpoint, with
/// responses as either a plain JSON body or a short-lived SSE stream.
///
/// Scope: `initialize`, `tools/list`, and `tools/call` — enough to let the
/// on-device agent discover and call tools from any MCP server. Resources
/// and prompts aren't implemented; add them here if a future tool needs them.
actor MCPClient {
    enum MCPError: LocalizedError {
        case invalidResponse
        case server(status: Int)
        case rpc(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The MCP server sent a response Omnie Agent couldn't understand."
            case .server(let status):
                return "The MCP server responded with status \(status)."
            case .rpc(let message):
                return message
            }
        }
    }

    let endpoint: URL
    let bearerToken: String

    private let session: URLSession
    private var sessionID: String?
    private var nextID = 1
    private var isInitialized = false

    init(endpoint: URL, bearerToken: String) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: configuration)
    }

    func listTools() async throws -> [MCPToolDefinition] {
        try await ensureInitialized()
        let result = try await send(method: "tools/list", params: [:])
        guard let tools = result["tools"] as? [[String: Any]] else { return [] }
        return tools.compactMap { tool in
            guard let name = tool["name"] as? String else { return nil }
            let description = (tool["description"] as? String) ?? ""
            let schema = tool["inputSchema"] ?? [String: Any]()
            let schemaData = (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? Data()
            let schemaJSON = String(data: schemaData, encoding: .utf8) ?? "{}"
            return MCPToolDefinition(name: name, description: description, inputSchemaJSON: schemaJSON)
        }
    }

    func callTool(name: String, argumentsJSON: String) async throws -> String {
        try await ensureInitialized()
        let argumentsObject = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]
        let result = try await send(method: "tools/call", params: ["name": name, "arguments": argumentsObject])
        if let contentArray = result["content"] as? [[String: Any]] {
            let texts = contentArray.compactMap { $0["text"] as? String }
            if !texts.isEmpty {
                return texts.joined(separator: "\n")
            }
        }
        // No text content — fall back to the raw result as JSON so the
        // model still has something to reason about.
        let data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - JSON-RPC plumbing

    private func ensureInitialized() async throws {
        guard !isInitialized else { return }
        _ = try await send(method: "initialize", params: [
            "protocolVersion": "2025-06-18",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "Omnie Agent", "version": "1.0"]
        ])
        try await sendNotification(method: "notifications/initialized", params: [:])
        isInitialized = true
    }

    private func nextRequestID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func send(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextRequestID()
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let (data, response) = try await perform(body: body)
        guard let http = response as? HTTPURLResponse else { throw MCPError.invalidResponse }
        if let newSessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionID = newSessionID
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MCPError.server(status: http.statusCode)
        }
        let message = try extractJSONRPCMessage(from: data, contentType: http.value(forHTTPHeaderField: "Content-Type"), matchingID: id)
        if let error = message["error"] as? [String: Any] {
            throw MCPError.rpc((error["message"] as? String) ?? "The MCP server returned an error.")
        }
        return (message["result"] as? [String: Any]) ?? [:]
    }

    private func sendNotification(method: String, params: [String: Any]) async throws {
        let body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        _ = try await perform(body: body)
    }

    private func perform(body: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await session.data(for: request)
    }

    /// The server may answer with a plain JSON body or an SSE stream of
    /// JSON-RPC messages; handle either and pick out the message whose `id`
    /// matches this request.
    private func extractJSONRPCMessage(from data: Data, contentType: String?, matchingID id: Int) throws -> [String: Any] {
        if contentType?.contains("text/event-stream") == true {
            let text = String(data: data, encoding: .utf8) ?? ""
            for rawLine in text.split(separator: "\n") {
                guard rawLine.hasPrefix("data:") else { continue }
                let jsonText = String(rawLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard let lineData = jsonText.data(using: .utf8),
                      let object = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] else { continue }
                if let messageID = object["id"] as? Int, messageID == id {
                    return object
                }
            }
            throw MCPError.invalidResponse
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MCPError.invalidResponse
        }
        return object
    }
}
