import SwiftUI

@main
struct OmnieApp: App {
    @State private var model = AppModel()
    @State private var theme = Theme()
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .overlay { if lock.isLocked { LockScreen() } }
                .modifier(ThemeRoot())
                .environment(model)
                .environment(theme)
                .environment(lock)
                .preferredColorScheme(theme.scheme.colorScheme)
                .onOpenURL { model.handle(url: $0) }
                .onReceive(NotificationCenter.default.publisher(for: IntentBridge.didQueue)) { _ in
                    IntentBridge.shared.drain(into: model)
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        lock.unlockIfNeeded()
                        IntentBridge.shared.drain(into: model)
                        Task { await model.foreground() }
                    case .background:
                        lock.didEnterBackground()
                    default:
                        break
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: RootTab = .chats

    var body: some View {
        Group {
            if model.connections.isEmpty {
                WelcomeView()
            } else {
                TabView(selection: $tab) {
                    Tab("Chats", systemImage: "bubble.left.and.text.bubble.right", value: RootTab.chats) {
                        ChatsTab()
                    }
                    Tab("Agent", systemImage: "cpu", value: RootTab.agent) {
                        AgentTab()
                    }
                    Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                        SettingsTab()
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
        .sheet(item: Binding(
            get: { model.pendingLink.map(PendingLink.init) },
            set: { if $0 == nil { model.pendingLink = nil } }
        )) { pending in
            ConnectionEditor(draft: pending.link.connection, secret: pending.link.secret ?? "", isNew: true)
        }
        .onChange(of: model.pendingPrompt) { _, prompt in
            if prompt != nil { tab = .chats }
        }
    }
}

enum RootTab: Hashable {
    case chats, agent, settings
}

private struct PendingLink: Identifiable {
    let link: ConnectionLink
    var id: UUID { link.connection.id }
}
