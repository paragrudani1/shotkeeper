import Foundation

/// One generated token and its log probability (`choices[].logprobs.content[]` of a chat completion;
/// docs/research/openrouter.md, "Logprobs").
public struct TokenLogprob: Equatable, Sendable {
    public var token: String
    public var logprob: Double
    /// "UTF-8 bytes of the token" (API reference `ChatTokenLogprob.bytes`, may be null). A token can be part of a
    /// multi-byte character, whose `token` string then cannot spell it; the bytes always can.
    public var bytes: [UInt8]?

    public init(token: String, logprob: Double, bytes: [UInt8]? = nil) {
        self.token = token
        self.logprob = logprob
        self.bytes = bytes
    }

    /// `bytes` when present, else the token's UTF-8.
    var utf8: [UInt8] { bytes ?? Array(token.utf8) }
}

/// Title confidence from token logprobs, on the same scale as Clairic's `perTokenConfidence`
/// (`exp(log_probability / tokens)`, docs/wiki/clairic-field-schema.md): the geometric mean probability of the tokens
/// that carry the `title` string value. A whole-sequence probability would shrink with every word, so a good 7-token
/// title would never pass the 0.5 rename threshold; the per-token mean does not depend on length.
public enum TitleTokenConfidence {
    /// Nil when the tokens do not spell out a top-level `"title": "<value>"` with a non-empty value. The text is
    /// rebuilt from each token's `bytes` when present. A token that only partly overlaps the value (e.g. `": "Tw`,
    /// which also carries the opening quote) counts with the share of its bytes inside the value.
    public static func confidence(tokens: [TokenLogprob], key: String = AnalysisFields.title) -> Double? {
        var offsets: [(start: Int, end: Int)] = []
        var text = [UInt8]()
        for token in tokens {
            let bytes = token.utf8
            offsets.append((text.count, text.count + bytes.count))
            text += bytes
        }
        guard let value = valueRange(of: key, in: text), value.lowerBound < value.upperBound else { return nil }
        var weightedSum = 0.0, totalWeight = 0.0
        for (token, offset) in zip(tokens, offsets) where offset.end > offset.start && token.logprob.isFinite {
            let overlap = min(offset.end, value.upperBound) - max(offset.start, value.lowerBound)
            guard overlap > 0 else { continue }
            let weight = Double(overlap) / Double(offset.end - offset.start)
            weightedSum += weight * min(0, token.logprob)
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        return exp(weightedSum / totalWeight)
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
        /// Fewer than `minCharacters` letters/digits after sanitizing (a CJK or Hangul character counts as two).
        case tooShort
        /// More than `maxWords` words or `maxCharacters` characters: a sentence, not a name.
        case tooLong
        /// Nothing usable is left after `FilenameSanitizer` (only punctuation, path characters…).
        case notFilenameSafe
        /// Only words like "Screenshot", "Image", "Untitled", "Screen" (`FilenameSanitizer.genericWords`), or one UI
        /// noun as the whole title ("Settings", "Error", "Dashboard").
        case generic
        /// Only digits, or only a date ("2026-11-22", "Nov 22, 2026", "2026年11月22日", "22 ноября 2026").
        case onlyDigitsOrDate
        /// No informative word besides the app or site name ("Slack" from Slack, "Google Chrome" from Google Chrome).
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

    /// Russian month and weekday names (nominative, genitive, short) and the year words.
    static let cyrillicDateWords: Set<String> = [
        "январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь",
        "декабрь", "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября",
        "ноября", "декабря", "янв", "фев", "мар", "апр", "июн", "июл", "авг", "сен", "сент", "окт", "ноя", "дек",
        "понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье",
        "пн", "вт", "ср", "чт", "пт", "сб", "вс", "г", "год", "года",
    ]

    /// Characters that make up CJK and Korean dates ("2026年11月22日", "11月22日（土）", "2026년 11월 22일").
    static let cjkDateCharacters: Set<Character> = [
        "年", "月", "日", "号", "號", "曜", "火", "水", "木", "金", "土", "周", "週", "星", "期", "一", "二", "三",
        "四", "五", "六", "天", "년", "월", "일", "요",
    ]

    /// UI nouns that say nothing on their own; generic only when one of them is the whole title.
    static let uiNouns: Set<String> = [
        "settings", "setting", "preferences", "options", "error", "errors", "dashboard", "page", "home", "homepage",
        "menu", "dialog", "window", "login", "signin", "app", "website", "site", "browser", "tab", "form", "profile",
        "notification", "notifications", "message", "messages", "chat", "inbox", "list", "search", "results", "view",
        "editor", "terminal", "console", "popup", "alert", "warning", "overview", "details",
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
        if raw.contains(where: \.isNumber), letterParts.allSatisfy(isDateWord) { return .onlyDigitsOrDate }
        if FilenameSanitizer.isGeneric(raw) { return .generic }
        if words.count == 1, uiNouns.contains(words[0]) { return .generic }
        guard let stem = FilenameSanitizer.stem(from: raw) else { return .notFilenameSafe }
        if stem.reduce(0, { $0 + weight(of: $1) }) < minCharacters { return .tooShort }
        if let source = sourceAppOrSite {
            let sourceWords = Set(Self.words(source)).subtracting(siteNoise)
            if !sourceWords.isEmpty {
                let informative = words.filter {
                    !sourceWords.contains($0) && !siteNoise.contains($0) && !FilenameSanitizer.genericWords.contains($0)
                }
                if informative.isEmpty { return .mostlyAppName }
            }
        }
        return nil
    }

    /// A month/weekday name or ordinal suffix (English, Russian), or a run of CJK/Korean date characters.
    static func isDateWord(_ letters: String) -> Bool {
        dateWords.contains(letters) || cyrillicDateWords.contains(letters) || letters.allSatisfy(cjkDateCharacters.contains)
    }

    /// How much a character counts toward `minCharacters`: 2 for CJK ideographs, kana and Hangul (one carries about
    /// a word: "設定" = settings), 1 for other letters and digits, 0 for the rest.
    static func weight(of character: Character) -> Int {
        guard character.isLetter || character.isNumber else { return 0 }
        let wide = character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xAC00...0xD7AF, 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
        return wide ? 2 : 1
    }

    /// Lowercased runs of letters and digits.
    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }
}
