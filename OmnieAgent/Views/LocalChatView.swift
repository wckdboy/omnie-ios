import SwiftUI

/// The on-device conversation: a single ongoing chat backed by Apple's
/// Foundation Models framework, persisted locally. No server, no network.
struct LocalChatView: View {
    @Environment(AppModel.self) private var model
    @State private var draft: String = ""
    @State private var showSettings = false
    @State private var showClearConfirmation = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if model.localMessages.isEmpty {
                                emptyState
                            }
                            ForEach(model.localMessages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.localMessages.last?.text) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: model.localMessages.count) {
                        scrollToBottom(proxy)
                    }
                }

                composer
            }
            .navigationTitle("On This iPhone")
            .navigationBarTitleDisplayMode(.inline)
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
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(model.localMessages.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .confirmationDialog("Clear this conversation?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    model.clearLocalConversation()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask me anything")
                .font(.headline)
            Text("This conversation runs entirely on your iPhone using Apple's on-device model. No network connection is used.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 40)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))

            Button {
                send()
            } label: {
                Image(systemName: model.isLocalStreaming ? "stop.fill" : "arrow.up")
                    .font(.body.bold())
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)
            .disabled(!model.isLocalStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func send() {
        if model.isLocalStreaming {
            model.stopLocalStreaming()
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        model.sendLocal(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = model.localMessages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

#Preview {
    LocalChatView()
        .environment(AppModel())
}
