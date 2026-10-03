import SwiftUI

/// Settings for whichever mode is active: edit/test the remote server, or
/// manage the on-device agent. Either way, lets you switch modes entirely.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var urlText: String = ""
    @State private var apiKey: String = ""
    @State private var displayName: String = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var showSignOutConfirmation = false
    @State private var showModeChangeConfirmation = false

    @State private var mcpURLText: String = ""
    @State private var mcpToken: String = ""
    @State private var isReconnectingMCP = false
    @State private var mcpStatusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if model.mode == .remote {
                    remoteSections
                } else if model.mode == .local {
                    localSection
                }

                Section {
                    Button("Switch Mode") {
                        showModeChangeConfirmation = true
                    }
                }

                Section("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Omnie Agent")
                            .font(.headline)
                        Text("An independent client for self-hosted Hermes Agent gateways, with an on-device fallback agent. Not affiliated with or endorsed by Nous Research.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.mode == .remote {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .disabled(urlText.isEmpty || apiKey.isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .confirmationDialog("Sign out of this server?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    model.signOut()
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
            urlText = config.baseURL.absoluteString
            apiKey = config.apiKey
            displayName = config.displayName
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
}
