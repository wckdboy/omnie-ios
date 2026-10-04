import SwiftUI

/// Color tokens from `BRANDING.md` §2. Two neutral sets: warm (default) and
/// true monochrome (a real, selectable theme). The gradient is the only
/// accent — one element per screen carries it.
enum Palette {
    struct Tokens {
        let background: Color
        let surface: Color
        let text: Color
        let secondary: Color
        let hairline: Color
    }

    static let warmLight = Tokens(
        background: Color(hex: 0xF6F6F4),
        surface: Color(hex: 0xFFFFFF),
        text: Color(hex: 0x161616),
        secondary: Color(hex: 0x6E6E6A),
        hairline: Color(hex: 0xD8D8D4)
    )

    static let warmDark = Tokens(
        background: Color(hex: 0x101010),
        surface: Color(hex: 0x1A1A1A),
        text: Color(hex: 0xE6E6E3),
        secondary: Color(hex: 0x8E8E8A),
        hairline: Color(hex: 0x2A2A2A)
    )

    static let monochromeLight = Tokens(
        background: Color(hex: 0xFFFFFF),
        surface: Color(hex: 0xF4F4F4),
        text: Color(hex: 0x000000),
        secondary: Color(hex: 0x6A6A6A),
        hairline: Color(hex: 0xE0E0E0)
    )

    static let monochromeDark = Tokens(
        background: Color(hex: 0x000000),
        surface: Color(hex: 0x0E0E0E),
        text: Color(hex: 0xFFFFFF),
        secondary: Color(hex: 0x9A9A9A),
        hairline: Color(hex: 0x2A2A2A)
    )

    static let purple = Color(hex: 0x9E2EDB)
    static let orange = Color(hex: 0xFA9429)

    /// Purple into orange, top-leading → bottom-trailing (§2.2).
    static let accent = LinearGradient(
        colors: [purple, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// App-level semantic colors (§2.3): desaturated, never a third brand
    /// color. Used for diff lines, error text and status dots only.
    enum Semantic {
        static let success = Color(hex: 0x5E8C61)
        static let warning = Color(hex: 0xB08A3E)
        static let danger = Color(hex: 0xB0524A)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
