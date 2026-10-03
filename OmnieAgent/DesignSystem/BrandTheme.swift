import SwiftUI
import Observation

/// Which neutral set is active: `default` (warm) or `monochrome` (true
/// black/white). `BRANDING.md` calls for monochrome to ship "as a real,
/// selectable theme, not just a figure of speech" — this is that switch.
enum BrandAppearance: String, Codable, CaseIterable, Identifiable {
    case `default`
    case monochrome

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: return "Default"
        case .monochrome: return "Monochrome"
        }
    }

    func tokens(for colorScheme: ColorScheme) -> BrandPalette.Tokens {
        switch (self, colorScheme) {
        case (.default, .dark):
            return BrandPalette.warmDark
        case (.default, _):
            return BrandPalette.warmLight
        case (.monochrome, .dark):
            return BrandPalette.monochromeDark
        case (.monochrome, _):
            return BrandPalette.monochromeLight
        }
    }
}

/// Persists the chosen appearance and is injected once into the environment
/// by `OmnieAgentApp`, the same way `AppModel` is.
@MainActor
@Observable
final class BrandTheme {
    var appearance: BrandAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.key) }
    }

    private static let key = "omnie.brand.appearance"

    init() {
        appearance = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(BrandAppearance.init(rawValue:)) ?? .default
    }
}
