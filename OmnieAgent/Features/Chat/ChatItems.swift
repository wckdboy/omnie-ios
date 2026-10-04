import SwiftUI
import UIKit

struct ChatItemView: View {
    let item: ChatItem
    let isLive: Bool
    let chat: ChatModel

    var body: some View {
        switch item.kind {
        case .user(let text, let images):
            UserBubble(text: text, images: images)
        case .assistant(let text):
            MarkdownText(text)
                .contextMenu {
                    Button { UIPasteboard.general.string = text } label: { Label("Copy", systemImage: "doc.on.doc") }
                    ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
                }
        case .reasoning(let text):
            ReasoningView(text: text, isLive: isLive)
        case .commentary(let text):
            Text(MarkdownText.inline(text))
                .font(.subheadline)
                .modifier(SecondaryText())
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(let tool):
            ToolCard(tool: tool)
        case .approval(let request, let resolved):
            ApprovalCard(request: request, resolved: resolved) { chat.approve(request, $0) }
        case .prompt(let prompt, let answered):
            PromptCard(prompt: prompt, answered: answered) { chat.answer(prompt, $0) }
        case .subagent(let update):
            SubagentRow(update: update)
        case .notice(let text, let isError):
            NoticeRow(text: text, isError: isError)
        }
    }
}

private struct SecondaryText: ViewModifier {
    @Environment(\.tokens) private var tokens
    func body(content: Content) -> some View { content.foregroundStyle(tokens.secondary) }
}

struct UserBubble: View {
    let text: String
    let images: [String]
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    InlineImage(source: image)
                        .frame(maxWidth: 220)
                }
                if !text.isEmpty {
                    Text(text)
                        .foregroundStyle(tokens.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .card(tokens, radius: 18)
                }
            }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = text } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
    }
}

