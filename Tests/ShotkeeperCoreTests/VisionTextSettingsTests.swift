import XCTest
@testable import ShotkeeperCore

/// The Vision constants that `text_recognized_by` records (spec "Vision settings to measure on a real Mac").
final class VisionTextSettingsTests: XCTestCase {
    func testTheRecognizerIdNamesTheRevisionLevelHeightAndLanguageCorrection() {
        // Same shape as scripts/measure-vision.swift's ids and the spec's example `vision-r3-accurate-h1/96-lc0`.
        XCTAssertEqual(VisionTextSettings(level: .accurate, minimumTextHeight: .fraction(96), usesLanguageCorrection: false)
            .recognizedBy, "vision-r3-accurate-h1/96-lc0")
        XCTAssertEqual(VisionTextSettings(level: .fast, minimumTextHeight: .pixelFloor(10), usesLanguageCorrection: true)
            .recognizedBy, "vision-r3-fast-h10px-lc1")
    }

    /// PROVISIONAL until Parag's measurement is in docs/research/vision-ocr-settings.md (merge gate of ticket 04):
    /// Apple's defaults, which the measurement replaces.
    func testTheCurrentSettingsAreApplesDefaultsUntilMeasured() {
        XCTAssertEqual(VisionTextSettings.current.recognizedBy, "vision-r3-accurate-h1/32-lc1")
    }

    func testAutomaticLanguageDetectionIsOnForAccurateOnly() {
        XCTAssertTrue(VisionTextSettings(level: .accurate, minimumTextHeight: .fraction(32), usesLanguageCorrection: true)
            .automaticallyDetectsLanguage)
        XCTAssertFalse(VisionTextSettings(level: .fast, minimumTextHeight: .fraction(32), usesLanguageCorrection: true)
            .automaticallyDetectsLanguage)
    }

    func testAFractionIsTheSameForEveryImage() {
        XCTAssertEqual(VisionTextSettings.MinimumTextHeight.fraction(32).relativeHeight(pixelHeight: 2880), 0.03125)
        XCTAssertEqual(VisionTextSettings.MinimumTextHeight.fraction(32).relativeHeight(pixelHeight: 100), 0.03125)
    }

    func testAPixelFloorIsConvertedPerImage() {
        let floor = VisionTextSettings.MinimumTextHeight.pixelFloor(10)
        XCTAssertEqual(floor.relativeHeight(pixelHeight: 2000), 0.005)
        XCTAssertEqual(floor.relativeHeight(pixelHeight: 40), 0.25)
        XCTAssertEqual(floor.relativeHeight(pixelHeight: 6), 1, "never more than the whole image")
        XCTAssertEqual(floor.relativeHeight(pixelHeight: 0), 1, "unknown height")
    }
}
