import XCTest
@testable import ShotkeeperCore

final class FinderMetadataTests: XCTestCase {
    func testTagsPayloadIsBinaryPlistArray() throws {
        let data = try FinderMetadata.tagsPayload(["invoice", "Red\n6", "café"])
        XCTAssertEqual(String(decoding: data.prefix(8), as: UTF8.self), "bplist00")
        var format = PropertyListSerialization.PropertyListFormat.xml
        let decoded = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        XCTAssertEqual(format, .binary)
        XCTAssertEqual(decoded as? [String], ["invoice", "Red\n6", "café"])
        XCTAssertEqual(FinderMetadata.decodeTags(data), ["invoice", "Red\n6", "café"])
    }

    func testCommentPayloadIsBinaryPlistString() throws {
        let data = try FinderMetadata.commentPayload("An invoice from Acme")
        XCTAssertEqual(String(decoding: data.prefix(8), as: UTF8.self), "bplist00")
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: data, format: nil) as? String, "An invoice from Acme")
        let long = try FinderMetadata.commentPayload(String(repeating: "a", count: 5000))
        XCTAssertEqual(FinderMetadata.decodeComment(long)?.count, FinderMetadata.maxCommentLength)
    }

    func testMergeKeepsExistingTagsAndColors() {
        XCTAssertEqual(FinderMetadata.mergedTags(existing: ["Invoice\n6", "Work"], adding: ["invoice", "acme", " ", "Acme"]),
                       ["Invoice\n6", "Work", "acme"])
    }

    func testApplyWritesBothAttributes() throws {
        let writer = RecordingMetadataWriter()
        let url = URL(fileURLWithPath: "/tmp/x.png")
        try writer.writeExtendedAttribute(FinderMetadata.tagsAttribute, data: try FinderMetadata.tagsPayload(["Red\n6"]), to: url)
        try FinderMetadata.apply(tags: ["invoice"], comment: "Acme invoice", to: url, using: writer)
        let tags = try writer.readExtendedAttribute(FinderMetadata.tagsAttribute, of: url).flatMap(FinderMetadata.decodeTags)
        XCTAssertEqual(tags, ["Red\n6", "invoice"])
        let comment = try writer.readExtendedAttribute(FinderMetadata.commentAttribute, of: url).flatMap(FinderMetadata.decodeComment)
        XCTAssertEqual(comment, "Acme invoice")
    }

    func testApplyWithNothingWritesNothing() throws {
        let writer = RecordingMetadataWriter()
        try FinderMetadata.apply(tags: [], comment: "  ", to: URL(fileURLWithPath: "/tmp/x.png"), using: writer)
        XCTAssertTrue(writer.attributes.get.isEmpty)
        XCTAssertNoThrow(try NoopFileMetadataWriter().writeExtendedAttribute("a", data: Data(), to: URL(fileURLWithPath: "/x")))
    }
}
