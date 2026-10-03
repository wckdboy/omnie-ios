import SwiftUI

/// Bring-your-own-key setup for a direct cloud provider connection: pick a
/// known provider (or "Custom" for anything else OpenAI-compatible), then
/// supply the model and API key.
struct CloudProviderSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrandTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedPresetID = AIProviderCatalog.presets[0].id
    @State private var baseURLText = AIProviderCatalog.presets[0].baseURL.absoluteString
    @State private var modelText = AIProviderCatalog.presets[0].defaultModel ?? ""
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private enum TestResult {
        case success
        case failure(String)
    }

    private var tokens: BrandPalette.Tokens { theme.appearance.tokens(for: colorScheme) }

    private var selectedPreset: AIProviderPreset {
        AIProviderCatalog.preset(withID: selectedPresetID) ?? AIProviderCatalog.presets[0]
    }

    private var canContinue: Bool {
        !modelText.isEmpty && !apiKey.isEmpty && URL(string: baseURLText) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use a Cloud Provider")
                        .font(.brandDisplay(28))
                        .foregroundStyle(tokens.text)
                    Text("Bring your own API key for DeepSeek, OpenAI, or any other OpenAI-compatible provider. The key stays in this device's Keychain and goes straight to the provider — never through an Omnie-run server.")
                        .foregroundStyle(tokens.secondary)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provider")
                            .font(.caption)
                            .foregroundStyle(tokens.secondary)
                        Picker("Provider", selection: $selectedPresetID) {
                            ForEach(AIProviderCatalog.all) { preset in
                                Text(preset.name).tag(preset.id)
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

                    labeledField("Base URL", text: $baseURLText, placeholder: "https://api.example.com/v1")
                        .keyboardType(.URL)
                    labeledField("Model", text: $modelText, placeholder: selectedPreset.modelPlaceholder)
                    labeledField("API Key", text: $apiKey, placeholder: "sk-…", isSecure: true)
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
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func applyPreset(_ id: String) {
        guard let preset = AIProviderCatalog.preset(withID: id) else { return }
        if preset.id != AIProviderPreset.custom.id {
            baseURLText = preset.baseURL.absoluteString
        }
        modelText = preset.defaultModel ?? ""
        testResult = nil
    }

    private func test() async {
        guard let url = URL(string: baseURLText) else { return }
        isTesting = true
        defer { isTesting = false }
        let config = CloudProviderConfig(providerID: selectedPreset.id, providerName: selectedPreset.name, baseURL: url, model: modelText, apiKey: apiKey)
        switch await model.testCloudConnection(config) {
        case .success:
            testResult = .success
        case .failure(let error):
            testResult = .failure(error.localizedDescription)
        }
    }

    private func save() {
        guard let url = URL(string: baseURLText) else { return }
        let config = CloudProviderConfig(providerID: selectedPreset.id, providerName: selectedPreset.name, baseURL: url, model: modelText, apiKey: apiKey)
        model.applyCloud(config)
    }
}

#Preview {
    CloudProviderSetupView()
        .environment(AppModel())
        .environment(BrandTheme())
}
