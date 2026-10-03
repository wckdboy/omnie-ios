import Foundation

/// Which backend is powering the current conversation: Apple's on-device
/// model, a remote Hermes-style agent gateway (Hermes Agent or OpenCode),
/// or a directly-configured cloud provider (BYOK).
enum AppMode: String, Codable {
    case local
    case remote
    case cloud
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
