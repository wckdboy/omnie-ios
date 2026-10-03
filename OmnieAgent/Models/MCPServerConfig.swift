import Foundation
import Security

/// An optional MCP server the on-device agent can pull extra tools from.
/// Hermes-style remote mode doesn't use this — Hermes's own gateway manages
/// its tools server-side, so the client has no tool list to extend there.
struct MCPServerConfig: Equatable {
    var endpoint: URL
    var bearerToken: String
}

/// Persists the MCP endpoint in `UserDefaults` and the bearer token in the
/// Keychain, mirroring `ServerConfigStore`.
@MainActor
final class MCPServerConfigStore {
    static let shared = MCPServerConfigStore()

    private let defaults = UserDefaults.standard
    private let urlDefaultsKey = "omnie.mcp.url"
    private let keychainService = "com.omnieagent.mcp"
    private let keychainAccount = "bearer-token"

    private init() {}

    var current: MCPServerConfig? {
        guard let urlString = defaults.string(forKey: urlDefaultsKey), let url = URL(string: urlString) else {
            return nil
        }
        return MCPServerConfig(endpoint: url, bearerToken: readToken() ?? "")
    }

    func save(_ config: MCPServerConfig) {
        defaults.set(config.endpoint.absoluteString, forKey: urlDefaultsKey)
        writeToken(config.bearerToken)
    }

    func clear() {
        defaults.removeObject(forKey: urlDefaultsKey)
        deleteToken()
    }

    // MARK: - Keychain

    private func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeToken(_ value: String) {
        deleteToken()
        guard !value.isEmpty else { return }
        var query = baseQuery()
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}
