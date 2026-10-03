import SwiftUI

/// First-run setup: point the app at a Hermes Agent gateway's API server.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var urlText: String = "http://"
    @State private var apiKey: String = ""
    @State private var displayName: String = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private enum TestResult {
        case success(String?)
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Omnie Agent")
                        .font(.largeTitle.bold())
                    Text("Connect to a Hermes Agent gateway running on your VPS, home server, or Mac.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 16) {
                    labeledField("Server URL", text: $urlText, placeholder: "http://100.x.x.x:8642")
                        .keyboardType(.URL)
                    labeledField("API Key", text: $apiKey, placeholder: "API_SERVER_KEY value", isSecure: true)
                    labeledField("Name (optional)", text: $displayName, placeholder: "My Hermes Server")
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
                    .disabled(urlText.isEmpty || apiKey.isEmpty || isTesting)

                    Button {
                        save()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(urlText.isEmpty || apiKey.isEmpty)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Run `hermes gateway` with `API_SERVER_ENABLED=true` and an `API_SERVER_KEY` set on your server first.")
                    Text("Use HTTPS if your server is reachable from the public internet.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .padding(24)
        }
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
        let config = ServerConfig(baseURL: url, apiKey: apiKey, displayName: displayName)
        switch await model.testConnection(config) {
        case .success(let name):
            testResult = .success(name)
        case .failure(let error):
            testResult = .failure(error.localizedDescription)
        }
    }

    private func save() {
        guard let url = URL(string: urlText) else { return }
        let name = displayName.isEmpty ? (url.host ?? "Hermes Agent") : displayName
        model.apply(ServerConfig(baseURL: url, apiKey: apiKey, displayName: name))
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel())
}
