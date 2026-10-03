import SwiftUI

/// The cloud-provider conversation: a single ongoing chat against whatever
/// OpenAI-compatible provider the user configured with their own key.
struct CloudChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(BrandTheme.self) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: String = ""
    @State private var showSettings = false
    @State private var showClearConfirmation = false
    @FocusState private var composerFocused: Bool

    private var tokens: BrandPalette.Tokens { theme.appearance.tokens(for: colorScheme) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if model.cloudMessages.isEmpty {
                                emptyState
                            }
                            ForEach(model.cloudMessages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.cloudMessages.last?.text) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: model.cloudMessages.count) {
                        scrollToBottom(proxy)
                    }
                }

                composer
            }
            .background(tokens.background)
            .navigationTitle(model.cloudConfig?.providerName ?? "Cloud Provider")
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
                    .disabled(model.cloudMessages.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .confirmationDialog("Clear this conversation?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    model.clearCloudConversation()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask me anything")
                .font(.brandDisplay(22))
                .foregroundStyle(tokens.text)
            if let config = model.cloudConfig {
                Text("Talking directly to \(config.providerName) (\(config.model)) using your own API key.")
                    .font(.footnote)
                    .foregroundStyle(tokens.secondary)
            }
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
                Image(systemName: model.isCloudStreaming ? "stop.fill" : "arrow.up")
                    .font(.body.bold())
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .brandPrimaryAction(in: .circle)
            .disabled(!model.isCloudStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func send() {
        if model.isCloudStreaming {
            model.stopCloudStreaming()
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        model.sendCloud(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = model.cloudMessages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

#Preview {
    CloudChatView()
        .environment(AppModel())
        .environment(BrandTheme())
}
