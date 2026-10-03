import SwiftUI

/// Chooses between the mode picker (no mode chosen yet), the on-device
/// agent, or the remote sessions list, based on `AppModel.mode`.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.mode {
        case .local:
            LocalChatView()
        case .remote:
            if model.isConfigured {
                SessionsView()
            } else {
                OnboardingView()
            }
        case .cloud:
            if model.cloudConfig != nil {
                CloudChatView()
            } else {
                CloudProviderSetupView()
            }
        case nil:
            WelcomeView()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
        .environment(BrandTheme())
}
