import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
@testable import ShotkeeperCore

final class ScreenshotProcessorTests: XCTestCase {
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
        configured.uploadGrants = [AppSettings.cloudflareSinceEver] // a user who allowed the default Clairic backend
        settings = Locked(configured)
    }

    override func tearDown() { dir = nil }

    private func processor(_ analyzer: StubAnalyzer) -> ScreenshotProcessor {
        let settings = self.settings!
        let now = self.now
        return ScreenshotProcessor(analyzer: analyzer, imagePreparer: PassthroughImagePreparer(), metadataWriter: writer,
                                   index: index, undoLog: undoLog, settings: { settings.get }, now: { now })
    }

    private func screenshot(_ contents: String = "png bytes") throws -> URL {
        try dir.file(shotName, contents: contents, in: "Desktop")
    }

    func testHappyPathRenamesIndexesTagsAndLogsUndo() async throws {
        let source = try screenshot()
        let analyzer = StubAnalyzer(analysis(title: "Invoice From Acme"))
        let outcome = try await processor(analyzer).process(source)

        let expected = dir.url.appendingPathComponent("Desktop/Invoice From Acme.png").standardizedFileURL
        XCTAssertEqual(outcome, .processed(finalURL: expected, renamed: true, moved: false))
        XCTAssertEqual(read(expected), "png bytes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(analyzer.calls.get.map(\.originalFilename), [shotName])

        let row = try XCTUnwrap(index.lookup(byPath: expected.path))
        XCTAssertEqual(row.status, .done)
        XCTAssertEqual(row.originalFilename, shotName)
        XCTAssertEqual(row.title, "Invoice From Acme")
        XCTAssertEqual(row.tags, ["invoice", "acme"])
        XCTAssertEqual(row.billedInputTokens, 640)
        XCTAssertEqual(row.processedAt, now)
        XCTAssertNil(row.note)
        XCTAssertNil(try index.lookup(byPath: source.standardizedFileURL.path))
        XCTAssertEqual(try index.search("acme").map(\.path), [expected.path])

        let records = try undoLog.records()
        XCTAssertEqual(records.map(\.from), [source.standardizedFileURL.path])
        XCTAssertEqual(records.map(\.to), [expected.path])

        let attributes = try XCTUnwrap(writer.attributes.get[expected.path])
        XCTAssertEqual(attributes[FinderMetadata.tagsAttribute].flatMap(FinderMetadata.decodeTags), ["invoice", "acme"])
        XCTAssertEqual(attributes[FinderMetadata.commentAttribute].flatMap(FinderMetadata.decodeComment), "An invoice from Acme Corp")
    }

    func testLowConfidenceKeepsNameButIndexes() async throws {
        let source = try screenshot()
        let outcome = try await processor(StubAnalyzer(analysis(title: "Maybe Invoice", confidence: 0.3))).process(source)
        XCTAssertEqual(outcome, .processed(finalURL: source.standardizedFileURL, renamed: false, moved: false))
        XCTAssertEqual(read(source), "png bytes")
        let row = try XCTUnwrap(index.lookup(byPath: source.standardizedFileURL.path))
        XCTAssertEqual(row.status, .done)
        XCTAssertEqual(row.title, "Maybe Invoice")
        XCTAssertEqual(row.note, "kept name: title confidence 0.30 < 0.50")
        XCTAssertEqual(try undoLog.records(), [])
    }

    func testNilTitleOrRenameOffKeepsName() async throws {
        let source = try screenshot()
        _ = try await processor(StubAnalyzer(analysis(title: nil))).process(source)
        XCTAssertEqual(try index.lookup(byPath: source.standardizedFileURL.path)?.note, "kept name: no title")

        settings.mutate { $0.renameEnabled = false }
        let other = try dir.file("Screenshot 2026-01-14 at 09.00.00.png", contents: "other bytes", in: "Desktop")
        let outcome = try await processor(StubAnalyzer(analysis(title: "Good Title"))).process(other)
        XCTAssertEqual(outcome, .processed(finalURL: other.standardizedFileURL, renamed: false, moved: false))
    }

    func testAnalyzerFailureKeepsFileAndRecordsError() async throws {
        let source = try screenshot()
        let analyzer = StubAnalyzer([.failure(.serverError(status: 503, message: "busy"))])
        do {
            _ = try await processor(analyzer).process(source)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AnalyzerError, .serverError(status: 503, message: "busy"))
        }
        XCTAssertEqual(read(source), "png bytes")
        let row = try XCTUnwrap(index.lookup(byPath: source.standardizedFileURL.path))
        XCTAssertEqual(row.status, .failed)
        XCTAssertTrue(row.lastError?.contains("503") == true, row.lastError ?? "")
        XCTAssertEqual(try undoLog.records(), [])

        // A retry after a failure is not skipped as "already indexed".
        let retry = try await processor(StubAnalyzer(analysis(title: "Recovered"))).process(source)
        guard case .processed(let url, true, false) = retry else { return XCTFail("\(retry)") }
        XCTAssertEqual(url.lastPathComponent, "Recovered.png")
        XCTAssertEqual(try index.stats().count, 1, "same row, not a duplicate")
    }

    func testPreparerFailureKeepsFile() async throws {
        let source = try dir.file("Screenshot 2026-01-13 at 10.22.11.heic", contents: "heic", in: "Desktop")
        let analyzer = StubAnalyzer(analysis(title: "X"))
        do {
            _ = try await processor(analyzer).process(source)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ImagePreparerError, .unsupportedType("heic"))
        }
        XCTAssertEqual(read(source), "heic")
        XCTAssertEqual(analyzer.calls.get.count, 0)
        XCTAssertEqual(try index.lookup(byPath: source.standardizedFileURL.path)?.status, .failed)
    }

    func testExcludedAndPausedFilesAreSkippedUntouched() async throws {
        let source = try screenshot()
        let analyzer = StubAnalyzer(analysis(title: "Secret"))
        settings.mutate { $0.excludeRules.rules = [.init(.folder, dir.url.appendingPathComponent("Desktop").path)] }
        let excluded = try await processor(analyzer).process(source)
        guard case .skipped(.excluded) = excluded else { return XCTFail("\(excluded)") }

        settings.mutate {
            $0.excludeRules.rules = []
            $0.excludeRules.pause(for: 600, from: now.addingTimeInterval(-60))
        }
        let paused = try await processor(analyzer).process(source)
        XCTAssertEqual(paused, .skipped(.paused(until: now.addingTimeInterval(540))))

        XCTAssertEqual(analyzer.calls.get.count, 0)
        XCTAssertEqual(read(source), "png bytes")
        XCTAssertEqual(try index.stats().count, 0, "excluded screenshots are not indexed")
    }

    /// Without consent for the selected backend's destination the file is skipped, not held, so it is never
    /// uploaded later just because consent arrived after it was queued.
    func testFilesAreSkippedWhileTheDestinationIsNotAllowed() async throws {
        let source = try screenshot()
        let analyzer = StubAnalyzer(analysis(title: "Secret"))
        settings.mutate { $0.uploadGrants = [] }
        let outcome = try await processor(analyzer).process(source)
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(analyzer.calls.get.count, 0)
        XCTAssertEqual(read(source), "png bytes")
        XCTAssertEqual(try index.stats().count, 0)

        // Cloudflare consent does not cover a custom endpoint.
        settings.mutate {
            $0.uploadGrants = [AppSettings.cloudflareSinceEver]
            $0.backend = .customEndpoint
            $0.customEndpointURL = URL(string: "http://192.168.1.5:8080")
        }
        let custom = try await processor(analyzer).process(source)
        XCTAssertEqual(custom, .skipped(.awaitingConsent))

        // The local model needs no consent.
        settings.mutate { $0.uploadGrants = []; $0.backend = .localInkling }
        let local = try await processor(analyzer).process(source)
        guard case .processed = local else { return XCTFail("\(local)") }
        XCTAssertEqual(analyzer.calls.get.count, 1)
    }

    /// The one choke point: a file taken before its destination was allowed is skipped on every run, whatever
    /// brought it to the queue (a resumed hold, a later file event). Only a user request (Process Existing) made for this
    /// destination lifts the time rule.
    func testFilesTakenBeforeTheGrantAreSkippedUnlessTheUserAskedForThisDestination() async throws {
        let source = try screenshot()
        let analyzer = StubAnalyzer(analysis(title: "Old receipt"))
        let later = Date().addingTimeInterval(3_600) // granted after the file was created
        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare, grantedAt: later)] }
        let skipped = try await processor(analyzer).process(source)
        XCTAssertEqual(skipped, .skipped(.awaitingConsent))

        let onLocal = try await processor(analyzer).process(source, userRequest: .init(target: .thisMac))
        XCTAssertEqual(onLocal, .skipped(.awaitingConsent), "a request made on another destination does not count")
        XCTAssertEqual(analyzer.calls.get.count, 0)

        let requested = try await processor(analyzer).process(source, userRequest: .init(target: .cloudflare))
        guard case .processed = requested else { return XCTFail("\(requested)") }
        XCTAssertEqual(analyzer.calls.get.count, 1, "Process Existing may send an older file to an allowed destination")
    }

    func testAUserRequestStillNeedsTheDestination() async throws {
        let source = try screenshot()
        let analyzer = StubAnalyzer(analysis(title: "Secret"))
        settings.mutate { $0.uploadGrants = [] }
        let outcome = try await processor(analyzer).process(source, userRequest: .init(target: .cloudflare))
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(analyzer.calls.get.count, 0)
    }

    /// Review 3 S2: a screenshot copied, downloaded or AirDropped after the grant has a fresh creation date; the time
    /// in its name (taken long before) counts.
    func testTheNameTimeCountsWhenItIsEarlierThanTheCreationDate() async throws {
        let source = try screenshot() // "Screenshot 2026-01-13 at 10.22.11.png", created now
        let analyzer = StubAnalyzer(analysis(title: "Old receipt"))
        let grant = Date().addingTimeInterval(-60) // before the file was created, after the name's time
        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare, grantedAt: grant)] }
        let outcome = try await processor(analyzer).process(source)
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(analyzer.calls.get.count, 0)

        let fresh = try dir.file("Screenshot \(Self.nameStamp(Date().addingTimeInterval(3_600))).png", contents: "new",
                                 in: "Desktop")
        let sent = try await processor(analyzer).process(fresh)
        guard case .processed = sent else { return XCTFail("a new screenshot is sent: \(sent)") }
    }

    /// Review 3 S1: no creation date and no time in the name means `.distantPast`, never now().
    func testAnUnknownCaptureTimeFailsClosed() {
        XCTAssertEqual(UploadConsent.decide(settings: settings.get, capturedAt: UploadConsent.effectiveCaptureTime(
            creationDate: nil, nameDate: nil)), .allow, "the fixture's Cloudflare grant is since .distantPast")
        var granted = settings.get
        granted.uploadGrants = [.init(destination: .cloudflare, grantedAt: now)]
        XCTAssertEqual(UploadConsent.decide(settings: granted, capturedAt: UploadConsent.effectiveCaptureTime(
            creationDate: nil, nameDate: nil)), .skip(.takenBeforeGrant(grantedAt: now)))
    }

    // MARK: Review 3 B2: the decision and the analyzer come from one snapshot

    /// The reviewer's reproduction: Local is selected when the job starts; while the image is prepared, setup saves
    /// Clairic and allows Cloudflare (from now on) and the analyzer is rebuilt. The cloud analyzer must not get it.
    func testSwitchingToACloudBackendWhilePreparingDoesNotSendTheFile() async throws {
        let source = try screenshot()
        let local = StubAnalyzer(analysis(title: "Local name"))
        let cloud = StubAnalyzer(analysis(title: "Cloud name"))
        var localSettings = AppSettings()
        localSettings.backend = .localInkling
        let box = Locked(AnalyzerSnapshot(analyzer: local, settings: localSettings))
        let preparer = HookedPreparer {
            var clairic = AppSettings()
            clairic.uploadGrants = [.init(destination: .cloudflare, grantedAt: Date().addingTimeInterval(1))]
            box.set(AnalyzerSnapshot(analyzer: cloud, settings: clairic))
        }
        let processor = ScreenshotProcessor(snapshot: { box.get }, imagePreparer: preparer, index: index, undoLog: undoLog)
        let outcome = try await processor.process(source)
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(cloud.calls.get.count, 0, "never sent to Cloudflare")
        XCTAssertEqual(local.calls.get.count, 0, "the job uses the pair read after preparing, not the old analyzer")
        XCTAssertEqual(read(source), "png bytes")
        XCTAssertEqual(try index.stats().count, 0, "nothing indexed")
    }

    func testRevokingWhilePreparingDoesNotSendTheFile() async throws {
        let source = try screenshot()
        let cloud = StubAnalyzer(analysis(title: "Cloud name"))
        let allowed = settings.get
        let box = Locked(AnalyzerSnapshot(analyzer: cloud, settings: allowed))
        let preparer = HookedPreparer {
            var revoked = allowed
            revoked.uploadGrants = []
            box.set(AnalyzerSnapshot(analyzer: cloud, settings: revoked))
        }
        let processor = ScreenshotProcessor(snapshot: { box.get }, imagePreparer: preparer, index: index, undoLog: undoLog)
        let outcome = try await processor.process(source)
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(cloud.calls.get.count, 0)
    }

    /// The other direction: Clairic allowed when the job starts, Local selected while preparing. The job goes to
    /// the analyzer of the pair it decided on (Local), never to the one it started with.
    func testSwitchingToLocalWhilePreparingUsesTheLocalAnalyzer() async throws {
        let source = try screenshot()
        let local = StubAnalyzer(analysis(title: "Local name"))
        let cloud = StubAnalyzer(analysis(title: "Cloud name"))
        let box = Locked(AnalyzerSnapshot(analyzer: cloud, settings: settings.get))
        let preparer = HookedPreparer {
            var localSettings = AppSettings()
            localSettings.backend = .localInkling
            box.set(AnalyzerSnapshot(analyzer: local, settings: localSettings))
        }
        let processor = ScreenshotProcessor(snapshot: { box.get }, imagePreparer: preparer, index: index, undoLog: undoLog)
        let outcome = try await processor.process(source)
        guard case .processed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(local.calls.get.count, 1)
        XCTAssertEqual(cloud.calls.get.count, 0)
    }

    /// Review 4 nit: the dates are read again after preparing, so a file replaced mid-job is judged by its own
    /// (earlier) dates.
    func testAFileReplacedWhilePreparingIsJudgedByItsOwnDates() async throws {
        let source = try dir.file("notes.png", contents: "png bytes", in: "Desktop") // no time in the name
        let analyzer = StubAnalyzer(analysis(title: "Notes"))
        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare, grantedAt: Date().addingTimeInterval(-60))] }
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let settings = self.settings!
        let processor = ScreenshotProcessor(
            snapshot: { AnalyzerSnapshot(analyzer: analyzer, settings: settings.get) },
            imagePreparer: HookedPreparer {
                // Replaced by an older file (e.g. extracted from an archive), keeping the modification date.
                try? Data("older".utf8).write(to: source)
                try? FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: source.path)
            },
            index: index, undoLog: undoLog)
        let outcome = try await processor.process(source)
        XCTAssertEqual(outcome, .skipped(.awaitingConsent))
        XCTAssertEqual(analyzer.calls.get.count, 0)
    }

    /// Review 4 S1: one job, many attempts. A Process Existing file that gets a 429 and then succeeds is analyzed
    /// and renamed on the retry, with the real queue and processor.
    func testAUserUploadRequestLastsTheWholeJobAcrossRetries() async throws {
        let source = try screenshot() // named 2026-01-13: before the grant
        settings.mutate { $0.uploadGrants = [.init(destination: .cloudflare, grantedAt: Date())] }
        let analyzer = StubAnalyzer([.failure(.rateLimited(retryAfter: 1)), .success(analysis(title: "Invoice From Acme"))])
        let processor = self.processor(analyzer)
        let requests = UserUploadRequests()
        let queue = ProcessingQueue(configuration: .init(requestsPerMinute: 0), clock: FakeClock(), random: { 0.5 },
                                    jobHandler: { job, request in
            guard case .process(let url) = job else { return XCTFail("only file jobs here") }
            _ = try await processor.process(url, userRequest: requests.authorization(for: request))
        })
        let request = try XCTUnwrap(requests.request(for: .cloudflare, madeIn: requests.generation))
        await queue.enqueue(.process(source), userRequest: request)
        await queue.waitUntilIdle()
        XCTAssertEqual(analyzer.calls.get.count, 2, "retried after the 429")
        let renamed = dir.url.appendingPathComponent("Desktop/Invoice From Acme.png")
        XCTAssertEqual(read(renamed), "png bytes")
        XCTAssertEqual(try index.lookup(byPath: renamed.standardizedFileURL.path)?.status, .done)
        let carried = await queue.carriedRequestCount
        XCTAssertEqual(carried, 0, "dropped when the job ended")
    }


    private static func nameStamp(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d at %02d.%02d.%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    func testAlreadyIndexedIsSkipped() async throws {
        settings.mutate { $0.renameEnabled = false }
        let source = try screenshot()
        let analyzer = StubAnalyzer(analysis(title: "Invoice"))
        _ = try await processor(analyzer).process(source)
        let second = try await processor(analyzer).process(source)
        XCTAssertEqual(second, .skipped(.alreadyIndexed))
        XCTAssertEqual(analyzer.calls.get.count, 1)
    }

    func testFileMovedByUserIsFollowedNotReanalyzed() async throws {
        settings.mutate { $0.renameEnabled = false }
        let source = try screenshot()
        let analyzer = StubAnalyzer(analysis(title: "Invoice"))
        _ = try await processor(analyzer).process(source)
        let moved = dir.url.appendingPathComponent("Desktop/Screenshot copy 2026-01-13.png")
        try FileManager.default.moveItem(at: source, to: moved)
        let outcome = try await processor(analyzer).process(moved)
        XCTAssertEqual(outcome, .skipped(.alreadyIndexed))
        XCTAssertEqual(analyzer.calls.get.count, 1)
        XCTAssertNotNil(try index.lookup(byPath: moved.standardizedFileURL.path), "index follows the move")
    }

    func testMissingFileIsSkipped() async throws {
        let outcome = try await processor(StubAnalyzer(analysis(title: "x"))).process(dir.url.appendingPathComponent("gone.png"))
        XCTAssertEqual(outcome, .skipped(.missing))
    }

    func testCollisionAndMoveIntoOrganizedFolder() async throws {
        let organized = dir.url.appendingPathComponent("Organized")
        try dir.file("Invoice From Acme.png", contents: "older", in: "Organized")
        settings.mutate {
            $0.moveEnabled = true
            $0.organizedFolder = organized
        }
        let source = try screenshot()
        let outcome = try await processor(StubAnalyzer(analysis(title: "Invoice From Acme"))).process(source)
        let expected = organized.appendingPathComponent("Invoice From Acme 2.png").standardizedFileURL
        XCTAssertEqual(outcome, .processed(finalURL: expected, renamed: true, moved: true))
        XCTAssertEqual(read(organized.appendingPathComponent("Invoice From Acme.png")), "older")
        XCTAssertEqual(read(expected), "png bytes")
    }

    func testRenameFailureKeepsNameAndNotes() async throws {
        let source = try screenshot()
        let failing = FileOrganizer(renameNoReplace: { _, _ in EACCES })
        let settings = self.settings!
        let processor = ScreenshotProcessor(analyzer: StubAnalyzer(analysis(title: "Invoice")),
                                            imagePreparer: PassthroughImagePreparer(), index: index, organizer: failing,
                                            undoLog: undoLog, settings: { settings.get })
        let outcome = try await processor.process(source)
        XCTAssertEqual(outcome, .processed(finalURL: source.standardizedFileURL, renamed: false, moved: false))
        let row = try XCTUnwrap(index.lookup(byPath: source.standardizedFileURL.path))
        XCTAssertEqual(row.status, .done)
        XCTAssertTrue(row.note?.hasPrefix("kept name: rename failed") == true, row.note ?? "")
        XCTAssertEqual(read(source), "png bytes")
    }

    func testUndoLastRestoresFileAndIndexPath() async throws {
        let source = try screenshot()
        let processor = processor(StubAnalyzer(analysis(title: "Invoice From Acme")))
        _ = try await processor.process(source)
        let record = try processor.undoLast()
        XCTAssertEqual(record.from, source.standardizedFileURL.path)
        XCTAssertEqual(read(source), "png bytes")
        XCTAssertEqual(try index.lookup(byPath: source.standardizedFileURL.path)?.title, "Invoice From Acme")
    }

    func testReportCarriesOriginalPathAndUndoRecord() async throws {
        let source = try screenshot()
        let report = try await processor(StubAnalyzer(analysis(title: "Invoice From Acme"))).processWithReport(source)
        XCTAssertEqual(report.originalURL, source.standardizedFileURL)
        XCTAssertEqual(report.undoRecordID, try undoLog.records().last?.id)
        guard case .processed(_, true, false) = report.outcome else { return XCTFail("\(report.outcome)") }
    }

    func testFileRestoredByUndoIsNeverProcessedAgainEvenAfterARestart() async throws {
        let source = try screenshot()
        let analyzer = StubAnalyzer(analysis(title: "Invoice From Acme"))
        let first = processor(analyzer)
        _ = try await first.process(source)
        let record = try XCTUnwrap(first.lastUndoable())
        _ = try first.undo(id: record.id)
        XCTAssertNil(first.lastUndoable())
        XCTAssertEqual(read(source), "png bytes")
        XCTAssertEqual(try index.lookup(byPath: source.standardizedFileURL.path)?.restoredByUndo, true)

        // The watcher sees the restored name appear; the user even edits the file (new fingerprint).
        try Data("edited bytes".utf8).write(to: source)
        let again = try await processor(analyzer).process(source)
        XCTAssertEqual(again, .skipped(.restoredByUndo))
        XCTAssertEqual(analyzer.calls.get.count, 1, "never sent to the model again")
        XCTAssertEqual(read(source), "edited bytes")
    }

    func testRestoredFlagPersistsInTheIndexFile() async throws {
        let file = dir.url.appendingPathComponent("state/index.sqlite")
        index = try ScreenshotIndex(fileURL: file)
        let source = try screenshot()
        let processor = processor(StubAnalyzer(analysis(title: "Invoice From Acme")))
        _ = try await processor.process(source)
        _ = try processor.undoLast()
        index = try ScreenshotIndex(fileURL: file)  // "restart"
        let outcome = try await self.processor(StubAnalyzer(analysis(title: "Other"))).process(source)
        XCTAssertEqual(outcome, .skipped(.restoredByUndo))
    }

    func testUndoWithoutAnIndexRowStillRecordsTheRestoredFlag() throws {
        let source = try screenshot()
        let renamed = dir.url.appendingPathComponent("Desktop/Renamed.png")
        try FileManager.default.moveItem(at: source, to: renamed)
        let record = try undoLog.append(from: source, to: renamed)
        _ = try processor(StubAnalyzer(analysis(title: "x"))).undo(id: record.id)
        let row = try XCTUnwrap(index.lookup(byPath: source.standardizedFileURL.path))
        XCTAssertTrue(row.restoredByUndo)
        XCTAssertEqual(row.status, .skipped)
    }

    func testUndoAllRevertsNewestFirstAndReportsFailures() async throws {
        let a = try dir.file("Screenshot A.png", contents: "a", in: "Desktop")
        let b = try dir.file("Screenshot B.png", contents: "b", in: "Desktop")
        let p = processor(StubAnalyzer([.success(analysis(title: "Alpha")), .success(analysis(title: "Beta"))]))
        let ra = try await p.processWithReport(a)
        let rb = try await p.processWithReport(b)
        // Something now occupies B's original name: that one cannot be restored, A still is.
        try Data("other".utf8).write(to: b)
        let result = p.undo(ids: [try XCTUnwrap(ra.undoRecordID), try XCTUnwrap(rb.undoRecordID)])
        XCTAssertEqual(result.restored.map(\.from), [a.standardizedFileURL.path])
        XCTAssertEqual(result.failed, [rb.undoRecordID])
        XCTAssertEqual(read(a), "a")
        XCTAssertEqual(read(b), "other", "never overwritten")
        XCTAssertEqual(read(dir.url.appendingPathComponent("Desktop/Beta.png")), "b")
    }

    func testManualRenameUsesSanitizerCollisionsIndexAndUndo() async throws {
        let source = try screenshot()
        let p = processor(StubAnalyzer(analysis(title: "Invoice From Acme")))
        let report = try await p.processWithReport(source)
        guard case .processed(let current, _, _) = report.outcome else { return XCTFail() }
        try dir.file("Acme - March invoice.png", contents: "taken", in: "Desktop")

        let result = try p.rename(current, to: "  Acme/March invoice\n")
        let expected = dir.url.appendingPathComponent("Desktop/Acme - March invoice 2.png").standardizedFileURL
        XCTAssertEqual(result.finalURL, expected)
        XCTAssertEqual(read(expected), "png bytes")
        XCTAssertEqual(read(dir.url.appendingPathComponent("Desktop/Acme - March invoice.png")), "taken")
        let row = try XCTUnwrap(index.lookup(byPath: expected.path))
        XCTAssertEqual(row.title, "Acme - March invoice")
        XCTAssertNil(try index.lookup(byPath: current.path))
        XCTAssertEqual(try index.search("march").map(\.path), [expected.path])
        XCTAssertEqual(try undoLog.records().last?.id, result.undoRecordID)

        // Undo from the toast: both records, newest first, back to the original screenshot name.
        let undone = p.undo(ids: [try XCTUnwrap(report.undoRecordID), try XCTUnwrap(result.undoRecordID)])
        XCTAssertEqual(undone.failed, [])
        XCTAssertEqual(read(source), "png bytes")
        XCTAssertEqual(try index.lookup(byPath: source.standardizedFileURL.path)?.restoredByUndo, true)
    }

    func testFilenameStyleAppliesInThePipelineAndToManualRenames() async throws {
        let source = try screenshot()
        let captured = Date(timeIntervalSince1970: 1_795_278_240)  // 2026-11-21 16:24 UTC
        try FileManager.default.setAttributes([.modificationDate: captured], ofItemAtPath: source.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        // What the processor reads (creation date where the file system has one, else the modification date).
        let day = FilenameStyle.dateString((attributes[.creationDate] as? Date) ?? captured,
                                           timeZone: TimeZone(secondsFromGMT: 0)!)
        settings.mutate { $0.filenameStyle = FilenameStyle(casing: .kebab, datePrefix: true) }
        let settings = self.settings!
        let now = self.now
        let p = ScreenshotProcessor(analyzer: StubAnalyzer(analysis(title: "Invoice from Acme")),
                                    imagePreparer: PassthroughImagePreparer(), index: index, undoLog: undoLog,
                                    settings: { settings.get }, now: { now }, timeZone: TimeZone(secondsFromGMT: 0)!)
        let outcome = try await p.process(source)
        let expected = dir.url.appendingPathComponent("Desktop/\(day)-invoice-from-acme.png").standardizedFileURL
        XCTAssertEqual(outcome, .processed(finalURL: expected, renamed: true, moved: false))

        // "Edit name": the same casing; the date already in the typed name is kept, not doubled.
        settings.mutate { $0.filenameStyle = FilenameStyle(casing: .title, datePrefix: true) }
        let edited = try p.rename(expected, to: "\(day) march invoice from acme")
        XCTAssertEqual(edited.finalURL.lastPathComponent, "\(day) March Invoice from Acme.png")
        // The user removed the date: it stays removed (what they typed is respected).
        let again = try p.rename(edited.finalURL, to: "acme invoice")
        XCTAssertEqual(again.finalURL.lastPathComponent, "Acme Invoice.png")
        XCTAssertEqual(read(again.finalURL), "png bytes")
        XCTAssertThrowsError(try p.rename(again.finalURL, to: "Screenshot")) { error in
            XCTAssertEqual(error as? ManualRenameError, .unusableName("Screenshot"), "sanitizer rules are unchanged")
        }
    }

    func testManualRenameRejectsUnusableNamesAndIgnoresNoChange() async throws {
        let source = try screenshot()
        let p = processor(StubAnalyzer(analysis(title: "Invoice From Acme")))
        _ = try await p.process(source)
        let current = dir.url.appendingPathComponent("Desktop/Invoice From Acme.png").standardizedFileURL
        for bad in ["", "  ", "...", "Screenshot", "///"] {
            XCTAssertThrowsError(try p.rename(current, to: bad), bad) { error in
                XCTAssertEqual(error as? ManualRenameError, .unusableName(bad))
            }
        }
        let same = try p.rename(current, to: "Invoice From Acme")
        XCTAssertEqual(same, ManualRenameResult(finalURL: current, undoRecordID: nil))
        XCTAssertEqual(try undoLog.records().count, 1)
        XCTAssertEqual(read(current), "png bytes")
    }

    func testRenameOntoPathOfDeletedIndexedFileIndexesNewFile() async throws {
        // The user deleted an already processed "Invoice From Acme.png"; its row stays in the index. The next
        // screenshot with the same title gets that (now free) name and must be indexed there, not fail half-way.
        let stalePath = dir.url.appendingPathComponent("Desktop/Invoice From Acme.png").standardizedFileURL.path
        try index.save(IndexedScreenshot(path: stalePath, originalFilename: "old.png", contentHash: "old-hash",
                                         title: "Old Title", status: .done))
        let source = try screenshot()
        let outcome = try await processor(StubAnalyzer(analysis(title: "Invoice From Acme"))).process(source)

        XCTAssertEqual(outcome, .processed(finalURL: URL(fileURLWithPath: stalePath), renamed: true, moved: false))
        let row = try XCTUnwrap(index.lookup(byPath: stalePath))
        XCTAssertEqual(row.status, .done)
        XCTAssertEqual(row.title, "Invoice From Acme")
        XCTAssertEqual(row.originalFilename, shotName)
        XCTAssertNil(try index.lookup(byPath: source.standardizedFileURL.path))
        XCTAssertEqual(try index.stats().count, 1)
    }

    func testPassthroughPreparerReadsFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tiny-3x2", withExtension: "png", subdirectory: "Fixtures"))
        let payload = try PassthroughImagePreparer().prepare(url)
        XCTAssertEqual(payload.mimeType, "image/png")
        XCTAssertEqual(payload.pixelWidth, 3)
        XCTAssertEqual(payload.pixelHeight, 2)
        XCTAssertEqual(payload.data.count, 73)
    }

    func testQueueAndProcessorTogether() async throws {
        let first = try screenshot("one")
        let second = try dir.file("Screenshot 2026-01-14 at 09.00.00.png", contents: "two", in: "Desktop")
        let analyzer = StubAnalyzer([.failure(.rateLimited(retryAfter: 1)), .success(analysis(title: "Same Title"))])
        let processor = processor(analyzer)
        let clock = FakeClock()
        let queue = ProcessingQueue(configuration: .init(requestsPerMinute: 0), clock: clock, random: { 0.5 }) {
            _ = try await processor.process($0)
        }
        await queue.enqueue(.process(first))
        await queue.enqueue(.process(second))
        await queue.waitUntilIdle()
        XCTAssertEqual(clock.sleeps, [1])
        XCTAssertEqual(try dir.names(in: "Desktop"), ["Same Title 2.png", "Same Title.png"])
        XCTAssertEqual(try index.stats().done, 2)
    }
}

/// Prepares like `PassthroughImagePreparer`, running `hook` first (to change the app's state mid-job).
struct HookedPreparer: ImagePreparer {
    let hook: @Sendable () -> Void

    func prepare(_ url: URL) throws -> ImagePayload {
        hook()
        return try PassthroughImagePreparer().prepare(url)
    }
}
