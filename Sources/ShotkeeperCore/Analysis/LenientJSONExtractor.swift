import Foundation

/// Pulls the first JSON object out of free-form LLM output.
///
/// Tolerates: `<think>…</think>` blocks, Markdown code fences, leading/trailing prose, trailing commas, and an object
/// cut off by the token limit (open strings/arrays/objects are closed; a dangling key or partial member is dropped).
public enum LenientJSONExtractor {
    public struct Extraction: Equatable, Sendable {
        public var object: [String: AnalysisJSON]
        /// True when the object was incomplete and had to be closed/trimmed to parse.
        public var wasTruncated: Bool
    }

    public static func firstObject(in text: String) -> Extraction? {
        let cleaned = stripThinking(text)
        var searchStart = cleaned.startIndex
        // Try each '{' in turn: prose before the object may itself contain braces.
        while let open = cleaned[searchStart...].firstIndex(of: "{") {
            if let result = parseObject(startingAt: open, in: cleaned) { return result }
            searchStart = cleaned.index(after: open)
        }
        return nil
    }

    /// Removes complete `<think>…</think>` / `<thinking>…</thinking>` blocks. An unclosed block is left in place
    /// (its text might still precede the answer), and the search simply skips over it.
    static func stripThinking(_ text: String) -> String {
        var s = text
        for (open, close) in [("<think>", "</think>"), ("<thinking>", "</thinking>")] {
            while let o = s.range(of: open, options: .caseInsensitive),
                  let c = s.range(of: close, options: .caseInsensitive, range: o.upperBound..<s.endIndex) {
                s.removeSubrange(o.lowerBound..<c.upperBound)
            }
            // A stray closing tag (opening tag consumed by the server's template): drop everything before it.
            if let c = s.range(of: close, options: [.caseInsensitive, .backwards]) {
                s = String(s[c.upperBound...])
            }
        }
        return s
    }

    private static func parseObject(startingAt open: String.Index, in text: String) -> Extraction? {
        // Scan for the matching close brace, tracking strings and escapes.
        var depth = 0
        var inString = false
        var escaped = false
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" || c == "[" {
                depth += 1
            } else if c == "}" || c == "]" {
                depth -= 1
                if depth == 0 {
                    let candidate = String(text[open...i])
                    if let obj = decodeObject(removingTrailingCommas(candidate)) {
                        return Extraction(object: obj, wasTruncated: false)
                    }
                    return nil
                }
            }
            i = text.index(after: i)
        }
        // Ran out of text inside the object: truncated.
        return repairTruncated(String(text[open...]))
    }

    private static func decodeObject(_ s: String) -> [String: AnalysisJSON]? {
        guard let value = try? AnalysisJSON.parse(s) else { return nil }
        return value.objectValue
    }

    /// Removes commas that are directly followed (ignoring whitespace) by `}` or `]`, outside strings.
    static func removingTrailingCommas(_ s: String) -> String {
        var out: [Character] = []
        var inString = false
        var escaped = false
        let chars = Array(s)
        for (idx, c) in chars.enumerated() {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                out.append(c)
                continue
            }
            if c == "\"" { inString = true }
            if c == "," {
                var j = idx + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" { continue }
            }
            out.append(c)
        }
        return String(out)
    }

    /// Closes a truncated object. Tries the full prefix first, then backs off to earlier member boundaries
    /// (commas outside strings) until something parses.
    static func repairTruncated(_ prefix: String) -> Extraction? {
        var cutPoints: [Int] = []
        var inString = false
        var escaped = false
        let chars = Array(prefix)
        for (idx, c) in chars.enumerated() {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "," {
                cutPoints.append(idx)
            }
        }
        var candidates = [chars.count]
        candidates.append(contentsOf: cutPoints.reversed())
        for end in candidates.prefix(64) {
            if let closed = close(Array(chars[0..<end])), let obj = decodeObject(removingTrailingCommas(closed)) {
                return Extraction(object: obj, wasTruncated: true)
            }
        }
        return nil
    }

    /// Appends whatever closers the prefix needs: a quote for an open string, `null` for a dangling `:`,
    /// then `]`/`}` in stack order. Returns nil when the result cannot be a valid object.
    private static func close(_ chars: [Character]) -> String? {
        var stack: [Character] = []
        var inString = false
        var escaped = false
        for c in chars {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                stack.append("}")
            } else if c == "[" {
                stack.append("]")
            } else if c == "}" || c == "]" {
                guard stack.popLast() == c else { return nil }
            }
        }
        var s = String(chars)
        if escaped { s.removeLast() }
        if inString { s.append("\"") }
        while let last = s.last, last.isWhitespace || last == "," { s.removeLast() }
        if s.last == ":" { s.append("null") }
        guard !stack.isEmpty else { return nil }
        s.append(contentsOf: stack.reversed())
        return s
    }
}
