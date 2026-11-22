import Foundation

/// Decides whether a filename is a finished macOS screenshot. Pure: looks only at the name, never the file.
///
/// macOS first writes a hidden temp file (leading "."), then renames it to the final name; only the final name matches.
/// Default names are "<localized prefix> <date> …", e.g. "Screenshot 2026-01-13 at 10.22.11.png"; some locales
/// (Chinese) put the date right after the prefix with no space. A custom prefix set with
/// `defaults write com.apple.screencapture name <prefix>` is passed in by the app.
public struct ScreenshotDetector: Sendable, Equatable {
    /// Lower-cased extensions macOS can write via `com.apple.screencapture type` that we handle.
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]

    /// Localized default prefixes (old and new macOS naming). Matched case-insensitively after Unicode NFC normalization.
    public static let defaultPrefixes: [String] = [
        "Screenshot", "Screen Shot",                 // English (macOS 10.14+ / older)
        "Bildschirmfoto",                            // German
        "Capture d’écran", "Capture d'écran",        // French (typographic and ASCII apostrophe)
        "Captura de pantalla",                       // Spanish
        "Istantanea schermo",                        // Italian
        "Schermafbeelding",                          // Dutch
        "Captura de Ecrã", "Captura de Tela",        // Portuguese (Portugal / Brazil)
        "スクリーンショット",                           // Japanese
        "截屏", "屏幕截图", "螢幕截圖", "截圖",          // Chinese (Simplified, Traditional)
        "스크린샷",                                    // Korean
    ]

    /// The user's `com.apple.screencapture name`, if set. Default prefixes still match (older files keep them).
    public var customPrefix: String?

    public init(customPrefix: String? = nil) {
        let trimmed = customPrefix?.trimmingCharacters(in: .whitespaces)
        self.customPrefix = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// True for a finished screenshot name such as "Screenshot 2026-01-13 at 10.22.11.png".
    public func isScreenshot(filename: String) -> Bool {
        guard !filename.hasPrefix("."), let dot = filename.lastIndex(of: ".") else { return false }
        let ext = filename[filename.index(after: dot)...].lowercased()
        guard Self.imageExtensions.contains(ext) else { return false }
        let base = String(filename[..<dot]).precomposedStringWithCanonicalMapping.lowercased()
        let prefixes = (customPrefix.map { [$0] } ?? []) + Self.defaultPrefixes
        return prefixes.contains { Self.matches(base: base, prefix: $0) }
    }

    /// The prefix must be followed by whitespace or a digit (the date), so "Screenshots of cats.png" does not match.
    private static func matches(base: String, prefix: String) -> Bool {
        let normalized = prefix.precomposedStringWithCanonicalMapping.lowercased()
        guard base.hasPrefix(normalized) else { return false }
        guard let next = base.dropFirst(normalized.count).first else { return false }
        return next.isWhitespace || next.isNumber
    }
}

extension ScreenshotDetector {
    /// Convenience for URLs.
    public func isScreenshot(_ url: URL) -> Bool { isScreenshot(filename: url.lastPathComponent) }
}

extension ScreenshotDetector {
    /// The moment in a screenshot name, in `timeZone` (macOS names use the Mac's local time): the first
    /// "yyyy-MM-dd" followed by "h.mm.ss" (or "h:mm:ss"), e.g. "Screenshot 2026-01-13 at 10.22.11.png",
    /// "Screen Shot 2019-01-13 at 3.04.05 PM.png", "截屏2026-01-13 10.22.11.png", "スクリーンショット 2026-01-13 午後3.04.05.png".
    /// Nil when there is no complete date and time. Any prefix is accepted.
    ///
    /// Used only to make the upload consent check stricter (the earlier of this and the creation date), so a name
    /// read wrongly can only hold a file back, never let it through. 12-hour markers recognised: AM/PM (also with
    /// dots, after the time), 午前/午後, 上午/下午, 오전/오후 (before or after). An unknown marker reads as the morning
    /// hour, which is the earlier time.
    public static func captureDate(fromFilename filename: String, timeZone: TimeZone = .current) -> Date? {
        guard let parts = scanDateAndTime(Array(filename.precomposedStringWithCanonicalMapping)) else { return nil }
        let (year, month, day, minute, second) = (parts.numbers[0], parts.numbers[1], parts.numbers[2], parts.numbers[4], parts.numbers[5])
        var hour = parts.numbers[3]
        guard (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour), (0...59).contains(minute),
              (0...59).contains(second) else { return nil }

        let before = parts.before.lowercased()
        let after = parts.after.trimmingCharacters(in: .whitespaces).lowercased()
        let isPM = ["pm", "p.m."].contains { after.hasPrefix($0) } || ["午後", "下午", "오후"].contains { before.contains($0) || after.hasPrefix($0) }
        let isAM = ["am", "a.m."].contains { after.hasPrefix($0) } || ["午前", "上午", "오전"].contains { before.contains($0) || after.hasPrefix($0) }
        if isPM || isAM {
            guard (1...12).contains(hour) else { return nil }
            if isPM, hour < 12 { hour += 12 }
            if isAM, hour == 12 { hour = 0 }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil } // "2026-02-30" does not roll over
        return date
    }

    /// The first "dddd-dd-dd", then the text up to the next digit (`before`), then "h.mm.ss" / "h:mm:ss", then the
    /// text up to the next digit (`after`). `numbers` = year, month, day, hour, minute, second.
    private static func scanDateAndTime(_ chars: [Character]) -> (numbers: [Int], before: String, after: String)? {
        func isDigit(_ i: Int) -> Bool { i < chars.count && chars[i].isASCII && chars[i].isNumber }
        func number(_ from: Int, _ length: Int) -> Int? {
            guard from + length <= chars.count, (from..<from + length).allSatisfy(isDigit) else { return nil }
            return Int(String(chars[from..<from + length]))
        }
        func isSeparator(_ i: Int) -> Bool { i < chars.count && (chars[i] == "." || chars[i] == ":") }
        var start = 0
        while start + 10 <= chars.count {
            defer { start += 1 }
            guard start == 0 || !isDigit(start - 1), let year = number(start, 4), chars[start + 4] == "-",
                  let month = number(start + 5, 2), chars[start + 7] == "-", let day = number(start + 8, 2),
                  !isDigit(start + 10) else { continue }
            var i = start + 10
            let beforeStart = i
            while i < chars.count, !isDigit(i) { i += 1 }
            let before = String(chars[beforeStart..<i])
            let hourLength = isDigit(i + 1) ? 2 : 1
            guard let hour = number(i, hourLength) else { return nil }
            i += hourLength
            guard isSeparator(i), let minute = number(i + 1, 2), isSeparator(i + 3), let second = number(i + 4, 2),
                  !isDigit(i + 6) else { return nil }
            i += 6
            let afterStart = i
            while i < chars.count, !isDigit(i) { i += 1 }
            return ([year, month, day, hour, minute, second], before, String(chars[afterStart..<i]))
        }
        return nil
    }
}
