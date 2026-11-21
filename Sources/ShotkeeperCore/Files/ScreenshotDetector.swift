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
