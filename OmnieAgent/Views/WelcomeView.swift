import SwiftUI

/// The first screen: choose between running the agent entirely on this
/// iPhone (Apple's on-device model) or connecting to a self-hosted Hermes
/// Agent gateway over Tailscale, a local network, or a public VPS.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showRemoteSetup = false
    @State private var localUnavailableMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Omnie Agent")
                            .font(.largeTitle.bold())
                        Text("Run an agent entirely on this iPhone, or connect to a Hermes Agent gateway on your VPS, home server, or Mac.")
                            .foregroundStyle(.secondary)
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
                                subtitle: "Hermes Agent over Tailscale, your local network, or a public VPS."
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .navigationDestination(isPresented: $showRemoteSetup) {
                OnboardingView()
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
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
}
