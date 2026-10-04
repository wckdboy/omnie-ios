import SwiftUI

/// The list of conversations on the configured server: tap to open, swipe to
/// delete, pencil to start a new chat, gear for settings.
struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var isCreating = false
    @State private var path: [ChatSession] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(model.sessions) { session in
                    NavigationLink(value: session) {
                        row(for: session)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let session = model.sessions[index]
                        Task { await model.deleteSession(session) }
                    }
                }
            }
            .overlay {
                if model.sessions.isEmpty && !model.isLoadingSessions {
                    ContentUnavailableView(
                        "No Chats Yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a new chat to talk to your Hermes agent.")
                    )
                }
            }
            .navigationTitle(model.providerConfig?.displayName ?? "Omnie Agent")
            .navigationDestination(for: ChatSession.self) { session in
                ChatView(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await startNewChat() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(isCreating ? AnyShapeStyle(.secondary) : AnyShapeStyle(BrandPalette.accentGradient))
                    }
                    .disabled(isCreating)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .refreshable {
                await model.refreshSessions()
            }
            .task {
                await model.refreshSessions()
            }
            .onChange(of: model.pendingRemoteSession) { _, newValue in
                guard let newValue else { return }
                path.append(newValue)
                model.pendingRemoteSession = nil
            }
        }
    }

    private func row(for session: ChatSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.displayTitle)
                .lineLimit(1)
            if let date = session.updatedAt {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func startNewChat() async {
        isCreating = true
        defer { isCreating = false }
        if let session = await model.createSession() {
            path.append(session)
        }
    }
}

#Preview {
    SessionsView()
        .environment(AppModel())
}
