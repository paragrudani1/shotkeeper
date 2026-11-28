import Foundation

/// Renders a CHANGELOG.md section as the HTML fragment Sparkle shows in its update window.
///
/// A deliberately small subset (auto-update spec, "Core seam: `ReleasePlan`"): paragraphs, `- ` bullet lists and
/// inline `` `code` ``. Everything else is escaped as text, so a stray `<` never becomes markup.
/// The result has no DOCTYPE or `<body>`, so `generate_appcast` treats it as a fragment and embeds it in the appcast
/// (Sparkle 2.10.1 `generate_appcast/ArchiveItem.swift:475-477`). The release job also passes
/// `--embed-release-notes`, which embeds it either way.
enum ReleaseNotesHTML {
    private enum Block {
        case paragraph([String])
        case list([String])
    }

    static func render(_ markdown: String) -> String {
        var blocks: [Block] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                blocks.append(.paragraph([])) // ends the current block; empty ones are dropped below
            } else if line.hasPrefix("- ") {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if case .list(let items) = blocks.last { blocks[blocks.count - 1] = .list(items + [item]) }
                else { blocks.append(.list([item])) }
            } else if case .list(var items) = blocks.last, line.first?.isWhitespace == true {
                items[items.count - 1] += " " + text // an indented line continues the bullet above it
                blocks[blocks.count - 1] = .list(items)
            } else if case .paragraph(let lines) = blocks.last, !lines.isEmpty {
                blocks[blocks.count - 1] = .paragraph(lines + [text])
            } else {
                blocks.append(.paragraph([text]))
            }
        }
        return blocks.compactMap { block -> String? in
            switch block {
            case .paragraph(let lines) where lines.isEmpty: return nil
            case .paragraph(let lines): return "<p>\(inline(lines.joined(separator: " ")))</p>"
            case .list(let items): return (["<ul>"] + items.map { "<li>\(inline($0))</li>" } + ["</ul>"]).joined(separator: "\n")
            }
        }.joined(separator: "\n")
    }

    /// Escapes the text and turns each pair of backticks into `<code>`; an unpaired last backtick stays literal.
    private static func inline(_ text: String) -> String {
        var parts = text.split(separator: "`", omittingEmptySubsequences: false).map(String.init)
        if parts.count.isMultiple(of: 2) { // an odd number of backticks
            let last = parts.removeLast()
            parts[parts.count - 1] += "`" + last
        }
        return parts.enumerated().map { index, part in
            index.isMultiple(of: 2) ? escape(part) : "<code>\(escape(part))</code>"
        }.joined()
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }
}
