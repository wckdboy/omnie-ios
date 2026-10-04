import SwiftUI

/// Chooses between the mode picker (no mode chosen yet), the on-device
/// agent, or a configured provider's chat UI — session-based providers
/// (Hermes, OpenCode) get the sessions list, OpenAI-compatible ones get a
/// single thread — based on `AppModel.mode` and `providerConfig.transport`.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.mode {
        case .local:
            LocalChatView()
        case .provider:
            if let config = model.providerConfig {
                if config.transport.isSessionBased {
                    SessionsView()
                } else {
                    ProviderChatView()
                }
            } else {
                ProviderSetupView()
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
