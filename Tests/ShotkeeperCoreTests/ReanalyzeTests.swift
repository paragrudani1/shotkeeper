import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import ShotkeeperCore

/// Spec "Analyze Again (core)" (ticket 06): `ScreenshotProcessor.reanalyze(rowID:request:)`, through seam 1
/// (`StubAnalyzer`, `TempDir`, in-memory index, real `UndoLog`) and, for the consent snapshot, seam 2.
final class ReanalyzeTests: XCTestCase {
    var dir: TempDir!
    var index: ScreenshotIndex!
    var undoLog: UndoLog!
    var writer: RecordingMetadataWriter!
    var settings: Locked<AppSettings>!
    let shotName = "Screenshot 2026-01-13 at 10.22.11.png"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        dir = try TempDir()
        index = try ScreenshotIndex.inMemory()
        undoLog = UndoLog(fileURL: dir.url.appendingPathComponent("state/undo.jsonl"))
        writer = RecordingMetadataWriter()
        var configured = AppSettings()
        configured.uploadGrants = [AppSettings.cloudflareSinceEver]
        settings = Locked(configured)
    }

    override func tearDown() { dir = nil }

    private func processor(_ analyzer: any ScreenshotAnalyzer, now: Date? = nil,
                           preparer: any ImagePreparer = PassthroughImagePreparer()) -> ScreenshotProcessor {
        let settings = self.settings!
        let now = now ?? self.now
        return ScreenshotProcessor(analyzer: analyzer, imagePreparer: preparer, metadataWriter: writer,
                                   index: index, undoLog: undoLog, settings: { settings.get }, now: { now })
    }

    /// A screenshot processed once ("Invoice From Acme"), as the row Analyze Again starts from.
    private func indexedScreenshot(title: String = "Invoice From Acme") async throws -> IndexedScreenshot {
        let source = try dir.file(shotName, contents: "png bytes", in: "Desktop")
        guard case .processed(let url, _, _) = try await processor(StubAnalyzer(analysis(title: title))).process(source)
        else { throw XCTSkip("setup did not process") }
        return try XCTUnwrap(index.lookup(byPath: url.path))
    }

    private func desktop(_ name: String) -> URL {
        dir.url.appendingPathComponent("Desktop/\(name)").standardizedFileURL
    }

    private let later = Date(timeIntervalSince1970: 1_800_086_400)

    private func newAnalysis(title: String? = "Acme Invoice For November", confidence: Double = 0.9) -> ScreenshotAnalysis {
        ScreenshotAnalysis(title: title, titleConfidence: confidence, sourceAppOrSite: "Safari", contentType: .article,
                           description: "A November invoice", tags: ["invoice", "november"], keyText: "Total 99.00 EUR",
                           dateMentioned: "2026-11-01", producedBy: "stub-2", billedInputTokens: 700)
    }

    // MARK: Updating the row

    func testAnalyzingAgainUpdatesTheRowAndRenamesTheFile() async throws {
        let row = try await indexedScreenshot()
        let outcome = try await processor(StubAnalyzer(newAnalysis()), now: later).reanalyze(rowID: row.id)

        let expected = desktop("Acme Invoice For November.png")
        XCTAssertEqual(outcome, .updated(finalURL: expected, renamed: true, moved: false, titleKept: nil,
                                         suggestedTitle: nil))
        XCTAssertEqual(read(expected), "png bytes")
        let updated = try XCTUnwrap(index.lookup(byPath: expected.path))
        XCTAssertEqual(updated.id, row.id)
        XCTAssertEqual(updated.status, .done)
        XCTAssertEqual(updated.title, "Acme Invoice For November")
        XCTAssertEqual(updated.titleConfidence, 0.9)
        XCTAssertEqual(updated.sourceAppOrSite, "Safari")
        XCTAssertEqual(updated.contentType, .article)
        XCTAssertEqual(updated.description, "A November invoice")
        XCTAssertEqual(updated.tags, ["invoice", "november"])
        XCTAssertEqual(updated.keyText, "Total 99.00 EUR")
        XCTAssertEqual(updated.dateMentioned, "2026-11-01")
        XCTAssertEqual(updated.producedBy, "stub-2")
        XCTAssertEqual(updated.billedInputTokens, 700)
        XCTAssertEqual(updated.processedAt, later)
        XCTAssertEqual(updated.note, "analyzed again")
        XCTAssertEqual(updated.titleSource, .model)
        XCTAssertEqual(updated.originalFilename, shotName)
        XCTAssertEqual(try index.search("november").map(\.id), [row.id])
        XCTAssertEqual(try index.stats().count, 1)
    }

    // MARK: Name

    func testAUserTypedNameIsKeptAndTheModelsTitleIsSuggested() async throws {
        let row = try await indexedScreenshot()
        let p = processor(StubAnalyzer(newAnalysis()), now: later)
        let typed = try p.rename(URL(fileURLWithPath: row.path), to: "Acme March").finalURL
        let recordsBefore = try undoLog.records()

        let outcome = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: typed, renamed: false, moved: false, titleKept: .yourName,
                                         suggestedTitle: "Acme Invoice For November"))
        XCTAssertEqual(read(typed), "png bytes")
        XCTAssertEqual(try undoLog.records(), recordsBefore)
        let updated = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(updated.path, typed.path)
        XCTAssertEqual(updated.title, "Acme March")
        XCTAssertEqual(updated.titleSource, .user)
        XCTAssertEqual(updated.description, "A November invoice", "the rest of the analysis is updated")
        XCTAssertEqual(updated.note, "renamed by the user; analyzed again")
        XCTAssertEqual(try index.search("Acme Invoice For November").count, 0, "the suggestion is not stored")

        // "Use This Name": the rename with the suggestion clears the mark.
        let used = try p.rename(typed, to: "Acme Invoice For November", asSuggestedTitle: true)
        XCTAssertEqual(used.finalURL, desktop("Acme Invoice For November.png"))
        let cleared = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(cleared.title, "Acme Invoice For November")
        XCTAssertEqual(cleared.titleSource, .model)
        XCTAssertEqual(try undoLog.records().last?.id, used.undoRecordID)
    }

    /// Spec decision 9 and the wiki's PR #20 note: a file the user put back with Undo keeps its name and place even
    /// when its title is marked as the user's (Undo after a hand rename), so `restored_by_undo` is checked first.
    func testARowRestoredWithUndoIsUpdatedInTheIndexOnly() async throws {
        let row = try await indexedScreenshot()
        let p = processor(StubAnalyzer(newAnalysis()), now: later)
        let modelNamed = URL(fileURLWithPath: row.path)
        _ = try p.rename(modelNamed, to: "Acme March")
        _ = try p.undoLast()  // back at the model's name, flagged, title_source still `user`
        settings.mutate { $0.organizedFolder = self.dir.url.appendingPathComponent("Organized"); $0.moveEnabled = true }
        let recordsBefore = try undoLog.records()
        let finderBefore = writer.attributes.get

        let outcome = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: modelNamed.standardizedFileURL, renamed: false, moved: false,
                                         titleKept: .restoredByUndo, suggestedTitle: nil))
        XCTAssertEqual(read(modelNamed), "png bytes")
        XCTAssertEqual(try undoLog.records(), recordsBefore)
        XCTAssertEqual(writer.attributes.get, finderBefore, "the file is not touched")
        let updated = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(updated.path, modelNamed.standardizedFileURL.path)
        XCTAssertTrue(updated.restoredByUndo)
        XCTAssertEqual(updated.title, "Acme March", "the title that goes with the kept name stays")
        XCTAssertEqual(updated.description, "A November invoice")
        XCTAssertEqual(updated.tags, ["invoice", "november"])
        XCTAssertEqual(updated.contentType, .article)
        XCTAssertEqual(updated.sourceAppOrSite, "Safari")
    }

    func testLowConfidenceKeepsTheCurrentNameAndTheOldTitle() async throws {
        let row = try await indexedScreenshot()
        let outcome = try await processor(StubAnalyzer(newAnalysis(confidence: 0.2))).reanalyze(rowID: row.id)
        let current = URL(fileURLWithPath: row.path).standardizedFileURL
        XCTAssertEqual(outcome, .updated(finalURL: current, renamed: false, moved: false, titleKept: .lowConfidence,
                                         suggestedTitle: nil))
        let updated = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(updated.title, "Invoice From Acme")
        XCTAssertEqual(updated.titleConfidence, 0.9)
        XCTAssertEqual(updated.description, "A November invoice")
        XCTAssertEqual(try undoLog.records().count, 1, "only the first rename")
    }

    func testNoTitleKeepsTheOldTitleAndRenameOffKeepsTheName() async throws {
        let row = try await indexedScreenshot()
        let current = URL(fileURLWithPath: row.path).standardizedFileURL
        let untitled = try await processor(StubAnalyzer(newAnalysis(title: nil))).reanalyze(rowID: row.id)
        XCTAssertEqual(untitled, .updated(finalURL: current, renamed: false, moved: false, titleKept: .unusable,
                                          suggestedTitle: nil))
        XCTAssertEqual(try index.lookup(id: row.id)?.title, "Invoice From Acme")

        let unusable = try await processor(StubAnalyzer(newAnalysis(title: "..."))).reanalyze(rowID: row.id)
        XCTAssertEqual(unusable, .updated(finalURL: current, renamed: false, moved: false, titleKept: .unusable,
                                          suggestedTitle: nil))
        XCTAssertEqual(try index.lookup(id: row.id)?.title, "Invoice From Acme")

        settings.mutate { $0.renameEnabled = false }
        let off = try await processor(StubAnalyzer(newAnalysis())).reanalyze(rowID: row.id)
        XCTAssertEqual(off, .updated(finalURL: current, renamed: false, moved: false, titleKept: .renameOff,
                                     suggestedTitle: nil))
        XCTAssertEqual(try index.lookup(id: row.id)?.title, "Acme Invoice For November",
                       "with renaming off the row has the model's title, as `process` stores it")
        XCTAssertEqual(try index.lookup(id: row.id)?.note, "analyzed again", "the note says it once")
    }

    /// Design §5.3 "The title is the same as before": the name follows the title (no kept reason) and is unchanged.
    func testTheSameTitleAsBeforeIsAnUpdateWithoutARename() async throws {
        let row = try await indexedScreenshot()
        let outcome = try await processor(StubAnalyzer(newAnalysis(title: "Invoice From Acme"))).reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: URL(fileURLWithPath: row.path).standardizedFileURL, renamed: false,
                                         moved: false, titleKept: nil, suggestedTitle: nil))
        XCTAssertEqual(try undoLog.records().count, 1)
    }

    // MARK: Place

    func testAnalyzeAgainAppliesTodaysMoveSettings() async throws {
        let row = try await indexedScreenshot()
        let organized = dir.url.appendingPathComponent("Organized")
        settings.mutate { $0.organizedFolder = organized; $0.moveEnabled = true }
        let outcome = try await processor(StubAnalyzer(newAnalysis())).reanalyze(rowID: row.id)
        let expected = organized.appendingPathComponent("Acme Invoice For November.png").standardizedFileURL
        XCTAssertEqual(outcome, .updated(finalURL: expected, renamed: true, moved: true, titleKept: nil,
                                         suggestedTitle: nil))
        XCTAssertEqual(read(expected), "png bytes")
        XCTAssertEqual(try index.lookup(id: row.id)?.path, expected.path)
        let attributes = try XCTUnwrap(writer.attributes.get[expected.path])
        XCTAssertEqual(attributes[FinderMetadata.tagsAttribute].flatMap(FinderMetadata.decodeTags), ["invoice", "november"])
        XCTAssertEqual(attributes[FinderMetadata.commentAttribute].flatMap(FinderMetadata.decodeComment), "A November invoice")
    }

    func testAUserNamedFileKeepsItsNameButMoves() async throws {
        let row = try await indexedScreenshot()
        let p = processor(StubAnalyzer(newAnalysis()))
        _ = try p.rename(URL(fileURLWithPath: row.path), to: "Acme March")
        let organized = dir.url.appendingPathComponent("Organized")
        settings.mutate { $0.organizedFolder = organized; $0.moveEnabled = true }
        let outcome = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: organized.appendingPathComponent("Acme March.png").standardizedFileURL,
                                         renamed: false, moved: true, titleKept: .yourName,
                                         suggestedTitle: "Acme Invoice For November"))
    }

    func testTheRenameAndMoveAreUndoable() async throws {
        let row = try await indexedScreenshot()
        let before = URL(fileURLWithPath: row.path).standardizedFileURL
        let organized = dir.url.appendingPathComponent("Organized")
        settings.mutate { $0.organizedFolder = organized; $0.moveEnabled = true }
        let p = processor(StubAnalyzer(newAnalysis()))
        guard case .updated(let after, true, true, nil, nil) = try await p.reanalyze(rowID: row.id)
        else { return XCTFail("not renamed and moved") }

        let record = try p.undoLast()
        XCTAssertEqual(record.from, before.path)
        XCTAssertEqual(record.to, after.path)
        XCTAssertEqual(read(before), "png bytes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: after.path))
        let restored = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(restored.path, before.path)
        XCTAssertTrue(restored.restoredByUndo)
    }

    func testARenameFailureKeepsTheNameAndTheOldTitle() async throws {
        let row = try await indexedScreenshot()
        let failing = FileOrganizer(renameNoReplace: { _, _ in EACCES })
        let settings = self.settings!
        let now = self.now
        let p = ScreenshotProcessor(analyzer: StubAnalyzer(newAnalysis()), imagePreparer: PassthroughImagePreparer(),
                                    index: index, organizer: failing, undoLog: undoLog, settings: { settings.get },
                                    now: { now })
        let current = URL(fileURLWithPath: row.path).standardizedFileURL
        let outcome = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: current, renamed: false, moved: false, titleKept: .renameFailed,
                                         suggestedTitle: nil))
        let updated = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(updated.title, "Invoice From Acme")
        XCTAssertEqual(updated.description, "A November invoice")
        XCTAssertTrue(updated.note?.hasPrefix("kept name: rename failed") == true, updated.note ?? "")
        XCTAssertTrue(updated.note?.hasSuffix("; analyzed again") == true, updated.note ?? "")
    }

    /// Keyed on the row id: a file renamed by hand while the job waited (the index followed it) is still found.
    func testTheRowIsFoundAtItsCurrentPath() async throws {
        let row = try await indexedScreenshot()
        let moved = desktop("renamed in Finder.png")
        try FileManager.default.moveItem(atPath: row.path, toPath: moved.path)
        try index.updatePath(from: row.path, to: moved.path)
        settings.mutate { $0.renameEnabled = false }
        let outcome = try await processor(StubAnalyzer(newAnalysis())).reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: moved, renamed: false, moved: false, titleKept: .renameOff,
                                         suggestedTitle: nil))
    }

    // MARK: Changes while the model works (review of PR #27)

    /// Every row's file exists and each file has one row: no ghost row at a path without a file.
    private func assertIndexMatchesDisk(_ expectedPaths: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try index.recent(limit: 100)
        XCTAssertEqual(Set(rows.map(\.path)), Set(expectedPaths), file: file, line: line)
        XCTAssertEqual(rows.count, expectedPaths.count, file: file, line: line)
        for row in rows {
            XCTAssertTrue(FileManager.default.fileExists(atPath: row.path), "no file at \(row.path)", file: file, line: line)
        }
    }

    /// The user renames the file by hand while the model works: their name is kept and the model's title becomes the
    /// suggestion, on the one row that follows the file.
    func testARenameByHandDuringTheAnalysisKeepsTheTypedName() async throws {
        let row = try await indexedScreenshot()
        let analyzer = HookedAnalyzer(newAnalysis())
        let p = processor(analyzer, now: later)
        let typed = desktop("Acme March.png")
        analyzer.hook.set { _ = try p.rename(URL(fileURLWithPath: row.path), to: "Acme March") }
        let recordsBefore = try undoLog.records().count

        let outcome = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: typed, renamed: false, moved: false, titleKept: .yourName,
                                         suggestedTitle: "Acme Invoice For November"))
        XCTAssertEqual(read(typed), "png bytes")
        try assertIndexMatchesDisk([typed.path])
        let updated = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(updated.path, typed.path)
        XCTAssertEqual(updated.title, "Acme March")
        XCTAssertEqual(updated.titleSource, .user)
        XCTAssertEqual(updated.description, "A November invoice")
        XCTAssertEqual(updated.note, "renamed by the user; analyzed again")
        XCTAssertEqual(try undoLog.records().count, recordsBefore + 1, "only the hand rename")
    }

    /// The user undoes the rename while the model works: the file stays where Undo put it (index only).
    func testAnUndoDuringTheAnalysisLeavesTheFileWhereUndoPutIt() async throws {
        let row = try await indexedScreenshot()
        let analyzer = HookedAnalyzer(newAnalysis())
        let p = processor(analyzer, now: later)
        analyzer.hook.set { _ = try p.undoLast() }
        settings.mutate { $0.organizedFolder = self.dir.url.appendingPathComponent("Organized"); $0.moveEnabled = true }
        let finderBefore = writer.attributes.get
        let restored = desktop(shotName)

        let outcome = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: restored, renamed: false, moved: false, titleKept: .restoredByUndo,
                                         suggestedTitle: nil))
        XCTAssertEqual(read(restored), "png bytes")
        try assertIndexMatchesDisk([restored.path])
        let updated = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(updated.path, restored.path)
        XCTAssertTrue(updated.restoredByUndo)
        XCTAssertEqual(updated.description, "A November invoice")
        XCTAssertEqual(writer.attributes.get, finderBefore, "a restored file is not touched")
        XCTAssertEqual(try undoLog.records().count, 0, "the one record was undone; nothing new")
    }

    /// The file is moved away outside Shotkeeper while the model works (the index cannot follow): nothing is written,
    /// so no row is left pointing at the old path with a new analysis.
    func testAFileMovedAwayDuringTheAnalysisIsNotWritten() async throws {
        let row = try await indexedScreenshot()
        let analyzer = HookedAnalyzer(newAnalysis())
        let away = dir.url.appendingPathComponent("elsewhere.png")
        let path = row.path
        analyzer.hook.set { try FileManager.default.moveItem(atPath: path, toPath: away.path) }
        let outcome = try await processor(analyzer, now: later).reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .refused(.missing))
        XCTAssertEqual(try index.lookup(id: row.id), row, "nothing written")
        XCTAssertEqual(try index.stats().count, 1)
        XCTAssertEqual(try undoLog.records().count, 1)
        XCTAssertEqual(read(away), "png bytes")
    }

    /// Only `done` rows are analyzed again, checked before the send and again after it (a `process` run may have
    /// taken the path meanwhile). Nothing is written either way.
    func testARowThatIsNotDoneIsRefusedBeforeOrAfterTheAnalysis() async throws {
        let row = try await indexedScreenshot()
        var failed = row
        failed.status = .failed
        try index.save(failed)
        let analyzer = HookedAnalyzer(newAnalysis())
        let p = processor(analyzer, now: later)
        let before = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(before, .refused(.notDone(.failed)))
        XCTAssertEqual(try index.lookup(id: row.id), failed)

        try index.save(row)
        let pending: IndexedScreenshot = { var copy = row; copy.status = .pending; return copy }()
        let index = self.index!
        analyzer.hook.set { try index.save(pending) }
        let after = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(after, .refused(.notDone(.pending)))
        XCTAssertEqual(try index.lookup(id: row.id), pending, "nothing written over the other job's row")
    }

    // MARK: Failure, refusals, text, feed

    func testAFailedAnalysisLeavesTheRowIdentical() async throws {
        let row = try await indexedScreenshot()
        let failing = StubAnalyzer([.failure(.serverError(status: 503, message: "busy"))])
        do {
            _ = try await processor(failing, now: later).reanalyze(rowID: row.id)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AnalyzerError, .serverError(status: 503, message: "busy"))
        }
        XCTAssertEqual(try index.lookup(id: row.id), row)
        XCTAssertEqual(try index.search("acme").map(\.id), [row.id], "still in search")

        let unreadable = StubAnalyzer(newAnalysis())
        do {
            _ = try await processor(unreadable, now: later, preparer: FailingPreparer()).reanalyze(rowID: row.id)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ImagePreparerError, .unreadable("test"))
        }
        XCTAssertEqual(unreadable.calls.get.count, 0)
        XCTAssertEqual(try index.lookup(id: row.id), row)
        XCTAssertEqual(try undoLog.records().count, 1)
    }

    func testMissingExcludedAndPausedAreRefusedWithoutAnUpload() async throws {
        let row = try await indexedScreenshot()
        let analyzer = StubAnalyzer(newAnalysis())
        let p = processor(analyzer)
        let unknown = try await p.reanalyze(rowID: row.id + 100)
        XCTAssertEqual(unknown, .refused(.missing))

        let rule = ExcludeRules.Rule(.folder, dir.url.appendingPathComponent("Desktop").path)
        settings.mutate { $0.excludeRules.rules = [rule] }
        let excluded = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(excluded, .refused(.excluded(rule)))

        settings.mutate {
            $0.excludeRules.rules = []
            $0.excludeRules.pause(for: 600, from: now.addingTimeInterval(-60))
        }
        let paused = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(paused, .refused(.paused(until: now.addingTimeInterval(540))))

        settings.mutate { $0.excludeRules.resume() }
        let away = dir.url.appendingPathComponent("elsewhere.png")
        try FileManager.default.moveItem(atPath: row.path, toPath: away.path)
        let missing = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(missing, .refused(.missing))

        XCTAssertEqual(analyzer.calls.get.count, 0, "nothing sent")
        XCTAssertEqual(try index.lookup(id: row.id), row, "nothing written")
    }

    func testTextStatusIsResetOnlyWhenTheContentChanged() async throws {
        var row = try await indexedScreenshot()
        row.textStatus = .done
        row.recognizedText = "Total 42.00 EUR"
        try index.save(row)
        _ = try await processor(StubAnalyzer(newAnalysis(title: "Invoice From Acme"))).reanalyze(rowID: row.id)
        let same = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(same.textStatus, .done)
        XCTAssertEqual(same.contentHash, row.contentHash)

        try Data("edited png bytes".utf8).write(to: URL(fileURLWithPath: row.path))
        _ = try await processor(StubAnalyzer(newAnalysis(title: "Invoice From Acme"))).reanalyze(rowID: row.id)
        let changed = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(changed.textStatus, .pending)
        XCTAssertEqual(changed.contentHash, try ContentFingerprint.compute(for: URL(fileURLWithPath: row.path)))
        XCTAssertNotEqual(changed.contentHash, row.contentHash)
    }

    /// Unlike `process`, a content change keeps a typed name the user's: they asked to analyze this file again, so
    /// its name is not replaced unasked; the model's title is the suggestion (wiki, review of PR #27).
    func testAUserNamedFileWhoseContentChangedKeepsTheUsersName() async throws {
        let row = try await indexedScreenshot()
        let p = processor(StubAnalyzer(newAnalysis()), now: later)
        let typed = try p.rename(URL(fileURLWithPath: row.path), to: "Acme March").finalURL
        try Data("edited png bytes".utf8).write(to: typed)

        let outcome = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .updated(finalURL: typed, renamed: false, moved: false, titleKept: .yourName,
                                         suggestedTitle: "Acme Invoice For November"))
        let updated = try XCTUnwrap(index.lookup(id: row.id))
        XCTAssertEqual(updated.titleSource, .user)
        XCTAssertEqual(updated.title, "Acme March")
        XCTAssertEqual(updated.contentHash, try ContentFingerprint.compute(for: typed))
        XCTAssertEqual(updated.textStatus, .pending)
    }

    /// An earlier run's "kept name: …" and "Finder metadata not written (…)" parts are replaced by this run's, not
    /// piled up; parts that still hold ("renamed by the user") stay.
    func testStaleNotePartsAreReplacedNotAppended() async throws {
        var row = try await indexedScreenshot()
        row.note = "kept name: title confidence 0.20 < 0.50; Finder metadata not written (EIO); undo record not written (EIO)"
        try index.save(row)
        let failing = FileOrganizer(renameNoReplace: { _, _ in EACCES })
        let settings = self.settings!
        let now = self.now
        let p = ScreenshotProcessor(analyzer: StubAnalyzer(newAnalysis()), imagePreparer: PassthroughImagePreparer(),
                                    index: index, organizer: failing, undoLog: undoLog, settings: { settings.get },
                                    now: { now })
        _ = try await p.reanalyze(rowID: row.id)
        _ = try await p.reanalyze(rowID: row.id)
        let note = try XCTUnwrap(index.lookup(id: row.id)?.note)
        XCTAssertEqual(note.components(separatedBy: "kept name:").count - 1, 1, note)
        XCTAssertTrue(note.hasPrefix("undo record not written (EIO); kept name: rename failed ("), note)
        XCTAssertTrue(note.hasSuffix("); analyzed again"), note)

        _ = try await processor(StubAnalyzer(newAnalysis())).reanalyze(rowID: row.id)
        XCTAssertEqual(try index.lookup(id: row.id)?.note, "undo record not written (EIO); analyzed again")
    }

    func testTheAnalyzerRequestCarriesNoRecognizedText() async throws {
        var row = try await indexedScreenshot()
        row.textStatus = .done
        row.recognizedText = "account 1234 5678"
        try index.save(row)
        let analyzer = StubAnalyzer(newAnalysis())
        _ = try await processor(analyzer).reanalyze(rowID: row.id)
        let capturedAt = try XCTUnwrap(row.capturedAt)
        XCTAssertEqual(analyzer.calls.get, [AnalysisContext(originalFilename: shotName, capturedAt: capturedAt)])
    }

    func testAReanalysisIsPublishedAsAnUpdate() async throws {
        let row = try await indexedScreenshot()
        let feed = index.changes()
        _ = try await processor(StubAnalyzer(newAnalysis())).reanalyze(rowID: row.id)
        var events: [IndexChange] = []
        for await change in feed {
            events.append(change)
            if change.path == desktop("Acme Invoice For November.png").path, events.count == 2 { break }
        }
        let expected = desktop("Acme Invoice For November.png").path
        XCTAssertEqual(events, [IndexChange(.updated, id: row.id, path: expected),
                                IndexChange(.updated, id: row.id, path: expected)], "the move, then the save")
    }

    // MARK: Seam 2: consent

    /// `ScreenshotProcessorTests.testSwitchingToACloudBackendWhilePreparingDoesNotSendTheFile`, for Analyze Again.
    func testSwitchingToACloudBackendWhilePreparingDoesNotSendTheFile() async throws {
        let row = try await indexedScreenshot()
        let local = StubAnalyzer(newAnalysis(title: "Local name"))
        let cloud = StubAnalyzer(newAnalysis(title: "Cloud name"))
        var localSettings = AppSettings()
        localSettings.backend = .localInkling
        let box = Locked(AnalyzerSnapshot(analyzer: local, settings: localSettings))
        let preparer = HookedPreparer {
            var clairic = AppSettings()
            clairic.uploadGrants = [.init(destination: .cloudflare, grantedAt: Date().addingTimeInterval(1))]
            box.set(AnalyzerSnapshot(analyzer: cloud, settings: clairic))
        }
        let processor = ScreenshotProcessor(snapshot: { box.get }, imagePreparer: preparer, index: index, undoLog: undoLog)
        let outcome = try await processor.reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(cloud.calls.get.count, 0, "never sent to Cloudflare")
        XCTAssertEqual(local.calls.get.count, 0, "the job uses the pair read after preparing")
        XCTAssertEqual(try index.lookup(id: row.id), row, "nothing written")
    }

    /// A file taken before the grant goes only with the user's request for that very target, and a request never
    /// lifts "destination not allowed" (wiki, review of PR #17).
    func testAFileTakenBeforeTheGrantIsAnalyzedAgainOnlyWithARequestForThatTarget() async throws {
        let row = try await indexedScreenshot()  // named 2026-01-13
        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare, grantedAt: Date().addingTimeInterval(60))] }
        let analyzer = StubAnalyzer(newAnalysis())
        let p = processor(analyzer)

        let none = try await p.reanalyze(rowID: row.id)
        XCTAssertEqual(none, .skipped(.awaitingConsent))
        let other = try await p.reanalyze(rowID: row.id, request: UserUploadAuthorization(target: .openRouter(model: "x")))
        XCTAssertEqual(other, .skipped(.awaitingConsent))
        XCTAssertEqual(analyzer.calls.get.count, 0)
        XCTAssertEqual(try index.lookup(id: row.id), row)

        settings.mutate { $0.uploadGrants = [] }
        let notAllowed = try await p.reanalyze(rowID: row.id, request: UserUploadAuthorization(target: .cloudflare))
        XCTAssertEqual(notAllowed, .skipped(.awaitingConsent))
        XCTAssertEqual(analyzer.calls.get.count, 0)

        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare, grantedAt: Date().addingTimeInterval(60))] }
        let asked = try await p.reanalyze(rowID: row.id, request: UserUploadAuthorization(target: .cloudflare))
        guard case .updated = asked else { return XCTFail("\(asked)") }
        XCTAssertEqual(analyzer.calls.get.count, 1)
    }

    /// With PR #25's queue: a `.reanalyze` job carrying the user's request for a file taken before the grant is
    /// analyzed again after a 429, and the request is dropped when the job ends.
    func testAReanalyzeJobKeepsItsRequestAcrossRetries() async throws {
        let row = try await indexedScreenshot()  // named 2026-01-13: before the grant
        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare, grantedAt: Date().addingTimeInterval(60))] }
        let analyzer = StubAnalyzer([.failure(.rateLimited(retryAfter: 1)), .success(newAnalysis())])
        let processor = self.processor(analyzer)
        let requests = UserUploadRequests()
        let outcomes = Locked<[ReanalysisOutcome]>([])
        let queue = ProcessingQueue(configuration: .init(requestsPerMinute: 0), clock: FakeClock(), random: { 0.5 },
                                    jobHandler: { job, request in
            guard case .reanalyze(let rowID) = job else { return XCTFail("\(job)") }
            let outcome = try await processor.reanalyze(rowID: rowID, request: requests.authorization(for: request))
            outcomes.mutate { $0.append(outcome) }
        })
        let request = try XCTUnwrap(requests.request(for: .cloudflare, madeIn: requests.generation))
        await queue.enqueue(.reanalyze(rowID: row.id), atFront: true, userRequest: request)
        await queue.waitUntilIdle()
        XCTAssertEqual(analyzer.calls.get.count, 2, "retried after the 429")
        XCTAssertEqual(outcomes.get, [.updated(finalURL: desktop("Acme Invoice For November.png"), renamed: true,
                                               moved: false, titleKept: nil, suggestedTitle: nil)])
        let carried = await queue.carriedRequestCount
        XCTAssertEqual(carried, 0, "dropped when the job ended")
    }

    /// `ScreenshotProcessorTests.testAFileReplacedWhilePreparingIsJudgedByItsOwnDates`, for Analyze Again: the dates
    /// are read again after preparing, and the earlier read wins.
    func testAFileReplacedWhilePreparingIsJudgedByItsOwnDates() async throws {
        let row = try await indexedScreenshot()  // original name 2026-01-13, file dates now
        // Granted before every date the file claims when the job starts.
        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare,
                                                   grantedAt: Date(timeIntervalSince1970: 1_700_000_000))] }
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let path = row.path
        let analyzer = StubAnalyzer(newAnalysis())
        let preparer = HookedPreparer {
            // Replaced by an older file (e.g. extracted from an archive), keeping the modification date.
            try? Data("older".utf8).write(to: URL(fileURLWithPath: path))
            try? FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
        }
        let outcome = try await processor(analyzer, preparer: preparer).reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(analyzer.calls.get.count, 0)
        XCTAssertEqual(try index.lookup(id: row.id), row, "nothing written")
    }

    /// A renamed file has lost the time in its name; its original name still counts for consent (fails closed).
    func testARenamedFileIsJudgedByItsOriginalNameToo() async throws {
        let row = try await indexedScreenshot()  // now "Invoice From Acme.png", originally named 2026-01-13
        var stored = row
        stored.capturedAt = nil
        try index.save(stored)
        // Grant before the file's own dates (now) but after the original name's time.
        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare,
                                                   grantedAt: Date(timeIntervalSince1970: 1_780_000_000))] }
        let analyzer = StubAnalyzer(newAnalysis())
        let outcome = try await processor(analyzer).reanalyze(rowID: row.id)
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(analyzer.calls.get.count, 0)
    }
}

/// Returns `analysis`, running `hook` first: the user acts (renames, undoes) while the model works.
final class HookedAnalyzer: ScreenshotAnalyzer, @unchecked Sendable {
    let backendID = "stub"
    let analysis: ScreenshotAnalysis
    let hook = Locked<(@Sendable () throws -> Void)?>(nil)

    init(_ analysis: ScreenshotAnalysis) { self.analysis = analysis }

    func analyze(_ image: ImagePayload, context: AnalysisContext) async throws -> ScreenshotAnalysis {
        try hook.get?()
        return analysis
    }
}

struct FailingPreparer: ImagePreparer {
    func prepare(_ url: URL) throws -> ImagePayload { throw ImagePreparerError.unreadable("test") }
}
