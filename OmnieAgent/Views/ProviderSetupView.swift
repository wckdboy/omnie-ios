import SwiftUI

/// One setup screen for every provider: self-hosted Hermes-style agent
/// servers (Hermes Agent, OpenCode) and direct BYOK cloud providers
/// (DeepSeek, OpenAI, and the rest of the catalog). Fields show or hide
/// based on the selected preset's transport — session-based servers don't
/// need a model field, OpenAI-compatible ones do.
struct ProviderSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrandTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedPresetID = "hermes"
    @State private var baseURLText = AIProviderCatalog.preset(withID: "hermes")!.baseURL.absoluteString
    @State private var modelText = ""
    @State private var apiKey = ""
    @State private var displayName = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private enum TestResult {
        case success(String?)
        case failure(String)
    }

    private var tokens: BrandPalette.Tokens { theme.appearance.tokens(for: colorScheme) }

    private var selectedPreset: AIProviderPreset {
        AIProviderCatalog.preset(withID: selectedPresetID) ?? AIProviderCatalog.agentServers[0]
    }

    private var needsModelField: Bool {
        selectedPreset.transport == .openAICompatible
    }

    private var canContinue: Bool {
        guard URL(string: baseURLText) != nil, !apiKey.isEmpty else { return false }
        return !needsModelField || !modelText.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect to a Provider")
                        .font(.brandDisplay(28))
                        .foregroundStyle(tokens.text)
                    Text("A self-hosted Hermes-style agent server, or your own API key for a cloud provider — either way, nothing goes through an Omnie-run server.")
                        .foregroundStyle(tokens.secondary)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.caption)
                        .foregroundStyle(tokens.secondary)
                    Picker("Provider", selection: $selectedPresetID) {
                        Section("Agent Servers") {
                            ForEach(AIProviderCatalog.agentServers) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                        Section("Cloud Providers") {
                            ForEach(AIProviderCatalog.cloudPresets) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                        Section {
                            Text(AIProviderPreset.custom.name).tag(AIProviderPreset.custom.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(tokens.text)
                    .onChange(of: selectedPresetID) { _, newValue in
                        applyPreset(newValue)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 16) {
                    labeledField(
                        selectedPreset.transport.isSessionBased ? "Server URL" : "Base URL",
                        text: $baseURLText,
                        placeholder: selectedPreset.baseURL.absoluteString
                    )
                    .keyboardType(.URL)

                    if needsModelField {
                        labeledField("Model", text: $modelText, placeholder: selectedPreset.modelPlaceholder)
                    }

                    labeledField(
                        "API Key",
                        text: $apiKey,
                        placeholder: apiKeyPlaceholder,
                        isSecure: true
                    )

                    labeledField("Name (optional)", text: $displayName, placeholder: selectedPreset.name)
                }

                if let testResult {
                    resultBanner(testResult)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView().controlSize(.small)
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
                    switch selectedPreset.id {
                    case "hermes":
                        Text("Run `hermes gateway` with `API_SERVER_ENABLED=true` and an `API_SERVER_KEY` set on your server first.")
                    case "opencode":
                        Text("Run `opencode serve` with `OPENCODE_SERVER_PASSWORD` set on your server first — the default port is 4096. Use that password as the API Key here.")
                    default:
                        Text("Your key is sent directly to \(selectedPreset.name) — never through an Omnie-run server.")
                    }
                    if selectedPreset.transport.isSessionBased {
                        Text("On a Tailscale network, use the device's 100.x.x.x address or MagicDNS name.")
                        Text("Connecting directly over Wi-Fi may prompt you to allow local network access — tap Allow.")
                        Text("Use HTTPS if your server is reachable from the public internet.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(tokens.secondary)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .background(tokens.background)
        .scrollDismissesKeyboard(.interactively)
    }

    private var apiKeyPlaceholder: String {
        switch selectedPreset.id {
        case "hermes": return "API_SERVER_KEY value"
        case "opencode": return "OPENCODE_SERVER_PASSWORD value"
        default: return "sk-…"
        }
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(tokens.secondary)
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

    private func applyPreset(_ id: String) {
        guard let preset = AIProviderCatalog.preset(withID: id) else { return }
        if preset.transport.isSessionBased || preset.id != AIProviderPreset.custom.id {
            baseURLText = preset.baseURL.absoluteString
        }
        modelText = preset.defaultModel ?? ""
        testResult = nil
    }

    private func currentConfig() -> ProviderConfig? {
        guard let url = URL(string: baseURLText) else { return nil }
        let name = displayName.isEmpty ? selectedPreset.name : displayName
        return ProviderConfig(
            presetID: selectedPreset.id,
            providerName: selectedPreset.name,
            transport: selectedPreset.transport,
            baseURL: url,
            apiKey: apiKey,
            model: modelText,
            displayName: name
        )
    }

    private func test() async {
        guard let config = currentConfig() else {
            testResult = .failure("That doesn't look like a valid URL.")
            return
        }
        isTesting = true
        defer { isTesting = false }
        switch await model.testProviderConnection(config) {
        case .success(let name):
            testResult = .success(name)
        case .failure(let error):
            testResult = .failure(error.localizedDescription)
        }
    }

    private func save() {
        guard let config = currentConfig() else { return }
        model.applyProvider(config)
    }
}

#Preview {
    ProviderSetupView()
        .environment(AppModel())
        .environment(BrandTheme())
}
