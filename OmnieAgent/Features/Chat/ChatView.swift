import SwiftUI
import UIKit
import PhotosUI

struct ChatView: View {
    let route: ChatRoute
    @Binding var path: [ChatRoute]
    @State private var chat: ChatModel
    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @State private var showModels = false
    @State private var showInfo = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var started = false
    @Environment(\.tokens) private var tokens

    init(agent: AgentConnection, route: ChatRoute, path: Binding<[ChatRoute]>) {
        self.route = route
        _path = path
        _chat = State(initialValue: ChatModel(agent: agent))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if chat.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
                ForEach(chat.transcript.items) { item in
                    ChatItemView(item: item, isLive: chat.isRunning && item.id == chat.transcript.items.last?.id, chat: chat)
                        .id(item.id)
                }
                if chat.isRunning {
                    WorkingIndicator(status: chat.statusLine)
                }
                if let error = chat.error {
                    InlineNotice(text: error)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if chat.isEmpty, !chat.isLoading, !chat.isRunning {
                EmptyChatHint(agent: chat.agent) { draft = $0 }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if !chat.transcript.todos.isEmpty {
                    TodoStrip(todos: chat.transcript.todos)
                }
                Composer(chat: chat, draft: $draft, attachments: $attachments)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(tokens.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(chat.title ?? titleFallback)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tokens.text)
                        .lineLimit(1)
                    if let model = chat.options.model ?? chat.session?.model ?? chat.agent.info?.model {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(tokens.secondary)
                            .lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ChatMenu(chat: chat, showModels: $showModels, showInfo: $showInfo, renaming: $renaming, renameText: $renameText, path: $path)
            }
        }
        .sheet(isPresented: $showModels) {
            ModelPicker(chat: chat).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showInfo) {
            SessionInfoSheet(chat: chat).presentationDetents([.medium])
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await chat.rename(renameText) } }
        }
        .task {
            guard !started else { return }
            started = true
            switch route {
            case .session(let id, let title):
                chat.title = title
                await chat.open(id)
            case .new(_, let prompt):
                if let prompt, !prompt.isEmpty {
                    chat.send(prompt)
                } else if chat.agent.connection.kind == .dashboard {
                    // Warm a live session so the first message streams at once.
                    await chat.startNew()
                }
            case .opened(let opened):
                chat.adopt(opened)
            }
        }
        .onDisappear {
            if !chat.isRunning { Task { await chat.agent.refreshSessions() } }
        }
    }

    private var titleFallback: String {
        if case .session(_, let title) = route, let title { return title }
        return "New chat"
    }
}

private struct ChatMenu: View {
    let chat: ChatModel
    @Binding var showModels: Bool
    @Binding var showInfo: Bool
    @Binding var renaming: Bool
    @Binding var renameText: String
    @Binding var path: [ChatRoute]

