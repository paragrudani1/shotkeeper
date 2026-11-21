import XCTest
@testable import ShotkeeperCore

final class UndoLogTests: XCTestCase {
    var dir: TempDir!
    var logURL: URL!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        dir = try TempDir()
        logURL = dir.url.appendingPathComponent("state/undo.jsonl")
    }

    override func tearDown() { dir = nil }

    /// Renames `name` to `newName` and logs it.
    private func renamed(_ name: String, to newName: String, log: UndoLog) throws -> (from: URL, to: URL, record: UndoRecord) {
        let from = try dir.file(name, contents: name)
        let to = try FileOrganizer().organize(from, stem: newName, into: nil)
        return (from, to, try log.append(from: from, to: to, at: t0))
    }

    func testUndoLastMovesBack() throws {
        let log = UndoLog(fileURL: logURL)
        let move = try renamed("Screenshot.png", to: "Invoice", log: log)
        XCTAssertEqual(try log.records().map(\.id), [move.record.id])
        XCTAssertEqual(try log.undoLast(), move.record)
        XCTAssertEqual(read(move.from), "Screenshot.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: move.to.path))
        XCTAssertEqual(try log.records(), [])
        XCTAssertThrowsError(try log.undoLast()) { XCTAssertEqual($0 as? UndoError, .nothingToUndo) }
    }

    func testUndoByIDAndAlreadyUndone() throws {
        let log = UndoLog(fileURL: logURL)
        let first = try renamed("A.png", to: "First", log: log)
        let second = try renamed("B.png", to: "Second", log: log)
        try log.undo(id: first.record.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.from.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.to.path))
        XCTAssertThrowsError(try log.undo(id: first.record.id)) {
            XCTAssertEqual($0 as? UndoError, .alreadyUndone(first.record.id))
        }
        XCTAssertThrowsError(try log.undo(id: UUID())) { guard case .notFound = $0 as? UndoError else { return XCTFail() } }
        XCTAssertEqual(try log.records().map(\.id), [second.record.id])
    }

    func testRefusesWhenOriginalPathOccupied() throws {
        let log = UndoLog(fileURL: logURL)
        let move = try renamed("Screenshot.png", to: "Invoice", log: log)
        try Data("newer".utf8).write(to: move.from)
        XCTAssertThrowsError(try log.undoLast()) {
            XCTAssertEqual($0 as? UndoError, .originalPathOccupied(move.from.path))
        }
        XCTAssertEqual(read(move.from), "newer")
        XCTAssertEqual(read(move.to), "Screenshot.png")
        XCTAssertEqual(try log.records().count, 1, "still undoable later")
    }

    func testRefusesWhenFileNoLongerAtDestination() throws {
        let log = UndoLog(fileURL: logURL)
        let move = try renamed("Screenshot.png", to: "Invoice", log: log)
        let elsewhere = dir.url.appendingPathComponent("moved-by-user.png")
        try FileManager.default.moveItem(at: move.to, to: elsewhere)
        XCTAssertThrowsError(try log.undoLast()) {
            XCTAssertEqual($0 as? UndoError, .fileNotAtDestination(move.to.path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    func testSurvivesRestart() throws {
        let move = try renamed("Screenshot.png", to: "Invoice", log: UndoLog(fileURL: logURL))
        let reopened = UndoLog(fileURL: logURL)
        XCTAssertEqual(try reopened.records(), [move.record])
        try reopened.undoLast()
        XCTAssertEqual(try UndoLog(fileURL: logURL).records(), [])
    }

    func testToleratesTruncatedLastLine() throws {
        let log = UndoLog(fileURL: logURL)
        let move = try renamed("Screenshot.png", to: "Invoice", log: log)
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"kind":"move","id":"6F1"#.utf8))  // crash mid-write
        try handle.close()
        XCTAssertEqual(try log.records(), [move.record])
        let next = try renamed("Other.png", to: "Second", log: log)
        XCTAssertEqual(try UndoLog(fileURL: logURL).records(), [move.record, next.record])
        XCTAssertEqual(try log.undoLast(), next.record)
    }

    func testMissingLogFileIsEmpty() throws {
        XCTAssertEqual(try UndoLog(fileURL: logURL).records(), [])
    }
}
