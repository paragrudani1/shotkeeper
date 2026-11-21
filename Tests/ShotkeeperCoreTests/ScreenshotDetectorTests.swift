import XCTest
@testable import ShotkeeperCore

final class ScreenshotDetectorTests: XCTestCase {
    let detector = ScreenshotDetector()

    func testDefaultLocaleNames() {
        let names = [
            "Screenshot 2026-01-13 at 10.22.11.png",
            "Screen Shot 2019-03-02 at 9.41.02 AM.png",
            "Bildschirmfoto 2026-01-13 um 10.22.11.png",
            "Capture d’écran 2026-01-13 à 10.22.11.png",
            "Capture d'écran 2026-01-13 à 10.22.11.png",
            "Captura de pantalla 2026-01-13 a las 10.22.11.png",
            "Istantanea schermo 2026-01-13 alle 10.22.11.png",
            "Schermafbeelding 2026-01-13 om 10.22.11.png",
            "Captura de Ecrã 2026-01-13 às 10.22.11.png",
            "スクリーンショット 2026-01-13 10.22.11.png",
            "截屏2026-01-13 10.22.11.png",
            "屏幕截图 2026-01-13 10.22.11.png",
            "Screenshot 2026-01-13 at 10.22.11 (2).png",
        ]
        for name in names { XCTAssertTrue(detector.isScreenshot(filename: name), name) }
    }

    func testExtensions() {
        for ext in ["png", "jpg", "jpeg", "heic", "tiff", "PNG", "JPG"] {
            XCTAssertTrue(detector.isScreenshot(filename: "Screenshot 2026-01-13 at 10.22.11.\(ext)"), ext)
        }
        for ext in ["mov", "pdf", "gif", "txt", ""] {
            XCTAssertFalse(detector.isScreenshot(filename: "Screenshot 2026-01-13 at 10.22.11.\(ext)"), ext)
        }
        XCTAssertFalse(detector.isScreenshot(filename: "Screenshot 2026-01-13 at 10.22.11"))
    }

    func testHiddenTempFileIgnored() {
        XCTAssertFalse(detector.isScreenshot(filename: ".Screenshot 2026-01-13 at 10.22.11.png"))
        XCTAssertFalse(detector.isScreenshot(filename: ".Screenshot 2026-01-13 at 10.22.11.png-tmp"))
    }

    func testNonScreenshots() {
        XCTAssertFalse(detector.isScreenshot(filename: "Screenshots of cats.png"))
        XCTAssertFalse(detector.isScreenshot(filename: "Invoice From Acme.png"))
        XCTAssertFalse(detector.isScreenshot(filename: "my Screenshot 2026.png"))
        XCTAssertFalse(detector.isScreenshot(filename: "Screenshot.png"))
    }

    func testDecomposedUnicodeMatches() {
        // "é" as e + combining acute (NFD), as some file APIs report it.
        XCTAssertTrue(detector.isScreenshot(filename: "Capture d’e\u{301}cran 2026-01-13 à 10.22.11.png"))
    }

    func testCustomPrefix() {
        let custom = ScreenshotDetector(customPrefix: "Shot")
        XCTAssertTrue(custom.isScreenshot(filename: "Shot 2026-01-13 at 10.22.11.png"))
        XCTAssertTrue(custom.isScreenshot(filename: "Screenshot 2026-01-13 at 10.22.11.png"))
        XCTAssertFalse(detector.isScreenshot(filename: "Shot 2026-01-13 at 10.22.11.png"))
        XCTAssertNil(ScreenshotDetector(customPrefix: "  ").customPrefix)
    }
}