    var body: some View {
        Menu {
            Section {
                if chat.features.modelSwitch || chat.agent.connection.kind == .openAI {
                    Button { showModels = true } label: { Label("Model", systemImage: "cpu") }
                }
                if chat.features.reasoningControl {
                    Picker(selection: Binding(
                        get: { chat.options.reasoning },
                        set: { effort in Task { await chat.setReasoning(effort) } }
                    )) {
                        ForEach(ReasoningEffort.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Reasoning", systemImage: "brain")
                    }
                    .pickerStyle(.menu)
                }
            }
            Section {
                if chat.features.rename, chat.session != nil {
                    Button {
                        renameText = chat.title ?? ""
                        renaming = true
                    } label: { Label("Rename", systemImage: "pencil") }
                }
                if chat.features.fork, chat.session != nil {
                    Button {
                        Task {
                            if let forked = await chat.fork() { path.append(.opened(forked)) }
                        }
                    } label: { Label("Branch from here", systemImage: "arrow.triangle.branch") }
                }
                Button { UIPasteboard.general.string = chat.exportText() } label: {
                    Label("Copy transcript", systemImage: "doc.on.doc")
                }
                ShareLink(item: chat.exportText()) { Label("Share transcript", systemImage: "square.and.arrow.up") }
                if chat.session != nil {
                    Button { Task { await chat.reload() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Button { showInfo = true } label: { Label("Details", systemImage: "info.circle") }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Conversation options")
    }
}

private struct WorkingIndicator: View {
    let status: String?
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(status ?? "Working")
                .font(.footnote)
                .foregroundStyle(tokens.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyChatHint: View {
    let agent: AgentConnection
    let onPick: (String) -> Void
    @Environment(\.tokens) private var tokens

    private let suggestions = [
        "What can you do on this machine?",
        "Summarize what you worked on today",
        "List my scheduled jobs",
        "Check disk space and running processes",
    ]

    var body: some View {
        VStack(spacing: 18) {
            Image("OmnieMark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 48)
                .foregroundStyle(tokens.text)
            Text(agent.connection.name)
                .font(.display(22))
                .foregroundStyle(tokens.text)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { onPick(suggestion) } label: {
                        Text(suggestion)
                            .font(.footnote)
                            .foregroundStyle(tokens.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .card(tokens, radius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 340)
        }
        .padding(24)
    }
}

private struct TodoStrip: View {
    let todos: [TodoItem]
    @State private var expanded = false
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                    Text(current?.content ?? "Plan")
                        .lineLimit(1)
                    Spacer()
                    Text("\(todos.filter(\.isDone).count)/\(todos.count)")
                        .monospacedDigit()
                    Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.caption2)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(tokens.text)
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(todos) { todo in
                    HStack(spacing: 8) {
                        Image(systemName: todo.isDone ? "checkmark.circle" : todo.isActive ? "circle.dotted" : "circle")
                            .foregroundStyle(tokens.secondary)
                        Text(todo.content)
                            .strikethrough(todo.isDone)
                            .foregroundStyle(todo.isDone ? tokens.secondary : tokens.text)
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var current: TodoItem? {
        todos.first(where: \.isActive) ?? todos.first { !$0.isDone }
    }
}

struct Attachment: Identifiable, Equatable {
    let id = UUID()
    let dataURL: String
    let preview: UIImage
}

struct Composer: View {
    let chat: ChatModel
    @Binding var draft: String
    @Binding var attachments: [Attachment]
    @FocusState private var focused: Bool
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var commands: [SlashCommand] = []
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(spacing: 8) {
            if !matchingCommands.isEmpty {
                CommandSuggestions(commands: matchingCommands) { command in
                    draft = command.name + " "
                }
            }
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            Image(uiImage: attachment.preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        attachments.removeAll { $0.id == attachment.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .offset(x: 6, y: -6)
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 4)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                if chat.features.images {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                            .foregroundStyle(tokens.text)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Attach photos")
                }
                TextField(placeholder, text: $draft, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($focused)
                    .padding(.vertical, 8)
                    .submitLabel(.send)
                sendButton
            }
            .padding(.leading, chat.features.images ? 4 : 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .onChange(of: pickerItems) { _, items in
            Task { await load(items) }
        }
        .task(id: chat.features.slashCommands) {
            guard chat.features.slashCommands else { return }
            commands = (try? await chat.backend.commands(session: chat.session)) ?? []
        }
    }

    private var placeholder: String {
        if chat.isRunning { return chat.features.steer ? "Add guidance…" : "Working…" }
        return chat.features.slashCommands ? "Message or /command" : "Message"
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    @ViewBuilder
    private var sendButton: some View {
        if chat.isRunning && !canSend {
            Button {
                chat.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.footnote)
                    .foregroundStyle(tokens.background)
                    .frame(width: 36, height: 36)
                    .background(tokens.text, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
        } else {
            Button {
                chat.send(draft, images: attachments.map(\.dataURL))
                draft = ""
                attachments = []
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .primaryAction(in: .circle)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
            .accessibilityLabel(chat.isRunning ? "Send guidance" : "Send")
        }
    }

    private var matchingCommands: [SlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(" "), !commands.isEmpty else { return [] }
        let query = draft.lowercased()
        return Array(commands.filter { $0.name.lowercased().hasPrefix(query) }.prefix(6))
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            let scaled = image.scaledDown(maxSide: 1600)
            guard let jpeg = scaled.jpegData(compressionQuality: 0.8) else { continue }
            attachments.append(Attachment(dataURL: "data:image/jpeg;base64," + jpeg.base64EncodedString(), preview: scaled))
        }
        pickerItems = []
    }
}

private struct CommandSuggestions: View {
    let commands: [SlashCommand]
    let onPick: (SlashCommand) -> Void
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commands) { command in
                Button { onPick(command) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(command.name)
                            .font(.footnote.monospaced().weight(.semibold))
                            .foregroundStyle(tokens.text)
                        Text(command.summary)
                            .font(.caption)
                            .foregroundStyle(tokens.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }
}

extension UIImage {
    func scaledDown(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
