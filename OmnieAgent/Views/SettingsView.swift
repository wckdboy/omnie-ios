import SwiftUI

/// Edit the configured server, re-test the connection, or sign out.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var apiKey: String = ""
    @State private var displayName: String = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("URL", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                    TextField("Name", text: $displayName)
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if isTesting {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    if let testMessage {
                        Text(testMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Omnie Agent")
                            .font(.headline)
                        Text("An independent client for self-hosted Hermes Agent gateways. Not affiliated with or endorsed by Nous Research.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(urlText.isEmpty || apiKey.isEmpty)
                }
            }
            .confirmationDialog("Sign out of this server?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    model.signOut()
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let config = model.config else { return }
        urlText = config.baseURL.absoluteString
        apiKey = config.apiKey
        displayName = config.displayName
    }

    private func testConnection() async {
        guard let url = URL(string: urlText) else {
            testMessage = "That doesn't look like a valid URL."
            return
        }
        isTesting = true
        defer { isTesting = false }
        let config = ServerConfig(baseURL: url, apiKey: apiKey, displayName: displayName)
        switch await model.testConnection(config) {
        case .success(let name):
            testMessage = name.map { "Connected · \($0)" } ?? "Connected"
        case .failure(let error):
            testMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let url = URL(string: urlText) else { return }
        let name = displayName.isEmpty ? (url.host ?? "Hermes Agent") : displayName
        model.apply(ServerConfig(baseURL: url, apiKey: apiKey, displayName: name))
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
