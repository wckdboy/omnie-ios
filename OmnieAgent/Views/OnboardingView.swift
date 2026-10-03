import SwiftUI

/// Point the app at a Hermes-style agent server — Hermes Agent itself or an
/// OpenCode server — reached over Tailscale, a local network, or a public
/// VPS address.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrandTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var kind: RemoteBackendKind = .hermes
    @State private var urlText: String = "http://"
    @State private var username: String = "opencode"
    @State private var apiKey: String = ""
    @State private var displayName: String = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private var canContinue: Bool {
        !urlText.isEmpty && !apiKey.isEmpty
    }

    private enum TestResult {
        case success(String?)
        case failure(String)
    }

    private var tokens: BrandPalette.Tokens { theme.appearance.tokens(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect to a Server")
                        .font(.brandDisplay(28))
                        .foregroundStyle(tokens.text)
                    Text("Works with a Hermes Agent gateway reached over Tailscale, your local Wi-Fi, or a public VPS address.")
                        .foregroundStyle(tokens.secondary)
                }
                .padding(.top, 8)

                Picker("Backend", selection: $kind) {
                    Text("Hermes Agent").tag(RemoteBackendKind.hermes)
                    Text("OpenCode").tag(RemoteBackendKind.opencode)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 16) {
                    labeledField("Server URL", text: $urlText, placeholder: kind == .hermes ? "http://100.x.x.x:8642" : "http://100.x.x.x:4096")
                        .keyboardType(.URL)
                    if kind == .opencode {
                        labeledField("Username", text: $username, placeholder: "opencode")
                        labeledField("Password", text: $apiKey, placeholder: "OPENCODE_SERVER_PASSWORD value", isSecure: true)
                    } else {
                        labeledField("API Key", text: $apiKey, placeholder: "API_SERVER_KEY value", isSecure: true)
                    }
                    labeledField("Name (optional)", text: $displayName, placeholder: kind == .hermes ? "My Hermes Server" : "My OpenCode Server")
                }

                if let testResult {
                    resultBanner(testResult)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isTesting ? "Testing…" : "Test Connection")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(!canContinue || isTesting)

                    Button {
                        save()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .brandPrimaryAction(in: .capsule)
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.5)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if kind == .hermes {
                        Text("Run `hermes gateway` with `API_SERVER_ENABLED=true` and an `API_SERVER_KEY` set on your server first.")
                    } else {
                        Text("Run `opencode serve` with `OPENCODE_SERVER_PASSWORD` set on your server first — the default port is 4096.")
                    }
                    Text("On a Tailscale network, use the device's 100.x.x.x address or MagicDNS name (e.g. `http://my-server:8642`).")
                    Text("Connecting directly over Wi-Fi may prompt you to allow local network access — tap Allow.")
                    Text("Use HTTPS if your server is reachable from the public internet.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .background(tokens.background)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func resultBanner(_ result: TestResult) -> some View {
        switch result {
        case .success(let name):
            Label(name.map { "Connected · \($0)" } ?? "Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func testConnection() async {
        guard let url = URL(string: urlText) else {
            testResult = .failure("That doesn't look like a valid URL.")
            return
        }
        isTesting = true
        defer { isTesting = false }
        let config = ServerConfig(kind: kind, baseURL: url, username: username, apiKey: apiKey, displayName: displayName)
        switch await model.testConnection(config) {
        case .success(let name):
            testResult = .success(name)
        case .failure(let error):
            testResult = .failure(error.localizedDescription)
        }
    }

    private func save() {
        guard let url = URL(string: urlText) else { return }
        let fallbackName = kind == .hermes ? "Hermes Agent" : "OpenCode"
        let name = displayName.isEmpty ? (url.host ?? fallbackName) : displayName
        model.apply(ServerConfig(kind: kind, baseURL: url, username: username, apiKey: apiKey, displayName: name))
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel())
        .environment(BrandTheme())
}
