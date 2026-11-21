import XCTest
@testable import ShotkeeperCore

final class ToastBatcherTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func renamed(_ n: Int, id: UUID = UUID()) -> ScreenshotEvent {
        .processed(ProcessingReport(originalURL: URL(fileURLWithPath: "/d/Screenshot \(n).png"),
                                    outcome: .processed(finalURL: URL(fileURLWithPath: "/d/Title \(n).png"),
                                                        renamed: true, moved: false),
                                    undoRecordID: id))
    }

    private func skipped(_ n: Int, _ reason: SkipReason) -> ScreenshotEvent {
        .processed(ProcessingReport(originalURL: URL(fileURLWithPath: "/d/Screenshot \(n).png"), outcome: .skipped(reason)))
    }

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testSingleRenameGivesARenamedToast() throws {
        var batcher = ToastBatcher()
        let id = UUID()
        guard case .renamed(let toast)? = batcher.record(renamed(1, id: id), at: t0) else { return XCTFail() }
        XCTAssertEqual(toast.label, "Renamed")
        XCTAssertEqual(toast.name, "Title 1")
        XCTAssertEqual(toast.subline, "was: Screenshot 1")
        XCTAssertEqual(toast.undoRecordIDs, [id])
        XCTAssertEqual(toast.undoTitle, "Undo")
        XCTAssertEqual(toast.editTitle, "Edit name")
    }

    func testFourthFileWithinTenSecondsTurnsIntoOneSummaryCountingAllFour() {
        var batcher = ToastBatcher()
        let ids = (0..<5).map { _ in UUID() }
        for n in 0..<3 {
            guard case .renamed? = batcher.record(renamed(n, id: ids[n]), at: at(Double(n) * 3)) else {
                return XCTFail("the first three are single toasts")
            }
        }
        guard case .batch(let summary)? = batcher.record(renamed(3, id: ids[3]), at: at(9.5)) else { return XCTFail() }
        XCTAssertEqual(summary.renamedCount, 4)
        XCTAssertEqual(summary.title, "Renamed 4 screenshots")
        XCTAssertNil(summary.subline)
        XCTAssertEqual(summary.undoRecordIDs, Array(ids[0..<4]))
        XCTAssertEqual(summary.thumbnailPaths, ["/d/Title 1.png", "/d/Title 2.png", "/d/Title 3.png"])
        XCTAssertEqual(summary.primaryTitle, "View in Search")
        XCTAssertEqual(summary.undoTitle, "Undo All")

        // The burst continues while files keep arriving within 10 s of the previous one.
        guard case .batch(let more)? = batcher.record(renamed(4, id: ids[4]), at: at(19)) else { return XCTFail() }
        XCTAssertEqual(more.renamedCount, 5)
        XCTAssertEqual(more.undoRecordIDs, ids)

        // A gap of more than 10 s ends it.
        guard case .renamed? = batcher.record(renamed(5), at: at(30)) else { return XCTFail("burst over") }
    }

    func testSlowFilesStaySingleToasts() {
        var batcher = ToastBatcher()
        for n in 0..<6 {
            guard case .renamed? = batcher.record(renamed(n), at: at(Double(n) * 4)) else {
                return XCTFail("only 3 files fit in any 10 s window at this pace (file \(n))")
            }
        }
    }

    func testExcludedFilesCountTowardsTheBurstAndTheSubline() {
        var batcher = ToastBatcher()
        let rule = ExcludeRules.Rule(.filenameContains, "bank")
        XCTAssertNil(batcher.record(skipped(0, .excluded(rule)), at: t0), "a lone excluded file shows nothing")
        _ = batcher.record(renamed(1), at: at(1))
        XCTAssertNil(batcher.record(skipped(2, .excluded(rule)), at: at(2)))
        guard case .batch(let summary)? = batcher.record(renamed(3), at: at(3)) else { return XCTFail() }
        XCTAssertEqual(summary.renamedCount, 2)
        XCTAssertEqual(summary.excludedCount, 2)
        XCTAssertEqual(summary.title, "Renamed 2 screenshots")
        XCTAssertEqual(summary.subline, "2 skipped by your exclude rules")
    }

    func testIgnoredOutcomesShowNothingAndDoNotCount() {
        var batcher = ToastBatcher()
        let keptName = ScreenshotEvent.processed(ProcessingReport(
            originalURL: URL(fileURLWithPath: "/d/a.png"),
            outcome: .processed(finalURL: URL(fileURLWithPath: "/d/a.png"), renamed: false, moved: false)))
        let ignored: [ScreenshotEvent] = [keptName, skipped(1, .alreadyIndexed), skipped(2, .missing),
                                          skipped(3, .restoredByUndo), skipped(4, .paused(until: at(60)))]
        for (n, event) in ignored.enumerated() { XCTAssertNil(batcher.record(event, at: at(Double(n)))) }
        guard case .renamed? = batcher.record(renamed(9), at: at(5)) else { return XCTFail("still a single toast") }
    }

    func testMoveOnlyIsLabelledMoved() {
        var batcher = ToastBatcher()
        let event = ScreenshotEvent.processed(ProcessingReport(
            originalURL: URL(fileURLWithPath: "/d/Screenshot.png"),
            outcome: .processed(finalURL: URL(fileURLWithPath: "/o/Screenshot.png"), renamed: false, moved: true)))
        guard case .renamed(let toast)? = batcher.record(event, at: t0) else { return XCTFail() }
        XCTAssertEqual(toast.label, "Moved")
    }

    func testExplicitRunIsOneSummaryHoweverSlowAndOtherFilesStaySingle() {
        var batcher = ToastBatcher()
        let runURLs = (0..<3).map { URL(fileURLWithPath: "/d/Screenshot \($0).png") }
        batcher.beginRun(runURLs)
        guard case .batch(let first)? = batcher.record(renamed(0), at: t0) else { return XCTFail() }
        XCTAssertEqual(first.title, "Renamed 1 screenshot")
        guard case .renamed? = batcher.record(renamed(7), at: at(1)) else { return XCTFail("not part of the run") }
        let rule = ExcludeRules.Rule(.filenameGlob, "*")
        guard case .batch(let second)? = batcher.record(skipped(1, .excluded(rule)), at: at(60)) else { return XCTFail() }
        XCTAssertEqual(second.excludedCount, 1)
        XCTAssertEqual(second.subline, "1 skipped by your exclude rules")
        guard case .batch(let last)? = batcher.record(renamed(2), at: at(120)) else { return XCTFail() }
        XCTAssertEqual(last.renamedCount, 2)
        // The run is over: the same path again is an ordinary single rename.
        guard case .renamed? = batcher.record(renamed(0), at: at(500)) else { return XCTFail("run finished") }
    }

    func testFailureGivesAnErrorToastAndFinishesItsRunItem() {
        var batcher = ToastBatcher()
        batcher.beginRun([URL(fileURLWithPath: "/d/Screenshot 0.png")])
        let problem = UserFacingProblem(message: "Cloudflare API token is not set", needsSettings: true)
        guard case .error(let toast)? = batcher.record(.failed(originalURL: URL(fileURLWithPath: "/d/Screenshot 0.png"),
                                                               problem: problem), at: t0) else { return XCTFail() }
        XCTAssertEqual(toast.title, "Could not rename: Cloudflare API token is not set")
        XCTAssertEqual(toast.fixTitle, "Fix Settings…")
        guard case .renamed? = batcher.record(renamed(0), at: at(1)) else { return XCTFail("run ended with the failure") }
        XCTAssertNil(ErrorToast(.undo, UserFacingProblem(message: "x")).fixTitle)
        XCTAssertEqual(ErrorToast(.undo, UserFacingProblem(message: "x")).title, "Could not undo: x")
    }
}

