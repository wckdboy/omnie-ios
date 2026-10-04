import SwiftUI

struct ModelPicker: View {
    let chat: ChatModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tokens) private var tokens
    @State private var search = ""
    @State private var loading = true
    @State private var custom = ""

    var body: some View {
        NavigationStack {
            List {
                if chat.agent.connection.kind == .openAI || chat.agent.models.isEmpty {
                    Section("Custom") {
                        HStack {
                            TextField("Model id", text: $custom)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Use") {
                                Task {
                                    await chat.setModel(ModelOption(id: custom, provider: nil, label: custom, isDefault: false))
                                    dismiss()
                                }
                            }
                            .disabled(custom.isEmpty)
                        }
                    }
                }
                ForEach(groups, id: \.0) { provider, models in
                    Section(provider) {
                        ForEach(models) { model in
                            Button {
                                Task {
                                    await chat.setModel(model)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Text(model.label).foregroundStyle(tokens.text)
                                    Spacer()
                                    if isSelected(model) {
                                        Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .overlay { if loading && chat.agent.models.isEmpty { ProgressView() } }
            .searchable(text: $search, prompt: "Search models")
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                await chat.agent.loadModels(for: chat.session)
                loading = false
            }
        }
    }

    private func isSelected(_ model: ModelOption) -> Bool {
        if let current = chat.options.model { return current == model.id && (chat.options.provider == nil || chat.options.provider == model.provider) }
        return model.isDefault
    }

    private var groups: [(String, [ModelOption])] {
        let query = search.lowercased()
        let filtered = chat.agent.models.filter { query.isEmpty || $0.id.lowercased().contains(query) || $0.label.lowercased().contains(query) }
        let grouped = Dictionary(grouping: filtered) { $0.provider ?? "Models" }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }
}

struct SessionInfoSheet: View {
    let chat: ChatModel
    @Environment(\.tokens) private var tokens

    var body: some View {
        NavigationStack {
            List {
                Section("Conversation") {
                    row("Agent", chat.agent.connection.name)
                    if let session = chat.session {
                        row("Session", session.storedID, mono: true)
                        if session.id != session.storedID { row("Live id", session.id, mono: true) }
                    }
                    if let model = chat.usage?.model ?? chat.session?.model { row("Model", model) }
                    if let provider = chat.usage?.provider, !provider.isEmpty { row("Provider", provider) }
                }
                if let usage = chat.usage, usage.totalTokens > 0 {
                    Section("Last turn") {
                        row("Input tokens", usage.inputTokens.compact)
                        row("Output tokens", usage.outputTokens.compact)
                        row("Total", usage.totalTokens.compact)
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(tokens.secondary)
            Spacer()
            Text(value)
                .font(mono ? .footnote.monospaced() : .body)
                .foregroundStyle(tokens.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
