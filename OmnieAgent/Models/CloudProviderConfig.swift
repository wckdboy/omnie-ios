import Foundation
import Security

/// A user-supplied ("BYOK") connection to an OpenAI-compatible cloud
/// provider: which preset it came from (for display/re-editing), the actual
/// base URL and model (editable even after picking a preset), and the key.
struct CloudProviderConfig: Equatable {
    var providerID: String
    var providerName: String
    var baseURL: URL
    var model: String
    var apiKey: String
}

/// Persists everything but the key in `UserDefaults`, and the key in the
/// Keychain — the same split as `ServerConfigStore` and `MCPServerConfigStore`.
@MainActor
final class CloudProviderConfigStore {
    static let shared = CloudProviderConfigStore()

    private let defaults = UserDefaults.standard
    private let providerIDKey = "omnie.cloud.providerID"
    private let providerNameKey = "omnie.cloud.providerName"
    private let baseURLKey = "omnie.cloud.baseURL"
    private let modelKey = "omnie.cloud.model"
    private let keychainService = "com.omnieagent.cloud"
    private let keychainAccount = "api-key"

    private init() {}

    var current: CloudProviderConfig? {
        guard let providerID = defaults.string(forKey: providerIDKey),
              let urlString = defaults.string(forKey: baseURLKey),
              let url = URL(string: urlString),
              let model = defaults.string(forKey: modelKey), !model.isEmpty,
              let apiKey = readKey(), !apiKey.isEmpty else {
            return nil
        }
        let name = defaults.string(forKey: providerNameKey) ?? providerID
        return CloudProviderConfig(providerID: providerID, providerName: name, baseURL: url, model: model, apiKey: apiKey)
    }

    func save(_ config: CloudProviderConfig) {
        defaults.set(config.providerID, forKey: providerIDKey)
        defaults.set(config.providerName, forKey: providerNameKey)
        defaults.set(config.baseURL.absoluteString, forKey: baseURLKey)
        defaults.set(config.model, forKey: modelKey)
        writeKey(config.apiKey)
    }

    func clear() {
        defaults.removeObject(forKey: providerIDKey)
        defaults.removeObject(forKey: providerNameKey)
        defaults.removeObject(forKey: baseURLKey)
        defaults.removeObject(forKey: modelKey)
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
