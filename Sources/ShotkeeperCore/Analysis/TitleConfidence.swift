import Foundation

/// One generated token and its log probability (`choices[].logprobs.content[]` of a chat completion;
/// docs/research/openrouter.md, "Logprobs").
public struct TokenLogprob: Equatable, Sendable {
    public var token: String
    public var logprob: Double

    public init(token: String, logprob: Double) {
        self.token = token
        self.logprob = logprob
    }
}

/// Title confidence from token logprobs, on the same scale as Clairic's `perTokenConfidence`
/// (`exp(log_probability / tokens)`, docs/wiki/clairic-field-schema.md): the geometric mean probability of the tokens
/// that carry the `title` string value. A whole-sequence probability would shrink with every word, so a good 7-token
/// title would never pass the 0.5 rename threshold; the per-token mean does not depend on length.
public enum TitleTokenConfidence {
    /// Nil when the tokens do not spell out a top-level `"title": "<value>"` with a non-empty value.
    public static func confidence(tokens: [TokenLogprob], key: String = AnalysisFields.title) -> Double? {
        var offsets: [(start: Int, end: Int)] = []
        var text = [UInt8]()
        for token in tokens {
            let bytes = Array(token.token.utf8)
            offsets.append((text.count, text.count + bytes.count))
            text += bytes
        }
        guard let value = valueRange(of: key, in: text), value.lowerBound < value.upperBound else { return nil }
        let logprobs = zip(tokens, offsets)
            .filter { $0.1.start < value.upperBound && $0.1.end > value.lowerBound }
            .map(\.0.logprob)
            .filter { $0.isFinite }
            .map { min(0, $0) }
        guard !logprobs.isEmpty else { return nil }
        return exp(logprobs.reduce(0, +) / Double(logprobs.count))
    }

    /// Byte range of the string value of top-level `key` in the JSON text (between the quotes), skipping anything
    /// before the first `{` (a code fence, prose) and keys or text inside nested values or other strings.
    static func valueRange(of key: String, in text: [UInt8]) -> Range<Int>? {
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        var depth = 0
        var expectKey = false
        var keyStart: Int?
        var pendingValueFor: String?
        var i = 0
        while i < text.count {
            let byte = text[i]
            if byte == quote {
                // Scan the string.
                let start = i + 1
                var j = start
                while j < text.count, text[j] != quote {
                    j += text[j] == backslash ? 2 : 1
                }
                let end = min(j, text.count)
                if depth == 1, expectKey {
                    keyStart = start
                    pendingValueFor = String(decoding: text[start..<end], as: UTF8.self)
                    expectKey = false
                } else if depth == 1, keyStart != nil, pendingValueFor == key {
                    return start..<end
                } else if depth == 1 {
                    keyStart = nil
                    pendingValueFor = nil
                }
                i = j + 1
                continue
            }
            switch byte {
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                if depth == 1 { expectKey = byte == UInt8(ascii: "{") }
                if depth > 1 { keyStart = nil; pendingValueFor = nil }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth <= 0 { return nil }
            case UInt8(ascii: ","):
                if depth == 1 { expectKey = true; keyStart = nil; pendingValueFor = nil }
            case UInt8(ascii: ":"), UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"):
                break
            default:
                // A non-string value (number, null, true) ends the pending key.
                if depth == 1 { keyStart = nil; pendingValueFor = nil }
            }
            i += 1
        }
        return nil
    }
}

/// Plain rules a title must pass before it can name a file, for backends whose confidence alone is not enough
/// (OpenRouter). A title that fails keeps the original filename.
public enum TitleRules {
    public enum Problem: Equatable, Sendable {
        /// Fewer than `minCharacters` letters/digits after sanitizing.
        case tooShort
        /// More than `maxWords` words or `maxCharacters` characters: a sentence, not a name.
        case tooLong
        /// Nothing usable is left after `FilenameSanitizer` (only punctuation, path characters…).
        case notFilenameSafe
        /// Only words like "Screenshot", "Image", "Untitled", "Screen" (`FilenameSanitizer.genericWords`).
        case generic
        /// Only digits, or only a date ("2026-11-22", "Nov 22, 2026").
        case onlyDigitsOrDate
        /// The words are mostly the app or site name ("Slack", "Google Chrome window" from Google Chrome).
        case mostlyAppName
    }

    public static let minCharacters = 3
    /// Twice the length the model is asked for (`AnalysisFields.titleMaxLength`).
    public static let maxCharacters = AnalysisFields.titleMaxLength * 2
    public static let maxWords = 12

    /// Month and weekday names (English, full and short): a title made only of these and digits is a date.
    static let dateWords: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november",
        "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun", "st", "nd", "rd", "th",
    ]

    /// Parts of a site name that say nothing about the content ("nytimes.com" → "nytimes").
    static let siteNoise: Set<String> = ["www", "com", "org", "net", "io", "app", "co", "ai", "dev"]

    /// Nil when `title` may name the file. `sourceAppOrSite` is the backend's app/site answer, if any.
    public static func problem(with title: String, sourceAppOrSite: String?) -> Problem? {
        let raw = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = Self.words(raw)
        if raw.count > maxCharacters || words.count > maxWords { return .tooLong }
        guard raw.contains(where: \.isLetter) else {
            return raw.contains(where: \.isNumber) ? .onlyDigitsOrDate : .notFilenameSafe
        }
        // "Nov 22, 2026", "Monday 3rd March 2026": the letters are only month/weekday names and ordinal suffixes.
        let letterParts = words.map { String($0.filter(\.isLetter)) }.filter { !$0.isEmpty }
        if raw.contains(where: \.isNumber), letterParts.allSatisfy(dateWords.contains) { return .onlyDigitsOrDate }
        if FilenameSanitizer.isGeneric(raw) { return .generic }
        guard let stem = FilenameSanitizer.stem(from: raw) else { return .notFilenameSafe }
        if stem.filter({ $0.isLetter || $0.isNumber }).count < minCharacters { return .tooShort }
        if let source = sourceAppOrSite {
            let sourceWords = Set(Self.words(source)).subtracting(siteNoise)
            if !sourceWords.isEmpty {
                let informative = words.filter {
                    !sourceWords.contains($0) && !siteNoise.contains($0) && !FilenameSanitizer.genericWords.contains($0)
                }
                if informative.isEmpty || informative.count * 2 < words.count { return .mostlyAppName }
            }
        }
        return nil
    }

    /// Lowercased runs of letters and digits.
    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }
}
