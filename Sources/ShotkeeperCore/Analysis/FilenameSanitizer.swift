import Foundation

/// Turns a model-proposed title into a safe filename stem (no extension), or nil when nothing usable remains.
///
/// Rules (in order):
/// 1. NFC-normalize. Control characters, tabs, newlines, line/paragraph separators become spaces.
/// 2. Invisible format characters (zero-width space/joiner/non-joiner, BOM, word joiner, bidi marks) are removed,
///    except inside emoji grapheme clusters (where ZWJ and tag characters are part of the emoji).
/// 3. Path/reserved punctuation: `/ \ | :` become a " - " separator; `* ? " < >` become spaces.
/// 4. Whitespace collapses to single spaces; repeated separators collapse to one.
/// 5. Leading dots, dashes and spaces are trimmed (no hidden files, no option-like names); trailing dots, spaces and
///    dangling separator dashes are trimmed.
/// 6. Generic titles ("Screenshot", "Untitled image", "Screenshot 2026-01-13 at 10.22.11", …) and titles with no
///    letters, digits or emoji return nil.
/// 7. Capped at `maxLength` UTF-16 units without splitting a grapheme cluster, preferring a word boundary when one
///    exists in the second half, and never leaving a trailing space/dot/dash.
///
/// Casing is left untouched: sentence-style casing is the model's job.
public enum FilenameSanitizer {
    public static func stem(from title: String, maxLength: Int = 80) -> String? {
        guard maxLength > 0 else { return nil }
        var s = title.precomposedStringWithCanonicalMapping

        s = s.compactMap(cleanCharacter).joined()
        s = collapseWhitespace(s)
        s = collapseSeparators(s)
        s = trimEnds(s)
        guard !s.isEmpty, s != ".", s != "..", hasSubstance(s), !isGeneric(s) else { return nil }

        s = cap(s, maxLength: maxLength)
        s = trimEnds(s).precomposedStringWithCanonicalMapping
        guard !s.isEmpty, hasSubstance(s) else { return nil }
        return s
    }

    // MARK: Character cleaning

    /// Characters that cannot appear in a macOS/Finder filename or would turn into a path separator.
    private static let separatorScalars: Set<Unicode.Scalar> = ["/", "\\", "|", ":"]
    private static let removedScalars: Set<Unicode.Scalar> = ["*", "?", "\"", "<", ">"]

