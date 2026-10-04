import SwiftUI

/// The toolbar title: active agent name + status. Taps open the picker.
struct AgentSwitcherButton: View {
    let action: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let agent = model.active {
                    StatusDot(state: agent.status.dot)
                    Text(agent.connection.name)
                        .font(.display(16, relativeTo: .headline))
                        .foregroundStyle(tokens.text)
                        .lineLimit(1)
                } else {
                    Text("omnie").font(.display(16, black: true, relativeTo: .headline))
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tokens.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch agent")
    }
}

/// Switch between saved agents, add or edit one.
struct AgentPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tokens) private var tokens
    @State private var editing: Connection?
    @State private var adding = false
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.connections) { connection in
                    let agent = model.agent(for: connection.id)
                    Button {
                        model.activeID = connection.id
                        Haptics.tap()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: connection.kind.systemImage)
                                .frame(width: 28)
                                .foregroundStyle(tokens.text)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(connection.name).font(.body.weight(.medium)).foregroundStyle(tokens.text)
                                    if let agent { StatusDot(state: agent.status.dot) }
                                }
                                Text("\(connection.kind.title) · \(connection.hostLabel)")
                                    .font(.caption)
                                    .foregroundStyle(tokens.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if connection.id == model.activeID {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Edit") { editing = connection }.tint(.gray)
                    }
                    .contextMenu {
                        Button { editing = connection } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { model.remove(connection) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                .onMove { model.move(from: $0, to: $1) }
                .listRowBackground(tokens.surface)

                Section {
                    Button { adding = true } label: { Label("Add Agent", systemImage: "plus") }
                    Button { scanning = true } label: { Label("Scan Connection Code", systemImage: "qrcode.viewfinder") }
                }
                .listRowBackground(tokens.surface)
            }
            .scrollContentBackground(.hidden)
            .background(tokens.background)
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            .sheet(item: $editing) { connection in
                ConnectionEditor(draft: connection, secret: Keychain.secret(for: connection.id) ?? "", isNew: false)
            }
            .sheet(isPresented: $adding) {
                ConnectionEditor(draft: Connection(name: "", kind: .dashboard, baseURL: ""), secret: "", isNew: true)
            }
            .sheet(isPresented: $scanning) {
                CodeScannerSheet { url in
                    scanning = false
                    model.handle(url: url)
                }
            }
        }
    }
}
