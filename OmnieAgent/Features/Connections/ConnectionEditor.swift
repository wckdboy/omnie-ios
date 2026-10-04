import SwiftUI

/// Add or edit an agent. "Test" probes the server with the entered details
/// before anything is saved.
struct ConnectionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tokens) private var tokens

    @State var draft: Connection
    @State var secret: String
    let isNew: Bool

    @State private var testing = false
    @State private var result: TestResult?
    @State private var showAdvanced = false
    @State private var confirmDelete = false

    enum TestResult: Equatable {
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $draft.kind) {
                        Text("Dashboard").tag(ConnectionKind.dashboard)
                        Text("Gateway").tag(ConnectionKind.gateway)
                        Text("OpenAI API").tag(ConnectionKind.openAI)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(draft.kind.summary)
                }

                Section("Server") {
                    TextField("Name", text: $draft.name, prompt: Text("Studio Mac"))
                        .textInputAutocapitalization(.words)
                    TextField("Address", text: $draft.baseURL, prompt: Text(addressPlaceholder))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if draft.kind != .openAI {
                        TextField("Profile", text: $draft.profile, prompt: Text("default"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    switch draft.kind {
                    case .dashboard:
                        TextField("Username", text: $draft.username, prompt: Text("Username"))
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField(draft.username.isEmpty ? "Session token" : "Password", text: $secret)
                            .textContentType(.password)
                    case .gateway:
                        SecureField("API_SERVER_KEY", text: $secret)
                    case .openAI:
                        SecureField("API key", text: $secret, prompt: Text("Optional for local servers"))
                        TextField("Model", text: $draft.model, prompt: Text("Server default"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Sign in")
                } footer: {
                    Text(authFooter)
                }

                if draft.kind == .dashboard {
                    Section {
                        DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                            TextField("Auth provider", text: $draft.authProvider, prompt: Text("basic"))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(!canSave || testing)
                    if let result {
                        switch result {
                        case .success(let text):
                            Label(text, systemImage: "checkmark.circle")
                                .foregroundStyle(Palette.Semantic.success)
                                .font(.footnote)
                        case .failure(let text):
                            Label(text, systemImage: "xmark.circle")
                                .foregroundStyle(Palette.Semantic.danger)
                                .font(.footnote)
                        }
                    }
                }

                Section {
                    SetupHelp(kind: draft.kind)
                }

                if !isNew {
                    Section {
                        Button("Remove Agent", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(tokens.background)
            .navigationTitle(isNew ? "Add Agent" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Remove \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let saved = model.connections.first(where: { $0.id == draft.id }) { model.remove(saved) }
                    dismiss()
                }
            } message: {
                Text("Conversations stay on the agent. On-device history for OpenAI-compatible agents is deleted.")
            }
            .onChange(of: draft.kind) { _, _ in result = nil }
        }
    }

    private var addressPlaceholder: String {
        switch draft.kind {
        case .dashboard: "studio.local:9119"
        case .gateway: "192.168.1.20:8642"
        case .openAI: "https://api.example.com/v1"
        }
    }

    private var authFooter: String {
        switch draft.kind {
        case .dashboard:
            "Use the dashboard's basic-auth user (HERMES_DASHBOARD_BASIC_AUTH_USERNAME). Leave the username empty to paste a session token instead, for SSH-tunnelled setups."
        case .gateway:
            "The API_SERVER_KEY from the agent's .env. Stored in the Keychain on this iPhone."
        case .openAI:
            "Stored in the Keychain on this iPhone."
        }
    }

    private var canSave: Bool {
        Connection.normalize(draft.baseURL) != nil
            && (draft.kind == .openAI || !secret.isEmpty)
    }

    private func normalized() -> Connection {
        var connection = draft
        if let url = Connection.normalize(draft.baseURL, defaultPort: draft.kind.defaultPort) {
            connection.baseURL = url.absoluteString
        }
        connection.name = draft.name.trimmingCharacters(in: .whitespaces)
        if connection.name.isEmpty { connection.name = connection.url?.host ?? draft.kind.title }
        connection.profile = draft.profile.trimmingCharacters(in: .whitespaces)
        connection.username = draft.username.trimmingCharacters(in: .whitespaces)
        if connection.authProvider.trimmingCharacters(in: .whitespaces).isEmpty { connection.authProvider = "basic" }
        return connection
    }

    private func test() async {
        testing = true
        result = nil
        defer { testing = false }
        let connection = normalized()
        draft.baseURL = connection.baseURL
        let backend = AgentConnection.makeBackend(connection, secret: secret)
        do {
            let info = try await backend.probe()
            var text = "Connected to \(info.name)"
            if let version = info.version, version != "unknown" { text += " \(version)" }
            if let model = info.model, model != info.name { text += " · \(model)" }
            result = .success(text)
            Haptics.success()
        } catch {
            result = .failure(error.localizedDescription)
            Haptics.error()
        }
        await backend.close()
    }

    private func save() {
        let connection = normalized()
        model.save(connection, secret: secret)
        dismiss()
    }
}

/// How to switch on the surface the selected type talks to.
struct SetupHelp: View {
    let kind: ConnectionKind
    @Environment(\.tokens) private var tokens

    var body: some View {
        DisclosureGroup("Setting up the agent") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    Text(step.text)
                        .font(.footnote)
                        .foregroundStyle(tokens.secondary)
                    if let code = step.code {
                        CopyableCode(code)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private struct Step {
        let text: String
        let code: String?
    }

    private var steps: [Step] {
        switch kind {
        case .dashboard:
            [
                Step(text: "Give the dashboard a password, in ~/.hermes/.env:", code: "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=me\nHERMES_DASHBOARD_BASIC_AUTH_PASSWORD=choose-a-password\nHERMES_DASHBOARD_BASIC_AUTH_SECRET=$(openssl rand -hex 32)"),
                Step(text: "Serve it on your network (or your Tailscale address):", code: "hermes serve --host 0.0.0.0 --port 9119"),
                Step(text: "Put it behind HTTPS before exposing it beyond your LAN or tailnet.", code: nil),
            ]
        case .gateway:
            [
                Step(text: "Enable the API server in ~/.hermes/.env:", code: "API_SERVER_ENABLED=true\nAPI_SERVER_KEY=$(openssl rand -hex 24)\nAPI_SERVER_HOST=0.0.0.0"),
                Step(text: "Restart the gateway:", code: "hermes gateway restart"),
                Step(text: "Port 8642 by default. Add a profile name above to reach /p/<profile>.", code: nil),
            ]
        case .openAI:
            [
                Step(text: "Any server with /v1/chat/completions works: a Hermes gateway, vLLM, Ollama, LM Studio, or a hosted API. Enter the base URL with or without /v1.", code: nil),
            ]
        }
    }
}

struct CopyableCode: View {
    let code: String
    @Environment(\.tokens) private var tokens
    @State private var copied = false

    init(_ code: String) { self.code = code }

    var body: some View {
        HStack(alignment: .top) {
            Text(code)
                .font(.caption.monospaced())
                .foregroundStyle(tokens.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = code
                copied = true
                Haptics.tap()
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(tokens.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy")
        }
        .padding(10)
        .background(tokens.background, in: .rect(cornerRadius: 8))
    }
}
