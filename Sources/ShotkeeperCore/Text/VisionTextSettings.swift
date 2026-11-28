import Foundation

/// The settings the app's `VisionTextRecognizer` gives each `VNRecognizeTextRequest` (revision 3), held in core so
/// `text_recognized_by` records them and a later change can find the rows to read again (spec "Vision settings to
/// measure on a real Mac"). The request setup is the one in `scripts/measure-vision.swift`, so its measurements apply.
/// Sources: docs/research/spotlight-shortcuts-ocr.md §3 [V1] [V3] [V4] [WV22];
/// https://developer.apple.com/documentation/vision/vnrecognizetextrequest
public struct VisionTextSettings: Equatable, Sendable {
    /// `VNRequestTextRecognitionLevel` [V4].
    public enum Level: String, Sendable {
        case accurate, fast
    }

    /// `minimumTextHeight`: text smaller than this, relative to the image height, is skipped [V1].
    public enum MinimumTextHeight: Equatable, Sendable {
        /// 1/n of the image height (Apple's default is 1/32 [V1]).
        case fraction(Int)
        /// n pixels, converted per image.
        case pixelFloor(Int)

        /// The value for `minimumTextHeight` for an image `pixelHeight` pixels tall: 1/n, or n / `pixelHeight` for a
        /// pixel floor (the whole image when the height is unknown or smaller than the floor).
        public func relativeHeight(pixelHeight: Int) -> Double {
            switch self {
            case .fraction(let n): return 1 / Double(n)
            case .pixelFloor(let pixels): return min(1, Double(pixels) / Double(max(pixelHeight, 1)))
            }
        }

        var label: String {
            switch self {
            case .fraction(let n): return "1/\(n)"
            case .pixelFloor(let pixels): return "\(pixels)px"
            }
        }
    }

    /// `VNRecognizeTextRequestRevision3`, the Live Text recognizer, on every supported macOS [V1] [WV22].
    public static let revision = 3

    public var level: Level
    public var minimumTextHeight: MinimumTextHeight
    public var usesLanguageCorrection: Bool

    public init(level: Level, minimumTextHeight: MinimumTextHeight, usesLanguageCorrection: Bool) {
        self.level = level
        self.minimumTextHeight = minimumTextHeight
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    /// `automaticallyDetectsLanguage`: on, but Vision supports it with `.accurate` only [V1] [WV22].
    public var automaticallyDetectsLanguage: Bool { level == .accurate }

    /// What `text_recognized_by` records, e.g. `vision-r3-accurate-h1/96-lc0` (the same ids as
    /// `scripts/measure-vision.swift`).
    public var recognizedBy: String {
        "vision-r\(Self.revision)-\(level.rawValue)-h\(minimumTextHeight.label)-lc\(usesLanguageCorrection ? 1 : 0)"
    }

    /// The settings the app uses, measured on a real Mac (2026-11-28, docs/research/vision-ocr-settings.md "Results"):
    /// - `.accurate`: `.fast` found no code line and no Japanese or Arabic text.
    /// - 1/32 (Apple's default [V1]): every lower height missed a spreadsheet number. Parag's decision, a dated
    ///   deviation from the spec's rule (which would pick 1/128).
    /// - Language correction off: on, it puts a space before `(` in code (`URL (string:`).
    /// - Automatic language detection on (`automaticallyDetectsLanguage`): off, Japanese came out as gibberish.
    public static let current = VisionTextSettings(level: .accurate, minimumTextHeight: .fraction(32),
                                                   usesLanguageCorrection: false)
}
