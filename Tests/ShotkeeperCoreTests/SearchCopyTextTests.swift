import XCTest
@testable import ShotkeeperCore

/// Copy Text (⇧⌘C and the badge on the preview image), wave 1 ticket 06. Rows are saved to an in-memory index with
/// their text columns and found by `search`, so the window state sees what the index stores (seam 1), then
/// `SearchWindowState` decides what the copy does (seam 2).
final class SearchCopyTextTests: XCTestCase {
    private var index: ScreenshotIndex!

    override func setUpWithError() throws {
        index = try ScreenshotIndex.inMemory()
    }

    /// Saves a row with the given text columns; newer `minutes` sort first in the recent list.
    private func save(_ name: String, minutes: Double, status: TextStatus?, text: String? = nil,
                      error: String? = nil) throws {
        let taken = Date(timeIntervalSince1970: 1_795_278_240 + minutes * 60)
        try index.save(IndexedScreenshot.testRow("/Users/parag/Desktop/\(name).png") {
            $0.capturedAt = taken
            $0.processedAt = taken
            $0.title = name
            $0.recognizedText = text
            $0.textStatus = status
            $0.textError = error
            $0.textRecognizedBy = status == nil || status == .pending ? nil : "vision-r3-accurate-h1/96-lc0"
        })
    }

    /// The window after the recent search, with the row titled `name` selected.
    private func window(selecting name: String) throws -> SearchWindowState {
        var state = SearchWindowState()
        let result = try index.search(state.query)
        XCTAssertTrue(state.apply(result, for: state.query))
        let position = try XCTUnwrap(state.items.firstIndex { $0.title == name }, "\(name) is a result")
        state.select(position)
        return state
    }

    // MARK: Seam 1: the result carries the text and its status

    func testAResultCarriesItsTextAndStatus() throws {
        try save("Terminal error", minutes: -1, status: .done, text: "error: no such module 'Vision'\nline 2")
        try save("Never read", minutes: -2, status: nil)
        try save("Unreadable", minutes: -3, status: .failed, error: "file missing")
        let items = try window(selecting: "Terminal error").items
        let byTitle = Dictionary(uniqueKeysWithValues: items.map { ($0.title, $0) })
        XCTAssertEqual(byTitle["Terminal error"]?.recognizedText, "error: no such module 'Vision'\nline 2")
        XCTAssertEqual(byTitle["Terminal error"]?.textStatus, .done)
        XCTAssertNil(byTitle["Never read"]?.textStatus)
        XCTAssertNil(byTitle["Never read"]?.recognizedText)
        XCTAssertEqual(byTitle["Unreadable"]?.textStatus, .failed)
        XCTAssertEqual(byTitle["Unreadable"]?.textError, "file missing")
    }

    // MARK: Seam 2: the copy outcome per text status

    func testADoneRowCopiesItsText() throws {
        try save("Terminal error", minutes: -1, status: .done, text: "error: no such module 'Vision'\nline 2")
        let state = try window(selecting: "Terminal error")
        XCTAssertEqual(state.copyTextOutcome, .copy("error: no such module 'Vision'\nline 2"))
    }

    /// A row indexed before migration 3 is read first (spec story 36). Ticket 07 performs it; until then the app beeps.
    func testANeverReadRowIsReadFirst() throws {
        try save("Old screenshot", minutes: -1, status: nil)
        let state = try window(selecting: "Old screenshot")
        XCTAssertEqual(state.copyTextOutcome, .readFirst(id: try XCTUnwrap(state.selected).id))
    }

    func testANoTextRowSaysSo() throws {
        try save("Sunset photo", minutes: -1, status: .noText)
        let state = try window(selecting: "Sunset photo")
        XCTAssertEqual(state.copyTextOutcome, .noText)
        XCTAssertEqual(state.copyTextOutcome.message, "No text found in this screenshot.")
    }

    /// A failed read says so; a file that was gone when it was read gets the existing missing-file sentence.
    func testAFailedRowTellsAMissingFileApart() throws {
        try save("Vision error", minutes: -1, status: .failed, error: "VNErrorDomain 9")
        // The reason the runner writes for a file that was gone (one constant, `SearchWindowState` points at it).
        try save("Moved away", minutes: -2, status: .failed, error: TextRecognitionRunner.fileMissingReason)
        let failed = try window(selecting: "Vision error")
        XCTAssertEqual(failed.copyTextOutcome, .failed(fileMissing: false))
        XCTAssertEqual(failed.copyTextOutcome.message, "The text could not be read.")
        let missing = try window(selecting: "Moved away")
        XCTAssertEqual(missing.copyTextOutcome, .failed(fileMissing: true))
        XCTAssertEqual(missing.copyTextOutcome.message, SearchWindowState.missingFileMessage)
    }

    func testAPendingRowWaits() throws {
        try save("Just taken", minutes: -1, status: .pending)
        let state = try window(selecting: "Just taken")
        XCTAssertEqual(state.copyTextOutcome, .wait(id: try XCTUnwrap(state.selected).id))
        XCTAssertNil(state.copyTextOutcome.message, "the badge says \"Reading text…\"; no pill")
    }

