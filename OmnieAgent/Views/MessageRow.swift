import SwiftUI

/// Renders one message: a neutral glass bubble for the user, plain Markdown
/// text for the assistant (with tool-use capsules above it), or a centered
/// caption for system messages.
///
/// The user bubble is deliberately *not* accent-tinted — `BRANDING.md`
/// reserves the one accent gradient for a single primary action or
/// active/selected item per screen, not for content like every message a
/// user sends.
struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !message.toolEvents.isEmpty {
                    ToolEventRow(events: message.toolEvents)
                }
                if !message.text.isEmpty {
                    Text(attributed(message.text))
                        .textSelection(.enabled)
                } else if message.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .system:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full)))
            ?? AttributedString(text)
    }
}

/// A compact wrap of tool-use capsules, e.g. "⚙︎ terminal · done".
private struct ToolEventRow: View {
    let events: [ToolEvent]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(events) { ToolCapsule(event: $0) }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(events) { ToolCapsule(event: $0) }
            }
        }
    }
}

private struct ToolCapsule: View {
    let event: ToolEvent

    var body: some View {
        HStack(spacing: 4) {
            icon
            Text(event.name)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder
    private var icon: some View {
        switch event.status {
        case .started:
            ProgressView().controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark").font(.caption2)
        case .failed:
            Image(systemName: "xmark").font(.caption2).foregroundStyle(.red)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        MessageRow(message: ChatMessage(role: .user, text: "What files are in my project?"))
        MessageRow(message: ChatMessage(
            role: .assistant,
            text: "Here's what I found in **README.md**.",
            toolEvents: [ToolEvent(name: "terminal", status: .completed)]
        ))
    }
    .padding()
}
