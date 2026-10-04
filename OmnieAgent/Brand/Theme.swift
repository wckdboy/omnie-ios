import SwiftUI
import Observation

/// Which neutral set is active. `BRANDING.md` asks for monochrome to ship
/// as a real, selectable theme.
enum Appearance: String, Codable, CaseIterable, Identifiable {
    case warm
    case monochrome

    var id: String { rawValue }

    var label: String {
        switch self {
        case .warm: "Default"
        case .monochrome: "Monochrome"
        }
    }

    func tokens(for scheme: ColorScheme) -> Palette.Tokens {
        switch (self, scheme) {
        case (.warm, .dark): Palette.warmDark
        case (.warm, _): Palette.warmLight
        case (.monochrome, .dark): Palette.monochromeDark
        case (.monochrome, _): Palette.monochromeLight
        }
    }
}

/// Light / dark / follow-system, independent of the neutral set.
enum SchemePreference: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@Observable
final class Theme {
    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "omnie.appearance") }
    }
    var scheme: SchemePreference {
        didSet { UserDefaults.standard.set(scheme.rawValue, forKey: "omnie.scheme") }
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = defaults.string(forKey: "omnie.appearance").flatMap(Appearance.init(rawValue:)) ?? .warm
        scheme = defaults.string(forKey: "omnie.scheme").flatMap(SchemePreference.init(rawValue:)) ?? .system
    }
}

extension EnvironmentValues {
    /// The resolved neutral tokens for the current appearance + color scheme.
    @Entry var tokens: Palette.Tokens = Palette.warmLight
}

/// Resolves `tokens` from the theme and the live color scheme, and paints
/// the window background. Applied once at the root.
struct ThemeRoot: ViewModifier {
    @Environment(Theme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let tokens = theme.appearance.tokens(for: colorScheme)
        content
            .environment(\.tokens, tokens)
            .tint(tokens.text)
            .background(tokens.background.ignoresSafeArea())
    }
}
