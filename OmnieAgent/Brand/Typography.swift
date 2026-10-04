import SwiftUI

extension Font {
    /// Unbounded, 600–900 weight, for headers and the wordmark only (§3).
    /// Scales with Dynamic Type relative to `textStyle`.
    static func display(_ size: CGFloat, black: Bool = false, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        .custom(black ? "Unbounded-Black" : "Unbounded-Bold", size: size, relativeTo: textStyle)
    }
}

/// The Omnie wordmark: Unbounded, monochrome (§6). The mark beside it may
/// carry the gradient as the one-time flourish; the letters never do.
struct Wordmark: View {
    var size: CGFloat = 28
    var showsMark = true
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack(spacing: size * 0.35) {
            if showsMark {
                Image("OmnieMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: size * 1.1)
                    .foregroundStyle(tokens.text)
                    .accessibilityHidden(true)
            }
            Text("omnie")
                .font(.display(size, black: true))
                .foregroundStyle(tokens.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Omnie")
    }
}