struct ReasoningView: View {
    let text: String
    let isLive: Bool
    @State private var expanded = false
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(isLive ? "Thinking" : "Thought")
                    if isLive { ProgressView().controlSize(.mini) }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(tokens.secondary)
            }
            .buttonStyle(.plain)
            if expanded || isLive {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.footnote)
                    .foregroundStyle(tokens.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .textSelection(.enabled)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(tokens.hairline).frame(width: 2) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToolCard: View {
    let tool: ToolCall
    @State private var expanded = false
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    statusIcon
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(tokens.text)
                        if let summary {
                            Text(summary)
                                .font(.caption.monospaced())
                                .foregroundStyle(tokens.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if let duration = tool.duration, tool.status != .running {
                        Text(duration < 1 ? "<1s" : "\(Int(duration.rounded()))s")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(tokens.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tokens.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let arguments = tool.arguments, !arguments.isEmpty {
                        SectionLabel("Input")
                        CodeBlock(language: nil, code: arguments)
                    }
                    if let result = tool.result, !result.isEmpty {
                        SectionLabel(tool.status == .failed ? "Error" : "Output")
                        CodeBlock(language: nil, code: Self.pretty(result))
                    }
                    if tool.arguments == nil && tool.result == nil {
                        Text(tool.status == .running ? "Running…" : "No details from the agent.")
                            .font(.footnote)
                            .foregroundStyle(tokens.secondary)
                    }
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
        .card(tokens, radius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.title), \(statusLabel)")
    }

    private var summary: String? {
        if let preview = tool.preview, !preview.isEmpty { return preview }
        if let arguments = tool.arguments, let json = JSONValue.parse(arguments), let object = json.object {
            for key in ["command", "query", "path", "url", "file_path", "pattern", "name", "goal", "code"] {
                if let value = object[key]?.string { return value }
            }
        }
        return nil
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tool.status {
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(tokens.secondary)
        case .failed:
            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Palette.Semantic.danger)
        }
    }

    private var statusLabel: String {
        switch tool.status {
        case .running: "running"
        case .done: "done"
        case .failed: "failed"
        }
    }

    static func pretty(_ text: String) -> String {
        guard text.count < 200_000, let json = JSONValue.parse(text), json.object != nil || json.array != nil else { return text }
        // Unwrap the common {"output": "..."} shape so terminal output reads naturally.
        if let object = json.object, let output = object["output"]?.string, object.count <= 4 {
            var lines = [output]
            if let error = object["error"]?.string, !error.isEmpty { lines.append("error: \(error)") }
            if let code = object["exit_code"]?.int, code != 0 { lines.append("exit code \(code)") }
            return lines.joined(separator: "\n")
        }
        return json.prettyPrinted
    }
}

struct ApprovalCard: View {
    let request: ApprovalRequest
    let resolved: ApprovalChoice?
    let onChoose: (ApprovalChoice) -> Void
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(resolved == nil ? "Approval needed" : "Approval", systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tokens.text)
            Text(request.description)
                .font(.footnote)
                .foregroundStyle(tokens.secondary)
            if !request.command.isEmpty {
                CodeBlock(language: "command", code: request.command)
            }
            if let resolved {
                Label(resolved.label, systemImage: resolved == .deny ? "xmark.circle" : "checkmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(resolved == .deny ? Palette.Semantic.danger : tokens.secondary)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(request.choices.filter { $0 != .deny }, id: \.self) { choice in
                            Button(choice.label) { onChoose(choice) }
                                .font(.footnote.weight(choice == .once ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .buttonStyle(.glass)
                        }
                    }
                    if request.choices.contains(.deny) {
                        Button("Deny", role: .destructive) { onChoose(.deny) }
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(14)
        .card(tokens, radius: 16)
    }
}

struct PromptCard: View {
    let prompt: AgentPrompt
    let answered: Bool
    let onAnswer: (PromptAnswer) -> Void
    @Environment(\.tokens) private var tokens
    @State private var selections: [String: Set<String>] = [:]
    @State private var freeText: [String: String] = [:]
    @State private var secret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(heading, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tokens.text)
            if answered {
                Text("Answered.").font(.footnote).foregroundStyle(tokens.secondary)
            } else {
                content
            }
        }
        .padding(14)
        .card(tokens, radius: 16)
    }

    private var heading: String {
        switch prompt.kind {
        case .clarify: "The agent has a question"
        case .sudo: "Password needed for sudo"
        case .secret(let envVar, _): "Value needed: \(envVar)"
        }
    }

    private var icon: String {
        switch prompt.kind {
        case .clarify: "questionmark.bubble"
        case .sudo: "lock"
        case .secret: "key"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch prompt.kind {
        case .clarify(let questions):
            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.question).font(.subheadline).foregroundStyle(tokens.text)
                    if !question.choices.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(question.choices, id: \.self) { choice in
                                let selected = selections[question.id, default: []].contains(choice)
                                Button {
                                    toggle(choice, in: question)
                                } label: {
                                    Text(choice.replacingOccurrences(of: " (recommended)", with: ""))
                                        .font(.footnote.weight(selected ? .semibold : .regular))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .foregroundStyle(selected ? tokens.background : tokens.text)
                                        .background(selected ? tokens.text : Color.clear, in: Capsule())
                                        .overlay(Capsule().strokeBorder(tokens.hairline))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    TextField(question.choices.isEmpty ? "Your answer" : "Or type an answer", text: Binding(
                        get: { freeText[question.id] ?? "" },
                        set: { freeText[question.id] = $0 }
                    ), axis: .vertical)
                    .font(.footnote)
                    .padding(10)
                    .background(tokens.background, in: .rect(cornerRadius: 10))
                }
            }
            HStack {
                Button("Skip") { onAnswer(.decline) }
                    .font(.footnote)
                    .foregroundStyle(tokens.secondary)
                Spacer()
                Button("Send answer") { onAnswer(.clarify(answers(questions))) }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.glass)
            }
        case .sudo(let command):
            if let command { CodeBlock(language: "sudo", code: command) }
            secretEntry(placeholder: "Password")
        case .secret(_, let message):
            Text(message).font(.footnote).foregroundStyle(tokens.secondary)
            secretEntry(placeholder: "Value")
        }
    }

    @ViewBuilder
    private func secretEntry(placeholder: String) -> some View {
        SecureField(placeholder, text: $secret)
            .textContentType(.password)
            .padding(10)
            .background(tokens.background, in: .rect(cornerRadius: 10))
        HStack {
            Button("Decline") { onAnswer(.decline) }
                .font(.footnote)
                .foregroundStyle(tokens.secondary)
            Spacer()
            Button("Send") { onAnswer(.value(secret)); secret = "" }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.glass)
                .disabled(secret.isEmpty)
        }
    }

    private func toggle(_ choice: String, in question: ClarifyQuestion) {
        var set = selections[question.id, default: []]
        if set.contains(choice) {
            set.remove(choice)
        } else {
            if !question.multiSelect { set.removeAll() }
            set.insert(choice)
        }
        selections[question.id] = set
        Haptics.tap()
    }

    private func answers(_ questions: [ClarifyQuestion]) -> [String: String] {
        var result: [String: String] = [:]
        for question in questions {
            let typed = (freeText[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let picked = question.choices.filter { selections[question.id, default: []].contains($0) }
            if !typed.isEmpty {
                result[question.id] = typed
            } else if !picked.isEmpty {
                result[question.id] = picked.joined(separator: ", ")
            }
        }
        return result
    }
}

struct SubagentRow: View {
    let update: SubagentUpdate
    @Environment(\.tokens) private var tokens

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if update.finished {
                Image(systemName: "person.2").foregroundStyle(tokens.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Subagent: \(update.goal)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(tokens.text)
                    .lineLimit(2)
                if let summary = update.summary, !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(tokens.secondary).lineLimit(3)
                } else {
                    Text(update.status.capitalized).font(.caption).foregroundStyle(tokens.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card(tokens, radius: 14)
    }
}

struct NoticeRow: View {
    let text: String
    let isError: Bool
    @Environment(\.tokens) private var tokens

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(isError ? Palette.Semantic.danger : tokens.secondary)
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }
}

/// Wraps children onto new lines, for answer chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
