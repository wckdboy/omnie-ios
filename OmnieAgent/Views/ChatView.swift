import SwiftUI

/// A single conversation: scrolling transcript plus a composer that can send
/// or, while a reply is streaming, stop it.
struct ChatView: View {
    let session: ChatSession

    @Environment(AppModel.self) private var model
    @State private var draft: String = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.messages.last?.text) {
                    scrollToBottom(proxy)
                }
                .onChange(of: model.messages.count) {
                    scrollToBottom(proxy)
                }
            }

            composer
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.openSession(session)
        }
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
                Image(systemName: model.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.body.bold())
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)
            .disabled(!model.isStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func send() {
        if model.isStreaming {
            model.stopStreaming()
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        model.send(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = model.messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(session: ChatSession(id: "preview", title: "Preview Chat"))
            .environment(AppModel())
    }
}