    func testNothingIsAvailableWithoutASelection() throws {
        var state = SearchWindowState()
        XCTAssertEqual(state.copyTextOutcome, .notAvailable, "before the first answer")
        state.apply(try index.search(state.query), for: state.query)
        XCTAssertNil(state.selected, "the index is empty")
        XCTAssertEqual(state.copyTextOutcome, .notAvailable)
    }

    // MARK: Late-copy rule (story 37): a waiting copy writes only if the clipboard and the panel are unchanged

    /// The runner's conditional write for the row titled `name`, then the panel's refresh on the `.updated` change.
    private func read(_ name: String, as result: TextRecognitionResult, in state: inout SearchWindowState) throws {
        let row = try XCTUnwrap(index.search(ScreenshotQuery(), limit: 100).rows.first { $0.title == name })
        XCTAssertTrue(try index.setRecognizedText(result, recognizedBy: "vision-r3-accurate-h1/96-lc0", id: row.id,
                                                  ifContentHash: row.contentHash))
        XCTAssertTrue(state.apply(try index.search(state.query), for: state.query))
    }

    func testAWaitingCopyCopiesWhenTheTextArrives() throws {
        try save("Just taken", minutes: -1, status: .pending)
        var state = try window(selecting: "Just taken")
        let id = try XCTUnwrap(state.selected).id
        XCTAssertEqual(state.requestCopyText(pasteboardChangeCount: 41), .wait(id: id))
        XCTAssertEqual(state.waitingTextCopy, WaitingTextCopy(id: id, pasteboardChangeCount: 41))
        try read("Just taken", as: .text("Order #A-20417"), in: &state)
        XCTAssertEqual(state.resolveWaitingTextCopy(pasteboardChangeCount: 41), .perform(.copy("Order #A-20417")))
        XCTAssertNil(state.waitingTextCopy, "done; a later refresh copies nothing")
        XCTAssertNil(state.resolveWaitingTextCopy(pasteboardChangeCount: 41))
    }

    func testAWaitingCopyIsDroppedWhenTheUserCopiedSomethingElse() throws {
        try save("Just taken", minutes: -1, status: .pending)
        var state = try window(selecting: "Just taken")
        _ = state.requestCopyText(pasteboardChangeCount: 41)
        try read("Just taken", as: .text("Order #A-20417"), in: &state)
        XCTAssertEqual(state.resolveWaitingTextCopy(pasteboardChangeCount: 42), .dropped)
        XCTAssertNil(state.waitingTextCopy)
        XCTAssertEqual(state.copyTextOutcome, .copy("Order #A-20417"), "the text is kept; the badge copies it again")
    }

    func testAWaitingCopyIsDroppedWhenTheUserMovedOn() throws {
        try save("Just taken", minutes: -1, status: .pending)
        try save("Older", minutes: -2, status: .done, text: "older text")
        var state = try window(selecting: "Just taken")
        _ = state.requestCopyText(pasteboardChangeCount: 41)
        state.moveSelection(by: 1)
        XCTAssertNil(state.waitingTextCopy, "another row is shown")
        state.moveSelection(by: -1)
        try read("Just taken", as: .text("Order #A-20417"), in: &state)
        XCTAssertNil(state.resolveWaitingTextCopy(pasteboardChangeCount: 41), "coming back does not revive it")
    }

    func testANewQueryThatShowsAnotherRowDropsTheWaitingCopy() throws {
        try save("Just taken", minutes: -1, status: .pending)
        try save("Older", minutes: -2, status: .done, text: "older text")
        var state = try window(selecting: "Just taken")
        _ = state.requestCopyText(pasteboardChangeCount: 41)
        state.setText("older")
        XCTAssertTrue(state.apply(try index.search(state.query), for: state.query))
        XCTAssertEqual(state.selected?.title, "Older")
        XCTAssertNil(state.waitingTextCopy)
    }

    func testHidingThePanelDropsTheWaitingCopy() throws {
        try save("Just taken", minutes: -1, status: .pending)
        var state = try window(selecting: "Just taken")
        _ = state.requestCopyText(pasteboardChangeCount: 41)
        state.windowHidden()
        XCTAssertNil(state.waitingTextCopy)
    }

    /// Another row's update (or the same row saved again as `pending`) leaves the request waiting.
    func testAWaitingCopyKeepsWaitingWhileTheRowIsPending() throws {
        try save("Just taken", minutes: -1, status: .pending)
        try save("Other pending", minutes: -2, status: .pending)
        var state = try window(selecting: "Just taken")
        _ = state.requestCopyText(pasteboardChangeCount: 41)
        try read("Other pending", as: .text("not this one"), in: &state)
        XCTAssertEqual(state.resolveWaitingTextCopy(pasteboardChangeCount: 41), .waiting)
        XCTAssertNotNil(state.waitingTextCopy)
    }

