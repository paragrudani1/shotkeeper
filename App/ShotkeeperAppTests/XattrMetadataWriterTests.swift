import XCTest
@testable import Shotkeeper

final class XattrMetadataWriterTests: XCTestCase {
    private var file: URL!
    private let writer = XattrMetadataWriter()

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("xattr-\(UUID().uuidString).png")
        try Data("not really a png".utf8).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    func testTagsRoundTripAsBinaryPlistArray() throws {
        let tags = ["receipt", "Work\n6", "café ☕️"]
        try writer.setTags(tags, for: file)
        XCTAssertEqual(try writer.tags(of: file), tags)

        let raw = try XCTUnwrap(try writer.readExtendedAttribute(XattrMetadataWriter.tagsAttribute, of: file))
        XCTAssertEqual(Array(raw.prefix(8)), Array("bplist00".utf8), "binary plist, as Finder writes it")
        var format = PropertyListSerialization.PropertyListFormat.xml
        let decoded = try PropertyListSerialization.propertyList(from: raw, format: &format) as? [String]
        XCTAssertEqual(decoded, tags)
        XCTAssertEqual(format, .binary)
    }

    func testCommentRoundTripAsBinaryPlistString() throws {
        try writer.setFinderComment("Invoice from ACME, due 2026-12-01", for: file)
        XCTAssertEqual(try writer.finderComment(of: file), "Invoice from ACME, due 2026-12-01")
        let raw = try XCTUnwrap(try writer.readExtendedAttribute(XattrMetadataWriter.commentAttribute, of: file))
        XCTAssertEqual(Array(raw.prefix(8)), Array("bplist00".utf8))
    }

    func testEmptyValuesRemoveTheAttributes() throws {
        try writer.setTags(["a"], for: file)
        try writer.setFinderComment("c", for: file)
        try writer.setTags([], for: file)
        try writer.setFinderComment("", for: file)
        XCTAssertNil(try writer.readExtendedAttribute(XattrMetadataWriter.tagsAttribute, of: file))
        XCTAssertNil(try writer.readExtendedAttribute(XattrMetadataWriter.commentAttribute, of: file))
        XCTAssertEqual(try writer.tags(of: file), [])
        XCTAssertNil(try writer.finderComment(of: file))
    }

    func testOverwriteReplacesPreviousValue() throws {
        try writer.setTags(["one", "two"], for: file)
        try writer.setTags(["three"], for: file)
        XCTAssertEqual(try writer.tags(of: file), ["three"])
    }

    func testMissingFileThrows() {
        let missing = file.deletingLastPathComponent().appendingPathComponent("missing-\(UUID().uuidString)")
        XCTAssertThrowsError(try writer.setTags(["x"], for: missing))
        XCTAssertThrowsError(try writer.readExtendedAttribute(XattrMetadataWriter.tagsAttribute, of: missing))
    }

    func testFileContentsAreUntouched() throws {
        try writer.setTags(["x"], for: file)
        try writer.setFinderComment("y", for: file)
        XCTAssertEqual(try Data(contentsOf: file), Data("not really a png".utf8))
    }
}
