import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import ShotkeeperCore

/// Seam 1 for "Sort into subfolders" (wave 2 ticket 04): `ScreenshotProcessor.process` with `StubAnalyzer`, a
/// `TempDir`, an in-memory index and a real `UndoLog`. Checks where the file ends up on disk, the index row, the
/// undo records and what the toast is told.
final class ScreenshotProcessorSubfolderTests: XCTestCase {
    var dir: TempDir!
    var index: ScreenshotIndex!
    var undoLog: UndoLog!
    var settings: Locked<AppSettings>!
    var organized: URL!
    let shotName = "Screenshot 2026-01-13 at 10.22.11.png"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        dir = try TempDir()
        index = try ScreenshotIndex.inMemory()
        undoLog = UndoLog(fileURL: dir.url.appendingPathComponent("state/undo.jsonl"))
        organized = dir.url.appendingPathComponent("Organized", isDirectory: true)
        try FileManager.default.createDirectory(at: organized, withIntermediateDirectories: true)
        var configured = AppSettings()
        configured.uploadGrants = [AppSettings.cloudflareSinceEver]
        configured.moveEnabled = true
        configured.organizedFolder = organized
        configured.subfolderRule = .byType
        settings = Locked(configured)
    }

    override func tearDown() { dir = nil }

    private func processor(_ analyzer: StubAnalyzer, organizer: FileOrganizer = FileOrganizer()) -> ScreenshotProcessor {
        let settings = self.settings!
        let now = self.now
        return ScreenshotProcessor(analyzer: analyzer, imagePreparer: PassthroughImagePreparer(), index: index,
                                   organizer: organizer, undoLog: undoLog, settings: { settings.get }, now: { now })
    }

    private func screenshot(_ name: String? = nil, contents: String = "png bytes") throws -> URL {
        try dir.file(name ?? shotName, contents: contents, in: "Desktop").standardizedFileURL
    }

    private func shot(_ type: ContentType, source: String?, title: String? = "Invoice From Acme",
                      confidence: Double = 0.9) -> ScreenshotAnalysis {
        var result = analysis(title: title, confidence: confidence)
        result.contentType = type
        result.sourceAppOrSite = source
        return result
    }

    private func path(_ relative: String) -> URL { organized.appendingPathComponent(relative).standardizedFileURL }

    func testByTypeMovesIntoTheTypeFolderAndReportsIt() async throws {
        let source = try screenshot()
        let report = try await processor(StubAnalyzer(shot(.receipt, source: "Mail"))).processWithReport(source)

        let expected = path("Receipts/Invoice From Acme.png")
        XCTAssertEqual(report.outcome, .processed(finalURL: expected, renamed: true, moved: true))
        XCTAssertEqual(report.sortedInto, ["Receipts"])
        XCTAssertEqual(read(expected), "png bytes")
        XCTAssertEqual(try index.lookup(byPath: expected.path)?.status, .done)
        XCTAssertNil(try index.lookup(byPath: expected.path)?.note)
        XCTAssertEqual(try undoLog.records().map(\.to), [expected.path], "one undo record for the move")
    }

    func testEachRuleRoutesEachType() async throws {
        let cases: [(SubfolderRule, ContentType, String?, String)] = [
            (.byType, .tweet, "X", "Tweets"), (.byType, .article, nil, "Articles"), (.byType, .code, "Xcode", "Code"),
            (.byType, .chat, "Slack", "Chats"), (.byType, .design, "Figma", "Designs"), (.byType, .other, nil, "Other"),
            (.bySource, .chat, "Slack", "Slack"), (.bySource, .code, nil, "Other"), (.bySource, .tweet, "unknown", "Other"),
            (.byTypeThenSource, .chat, "Slack", "Chats/Slack"), (.byTypeThenSource, .code, "GitHub", "Code/GitHub"),
            (.byTypeThenSource, .receipt, nil, "Receipts"), (.byTypeThenSource, .design, "Desktop", "Designs"),
            (.off, .receipt, "Mail", ""),
        ]
        for (offset, (rule, type, source, folder)) in cases.enumerated() {
            settings.mutate { $0.subfolderRule = rule }
            let original = try screenshot("Screenshot 2026-01-13 at 10.22.\(10 + offset).png", contents: "shot \(offset)")
            let outcome = try await processor(StubAnalyzer(shot(type, source: source, title: "Note \(offset)")))
                .process(original)
            let expected = path(folder.isEmpty ? "Note \(offset).png" : "\(folder)/Note \(offset).png")
            XCTAssertEqual(outcome, .processed(finalURL: expected, renamed: true, moved: true), "\(rule) \(type)")
            XCTAssertEqual(read(expected), "shot \(offset)")
        }
    }

    func testAnExistingFolderIsReusedBySourceKeyAndInAnyLetterCase() async throws {
        settings.mutate { $0.subfolderRule = .byTypeThenSource }
        for folder in ["chats/slack", "Tweets/x.com"] {
            try FileManager.default.createDirectory(at: path(folder), withIntermediateDirectories: true)
        }
        let first = try screenshot("Screenshot 2026-01-13 at 10.22.11.png", contents: "one")
        let second = try screenshot("Screenshot 2026-01-13 at 10.22.12.png", contents: "two")
        let slack = try await processor(StubAnalyzer(shot(.chat, source: "Slack", title: "Standup"))).process(first)
        let tweet = try await processor(StubAnalyzer(shot(.tweet, source: "X", title: "Thread"))).process(second)
        XCTAssertEqual(slack, .processed(finalURL: path("chats/slack/Standup.png"), renamed: true, moved: true))
        XCTAssertEqual(tweet, .processed(finalURL: path("Tweets/x.com/Thread.png"), renamed: true, moved: true))
        XCTAssertEqual(try dir.names(in: "Organized"), ["Tweets", "chats"], "no second folder for one source")
    }

    func testANewSourceFolderIsNamedFromTheIndexDisplayNameNotTheKey() async throws {
        settings.mutate { $0.subfolderRule = .bySource }
        // The index already calls this source "GitHub" most often; the new screenshot says "github.com".
        for (offset, spelling) in ["GitHub", "GitHub", "github.com"].enumerated() {
            try index.save(.testRow("/elsewhere/\(offset).png") {
                $0.sourceAppOrSite = spelling
                $0.status = .done
            })
        }
        let source = try screenshot()
        let outcome = try await processor(StubAnalyzer(shot(.code, source: "github.com", title: "PR"))).process(source)
        XCTAssertEqual(outcome, .processed(finalURL: path("GitHub/PR.png"), renamed: true, moved: true))

        // A source the index doesn't know yet keeps the screenshot's own spelling (trimmed), never the folded key.
        let other = try screenshot("Screenshot 2026-01-13 at 10.22.12.png", contents: "two")
        let named = try await processor(StubAnalyzer(shot(.chat, source: "  Café Chat ", title: "Menu"))).process(other)
        XCTAssertEqual(named, .processed(finalURL: path("Café Chat/Menu.png"), renamed: true, moved: true))
    }

    func testAKeptNameIsStillSorted() async throws {
        let lowConfidence = try screenshot()
        let outcome = try await processor(StubAnalyzer(shot(.receipt, source: "Mail", confidence: 0.2))).process(lowConfidence)
        XCTAssertEqual(outcome, .processed(finalURL: path("Receipts/\(shotName)"), renamed: false, moved: true))
        XCTAssertEqual(try index.lookup(byPath: path("Receipts/\(shotName)").path)?.note, "kept name: title confidence 0.20 < 0.50")

        settings.mutate { $0.renameEnabled = false }
        let renameOff = try screenshot("Screenshot 2026-01-14 at 09.00.00.png", contents: "two")
        let kept = try await processor(StubAnalyzer(shot(.code, source: nil))).processWithReport(renameOff)
        XCTAssertEqual(kept.outcome, .processed(finalURL: path("Code/Screenshot 2026-01-14 at 09.00.00.png"),
                                                renamed: false, moved: true))
        XCTAssertEqual(kept.sortedInto, ["Code"])
    }

    func testNoSubfolderWhenMovingIsOffOrNoOrganizedFolder() async throws {
        settings.mutate { $0.moveEnabled = false }
        let first = try screenshot()
        let report = try await processor(StubAnalyzer(shot(.receipt, source: "Mail"))).processWithReport(first)
        XCTAssertEqual(report.outcome, .processed(finalURL: dir.url.appendingPathComponent("Desktop/Invoice From Acme.png")
                                                    .standardizedFileURL, renamed: true, moved: false))
        XCTAssertEqual(report.sortedInto, [])

        settings.mutate {
            $0.moveEnabled = true
            $0.organizedFolder = nil
        }
        let second = try screenshot("Screenshot 2026-01-14 at 09.00.00.png", contents: "two")
        _ = try await processor(StubAnalyzer(shot(.code, source: "Xcode", title: "Build"))).process(second)
        XCTAssertEqual(try dir.names(in: "Desktop"), ["Build.png", "Invoice From Acme.png"])
        XCTAssertEqual(try dir.names(in: "Organized"), [], "no folder made anywhere")
    }

    // MARK: Fallbacks, clashes, undo, change feed

    func testAFileNamedLikeTheSubfolderSendsTheScreenshotToTheOrganizedFolder() async throws {
        try dir.file("Receipts", contents: "a file, not a folder", in: "Organized")
        let source = try screenshot()
        let report = try await processor(StubAnalyzer(shot(.receipt, source: "Mail"))).processWithReport(source)

        let expected = path("Invoice From Acme.png")
        XCTAssertEqual(report.outcome, .processed(finalURL: expected, renamed: true, moved: true))
        XCTAssertEqual(report.sortedInto, [], "the toast says Renamed, not Sorted")
        XCTAssertEqual(read(path("Receipts")), "a file, not a folder", "the file in the way is untouched")
        XCTAssertEqual(try index.lookup(byPath: expected.path)?.note, "subfolder not created (“Receipts” is a file, not a folder)")
        XCTAssertEqual(try undoLog.records().map(\.to), [expected.path])
    }

    func testALinkNamedLikeTheSubfolderIsNotFollowedOutOfTheOrganizedFolder() async throws {
        settings.mutate { $0.subfolderRule = .bySource }
        let outside = dir.url.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: path("Slack"), withDestinationURL: outside)
        let source = try screenshot()
        let outcome = try await processor(StubAnalyzer(shot(.chat, source: "Slack"))).process(source)
        XCTAssertEqual(outcome, .processed(finalURL: path("Invoice From Acme.png"), renamed: true, moved: true))
        XCTAssertEqual(try dir.names(in: "Outside"), [])
    }

    func testWhenTheOrganizedFolderFailsTooTheFileKeepsItsNameAndPlace() async throws {
        let source = try screenshot()
        let failing = FileOrganizer(renameNoReplace: { _, _ in EACCES })
        let report = try await processor(StubAnalyzer(shot(.receipt, source: "Mail")), organizer: failing)
            .processWithReport(source)
        XCTAssertEqual(report.outcome, .processed(finalURL: source, renamed: false, moved: false))
        XCTAssertEqual(report.sortedInto, [])
        XCTAssertEqual(read(source), "png bytes")
        let note = try XCTUnwrap(index.lookup(byPath: source.path)?.note)
        XCTAssertTrue(note.hasPrefix("subfolder not used ("), note)
        XCTAssertTrue(note.contains("; kept name: rename failed ("), note)
        XCTAssertEqual(try undoLog.records(), [])
    }

    func testAClashInASubfolderGetsANumberAndReplacesNothing() async throws {
        try dir.file("Invoice From Acme.png", contents: "older", in: "Organized/Receipts")
        let source = try screenshot()
        let outcome = try await processor(StubAnalyzer(shot(.receipt, source: "Mail"))).process(source)
        XCTAssertEqual(outcome, .processed(finalURL: path("Receipts/Invoice From Acme 2.png"), renamed: true, moved: true))
        XCTAssertEqual(read(path("Receipts/Invoice From Acme.png")), "older")
        XCTAssertEqual(read(path("Receipts/Invoice From Acme 2.png")), "png bytes")
    }

    func testUndoPutsASortedFileBackAndLeavesTheEmptySubfolder() async throws {
        settings.mutate { $0.subfolderRule = .byTypeThenSource }
        let source = try screenshot()
        let processor = processor(StubAnalyzer(shot(.chat, source: "Slack")))
        let report = try await processor.processWithReport(source)
        XCTAssertEqual(report.sortedInto, ["Chats", "Slack"])
        XCTAssertEqual(try undoLog.records().count, 1, "one undo record for rename + move")

        let record = try processor.undo(id: XCTUnwrap(report.undoRecordID))
        XCTAssertEqual(record.from, source.path)
        XCTAssertEqual(read(source), "png bytes")
        XCTAssertEqual(try index.lookup(byPath: source.path)?.restoredByUndo, true)
        XCTAssertEqual(try dir.names(in: "Organized/Chats/Slack"), [], "the empty folder is left alone")
    }

    func testTheMoveIsPublishedOnTheChangeFeed() async throws {
        let source = try screenshot()
        let changes = index.changes()
        _ = try await processor(StubAnalyzer(shot(.receipt, source: "Mail"))).process(source)
        index = nil

        var received: [IndexChange] = []
        for await change in changes { received.append(change) }
        let id = try XCTUnwrap(received.first?.id)
        XCTAssertEqual(received, [IndexChange(.inserted, id: id, path: source.path),
                                  IndexChange(.updated, id: id, path: path("Receipts/Invoice From Acme.png").path),
                                  IndexChange(.updated, id: id, path: path("Receipts/Invoice From Acme.png").path)])
    }
}
