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

    // MARK: Time in the name (upload consent: the earlier of this and the creation date)

    func testCaptureDateFromDefaultNames() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let at102211 = Date(timeIntervalSince1970: 1_768_299_731) // 2026-01-13 10:22:11 UTC
        let names = [
            "Screenshot 2026-01-13 at 10.22.11.png",
            "Screenshot 2026-01-13 at 10.22.11 (2).png",
            "Bildschirmfoto 2026-01-13 um 10.22.11.png",
            "Capture d’écran 2026-01-13 à 10.22.11.png",
            "Captura de pantalla 2026-01-13 a las 10.22.11.png",
            "スクリーンショット 2026-01-13 10.22.11.png",
            "截屏2026-01-13 10.22.11.png",
            "Shot 2026-01-13 at 10:22:11.png",
        ]
        for name in names { XCTAssertEqual(ScreenshotDetector.captureDate(fromFilename: name, timeZone: utc), at102211, name) }
    }

    func testCaptureDateWithTwelveHourMarkers() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let pm = Date(timeIntervalSince1970: 1_547_391_845) // 2019-01-13 15:04:05 UTC
        XCTAssertEqual(ScreenshotDetector.captureDate(fromFilename: "Screen Shot 2019-01-13 at 3.04.05 PM.png", timeZone: utc), pm)
        XCTAssertEqual(ScreenshotDetector.captureDate(fromFilename: "Screen Shot 2019-01-13 at 3.04.05 p.m..png", timeZone: utc), pm)
        XCTAssertEqual(ScreenshotDetector.captureDate(fromFilename: "スクリーンショット 2019-01-13 午後3.04.05.png", timeZone: utc), pm)
        XCTAssertEqual(ScreenshotDetector.captureDate(fromFilename: "스크린샷 2019-01-13 오후 3.04.05.png", timeZone: utc), pm)
        XCTAssertEqual(ScreenshotDetector.captureDate(fromFilename: "截屏2019-01-13 下午3.04.05.png", timeZone: utc), pm)
        let midnight = Date(timeIntervalSince1970: 1_768_262_645) // 2026-01-13 00:04:05 UTC
        XCTAssertEqual(ScreenshotDetector.captureDate(fromFilename: "Screen Shot 2026-01-13 at 12.04.05 AM.png", timeZone: utc),
                       midnight)
        XCTAssertNil(ScreenshotDetector.captureDate(fromFilename: "Screen Shot 2026-01-13 at 15.04.05 PM.png", timeZone: utc),
                     "a 12-hour marker on a 24-hour time is not a time")
    }

    func testCaptureDateUsesTheGivenTimeZone() throws {
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        XCTAssertEqual(ScreenshotDetector.captureDate(fromFilename: "Screenshot 2026-01-13 at 10.22.11.png", timeZone: berlin),
                       Date(timeIntervalSince1970: 1_768_299_731 - 3_600))
    }

    func testNamesWithoutACompleteDateAndTime() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        for name in ["holiday.png", "Screenshot 2026-01-13.png", "Screenshot 2026-02-30 at 10.22.11.png",
                     "Screenshot 2026-13-01 at 10.22.11.png", "Screenshot 2026-01-13 at 25.22.11.png",
                     "Screenshot 2026-01-13 at 10.61.11.png", "Screenshot 12026-01-13 at 10.22.11.png",
                     "Screenshot 2026-01-13 at 10.22.png", "Invoice From Acme.png"] {
            XCTAssertNil(ScreenshotDetector.captureDate(fromFilename: name, timeZone: utc), name)
        }
    }
}