    private static func cleanCharacter(_ c: Character) -> String? {
        let scalars = c.unicodeScalars
        if isEmojiCluster(c) {
            // Keep the cluster intact but drop a stray BOM / word joiner that might ride along.
            let kept = scalars.filter { $0.value != 0xFEFF && $0.value != 0x2060 }
            return kept.isEmpty ? nil : String(String.UnicodeScalarView(kept))
        }
        var out = String.UnicodeScalarView()
        for u in scalars {
            switch u.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                out.append(" ")
            case .format:
                continue // zero-width chars, BOM, bidi controls
            default:
                if separatorScalars.contains(u) {
                    out.append(contentsOf: " - ".unicodeScalars)
                } else if removedScalars.contains(u) {
                    out.append(" ")
                } else {
                    out.append(u)
                }
            }
        }
        return out.isEmpty ? nil : String(out)
    }

    private static func isEmojiCluster(_ c: Character) -> Bool {
        c.unicodeScalars.contains { u in
            u.properties.isEmojiPresentation || (u.properties.isEmoji && u.value > 0xFF && u.value != 0x200D)
                || u.value == 0xFE0F
        } && !c.unicodeScalars.allSatisfy { $0.properties.generalCategory == .format }
    }

    // MARK: Whitespace and separators

    private static func collapseWhitespace(_ s: String) -> String {
        var out = ""
        var pendingSpace = false
        for c in s {
            if c.isWhitespace {
                pendingSpace = true
            } else {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(c)
            }
        }
        return out
    }

    /// "a -  - b" → "a - b" (after whitespace collapse separators look like " - ").
    private static func collapseSeparators(_ s: String) -> String {
        var s = s
        while s.contains(" - - ") { s = s.replacingOccurrences(of: " - - ", with: " - ") }
        return s
    }

    private static func trimEnds(_ s: String) -> String {
        var chars = Substring(s)
        while let f = chars.first, f == "." || f == "-" || f == " " || f == "\u{2013}" || f == "\u{2014}" {
            chars = chars.dropFirst()
        }
        // Trailing: dots and spaces always; a dash only when it is a dangling separator (" -") or a lone dash,
        // so "COVID-19" stays intact and "Notes -" becomes "Notes".
        while let l = chars.last {
            if l == "." || l == " " {
                chars = chars.dropLast()
            } else if l == "-" || l == "\u{2013}" || l == "\u{2014}" {
                let before = chars.dropLast()
                if before.isEmpty || before.last == " " || before.last == "-" { chars = before } else { break }
            } else {
                break
            }
        }
        return String(chars)
    }

    // MARK: Usefulness

    private static func hasSubstance(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
            || s.contains(where: isEmojiCluster)
    }

    /// Words that carry no information about a screenshot's content. A title made only of these
    /// (ignoring digits and punctuation, e.g. "Screenshot 2026-01-13 at 10.22.11 PM") is generic.
    static let genericWords: Set<String> = [
        "screenshot", "screenshots", "screen", "screens", "shot", "shots", "capture", "captured", "screencap",
        "screengrab", "grab", "snapshot", "cleanshot", "image", "images", "img", "picture", "pic", "photo",
        "untitled", "unnamed", "unknown", "file", "document", "doc", "title", "none", "null", "nil", "na", "n", "a",
        "an", "the", "of", "at", "on", "no", "new", "copy", "am", "pm", "and", "my", "this", "from", "with",
    ]

    static func isGeneric(_ s: String) -> Bool {
        let words = s.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        guard !words.isEmpty else { return !s.contains(where: isEmojiCluster) && !s.contains(where: \.isNumber) }
        return words.allSatisfy(genericWords.contains)
    }

    // MARK: Length cap

    private static func cap(_ s: String, maxLength: Int) -> String {
        guard s.utf16.count > maxLength else { return s }
        var out = ""
        var units = 0
        for c in s {
            let n = c.utf16.count
            if units + n > maxLength { break }
            out.append(c)
            units += n
        }
        // We cut inside a word if the next character in the original is not a space: back off to the last space
        // when that keeps at least half of the budget.
        let nextIndex = s.index(s.startIndex, offsetBy: out.count)
        let cutMidWord = nextIndex < s.endIndex && s[nextIndex] != " "
        if cutMidWord, let space = out.lastIndex(of: " "), out[..<space].utf16.count >= maxLength / 2 {
            out = String(out[..<space])
        }
        return out
    }
}

/// Normalizes keyword tags from any backend: lowercase, trimmed, no leading '#', short, unique, not generic.
public enum TagNormalizer {
    public static let maxTags = 8
    public static let maxTagLength = 32
    public static let maxWordsPerTag = 3

    public static func normalize(_ raw: [String], limit: Int = maxTags) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for tag in raw {
            guard out.count < limit, let t = normalizeOne(tag), seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return out
    }

    static func normalizeOne(_ raw: String) -> String? {
        var t = raw.precomposedStringWithCanonicalMapping.lowercased()
        t = String(t.unicodeScalars.filter {
            let cat = $0.properties.generalCategory
            return cat != .control && cat != .format
        }.map(Character.init))
        t = t.split(whereSeparator: { $0.isWhitespace || $0 == "_" }).joined(separator: " ")
        while t.hasPrefix("#") { t.removeFirst() }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?\"'`()[]{}"))
        guard !t.isEmpty, t.utf16.count <= maxTagLength,
              t.split(separator: " ").count <= maxWordsPerTag,
              t.contains(where: { $0.isLetter || $0.isNumber }),
              !FilenameSanitizer.isGeneric(t)
        else { return nil }
        return t
    }
}
