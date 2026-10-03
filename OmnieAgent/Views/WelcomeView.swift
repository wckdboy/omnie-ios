import SwiftUI

/// The first screen: choose between running the agent entirely on this
/// iPhone (Apple's on-device model) or connecting to a self-hosted Hermes
/// Agent gateway over Tailscale, a local network, or a public VPS.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrandTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var showRemoteSetup = false
    @State private var showCloudSetup = false
    @State private var localUnavailableMessage: String?

    private var tokens: BrandPalette.Tokens { theme.appearance.tokens(for: colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Omnie Agent")
                            .font(.brandDisplay(34))
                            .foregroundStyle(tokens.text)
                        Text("Run an agent entirely on this iPhone, connect to a Hermes-style agent server, or bring your own cloud provider key.")
                            .foregroundStyle(tokens.secondary)
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            chooseLocal()
                        } label: {
                            optionRow(
                                icon: "iphone.gen3",
                                title: "Run On This iPhone",
                                subtitle: "Apple's on-device model. Works offline, nothing leaves your phone."
                            )
                        }
                        .buttonStyle(.plain)

                        if let localUnavailableMessage {
                            Label(localUnavailableMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            showRemoteSetup = true
                        } label: {
                            optionRow(
                                icon: "server.rack",
                                title: "Connect to a Server",
                                subtitle: "Hermes Agent or OpenCode, over Tailscale, your local network, or a public VPS."
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            showCloudSetup = true
                        } label: {
                            optionRow(
                                icon: "key.fill",
                                title: "Use a Cloud Provider",
                                subtitle: "Bring your own key — DeepSeek, OpenAI, OpenRouter, and most others."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .background(tokens.background)
            .navigationDestination(isPresented: $showRemoteSetup) {
                OnboardingView()
            }
            .navigationDestination(isPresented: $showCloudSetup) {
                CloudProviderSetupView()
            }
        }
    }

    private func chooseLocal() {
        Task {
            if !(await model.enterLocalMode()) {
                localUnavailableMessage = model.localAvailabilityMessage
            }
        }
    }

    @ViewBuilder
    private func optionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(tokens.text)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(tokens.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    WelcomeView()
        .environment(AppModel())
        .environment(BrandTheme())
}
