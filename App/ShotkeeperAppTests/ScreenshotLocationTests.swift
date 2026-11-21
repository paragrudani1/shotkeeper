import XCTest
@testable import Shotkeeper

final class ScreenshotLocationTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    func testMissingPreferenceFallsBackToDesktop() {
        let result = ScreenshotLocation.resolve(location: nil, name: nil, home: home) { _ in true }
        XCTAssertEqual(result.folder.path, "/Users/tester/Desktop")
        XCTAssertEqual(result.namePrefix, "Screenshot")
    }

    func testBlankPreferenceFallsBackToDesktop() {
        let result = ScreenshotLocation.resolve(location: "  ", name: " ", home: home) { _ in true }
        XCTAssertEqual(result.folder.path, "/Users/tester/Desktop")
        XCTAssertEqual(result.namePrefix, "Screenshot")
    }

    func testTildeIsExpanded() {
        let result = ScreenshotLocation.resolve(location: "~/Pictures/Shots", name: "Shot", home: home) { _ in true }
        XCTAssertEqual(result.folder.path, "/Users/tester/Pictures/Shots")
        XCTAssertEqual(result.namePrefix, "Shot")
    }

    func testAbsoluteAndFileURLPaths() {
        let absolute = ScreenshotLocation.resolve(location: "/Volumes/Data/Shots/", name: nil, home: home) { _ in true }
        XCTAssertEqual(absolute.folder.path, "/Volumes/Data/Shots")
        let fileURL = ScreenshotLocation.resolve(location: "file:///Users/tester/Shots%20Here/", name: nil,
                                                 home: home) { _ in true }
        XCTAssertEqual(fileURL.folder.path, "/Users/tester/Shots Here")
    }

    func testNonexistentFolderFallsBackToDesktop() {
        let result = ScreenshotLocation.resolve(location: "/nope", name: nil, home: home) { _ in false }
        XCTAssertEqual(result.folder.path, "/Users/tester/Desktop")
    }

    func testCurrentReturnsAnAbsoluteFolder() {
        // Reads the real preferences of the CI user; only the shape is asserted.
        let current = ScreenshotLocation.current()
        XCTAssertTrue(current.folder.path.hasPrefix("/"))
        XCTAssertFalse(current.namePrefix.isEmpty)
    }
}
