import CoreGraphics
import CoreText
import Foundation
import ImageIO
import ShotkeeperCore
import UniformTypeIdentifiers

/// A small generated "screenshot" (a fake receipt) for the setup screen's "Test connection" button, so a test never
/// sends one of the user's real screenshots.
enum ConnectionTestImage {
    static let size = (width: 640, height: 400)
    static let lines = ["Coffee Corner — Receipt #1042", "Flat white   $4.50", "Croissant    $3.75",
                        "Total        $8.25", "Paid by card, 21 Nov 2026"]

    static func payload() throws -> ImagePayload {
        let (width, height) = size
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImagePreparerError.unreadable("test image")
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 30, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        for (offset, text) in lines.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 40, y: height - 70 - offset * 64)
            CTLineDraw(line, context)
        }
        guard let image = context.makeImage() else { throw ImagePreparerError.unreadable("test image") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImagePreparerError.unreadable("test image")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImagePreparerError.unreadable("test image") }
        return ImagePayload(data: data as Data, mimeType: "image/png", pixelWidth: width, pixelHeight: height)
    }

    static var context: AnalysisContext {
        AnalysisContext(originalFilename: "Screenshot 2026-11-21 at 10.00.00.png", capturedAt: Date())
    }

    /// One line for the UI, e.g. `OK: “Coffee Corner receipt” (receipt, 4 tags)`.
    static func summary(_ analysis: ScreenshotAnalysis) -> String {
        let title = analysis.title.map { "“\($0)”" } ?? "no title"
        let tags = analysis.tags.count == 1 ? "1 tag" : "\(analysis.tags.count) tags"
        var text = "OK: \(title) (\(analysis.contentType.rawValue), \(tags))"
        if let tokens = analysis.billedInputTokens { text += ", \(tokens) input tokens" }
        return text
    }
}
