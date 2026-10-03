import SwiftUI

/// Chooses between onboarding (no server configured yet) and the main
/// sessions list, based on `AppModel.isConfigured`.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isConfigured {
            SessionsView()
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
