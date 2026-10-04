import SwiftUI

extension View {
    /// Gradient fill behind clear glass (§4). Exactly one per screen.
    func primaryAction(in shape: some Shape = Capsule()) -> some View {
        self
            .foregroundStyle(.white)
            .background(Palette.accent, in: shape)
            .glassEffect(.clear.interactive(), in: shape)
    }

    /// Hairline-bordered surface for cards in the content layer (no glass).
    func card(_ tokens: Palette.Tokens, radius: CGFloat = 16) -> some View {
        self
            .background(tokens.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(tokens.hairline, lineWidth: 0.5))
    }
}

/// Section header in the content layer: small caps, secondary color.
struct SectionLabel: View {
    let text: String
    @Environment(\.tokens) private var tokens

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(tokens.secondary)
    }
}

/// A large header in Unbounded, for screen titles that aren't nav bars.
struct DisplayTitle: View {
    let text: String
    var size: CGFloat = 30
    @Environment(\.tokens) private var tokens

    init(_ text: String, size: CGFloat = 30) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.display(size))
            .foregroundStyle(tokens.text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Connection status dot. Uses semantic colors, never the accent.
struct StatusDot: View {
    enum State { case online, connecting, offline, unknown }
    let state: State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch state {
        case .online: Palette.Semantic.success
        case .connecting: Palette.Semantic.warning
        case .offline: Palette.Semantic.danger
        case .unknown: .gray
        }
    }

    private var label: String {
        switch state {
        case .online: "Online"
        case .connecting: "Connecting"
        case .offline: "Offline"
        case .unknown: "Unknown"
        }
    }
}

/// Inline, non-modal notice (§4: no modals for things that aren't decisions).
struct InlineNotice: View {
    let text: String
    var systemImage = "exclamationmark.triangle"
    var tone: Color = Palette.Semantic.danger
    @Environment(\.tokens) private var tokens

    var body: some View {
        Label {
            Text(text).font(.footnote).foregroundStyle(tokens.text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tone)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, radius: 12)
    }
}
