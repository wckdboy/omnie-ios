import SwiftUI

extension Font {
    /// The brand's display/header font — Unbounded, 600–900 weight per
    /// `BRANDING.md` ("lighter weights read weak at display size"). Reserved
    /// for headers, the wordmark, and marketing-ish surfaces; body text
    /// stays on the system font everywhere else.
    static func brandDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        switch weight {
        case .black, .heavy:
            return .custom("Unbounded-Black", size: size)
        default:
            return .custom("Unbounded-Bold", size: size)
        }
    }
}
