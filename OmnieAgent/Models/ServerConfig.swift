import Foundation
import Security

/// Everything needed to reach a Hermes Agent gateway: its base URL, the bearer
/// token for the API server, and a friendly name shown in the UI.
struct ServerConfig: Equatable {
    var baseURL: URL
    var apiKey: String
    var displayName: String
}

/// Persists the server URL and display name in `UserDefaults`, and the API key
/// in the Keychain since it's a secret. Everything funnels through `current`,
/// `save`, and `clear` so the rest of the app never touches Keychain APIs directly.
@MainActor
final class ServerConfigStore {
    static let shared = ServerConfigStore()

    private let defaults = UserDefaults.standard
    private let urlDefaultsKey = "omnie.server.url"
    private let nameDefaultsKey = "omnie.server.name"
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
        return ServerConfig(baseURL: url, apiKey: apiKey, displayName: name)
    }

    func save(_ config: ServerConfig) {
        defaults.set(config.baseURL.absoluteString, forKey: urlDefaultsKey)
        defaults.set(config.displayName, forKey: nameDefaultsKey)
        writeKey(config.apiKey)
    }

    func clear() {
        defaults.removeObject(forKey: urlDefaultsKey)
        defaults.removeObject(forKey: nameDefaultsKey)
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
