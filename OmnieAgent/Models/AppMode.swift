import Foundation

/// Which backend is powering the current conversation: Apple's on-device
/// model, or a configured provider (a Hermes-style agent server, or a
/// direct BYOK cloud provider — see `ProviderTransport` for which).
enum AppMode: String, Codable {
    case local
    case provider
}

/// Persists the chosen mode across launches in `UserDefaults`.
@MainActor
final class AppModeStore {
    static let shared = AppModeStore()

    private let defaults = UserDefaults.standard
    private let key = "omnie.mode"

    private init() {}

    var current: AppMode? {
        defaults.string(forKey: key).flatMap(AppMode.init(rawValue:))
    }

    func save(_ mode: AppMode?) {
        if let mode {
            defaults.set(mode.rawValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
