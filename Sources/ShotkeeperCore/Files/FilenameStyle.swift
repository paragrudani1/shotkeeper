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
        FilenameStyle(casing: casing).apply(toStem: "Tweet semiconductor flashcards", capturedAt: nil, timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    /// The final file stem for a title (model title or a name the user typed), or nil when `FilenameSanitizer` finds
    /// nothing usable. `capturedAt` is the date for `datePrefix` (in `timeZone`); without one no date is added.
    public func stem(from title: String, capturedAt: Date?, timeZone: TimeZone,
                     maxLength: Int = FilenameSanitizer.defaultMaxLength) -> String? {
        // Leave room for the date, so it never pushes the name over the limit.
        let reserved = datePrefix && capturedAt != nil ? Self.dateLength + 1 : 0
        guard let clean = FilenameSanitizer.stem(from: title, maxLength: max(1, maxLength - reserved)) else { return nil }
        let styled = apply(toStem: clean, capturedAt: capturedAt, timeZone: timeZone)
        guard styled.utf16.count > maxLength else { return styled }
        // A case change can lengthen a name ("ß" → "SS"): cap again with the sanitizer's rules.
        return FilenameSanitizer.stem(from: styled, maxLength: maxLength) ?? clean
    }

    /// Styles an already sanitized stem. A date already at the start ("2026-11-21 …", typed by the user or left
    /// from an earlier rename) is kept, in this style's separator, and no second date is added.
    func apply(toStem stem: String, capturedAt: Date?, timeZone: TimeZone) -> String {
        let (existingDate, rest) = Self.splitLeadingDate(stem)
        let words: String
        switch casing {
        case .sentence: words = Self.sentenceCase(rest)
        case .title: words = Self.titleCase(rest)
        case .kebab: words = Self.kebabCase(rest)
        }
        let date = existingDate ?? (datePrefix ? capturedAt.map { Self.dateString($0, timeZone: timeZone) } : nil)
        guard let date else { return words }
        guard !words.isEmpty else { return date }
        return date + (casing == .kebab ? "-" : " ") + words
    }

    // MARK: Date

    static let dateLength = 10

    /// "2026-11-21": Gregorian, ISO order, whatever the user's locale (names sort by date in Finder).
    static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Splits "2026-11-21 Rest" / "2026-11-21-rest" / "2026-11-21" into the date and the rest.
    static func splitLeadingDate(_ stem: String) -> (date: String?, rest: String) {
        let chars = Array(stem)
        guard chars.count >= dateLength else { return (nil, stem) }
        let pattern = "dddd-dd-dd"
        for (char, kind) in zip(chars.prefix(dateLength), pattern) {
            let ok = kind == "d" ? (char.isASCII && char.isNumber) : char == "-"
            if !ok { return (nil, stem) }
        }
        let date = String(chars.prefix(dateLength))
        if chars.count == dateLength { return (date, "") }
        let next = chars[dateLength]
        guard next == " " || next == "-" else { return (nil, stem) }  // "2026-11-210" is not a date prefix
        var rest = chars.dropFirst(dateLength)
        while let first = rest.first, first == " " || first == "-" { rest = rest.dropFirst() }
        return (date, String(rest))
    }

    // MARK: Casing

    /// Raises the first letter when the first word is all lowercase. A first word with capitals ("iPhone", "macOS",
    /// "PDF") or without letters ("42", "東京") is left alone.
    static func sentenceCase(_ s: String) -> String {
        guard let firstWord = s.split(separator: " ", omittingEmptySubsequences: true).first,
              isAllLowercase(firstWord) else { return s }
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
            return p.isAlphabetic || p.numericType != nil || p.isEmojiPresentation || (p.isEmoji && scalar.value > 0xFF)
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
