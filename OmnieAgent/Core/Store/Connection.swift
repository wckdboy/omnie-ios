import Foundation

/// The three Hermes surfaces Omnie can drive.
nonisolated enum ConnectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// `hermes serve` / `hermes dashboard` — the Hermes Desktop protocol.
    case dashboard
    /// The gateway's API server (`API_SERVER_KEY`).
    case gateway
    /// Any OpenAI-compatible endpoint.
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Hermes Dashboard"
        case .gateway: "Hermes Gateway"
        case .openAI: "OpenAI-compatible"
        }
    }

    var summary: String {
        switch self {
        case .dashboard:
            "The same connection Hermes Desktop uses. Full control: questions, approvals, todos, slash commands, cron, skills and logs."
        case .gateway:
            "The gateway's API server. Sessions, streaming tools, approvals, steering and cron over one API key."
        case .openAI:
            "Any /v1/chat/completions server. History stays on this iPhone."
        }
    }

    var defaultPort: Int {
        switch self {
        case .dashboard: 9119
        case .gateway: 8642
        case .openAI: 8642
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.connected.to.line.below"
        case .gateway: "point.3.connected.trianglepath.dotted"
        case .openAI: "curlybraces"
        }
    }
}

/// A saved agent. Secrets (API key / password) live in the Keychain under
/// `id`, never in this struct.
nonisolated struct Connection: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var kind: ConnectionKind
    var baseURL: String
    /// Hermes profile (`/p/{profile}` on the gateway, `profile` on the dashboard).
    var profile: String = ""
    /// Dashboard password-provider username; empty means token auth.
    var username: String = ""
    /// Dashboard auth provider name (`basic` by default).
    var authProvider: String = "basic"
    /// OpenAI-compatible default model.
    var model: String = ""
    var createdAt: Date = Date()

    var url: URL? { Connection.normalize(baseURL) }

    var hostLabel: String {
        guard let url else { return baseURL }
        var label = url.host ?? baseURL
        if let port = url.port { label += ":\(port)" }
        if !profile.isEmpty { label += " · \(profile)" }
        return label
    }

    /// Accepts "host", "host:port", "http://host:port/prefix". Adds the
    /// kind's default port and http for bare LAN/Tailscale hosts.
    static func normalize(_ raw: String, defaultPort: Int? = nil) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty else { return nil }
        // Bare LAN / Tailscale hosts get the kind's default port; named
        // https hosts are assumed to sit behind a reverse proxy.
        if components.port == nil, components.scheme == "http", let defaultPort {
            let isAddress = host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
            let isLocalName = host == "localhost" || host.hasSuffix(".local") || !host.contains(".")
                || host.hasSuffix(".ts.net") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa")
            if isAddress || isLocalName { components.port = defaultPort }
        }
        if components.path.hasSuffix("/") { components.path.removeLast() }
        return components.url
    }
}

/// Parses `omnie://connect?...` links and QR codes:
/// `omnie://connect?kind=dashboard&url=http://host:9119&name=Studio&user=me&profile=work`
/// The secret may be included as `key=` (gateway / OpenAI) or `password=`.
nonisolated struct ConnectionLink: Sendable {
    var connection: Connection
    var secret: String?

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "omnie" || components.scheme == "hermes",
              components.host == "connect" || components.path.contains("connect") else { return nil }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] { values[item.name] = item.value ?? "" }
        guard let raw = values["url"], !raw.isEmpty else { return nil }
        let kind = values["kind"].flatMap(ConnectionKind.init(rawValue:)) ?? .dashboard
        var connection = Connection(name: values["name"] ?? "Hermes", kind: kind, baseURL: raw)
        connection.profile = values["profile"] ?? ""
        connection.username = values["user"] ?? values["username"] ?? ""
        connection.authProvider = values["provider"] ?? "basic"
        connection.model = values["model"] ?? ""
        self.connection = connection
        secret = values["key"] ?? values["password"] ?? values["token"]
    }
}
