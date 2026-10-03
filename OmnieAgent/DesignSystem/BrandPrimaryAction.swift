import SwiftUI

extension View {
    /// The brand's primary-action treatment — "gradient fill behind clear
    /// glass for the primary action, plain glass for everything else that
    /// needs the material at all" (`BRANDING.md` §4). Apply to exactly one
    /// control per screen: the create/continue/send action.
    func brandPrimaryAction(in shape: some Shape = .rect(cornerRadius: 14)) -> some View {
        self
            .foregroundStyle(.white)
            .background(BrandPalette.accentGradient, in: shape)
            .glassEffect(.clear, in: shape)
    }
}
