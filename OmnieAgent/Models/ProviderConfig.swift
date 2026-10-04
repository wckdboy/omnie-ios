import Foundation
import Security

/// Everything needed to reach one configured provider — a self-hosted
/// agent server (Hermes, OpenCode) or a direct BYOK cloud provider — in one
/// shape, regardless of `transport`.
///
/// - `username` is only meaningful for `.opencode` (HTTP Basic auth);
///   `apiKey` doubles as the Basic-auth password there, and the Settings UI
///   shows a single "API Key" field for it like everything else.
/// - `model` is only meaningful for `.openAICompatible`; session-based
///   transports pick their model server-side.
struct ProviderConfig: Equatable {
    var presetID: String
    var providerName: String
    var transport: ProviderTransport
    var baseURL: URL
    var username: String = ""
    var apiKey: String
    var model: String = ""
    var displayName: String = ""
}

/// Persists everything but the secret in `UserDefaults`, and the secret
/// (API key, or the OpenCode Basic-auth password) in the Keychain.
@MainActor
final class ProviderConfigStore {
    static let shared = ProviderConfigStore()

    private let defaults = UserDefaults.standard
    private let presetIDKey = "omnie.provider.presetID"
    private let providerNameKey = "omnie.provider.providerName"
    private let transportKey = "omnie.provider.transport"
    private let baseURLKey = "omnie.provider.baseURL"
    private let usernameKey = "omnie.provider.username"
    private let modelKey = "omnie.provider.model"
    private let displayNameKey = "omnie.provider.displayName"
    private let keychainService = "com.omnieagent.provider"
    private let keychainAccount = "api-key"

    private init() {}

    var current: ProviderConfig? {
        guard let presetID = defaults.string(forKey: presetIDKey),
              let transportRaw = defaults.string(forKey: transportKey),
              let transport = ProviderTransport(rawValue: transportRaw),
              let urlString = defaults.string(forKey: baseURLKey),
              let url = URL(string: urlString),
              let apiKey = readKey(), !apiKey.isEmpty else {
            return nil
        }
        let providerName = defaults.string(forKey: providerNameKey) ?? presetID
        return ProviderConfig(
            presetID: presetID,
            providerName: providerName,
            transport: transport,
            baseURL: url,
            username: defaults.string(forKey: usernameKey) ?? "",
            apiKey: apiKey,
            model: defaults.string(forKey: modelKey) ?? "",
            displayName: defaults.string(forKey: displayNameKey) ?? providerName
        )
    }

    func save(_ config: ProviderConfig) {
        defaults.set(config.presetID, forKey: presetIDKey)
        defaults.set(config.providerName, forKey: providerNameKey)
        defaults.set(config.transport.rawValue, forKey: transportKey)
        defaults.set(config.baseURL.absoluteString, forKey: baseURLKey)
        defaults.set(config.username, forKey: usernameKey)
        defaults.set(config.model, forKey: modelKey)
        defaults.set(config.displayName, forKey: displayNameKey)
        writeKey(config.apiKey)
    }

    func clear() {
        defaults.removeObject(forKey: presetIDKey)
        defaults.removeObject(forKey: providerNameKey)
        defaults.removeObject(forKey: transportKey)
        defaults.removeObject(forKey: baseURLKey)
        defaults.removeObject(forKey: usernameKey)
        defaults.removeObject(forKey: modelKey)
        defaults.removeObject(forKey: displayNameKey)
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