final class ToastTextTests: XCTestCase {
    func testEditedToastKeepsTheOriginalAndAppendsTheUndoRecord() {
        let first = UUID(), second = UUID()
        let toast = RenamedToast(originalURL: URL(fileURLWithPath: "/d/Screenshot 2026-11-21 at 16.24.11.png"),
                                 currentURL: URL(fileURLWithPath: "/d/Tweet.png"), undoRecordIDs: [first])
        let edited = toast.edited(to: URL(fileURLWithPath: "/d/Tweet semiconductor flashcards.png"), undoRecordID: second)
        XCTAssertEqual(edited.name, "Tweet semiconductor flashcards")
        XCTAssertEqual(edited.subline, "was: Screenshot 2026-11-21 at 16.24.11")
        XCTAssertEqual(edited.undoRecordIDs, [first, second])
        XCTAssertEqual(toast.edited(to: toast.currentURL, undoRecordID: nil).undoRecordIDs, [first])
    }

    func testRestoredWording() {
        let single = RestoredToast(restoredPaths: ["/d/Screenshot 2026-11-21 at 16.24.11.png"])
        XCTAssertEqual(single.label, "Original name restored")
        XCTAssertEqual(single.title, "Screenshot 2026-11-21 at 16.24.11")
        XCTAssertEqual(single.subline, "Shotkeeper will not rename this file again")

        let many = RestoredToast(restoredPaths: ["/a.png", "/b.png", "/c.png"])
        XCTAssertEqual(many.label, "Original names restored")
        XCTAssertEqual(many.title, "Restored 3 screenshots")
        XCTAssertEqual(many.subline, "Shotkeeper will not rename these files again")

        let partial = RestoredToast(restoredPaths: ["/a.png"], failedCount: 2)
        XCTAssertEqual(partial.title, "Restored 1 of 3 screenshots")
        XCTAssertEqual(partial.subline, "2 could not be restored: moved, renamed or name taken")
    }

