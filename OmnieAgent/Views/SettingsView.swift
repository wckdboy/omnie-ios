import SwiftUI

/// Settings for whichever mode is active: edit/test the remote server, the
/// cloud provider, or manage the on-device agent. Either way, lets you
/// switch modes entirely.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrandTheme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    // Remote (Hermes / OpenCode)
    @State private var kind: RemoteBackendKind = .hermes
    @State private var urlText: String = ""
    @State private var username: String = ""
    @State private var apiKey: String = ""
    @State private var displayName: String = ""
    @State private var isTesting = false
    @State private var testMessage: String?

    // Cloud (BYOK)
    @State private var cloudModel: String = ""
    @State private var cloudAPIKey: String = ""
    @State private var isTestingCloud = false
    @State private var cloudTestMessage: String?

    @State private var showSignOutConfirmation = false
    @State private var showModeChangeConfirmation = false

    @State private var mcpURLText: String = ""
    @State private var mcpToken: String = ""
    @State private var isReconnectingMCP = false
    @State private var mcpStatusMessage: String?

    private var canSaveRemote: Bool { !urlText.isEmpty && !apiKey.isEmpty }
    private var canSaveCloud: Bool { !cloudModel.isEmpty && !cloudAPIKey.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                switch model.mode {
                case .remote:
                    remoteSections
                case .local:
                    localSection
                case .cloud:
                    cloudSections
                case nil:
                    EmptyView()
                }

                Section {
                    Picker("Theme", selection: Binding(
                        get: { theme.appearance },
                        set: { theme.appearance = $0 }
                    )) {
                        ForEach(BrandAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Monochrome is true black and white — maximum contrast, minimum chroma.")
                }

                Section {
                    Button("Switch Mode") {
                        showModeChangeConfirmation = true
                    }
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Omnie Agent")
                            .font(.brandDisplay(17))
                        Text("An independent client for self-hosted Hermes-style agent servers, direct cloud providers, and an on-device fallback agent. Not affiliated with or endorsed by Nous Research.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                switch model.mode {
                case .remote:
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { saveRemote() }
                            .disabled(!canSaveRemote)
                    }
                case .cloud:
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { saveCloud() }
                            .disabled(!canSaveCloud)
                    }
                default:
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    if model.mode == .cloud {
                        model.signOutCloud()
                    } else {
                        model.signOut()
                    }
                    dismiss()
                }
            }
            .confirmationDialog("Switch mode?", isPresented: $showModeChangeConfirmation, titleVisibility: .visible) {
                Button("Switch Mode") {
                    model.changeMode()
                    dismiss()
                }
            } message: {
                Text("You can switch back later without losing your server details or on-device conversation.")
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private var remoteSections: some View {
        Section("Server") {
            Picker("Backend", selection: $kind) {
                Text("Hermes Agent").tag(RemoteBackendKind.hermes)
                Text("OpenCode").tag(RemoteBackendKind.opencode)
            }
            .pickerStyle(.segmented)
            TextField("URL", text: $urlText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if kind == .opencode {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $apiKey)
            } else {
                SecureField("API Key", text: $apiKey)
            }
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
    }

    @ViewBuilder
    private var cloudSections: some View {
        Section {
            if let config = model.cloudConfig {
                LabeledContent("Provider", value: config.providerName)
                LabeledContent("Base URL", value: config.baseURL.absoluteString)
            }
            TextField("Model", text: $cloudModel)
            SecureField("API Key", text: $cloudAPIKey)
        } header: {
            Text("Provider")
        } footer: {
            Text("To switch providers entirely, sign out and reconnect from the welcome screen.")
        }

        Section {
            Button {
                Task { await testCloudConnection() }
            } label: {
                HStack {
                    Text("Test Connection")
                    if isTestingCloud {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            if let cloudTestMessage {
                Text(cloudTestMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Button("Clear Conversation", role: .destructive) {
                model.clearCloudConversation()
            }
            .disabled(model.cloudMessages.isEmpty)
            Button("Sign Out", role: .destructive) {
                showSignOutConfirmation = true
            }
        }
    }

    @ViewBuilder
    private var localSection: some View {
        Section("On-Device Agent") {
            Label("Running Apple's on-device model", systemImage: "iphone.gen3")
            if let message = model.localAvailabilityMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button("Clear Conversation", role: .destructive) {
                model.clearLocalConversation()
            }
            .disabled(model.localMessages.isEmpty)
        }

        Section {
            TextField("MCP Server URL", text: $mcpURLText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Bearer Token (optional)", text: $mcpToken)

            Button {
                Task { await reconnectMCP() }
            } label: {
                HStack {
                    Text("Save & Reconnect")
                    if isReconnectingMCP {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(mcpURLText.isEmpty || isReconnectingMCP)

            if !mcpURLText.isEmpty {
                Button("Remove MCP Server", role: .destructive) {
                    removeMCP()
                }
            }

            if let mcpStatusMessage {
                Text(mcpStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("MCP Tools")
        } footer: {
            Text("Gives the on-device agent extra tools from an MCP server, on top of its built-in ones. Hermes-style remote mode manages its own tools and isn't affected by this.")
        }
    }

    private func load() {
        if let config = model.config {
            kind = config.kind
            urlText = config.baseURL.absoluteString
            username = config.username
            apiKey = config.apiKey
            displayName = config.displayName
        }
        if let cloudConfig = model.cloudConfig {
            cloudModel = cloudConfig.model
            cloudAPIKey = cloudConfig.apiKey
        }
        if let mcpConfig = MCPServerConfigStore.shared.current {
            mcpURLText = mcpConfig.endpoint.absoluteString
            mcpToken = mcpConfig.bearerToken
        }
    }

    private func testConnection() async {
        guard let url = URL(string: urlText) else {
            testMessage = "That doesn't look like a valid URL."
            return
        }
        isTesting = true
        defer { isTesting = false }
        let config = ServerConfig(kind: kind, baseURL: url, username: username, apiKey: apiKey, displayName: displayName)
        switch await model.testConnection(config) {
        case .success(let name):
            testMessage = name.map { "Connected · \($0)" } ?? "Connected"
        case .failure(let error):
            testMessage = error.localizedDescription
        }
    }

    private func saveRemote() {
        guard let url = URL(string: urlText) else { return }
        let fallbackName = kind == .hermes ? "Hermes Agent" : "OpenCode"
        let name = displayName.isEmpty ? (url.host ?? fallbackName) : displayName
        model.apply(ServerConfig(kind: kind, baseURL: url, username: username, apiKey: apiKey, displayName: name))
        dismiss()
    }

    private func testCloudConnection() async {
        guard let existing = model.cloudConfig else { return }
        isTestingCloud = true
        defer { isTestingCloud = false }
        let config = CloudProviderConfig(providerID: existing.providerID, providerName: existing.providerName, baseURL: existing.baseURL, model: cloudModel, apiKey: cloudAPIKey)
        switch await model.testCloudConnection(config) {
        case .success:
            cloudTestMessage = "Connected"
        case .failure(let error):
            cloudTestMessage = error.localizedDescription
        }
    }

    private func saveCloud() {
        guard let existing = model.cloudConfig else { return }
        let config = CloudProviderConfig(providerID: existing.providerID, providerName: existing.providerName, baseURL: existing.baseURL, model: cloudModel, apiKey: cloudAPIKey)
        model.applyCloud(config)
        dismiss()
    }

    private func reconnectMCP() async {
        guard let url = URL(string: mcpURLText) else {
            mcpStatusMessage = "That doesn't look like a valid URL."
            return
        }
        isReconnectingMCP = true
        defer { isReconnectingMCP = false }
        MCPServerConfigStore.shared.save(MCPServerConfig(endpoint: url, bearerToken: mcpToken))
        let mcpClient = MCPClient(endpoint: url, bearerToken: mcpToken)
        do {
            let tools = try await mcpClient.listTools()
            mcpStatusMessage = tools.isEmpty
                ? "Connected — the server reported no tools."
                : "Connected — \(tools.count) tool\(tools.count == 1 ? "" : "s"): \(tools.map(\.name).joined(separator: ", "))."
            await model.reloadLocalTools()
        } catch {
            mcpStatusMessage = error.localizedDescription
        }
    }

    private func removeMCP() {
        MCPServerConfigStore.shared.clear()
        mcpURLText = ""
        mcpToken = ""
        mcpStatusMessage = nil
        Task { await model.reloadLocalTools() }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .environment(BrandTheme())
}
