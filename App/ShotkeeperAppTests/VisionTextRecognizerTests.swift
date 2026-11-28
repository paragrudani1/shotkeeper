import CoreGraphics
import CoreText
import Foundation
import ImageIO
import ShotkeeperCore
import UniformTypeIdentifiers
import XCTest
@testable import Shotkeeper

/// The Vision recognizer on generated images (macos-app CI; a real-Mac check covers real screenshots and timing).
final class VisionTextRecognizerTests: TempDirectoryTestCase {
    /// Black text on white, `yFromTop` in pixels (the drawing of scripts/measure-vision.swift's samples).
    private func render(_ name: String, width: Int, height: Int, texts: [(String, CGFloat, CGFloat)]) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (text, size, yFromTop) in texts {
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ]
            context.textPosition = CGPoint(x: 60, y: CGFloat(height) - yFromTop)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
        }
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testItReadsTheTextOfAnImageInReadingOrder() async throws {
        let url = try render("sample.png", width: 1600, height: 600, texts: [
            ("Quarterly summary", 64, 150),
            ("Invoice number 2026", 64, 400),
        ])

        let lines = try await VisionTextRecognizer().recognize(url)

        guard case .text(let text) = RecognizedText.result(from: lines) else { return XCTFail("no text in \(lines.count) lines") }
        let rows = text.lowercased().components(separatedBy: "\n")
        let summary = try XCTUnwrap(rows.firstIndex { $0.contains("quarterly") }, "found: \(rows.count) lines")
        let invoice = try XCTUnwrap(rows.firstIndex { $0.contains("invoice") }, "found: \(rows.count) lines")
        XCTAssertLessThan(summary, invoice, "top line first")
    }

    func testItRecordsTheCoreSettingsAndReadsTheImageHeight() throws {
        XCTAssertEqual(VisionTextRecognizer().recognizedBy, VisionTextSettings.current.recognizedBy)
        let url = try render("size.png", width: 300, height: 120, texts: [])
        XCTAssertEqual(VisionTextRecognizer.pixelHeight(of: url), 120)
        XCTAssertEqual(VisionTextRecognizer.pixelHeight(of: directory.appendingPathComponent("missing.png")), 0)
    }

    func testAMissingFileThrows() async {
        do {
            _ = try await VisionTextRecognizer().recognize(directory.appendingPathComponent("missing.png"))
            XCTFail("expected an error")
        } catch {}
    }
}
