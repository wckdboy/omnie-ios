import Foundation

/// Block-level Markdown for agent replies. Inline styling (bold, code,
/// links) is left to `AttributedString(markdown:)` per block.
nonisolated enum MarkdownBlock: Hashable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String?, text: String)
    case bullet(items: [ListItem])
    case quote(String)
    case table(header: [String], rows: [[String]])
    case image(alt: String, url: String)
    case rule

    nonisolated struct ListItem: Hashable, Sendable {
        var marker: String
        var text: String
        var indent: Int
        var checked: Bool?
    }
}

nonisolated enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var list: [MarkdownBlock.ListItem] = []
        var quote: [String] = []
        var table: [[String]] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }
        func flushList() {
            if !list.isEmpty { blocks.append(.bullet(items: list)); list.removeAll() }
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote.removeAll() }
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            let header = table[0]
            let rows = table.dropFirst().filter { row in !row.allSatisfy { cell in cell.allSatisfy { "-: ".contains($0) } } }
            blocks.append(.table(header: header, rows: Array(rows)))
            table.removeAll()
        }
        func flushAll() { flushParagraph(); flushList(); flushQuote(); flushTable() }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code. An unterminated fence (still streaming) runs to the end.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushAll()
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, text: code.joined(separator: "\n")))
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if hashes <= 6, trimmed.dropFirst(hashes).first == " " {
                    flushAll()
                    blocks.append(.heading(level: hashes, text: trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)))
                    index += 1
                    continue
                }
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAll()
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.hasPrefix("!["), let close = trimmed.range(of: "]("), trimmed.hasSuffix(")") {
                flushAll()
                let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
                let url = String(trimmed[close.upperBound..<trimmed.index(before: trimmed.endIndex)])
                blocks.append(.image(alt: alt, url: url))
                index += 1
                continue
            }

            if trimmed.hasPrefix("|"), trimmed.count > 1 {
                flushParagraph(); flushList(); flushQuote()
                var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.first == "" { cells.removeFirst() }
                if cells.last == "" { cells.removeLast() }
                table.append(cells)
                index += 1
                continue
            } else {
                flushTable()
            }

            if trimmed.hasPrefix(">") {
                flushParagraph(); flushList()
                quote.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                index += 1
                continue
            } else {
                flushQuote()
            }

            if let item = listItem(line) {
                flushParagraph()
                list.append(item)
                index += 1
                continue
            }

            // Lazy continuation of a list item.
            if !list.isEmpty, line.hasPrefix("  ") {
                list[list.count - 1].text += " " + trimmed
                index += 1
                continue
            }
            flushList()
            paragraph.append(line)
            index += 1
        }
        flushAll()
        return blocks
    }

    private static func listItem(_ line: String) -> MarkdownBlock.ListItem? {
        let indent = line.prefix { $0 == " " }.count / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var marker: String
        var rest: Substring
        if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
            marker = "•"
            rest = trimmed.dropFirst(2)
        } else {
            let digits = trimmed.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count < 4 else { return nil }
            let after = trimmed.dropFirst(digits.count)
            guard let dot = after.first, dot == "." || dot == ")", after.dropFirst().first == " " else { return nil }
            marker = digits + "."
            rest = after.dropFirst(2)
        }
        var checked: Bool?
        if rest.hasPrefix("[ ] ") { checked = false; rest = rest.dropFirst(4) }
        else if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") { checked = true; rest = rest.dropFirst(4) }
        if checked != nil { marker = "" }
        return MarkdownBlock.ListItem(marker: marker, text: String(rest), indent: indent, checked: checked)
    }
}
