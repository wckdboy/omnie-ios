import Foundation

/// Which backend is powering the current conversation: Apple's on-device
/// model, or a remote Hermes Agent gateway.
enum AppMode: String, Codable {
    case local
    case remote
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
