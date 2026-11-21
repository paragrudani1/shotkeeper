import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import ShotkeeperCore

final class FileOrganizerTests: XCTestCase {
    var dir: TempDir!
    let organizer = FileOrganizer()

    override func setUpWithError() throws { dir = try TempDir() }
    override func tearDown() { dir = nil }

    func testRenameInPlaceKeepsExtension() throws {
        let source = try dir.file("Screenshot 1.PNG", contents: "img")
        let result = try organizer.organize(source, stem: "Invoice From Acme", into: nil)
        XCTAssertEqual(result.lastPathComponent, "Invoice From Acme.PNG")
        XCTAssertEqual(read(result), "img")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testCollisionsGetSuffixesAndNeverOverwrite() throws {
        let first = try dir.file("Title.png", contents: "one")
        let second = try dir.file("Title 2.png", contents: "two")
        let source = try dir.file("Screenshot.png", contents: "new")
        let result = try organizer.organize(source, stem: "Title", into: nil)
        XCTAssertEqual(result.lastPathComponent, "Title 3.png")
        XCTAssertEqual(read(first), "one")
        XCTAssertEqual(read(second), "two")
        XCTAssertEqual(read(result), "new")
        XCTAssertEqual(try dir.names(), ["Title 2.png", "Title 3.png", "Title.png"])
    }

    func testAlreadyNamedIsNoOp() throws {
        let source = try dir.file("Title.png")
        XCTAssertEqual(try organizer.organize(source, stem: "Title", into: nil), source.standardizedFileURL)
        XCTAssertEqual(try organizer.organize(source, stem: nil, into: nil), source.standardizedFileURL)
        // "Title 2.png" with stem "Title" while "Title.png" exists: already the right collision name.
        let second = try dir.file("Title 2.png")
        XCTAssertEqual(try organizer.organize(second, stem: "Title", into: nil), second.standardizedFileURL)
    }

    func testMoveIntoFolderCreatesIt() throws {
        let source = try dir.file("Screenshot.png", contents: "img")
        let target = dir.url.appendingPathComponent("Organized/2026", isDirectory: true)
        let result = try organizer.organize(source, stem: "Receipt", into: target)
        XCTAssertEqual(result.path, target.appendingPathComponent("Receipt.png").path)
        XCTAssertEqual(read(result), "img")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testMoveKeepingName() throws {
        let source = try dir.file("Screenshot.png", contents: "img")
        try dir.file("Screenshot.png", contents: "other", in: "Organized")
        let result = try organizer.organize(source, stem: nil, into: dir.url.appendingPathComponent("Organized"))
        XCTAssertEqual(result.lastPathComponent, "Screenshot 2.png")
        XCTAssertEqual(read(dir.url.appendingPathComponent("Organized/Screenshot.png")), "other")
    }

    func testCrossVolumeMoveCopiesVerifiesThenRemovesSource() throws {
        let source = try dir.file("Screenshot.png", contents: String(repeating: "x", count: 10_000))
        try dir.file("Receipt.png", contents: "existing", in: "Other")
        let sourcePath = source.standardizedFileURL.path
        let crossVolume = FileOrganizer(renameNoReplace: { from, to in
            from == sourcePath ? EXDEV : NoReplaceRename.rename(from, to)
        })
        let result = try crossVolume.organize(source, stem: "Receipt", into: dir.url.appendingPathComponent("Other"))
        XCTAssertEqual(result.lastPathComponent, "Receipt 2.png")
        XCTAssertEqual(read(result)?.count, 10_000)
        XCTAssertEqual(read(dir.url.appendingPathComponent("Other/Receipt.png")), "existing")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try dir.names(in: "Other"), ["Receipt 2.png", "Receipt.png"], "no temp files left")
    }

    func testCrossVolumeFailureKeepsSource() throws {
        let source = try dir.file("Screenshot.png", contents: "img")
        let sourcePath = source.standardizedFileURL.path
        let failing = FileOrganizer(renameNoReplace: { from, _ in from == sourcePath ? EXDEV : EACCES })
        XCTAssertThrowsError(try failing.organize(source, stem: "Receipt", into: dir.url.appendingPathComponent("Other")))
        XCTAssertEqual(read(source), "img")
        XCTAssertEqual(try dir.names(in: "Other"), [], "temp copy cleaned up")
    }

    func testInvalidStemsAreRejectedNotFixed() throws {
        let source = try dir.file("Screenshot.png")
        for stem in ["", "   ", "a/b", ".hidden", String(repeating: "a", count: 300)] {
            XCTAssertThrowsError(try organizer.organize(source, stem: stem, into: nil), stem) { error in
                XCTAssertEqual(error as? FileOrganizerError, .invalidStem(stem))
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMissingSource() {
        let missing = dir.url.appendingPathComponent("nope.png")
        XCTAssertThrowsError(try organizer.organize(missing, stem: "x", into: nil)) {
            XCTAssertEqual($0 as? FileOrganizerError, .sourceMissing(missing.path))
        }
    }

    func testTooManyCollisions() throws {
        var limited = FileOrganizer()
        limited.maxCollisionSuffix = 2
        try dir.file("T.png"); try dir.file("T 2.png")
        let source = try dir.file("S.png")
        XCTAssertThrowsError(try limited.organize(source, stem: "T", into: nil)) {
            guard case .tooManyCollisions = $0 as? FileOrganizerError else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testExactMoveRefusesExistingDestination() throws {
        let source = try dir.file("a.png", contents: "a")
        let dest = try dir.file("b.png", contents: "b")
        XCTAssertThrowsError(try organizer.move(source, to: dest)) {
            XCTAssertEqual($0 as? FileOrganizerError, .destinationExists(dest.path))
        }
        XCTAssertEqual(read(source), "a")
        XCTAssertEqual(read(dest), "b")
    }

    func testNoReplacePrimitivesNeverReplace() throws {
        for strategy in [NoReplaceRename.rename, NoReplaceRename.linkThenUnlink, NoReplaceRename.reserveThenRename] {
            let a = try dir.file("a.png", contents: "a")
            let b = try dir.file("b.png", contents: "b")
            XCTAssertEqual(strategy(a.path, b.path), EEXIST)
            XCTAssertEqual(read(a), "a")
            XCTAssertEqual(read(b), "b")
            let c = dir.url.appendingPathComponent("c.png")
            XCTAssertEqual(strategy(a.path, c.path), 0)
            XCTAssertEqual(read(c), "a")
            XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
            try FileManager.default.removeItem(at: b)
            try FileManager.default.removeItem(at: c)
        }
    }
}
