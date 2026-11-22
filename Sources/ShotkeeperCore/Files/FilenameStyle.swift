import Foundation

/// How a renamed screenshot's name is written (Settings → General → "Filename style"). Applied after
/// `FilenameSanitizer` by the pipeline and by the toast's "Edit name"; the sanitizer and the collision rules
/// ("Name 2.png") are the same for every style.
public struct FilenameStyle: Equatable, Sendable {
    public enum Casing: String, Codable, Sendable, CaseIterable {
        /// "Tweet semiconductor flashcards" (default). Only the first letter is raised: the model already writes
        /// sentence case and keeps proper nouns ("Invoice from Acme"), which lowering every word would break.
        case sentence
        /// "Tweet Semiconductor Flashcards". Short joining words stay lowercase inside the name.
        case title
        /// "tweet-semiconductor-flashcards". Lowercase, words joined by "-", punctuation dropped.
        case kebab
    }

    public var casing: Casing
    /// Puts the capture date first: "2026-11-21 Tweet semiconductor flashcards" ("2026-11-21-tweet-…" in kebab-case).
    public var datePrefix: Bool

    public init(casing: Casing = .sentence, datePrefix: Bool = false) {
        self.casing = casing
        self.datePrefix = datePrefix
    }

    /// Settings' example for each option.
    public static func example(_ casing: Casing) -> String {
        FilenameStyle(casing: casing).stem(from: "Tweet semiconductor flashcards", capturedAt: nil,
                                           timeZone: TimeZone(secondsFromGMT: 0)!) ?? ""
    }

    /// The final file stem for a title, or nil when nothing usable is left (`FilenameSanitizer` refused it, or the
    /// style removed every character).
    ///
    /// A date the title already starts with ("2026-11-21 …", "2026-11-2 …") is kept as it is and the rest is styled;
    /// no second date is added. Otherwise `capturedAt` is added as the date when `datePrefix` is on. The pipeline
    /// passes the capture time; "Edit name" passes nil, so the name the user typed is kept with or without a date.
    /// Room for the date is reserved only when there is one, so styling a styled name again changes nothing.
    public func stem(from title: String, capturedAt: Date?, timeZone: TimeZone,
                     maxLength: Int = FilenameSanitizer.defaultMaxLength) -> String? {
        let (typedDate, rest) = Self.splitLeadingDate(title.trimmingCharacters(in: .whitespacesAndNewlines))
        let date = typedDate ?? (datePrefix ? capturedAt.map { Self.dateString($0, timeZone: timeZone) } : nil)
        let budget = max(1, maxLength - (date.map { $0.count + 1 } ?? 0))
        guard !rest.isEmpty else { return typedDate }
        guard let clean = FilenameSanitizer.stem(from: rest, maxLength: budget) else { return nil }
        let words = Self.cap(styleWords(clean), maxLength: budget, separator: casing == .kebab ? "-" : " ")
        guard !words.isEmpty else { return typedDate }
        guard let date else { return words }
        return date + (casing == .kebab ? "-" : " ") + words
    }

    private func styleWords(_ stem: String) -> String {
        switch casing {
        case .sentence: return Self.sentenceCase(stem)
        case .title: return Self.titleCase(stem)
        case .kebab: return Self.kebabCase(stem)
        }
    }

    /// Caps at `maxLength` UTF-16 units without splitting a character, backing off to the last `separator` when that
    /// keeps at least half (a case change can lengthen a name: "ß" → "SS"). No trailing separator, dot or space.
    static func cap(_ s: String, maxLength: Int, separator: Character) -> String {
        guard s.utf16.count > maxLength else { return s }
        var out = ""
        var units = 0
        for c in s {
            if units + c.utf16.count > maxLength { break }
            out.append(c)
            units += c.utf16.count
        }
        let next = s.index(s.startIndex, offsetBy: out.count)
        if s[next] != separator, let cut = out.lastIndex(of: separator), out[..<cut].utf16.count >= maxLength / 2 {
            out = String(out[..<cut])
        }
        while let last = out.last, last == separator || last == " " || last == "." || last == "-" { out.removeLast() }
        return out
    }

    // MARK: Date

    /// "2026-11-21": Gregorian, ISO order, whatever the user's locale (names sort by date in Finder).
    static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Splits a leading "yyyy-m-d" date (month and day with 1 or 2 digits) followed by the end, " " or "-":
    /// "2026-11-21 Rest", "2026-11-21-rest", "2026-11-2 rest", "2026-11-21". "2026-11-210 units" has none.
    static func splitLeadingDate(_ stem: String) -> (date: String?, rest: String) {
        let chars = Array(stem)
        var index = 0
        func digits(_ min: Int, _ max: Int) -> Bool {
            var count = 0
            while index < chars.count, count < max, chars[index].isASCII, chars[index].isNumber { index += 1; count += 1 }
            return count >= min
        }
        func dash() -> Bool {
            guard index < chars.count, chars[index] == "-" else { return false }
            index += 1
            return true
        }
        guard digits(4, 4), dash(), digits(1, 2), dash(), digits(1, 2) else { return (nil, stem) }
        let date = String(chars[..<index])
        guard index < chars.count else { return (date, "") }
        guard chars[index] == " " || chars[index] == "-" else { return (nil, stem) }
        var rest = chars[index...]
        while let first = rest.first, first == " " || first == "-" { rest = rest.dropFirst() }
        return (date, String(rest))
    }

