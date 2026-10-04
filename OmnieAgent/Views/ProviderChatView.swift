import SwiftUI

/// The single-thread conversation for an OpenAI-compatible provider (one
/// ongoing chat, no server-side session list — the API is stateless per
/// call). Session-based providers (Hermes, OpenCode) use `SessionsView` +
/// `ChatView` instead.
struct ProviderChatView: View {
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
                            if model.providerMessages.isEmpty {
                                emptyState
                            }
                            ForEach(model.providerMessages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.providerMessages.last?.text) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: model.providerMessages.count) {
                        scrollToBottom(proxy)
                    }
                }

                composer
            }
            .background(tokens.background)
            .navigationTitle(model.providerConfig?.providerName ?? "Provider")
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
                    .disabled(model.providerMessages.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .confirmationDialog("Clear this conversation?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    model.clearProviderConversation()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask me anything")
                .font(.brandDisplay(22))
                .foregroundStyle(tokens.text)
            if let config = model.providerConfig {
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
                Image(systemName: model.isProviderStreaming ? "stop.fill" : "arrow.up")
                    .font(.body.bold())
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .brandPrimaryAction(in: .circle)
            .disabled(!model.isProviderStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func send() {
        if model.isProviderStreaming {
            model.stopProviderStreaming()
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        model.sendProvider(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = model.providerMessages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

#Preview {
    ProviderChatView()
        .environment(AppModel())
        .environment(BrandTheme())
}
