import SwiftUI
import UIKit

/// Renders an agent reply: block Markdown with inline styling, code blocks
/// with copy, tables and inline images.
struct MarkdownText: View {
    let source: String
    @Environment(\.tokens) private var tokens

    init(_ source: String) { self.source = source }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownParser.parse(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text))
                .foregroundStyle(tokens.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level <= 1 ? Font.title3.weight(.bold) : level == 2 ? Font.headline : Font.subheadline.weight(.semibold))
                .foregroundStyle(tokens.text)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case .code(let language, let text):
            CodeBlock(language: language, code: text)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square" : "square")
                                .font(.footnote)
                                .foregroundStyle(tokens.secondary)
                        } else {
                            Text(item.marker)
                                .foregroundStyle(tokens.secondary)
                                .monospacedDigit()
                        }
                        Text(Self.inline(item.text))
                            .foregroundStyle(tokens.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 16)
                }
            }
            .textSelection(.enabled)
        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle().fill(tokens.hairline).frame(width: 3)
                Text(Self.inline(text))
                    .foregroundStyle(tokens.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(Self.inline(cell)).font(.footnote.weight(.semibold))
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(Self.inline(cell)).font(.footnote)
                            }
                        }
                    }
                }
                .foregroundStyle(tokens.text)
                .padding(12)
            }
            .card(tokens, radius: 12)
        case .image(let alt, let url):
            InlineImage(source: url, alt: alt)
        case .rule:
            Rectangle().fill(tokens.hairline).frame(height: 0.5)
        }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        // Inline code: monospaced, no color — the brand keeps chrome neutral.
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = Font.body.monospaced()
        }
        return attributed
    }
}

struct CodeBlock: View {
    let language: String?
    let code: String
    @Environment(\.tokens) private var tokens
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption2.monospaced())
                    .foregroundStyle(tokens.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Haptics.tap()
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(tokens.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Rectangle().fill(tokens.hairline).frame(height: 0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.footnote.monospaced())
                    .foregroundStyle(tokens.text)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .card(tokens, radius: 12)
    }
}

/// Shows a `data:` URL or remote image inline; taps open it full screen.
struct InlineImage: View {
    let source: String
    var alt: String = ""
    @State private var expanded = false
    @Environment(\.tokens) private var tokens

    var body: some View {
        Group {
            if let image = Self.decode(source) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let url = URL(string: source), url.scheme?.hasPrefix("http") == true {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().frame(height: 120)
                }
            } else {
                Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(tokens.secondary)
            }
        }
        .frame(maxHeight: 320)
        .clipShape(.rect(cornerRadius: 12))
        .onTapGesture { expanded = true }
        .fullScreenCover(isPresented: $expanded) {
            ImageViewer(source: source)
        }
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
    }

    static func decode(_ source: String) -> UIImage? {
        guard source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") else { return nil }
        let base64 = String(source[source.index(after: comma)...])
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}

private struct ImageViewer: View {
    let source: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = InlineImage.decode(source) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if let url = URL(string: source) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if let image = InlineImage.decode(source) {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Image", image: Image(uiImage: image)))
                    }
                }
            }
        }
    }
}
