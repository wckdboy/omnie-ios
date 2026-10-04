import SwiftUI

struct SettingsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(Theme.self) private var theme
    @Environment(AppLock.self) private var lock
    @Environment(\.tokens) private var tokens
    @AppStorage("omnie.haptics") private var haptics = true
    @AppStorage("omnie.notify") private var notify = true
    @AppStorage("omnie.chat.reasoning") private var reasoning = ReasoningEffort.auto.rawValue
    @AppStorage("omnie.chat.instructions") private var instructions = ""
    @State private var editing: Connection?
    @State private var adding = false

    var body: some View {
        @Bindable var theme = theme
        @Bindable var lock = lock
        NavigationStack {
            Form {
                Section("Agents") {
                    ForEach(model.connections) { connection in
                        Button { editing = connection } label: {
                            HStack(spacing: 12) {
                                Image(systemName: connection.kind.systemImage).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(connection.name).foregroundStyle(tokens.text)
                                    Text(connection.hostLabel).font(.caption).foregroundStyle(tokens.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(tokens.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button { adding = true } label: { Label("Add Agent", systemImage: "plus") }
                }

                Section("Appearance") {
                    Picker("Palette", selection: $theme.appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Mode", selection: $theme.scheme) {
                        ForEach(SchemePreference.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Reasoning", selection: $reasoning) {
                        ForEach(ReasoningEffort.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    TextField("Extra instructions for every chat", text: $instructions, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("New chats")
                } footer: {
                    Text("Instructions are added on top of the agent's own system prompt, per turn.")
                }

                Section {
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Notify when a reply finishes", isOn: $notify)
                        .onChange(of: notify) { _, on in if on { Notifier.requestPermission() } }
                    Toggle("Require Face ID", isOn: $lock.isEnabled)
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("Notifications are local. Omnie keeps a finishing reply streaming for a short time after you leave the app.")
                }

                Section("Shortcuts") {
                    Text("“Ask Omnie” is available in Shortcuts and Siri. Links: omnie://chat?text=…, omnie://agent?name=…")
                        .font(.footnote)
                        .foregroundStyle(tokens.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Wordmark(size: 22)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") — a client for Hermes Agent by Nous Research. Omnie runs no server of its own: it talks only to the agents you add.")
                            .font(.footnote)
                            .foregroundStyle(tokens.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(tokens.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .sheet(item: $editing) { connection in
                ConnectionEditor(draft: connection, secret: Keychain.secret(for: connection.id) ?? "", isNew: false)
            }
            .sheet(isPresented: $adding) {
                ConnectionEditor(draft: Connection(name: "", kind: .dashboard, baseURL: ""), secret: "", isNew: true)
            }
        }
    }
}
