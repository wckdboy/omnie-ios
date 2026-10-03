import SwiftUI

/// Color tokens from `BRANDING.md` — the shared Omnie brand guide, canonical
/// copy in `omnie-edit`. Two neutral sets exist: "warm" (what people see
/// day to day) and "monochrome" (true black/white, offered as a real
/// selectable theme — see `BrandTheme` — not just a figure of speech).
///
/// These tokens are for Omnie Agent's own custom-drawn surfaces (the
/// backgrounds and headers in `WelcomeView`, `OnboardingView`, etc.).
/// Native system controls (`Form`, `List`, toolbars) are deliberately left
/// to render with their own system materials — "native, not skinned."
enum BrandPalette {
    struct Tokens {
        let background: Color
        let text: Color
        let secondary: Color
        let hairline: Color
    }

    static let warmLight = Tokens(
        background: Color(brandHex: 0xF6F6F4),
        text: Color(brandHex: 0x161616),
        secondary: Color(brandHex: 0x6E6E6A),
        hairline: Color(brandHex: 0xD8D8D4)
    )

    static let warmDark = Tokens(
        background: Color(brandHex: 0x101010),
        text: Color(brandHex: 0xE6E6E3),
        secondary: Color(brandHex: 0x8E8E8A),
        hairline: Color(brandHex: 0x2A2A2A)
    )

    static let monochromeLight = Tokens(
        background: Color(brandHex: 0xFFFFFF),
        text: Color(brandHex: 0x000000),
        secondary: Color(brandHex: 0x6A6A6A),
        hairline: Color(brandHex: 0xE0E0E0)
    )

    static let monochromeDark = Tokens(
        background: Color(brandHex: 0x000000),
        text: Color(brandHex: 0xFFFFFF),
        secondary: Color(brandHex: 0x9A9A9A),
        hairline: Color(brandHex: 0x2A2A2A)
    )

    /// The one accent: purple into orange, diagonal. Reserve it for exactly
    /// one primary action or active/selected item per screen — never as a
    /// background fill, never on more than one element at once.
    static let accentGradient = LinearGradient(
        colors: [Color(brandHex: 0x9E2EDB), Color(brandHex: 0xFA9429)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private extension Color {
    init(brandHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
