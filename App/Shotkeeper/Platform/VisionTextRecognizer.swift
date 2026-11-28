import Foundation
import ImageIO
import ShotkeeperCore
import Vision

/// Core's `TextRecognizer` with Apple Vision: one `VNRecognizeTextRequest`, revision 3 (the Live Text recognizer), on
/// the original file at full resolution, on this Mac. The same request setup as `scripts/measure-vision.swift`, so its
/// measurements apply; the values come from core's `VisionTextSettings.current`.
/// Sources: docs/research/spotlight-shortcuts-ocr.md §3 [V1] [V2] [V3] [V4] [WV19] [WV22] [WV24];
///   https://developer.apple.com/documentation/vision/vnrecognizetextrequest
///   https://developer.apple.com/documentation/vision/recognizing-text-in-images
/// - Vision runs on the device: "all of Vision's processing happens on the user's device" [V3] [WV19].
/// - One code path on every supported macOS: not the macOS 15 `RecognizeTextRequest` [V2] [WV24], so results don't
///   differ by OS. Revision 3 and `automaticallyDetectsLanguage` need macOS 13 [V1]; the app targets 14.
///
/// Privacy: the recognized lines are only returned to `TextRecognitionRunner`, never logged. Errors are Vision's
/// own (`TextRecognitionRunner` stores only their domain and code).
struct VisionTextRecognizer: TextRecognizer {
    let settings: VisionTextSettings

    init(settings: VisionTextSettings = .current) {
        self.settings = settings
    }

    var recognizedBy: String { settings.recognizedBy }

    /// Runs Vision on a utility-priority queue, not on the main thread or the Swift concurrency pool: `perform` blocks
    /// for the whole read. No timeout: the first read after launch once took 28.9 s, probably the model load
    /// (docs/research/vision-ocr-settings.md "Results").
    func recognize(_ url: URL) async throws -> [RecognizedLine] {
        let settings = settings
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try Self.recognizeNow(url, settings: settings) })
            }
        }
    }

    static func recognizeNow(_ url: URL, settings: VisionTextSettings) throws -> [RecognizedLine] {
        // One image at a time, its buffers freed before the next (memory stays bounded while reading).
        try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = settings.level == .accurate ? .accurate : .fast
            request.minimumTextHeight = Float(settings.minimumTextHeight.relativeHeight(pixelHeight: pixelHeight(of: url)))
            request.usesLanguageCorrection = settings.usesLanguageCorrection
            request.automaticallyDetectsLanguage = settings.automaticallyDetectsLanguage
            // recognitionLanguages left at the default, as in the measurement.
            let handler = VNImageRequestHandler(url: url, options: [:])
            try handler.perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                // Normalized, origin at the bottom left [V3]: the same convention as core's `NormalizedBox`.
                let box = observation.boundingBox
                return RecognizedLine(text: candidate.string, confidence: Double(candidate.confidence),
                                      boundingBox: NormalizedBox(x: Double(box.origin.x), y: Double(box.origin.y),
                                                                 width: Double(box.width), height: Double(box.height)))
            }
        }
    }

    /// The image's height in pixels from its header (ImageIO), 0 when unknown (a pixel floor then covers the image).
    static func pixelHeight(of url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return 0 }
        return properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    }
}