    /// Only the last waiting request counts: pressing ⇧⌘C again records the clipboard as it is now.
    func testOnlyTheLastWaitingRequestCounts() throws {
        try save("Just taken", minutes: -1, status: .pending)
        var state = try window(selecting: "Just taken")
        _ = state.requestCopyText(pasteboardChangeCount: 41)
        _ = state.requestCopyText(pasteboardChangeCount: 44)
        try read("Just taken", as: .text("Order #A-20417"), in: &state)
        XCTAssertEqual(state.resolveWaitingTextCopy(pasteboardChangeCount: 44), .perform(.copy("Order #A-20417")))
    }

    /// The read found no text, or failed: the user asked to copy, so the pill says why nothing was copied.
    func testAWaitingCopyThatEndsWithoutTextSaysWhy() throws {
        try save("Blank", minutes: -1, status: .pending)
        try save("Broken", minutes: -2, status: .pending)
        var blank = try window(selecting: "Blank")
        _ = blank.requestCopyText(pasteboardChangeCount: 41)
        try read("Blank", as: .noText, in: &blank)
        XCTAssertEqual(blank.resolveWaitingTextCopy(pasteboardChangeCount: 41), .perform(.noText))
        var broken = try window(selecting: "Broken")
        _ = broken.requestCopyText(pasteboardChangeCount: 41)
        try read("Broken", as: .failed(reason: "file missing"), in: &broken)
        XCTAssertEqual(broken.resolveWaitingTextCopy(pasteboardChangeCount: 41), .perform(.failed(fileMissing: true)))
    }

    /// A request that doesn't wait (a ready row) records nothing.
    func testARequestThatDoesNotWaitRecordsNothing() throws {
        try save("Ready", minutes: -1, status: .done, text: "ready text")
        var state = try window(selecting: "Ready")
        XCTAssertEqual(state.requestCopyText(pasteboardChangeCount: 41), .copy("ready text"))
        XCTAssertNil(state.waitingTextCopy)
    }

    // MARK: The badge on the preview image (design §5, "Copy Text: badge, pills, announcements")

    func testTheBadgeFollowsTheTextStatus() throws {
        try save("Ready", minutes: -1, status: .done, text: "ready text")
        try save("Reading", minutes: -2, status: .pending)
        try save("Unreadable", minutes: -3, status: .failed, error: "VNErrorDomain 9")
        try save("Blank", minutes: -4, status: .noText)
        try save("Old", minutes: -5, status: nil)
        XCTAssertEqual(try window(selecting: "Ready").copyTextBadge, .copyText)
        XCTAssertEqual(try window(selecting: "Reading").copyTextBadge, .reading)
        XCTAssertEqual(try window(selecting: "Unreadable").copyTextBadge, .readAgain)
        XCTAssertNil(try window(selecting: "Blank").copyTextBadge, "no text: hidden")
        XCTAssertNil(try window(selecting: "Old").copyTextBadge, "never read: hidden until ticket 07 reads on demand")
        XCTAssertNil(SearchWindowState().copyTextBadge, "no selection")
    }

    func testTheBadgeWording() {
        XCTAssertEqual(CopyTextBadge.copyText.title, "Copy Text")
        XCTAssertEqual(CopyTextBadge.copyText.shortcut, "⇧⌘C")
        XCTAssertEqual(CopyTextBadge.copyText.help, "Copy the text in this screenshot (⇧⌘C)")
        XCTAssertEqual(CopyTextBadge.copyText.accessibilityLabel, "Copy Text")
        XCTAssertNil(CopyTextBadge.copyText.accessibilityHint)

        XCTAssertEqual(CopyTextBadge.reading.title, "Reading text…")
        XCTAssertNil(CopyTextBadge.reading.shortcut)
        XCTAssertEqual(CopyTextBadge.reading.help, "Reading the text. It's copied when it's ready.")
        XCTAssertEqual(CopyTextBadge.reading.accessibilityLabel, "Reading text")

        XCTAssertEqual(CopyTextBadge.readAgain.title, "Read text again")
        XCTAssertNil(CopyTextBadge.readAgain.shortcut)
        XCTAssertEqual(CopyTextBadge.readAgain.help, "The text could not be read. Read it again.")
        XCTAssertEqual(CopyTextBadge.readAgain.accessibilityLabel, "Read text again")
        XCTAssertEqual(CopyTextBadge.readAgain.accessibilityHint, "The text could not be read last time.")
    }

    /// ⇧⌘C appears on the badge, and the key map binds the same key.
    func testTheBadgeShowsTheKeyTheMapBinds() {
        XCTAssertEqual(CopyTextBadge.copyText.shortcut, SearchKeyMap.commandShortcutText(for: .copyText))
    }

    /// A `done` row always has text (the runner stores an empty read as `none`); if one hasn't, nothing is copied.
    func testADoneRowWithoutTextCountsAsNoText() throws {
        try save("Odd row", minutes: -1, status: .done, text: "  \n ")
        XCTAssertEqual(try window(selecting: "Odd row").copyTextOutcome, .noText)
    }
}
