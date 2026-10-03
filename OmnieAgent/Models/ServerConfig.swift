import Foundation
import Security

/// Which Hermes-style agent server protocol to speak. Both are "remote
/// mode" — same session list, same chat UI — just different wire formats.
enum RemoteBackendKind: String, Codable {
    case hermes
    case opencode
}

/// Everything needed to reach a remote agent server: its kind, base URL,
/// credentials, and a friendly name shown in the UI. Hermes uses a single
/// bearer token (`apiKey`); OpenCode uses HTTP Basic auth, so `username`
/// is also set there (defaulting to OpenCode's own default, `"opencode"`)
/// and `apiKey` holds the password.
struct ServerConfig: Equatable {
    var kind: RemoteBackendKind = .hermes
    var baseURL: URL
    var username: String = ""
    var apiKey: String
    var displayName: String
}

/// Persists the server URL, kind, username, and display name in
/// `UserDefaults`, and the secret (API key or Basic auth password) in the
/// Keychain. Everything funnels through `current`, `save`, and `clear` so
/// the rest of the app never touches Keychain APIs directly.
@MainActor
final class ServerConfigStore {
    static let shared = ServerConfigStore()

    private let defaults = UserDefaults.standard
    private let urlDefaultsKey = "omnie.server.url"
    private let nameDefaultsKey = "omnie.server.name"
    private let kindDefaultsKey = "omnie.server.kind"
    private let usernameDefaultsKey = "omnie.server.username"
    private let keychainService = "com.omnieagent.hermes"
    private let keychainAccount = "api-key"

    private init() {}

    var current: ServerConfig? {
        guard let urlString = defaults.string(forKey: urlDefaultsKey),
              let url = URL(string: urlString),
              let apiKey = readKey(),
              !apiKey.isEmpty else {
            return nil
        }
        let name = defaults.string(forKey: nameDefaultsKey) ?? url.host ?? "Hermes Agent"
        let kind = defaults.string(forKey: kindDefaultsKey).flatMap(RemoteBackendKind.init(rawValue:)) ?? .hermes
        let username = defaults.string(forKey: usernameDefaultsKey) ?? ""
        return ServerConfig(kind: kind, baseURL: url, username: username, apiKey: apiKey, displayName: name)
    }

    func save(_ config: ServerConfig) {
        defaults.set(config.baseURL.absoluteString, forKey: urlDefaultsKey)
        defaults.set(config.displayName, forKey: nameDefaultsKey)
        defaults.set(config.kind.rawValue, forKey: kindDefaultsKey)
        defaults.set(config.username, forKey: usernameDefaultsKey)
        writeKey(config.apiKey)
    }

    func clear() {
        defaults.removeObject(forKey: urlDefaultsKey)
        defaults.removeObject(forKey: nameDefaultsKey)
        defaults.removeObject(forKey: kindDefaultsKey)
        defaults.removeObject(forKey: usernameDefaultsKey)
        deleteKey()
    }

    // MARK: - Keychain

    private func readKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeKey(_ value: String) {
        deleteKey()
        var query = baseQuery()
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKey() {
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