    // MARK: Casing

    /// Raises the first letter when the first word is all lowercase. A first word with capitals ("iPhone", "macOS",
    /// "PDF"), with a dot or digits ("x.com", "v1.2") or without letters ("42", "東京") is left alone.
    static func sentenceCase(_ s: String) -> String {
        guard let firstWord = s.split(separator: " ", omittingEmptySubsequences: true).first,
              isAllLowercase(firstWord), !firstWord.contains("."), !firstWord.contains(where: \.isNumber) else { return s }
        return capitalizingFirstLetter(s)
    }

    /// Joining words that stay lowercase inside a Title Case name (Chicago-style short list).
    static let minorWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet", "as", "at", "by", "in", "of", "off", "on",
        "per", "to", "up", "via", "vs", "from", "into", "with",
    ]

    /// Raises the first letter of every all-lowercase word, except minor words that are neither first nor last
    /// nor right after a " - " separator. Words with capitals ("iPhone", "PDF", "GitHub"), words with digits
    /// ("v1.2", "3x") and words without letters are kept. Hyphenated words get each part raised ("Wi-Fi").
    static func titleCase(_ s: String) -> String {
        let words = s.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let lastWordIndex = words.lastIndex { !$0.isEmpty && $0 != "-" }
        var out: [String] = []
        var startsPhrase = true
        for (index, word) in words.enumerated() {
            if word == "-" {  // the sanitizer's separator: what follows starts a new phrase
                out.append(word)
                startsPhrase = true
                continue
            }
            let isMinor = minorWords.contains(word.lowercased()) && isAllLowercase(Substring(word))
            if isMinor, !startsPhrase, index != lastWordIndex {
                out.append(word)
            } else {
                out.append(word.split(separator: "-", omittingEmptySubsequences: false)
                    .map { isAllLowercase($0) && !$0.contains(where: \.isNumber) ? capitalizingFirstLetter(String($0)) : String($0) }
                    .joined(separator: "-"))
            }
            if word.contains(where: \.isLetter) { startsPhrase = false }
        }
        return out.joined(separator: " ")
    }

    /// Lowercase words joined by single "-". Letters and digits of every script, their combining marks and emoji are
    /// kept; apostrophes disappear ("Parag's" → "parags"); a "." between digits stays ("v1.2"); everything else
    /// (spaces, punctuation, symbols, the sanitizer's " - ") becomes one "-".
    static func kebabCase(_ s: String) -> String {
        let chars = Array(s.lowercased())
        var out = ""
        var pendingDash = false
        for (index, char) in chars.enumerated() {
            if isWordCharacter(char) {
                if pendingDash, !out.isEmpty { out.append("-") }
                pendingDash = false
                out.append(char)
            } else if char == "'" || char == "\u{2019}" {
                continue
            } else if char == ".", index > 0, index + 1 < chars.count, chars[index - 1].isNumber, chars[index + 1].isNumber {
                out.append(char)
            } else {
                pendingDash = true
            }
        }
        return out
    }

    private static func isWordCharacter(_ char: Character) -> Bool {
        char.unicodeScalars.contains { scalar in
            let p = scalar.properties
            // The sanitizer's emoji test (incl. U+FE0F: "©️"), so kebab-case keeps what the sanitizer kept.
            return p.isAlphabetic || p.numericType != nil || p.isEmojiPresentation || (p.isEmoji && scalar.value > 0xFF)
                || scalar.value == 0xFE0F
        }
    }

    /// True when the word has letters and none of them is uppercase or titlecase. Caseless scripts (CJK, Arabic)
    /// count as "not lowercase", so nothing is changed for them.
    private static func isAllLowercase(_ word: Substring) -> Bool {
        var sawLowercase = false
        for scalar in word.unicodeScalars {
            let p = scalar.properties
            if p.isUppercase || p.generalCategory == .titlecaseLetter { return false }
            if p.isLowercase { sawLowercase = true }
        }
        return sawLowercase
    }

    private static func capitalizingFirstLetter(_ s: String) -> String {
        guard let index = s.firstIndex(where: \.isLetter) else { return s }
        let letter = s[index]
        return String(s[..<index]) + String(letter).uppercased() + String(s[s.index(after: index)...])
    }
}

extension FilenameSanitizer {
    /// The longest stem (UTF-16 units) the pipeline and "Edit name" produce.
    public static let defaultMaxLength = 80
}