    func testBatchSingular() {
        XCTAssertEqual(BatchToast(renamedCount: 1).title, "Renamed 1 screenshot")
        XCTAssertEqual(BatchToast(renamedCount: 37, excludedCount: 2).subline, "2 skipped by your exclude rules")
        XCTAssertFalse(BatchToast(renamedCount: 3).canUndo)
    }
}

final class ToastCountdownTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRunsForFourSecondsThenExpires() {
        let countdown = ToastCountdown(startingAt: t0)
        XCTAssertEqual(countdown.duration, 4)
        XCTAssertEqual(countdown.fraction(at: t0), 1)
        XCTAssertEqual(countdown.fraction(at: t0.addingTimeInterval(1)), 0.75)
        XCTAssertFalse(countdown.isExpired(at: t0.addingTimeInterval(3.9)))
        XCTAssertTrue(countdown.isExpired(at: t0.addingTimeInterval(4)))
    }

    func testPauseStopsTheClockAndResumeContinues() {
        var countdown = ToastCountdown(startingAt: t0)
        countdown.pause(at: t0.addingTimeInterval(1))
        XCTAssertFalse(countdown.isRunning)
        XCTAssertFalse(countdown.isExpired(at: t0.addingTimeInterval(60)), "never expires while hovered or editing")
        XCTAssertEqual(countdown.remaining(at: t0.addingTimeInterval(60)), 3)
        countdown.resume(at: t0.addingTimeInterval(60))
        XCTAssertEqual(countdown.remaining(at: t0.addingTimeInterval(61)), 2)
        XCTAssertTrue(countdown.isExpired(at: t0.addingTimeInterval(63)))
    }

    func testResumeLeavesAtLeastTheMinimum() {
        var countdown = ToastCountdown(startingAt: t0)
        countdown.pause(at: t0.addingTimeInterval(3.9))
        countdown.resume(at: t0.addingTimeInterval(10))
        XCTAssertEqual(countdown.remaining(at: t0.addingTimeInterval(10)), ToastCountdown.minimumAfterResume, accuracy: 0.0001)
        countdown.pause(at: t0.addingTimeInterval(10))
        countdown.pause(at: t0.addingTimeInterval(11))
        XCTAssertEqual(countdown.remaining(at: t0.addingTimeInterval(11)), 1.5, accuracy: 0.0001, "double pause is harmless")
    }
}
