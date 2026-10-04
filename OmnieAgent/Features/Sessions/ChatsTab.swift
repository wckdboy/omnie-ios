import SwiftUI

enum ChatRoute: Hashable {
    case session(id: String, title: String?)
    case new(token: UUID, prompt: String?)
    case opened(OpenedSession)
}

/// Home: the active agent's conversations.
struct ChatsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @State private var path: [ChatRoute] = []
    @State private var search = ""
    @State private var showAgents = false
    @State private var renaming: AgentSession?
    @State private var renameText = ""
    @State private var actionError: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let agent = model.active {
                    SessionList(agent: agent, search: search, path: $path, renaming: $renaming, renameText: $renameText, actionError: $actionError)
                        .id(agent.id)
                } else {
                    ContentUnavailableView("No agent selected", systemImage: "cpu")
                }
            }
            .background(tokens.background.ignoresSafeArea())
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AgentSwitcherButton { showAgents = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(.new(token: UUID(), prompt: nil))
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .primaryAction(in: .circle)
                    .accessibilityLabel("New chat")
                    .disabled(model.active == nil)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ChatRoute.self) { route in
                if let agent = model.active {
                    ChatView(agent: agent, route: route, path: $path)
                }
            }
        }
        .sheet(isPresented: $showAgents) {
            AgentPicker()
                .presentationDetents([.medium, .large])
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let session = renaming, let agent = model.active {
                    let title = renameText
                    Task {
                        do { try await agent.rename(session, to: title) } catch { actionError = error.localizedDescription }
                    }
                }
                renaming = nil
            }
        }
        .alert("Couldn't finish that", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .onChange(of: model.pendingPrompt, initial: true) { _, prompt in
            guard let prompt, model.active != nil else { return }
            model.pendingPrompt = nil
            path = [.new(token: UUID(), prompt: prompt)]
        }
        .onChange(of: model.activeID) { _, _ in path = [] }
    }
}

private struct SessionList: View {
    let agent: AgentConnection
    let search: String
    @Binding var path: [ChatRoute]
    @Binding var renaming: AgentSession?
    @Binding var renameText: String
    @Binding var actionError: String?
    @Environment(\.tokens) private var tokens

    var body: some View {
        List {
            if case .failed(let message) = agent.status {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        InlineNotice(text: message)
                        Button("Try again") { Task { await agent.connect() } }
                            .font(.subheadline.weight(.medium))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            let filtered = filteredSessions
            let pinned = filtered.filter(\.pinned)
            let rest = filtered.filter { !$0.pinned }

            if !pinned.isEmpty {
                Section { rows(pinned) } header: { SectionLabel("Pinned") }
            }
            if !rest.isEmpty {
                Section { rows(rest) } header: { if !pinned.isEmpty { SectionLabel("Recent") } }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if agent.sessions.isEmpty {
                if agent.status == .connecting || agent.isLoadingSessions {
                    ProgressView()
                } else if agent.isOnline {
                    EmptyChats { path.append(.new(token: UUID(), prompt: nil)) }
                }
            } else if filteredSessions.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .refreshable {
            if agent.isOnline { await agent.refreshSessions() } else { await agent.connect() }
        }
        .task {
            if agent.status == .idle { await agent.connect() }
        }
    }

    private var filteredSessions: [AgentSession] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return agent.sessions }
        return agent.sessions.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || ($0.preview ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func rows(_ sessions: [AgentSession]) -> some View {
        ForEach(sessions) { session in
            Button {
                path.append(.session(id: session.id, title: session.title))
            } label: {
                SessionRow(session: session)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if agent.features.delete {
                    Button(role: .destructive) {
                        Task { do { try await agent.delete(session) } catch { actionError = error.localizedDescription } }
                    } label: { Label("Delete", systemImage: "trash") }
                }
                if agent.features.rename {
                    Button {
                        renameText = session.title ?? ""
                        renaming = session
                    } label: { Label("Rename", systemImage: "pencil") }
                    .tint(.gray)
                }
            }
            .swipeActions(edge: .leading) {
                if agent.features.pin {
                    Button {
                        Task { do { try await agent.togglePin(session) } catch { actionError = error.localizedDescription } }
                    } label: {
                        Label(session.pinned ? "Unpin" : "Pin", systemImage: session.pinned ? "pin.slash" : "pin")
                    }
                    .tint(.gray)
                }
            }
            .contextMenu {
                if agent.features.rename {
                    Button { renameText = session.title ?? ""; renaming = session } label: { Label("Rename", systemImage: "pencil") }
                }
                if agent.features.pin {
                    Button { Task { try? await agent.togglePin(session) } } label: {
                        Label(session.pinned ? "Unpin" : "Pin", systemImage: "pin")
                    }
                }
                Button { UIPasteboard.general.string = session.id } label: { Label("Copy Session ID", systemImage: "number") }
                if agent.features.delete {
                    Button(role: .destructive) { Task { try? await agent.delete(session) } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: AgentSession
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tokens.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if session.sortDate != .distantPast {
                    Text(session.sortDate.shortRelative)
                        .font(.caption)
                        .foregroundStyle(tokens.secondary)
                        .monospacedDigit()
                }
            }
            HStack(spacing: 6) {
                if let source = session.source, !["api_server", "tui", "cli", "desktop", "dashboard"].contains(source) {
                    Text(source.capitalized)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(tokens.hairline))
                        .foregroundStyle(tokens.secondary)
                }
                if let preview = session.preview, !preview.isEmpty, preview != session.displayTitle {
                    Text(preview)
                        .lineLimit(2)
                } else if session.messageCount > 0 {
                    Text("\(session.messageCount) messages")
                }
            }
            .font(.subheadline)
            .foregroundStyle(tokens.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct EmptyChats: View {
    let start: () -> Void
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(spacing: 14) {
            DisplayTitle("No chats yet", size: 22)
            Text("Conversations you start here, in the terminal, or on any connected platform show up in this list.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(tokens.secondary)
            Button("Start a chat", action: start)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
        }
        .padding(32)
    }
}
