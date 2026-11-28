import Foundation

/// A rectangle in normalized image coordinates (0…1), origin at the bottom left, as Vision reports
/// `VNRecognizedTextObservation.boundingBox` (docs/research/spotlight-shortcuts-ocr.md §3 [V3]).
public struct NormalizedBox: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One line of text found in an image.
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    /// 0…1, the recognizer's confidence in `text`.
    public var confidence: Double
    public var boundingBox: NormalizedBox

    public init(text: String, confidence: Double, boundingBox: NormalizedBox) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Reads the text in a screenshot, on this Mac (spec "Text recognition: where it runs"). The macOS app implements it
/// with Vision (`VisionTextRecognizer`); Linux and the CLI have none, so their rows stay `pending`.
///
/// Privacy: the lines it returns must never leave the Mac or reach a log, an error message or `text_error`.
public protocol TextRecognizer: Sendable {
    /// What `text_recognized_by` records: the recognizer and its settings, e.g. `vision-r3-accurate-h1/32-lc0`.
    var recognizedBy: String { get }
    /// Reads the original file at `url`, at full resolution. Lines in any order; `TextRecognitionRunner` orders them.
    /// It may take long: the first Vision read once took 28.9 s (model load), so callers set no timeout.
    func recognize(_ url: URL) async throws -> [RecognizedLine]
}
