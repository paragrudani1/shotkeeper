import AppKit
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

/// Copy Text in the panel (wave 1 ticket 06): ⇧⌘C and the badge perform core's `CopyTextOutcome` on a private
/// pasteboard, with the pills and VoiceOver announcements, and a waiting copy follows the late-copy rule through a real
/// in-memory index and its change feed. The rules are core's (`SearchCopyTextTests`).
@MainActor
final class SearchCopyTextAppTests: XCTestCase {
    /// The panel over an in-memory index, with a private pasteboard and recorded announcements and beeps.
    @MainActor
    private final class Harness {
        let index: ScreenshotIndex
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("shotkeeper-test-\(UUID().uuidString)"))
        let controller: SearchPanelController
        var announced: [String] = []
        var beeps = 0

        init() throws {
            let index = try ScreenshotIndex.inMemory()
            self.index = index
            controller = SearchPanelController(model: SearchViewModel(debounce: .zero) { query, limit, now, calendar in
                try index.search(query, limit: limit, now: now, calendar: calendar)
            })
            controller.indexChanges = { index.changes() }
            controller.resultActions.pasteboard = pasteboard
            controller.resultActions.announce = { [unowned self] in self.announced.append($0) }
            controller.resultActions.beep = { [unowned self] in self.beeps += 1 }
        }

        func close() {
            controller.hide()
            pasteboard.releaseGlobally()
        }
    }

    private var harness: Harness!
    private var index: ScreenshotIndex { harness.index }
    private var pasteboard: NSPasteboard { harness.pasteboard }
    private var controller: SearchPanelController { harness.controller }
    private var announced: [String] { harness.announced }
    private var beeps: Int { harness.beeps }

    /// A fresh harness for the test; the test closes it (`defer { close() }`).
    private func start() throws {
        harness = try Harness()
    }

    private func close() {
        harness.close()
    }

    /// Saves one row with the given text columns and shows the panel with it selected.
    @discardableResult
    private func show(status: TextStatus?, text: String? = nil, error: String? = nil) async throws -> IndexedScreenshot {
        var row = ScreenshotRow.make("Terminal error", processedAt: Date(), type: .code)
        row.textStatus = status
        row.recognizedText = text
        row.textError = error
        try index.save(row)
        controller.show()
        await controller.model.waitForPendingSearch()
        let selected = try XCTUnwrap(controller.model.selected, "the saved row is shown")
        row.id = selected.id
        return row
    }

    // MARK: Ready, no text, failed, never read

    func testShiftCommandCCopiesThePlainTextAndSaysSo() async throws {
        try start()
        defer { close() }
        try await show(status: .done, text: "error: no such module 'Vision'\n  at line 2")
        XCTAssertTrue(controller.handle(.copyText))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.types, [.string])
        XCTAssertEqual(pasteboard.string(forType: .string), "error: no such module 'Vision'\n  at line 2")
        XCTAssertEqual(controller.model.pill, .textCopied)
        XCTAssertEqual(announced, ["Text copied"])
    }

    func testCommandCStillCopiesTheImage() async throws {
        try start()
        defer { close() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        var row = ScreenshotRow.make("Shot", folder: directory.path, processedAt: Date())
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: row.path))
        row.textStatus = .done
        row.recognizedText = "text"
        try index.save(row)
        controller.show()
        await controller.model.waitForPendingSearch()
        XCTAssertTrue(controller.handle(.copyImage))
        XCTAssertNotNil(pasteboard.data(forType: .png), "⌘C copies the image, not the text")
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(controller.model.pill, .copied)
    }

    func testNoTextShowsItsPillAndWritesNothing() async throws {
        try start()
        defer { close() }
        try await show(status: .noText)
        let before = pasteboard.changeCount
        XCTAssertTrue(controller.handle(.copyText))
        XCTAssertEqual(pasteboard.changeCount, before)
        XCTAssertEqual(controller.model.pill, .noText)
        XCTAssertEqual(announced, ["No text found in this screenshot."])
        XCTAssertNil(controller.model.state.copyTextBadge, "no badge for a screenshot without text")
    }

    func testAFailedReadShowsWhy() async throws {
        try start()
        defer { close() }
        try await show(status: .failed, error: "VNErrorDomain 9")
        XCTAssertTrue(controller.handle(.copyText))
        XCTAssertEqual(controller.model.pill, .problem("The text could not be read."))
        XCTAssertEqual(announced, ["The text could not be read."])
        XCTAssertEqual(controller.model.state.copyTextBadge, .readAgain)
    }

    func testAFileMissingAtReadTimeGetsTheMissingFileSentence() async throws {
        try start()
        defer { close() }
        try await show(status: .failed, error: "file missing")
        XCTAssertTrue(controller.handle(.copyText))
        XCTAssertEqual(controller.model.pill, .problem(SearchWindowState.missingFileMessage))
    }

    /// Interim until ticket 07: a never-read row has no badge and ⇧⌘C beeps.
    func testANeverReadRowBeeps() async throws {
        try start()
        defer { close() }
        try await show(status: nil)
        let before = pasteboard.changeCount
        XCTAssertTrue(controller.handle(.copyText))
        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(pasteboard.changeCount, before)
        XCTAssertNil(controller.model.pill)
        XCTAssertNil(controller.model.state.copyTextBadge)
    }

    func testWithoutASelectionTheKeyIsNotHandled() throws {
        try start()
        defer { close() }
        XCTAssertFalse(controller.handle(.copyText))
    }

    func testTheDatePickerIgnoresShiftCommandC() async throws {
        try start()
        defer { close() }
        try await show(status: .done, text: "text")
        XCTAssertTrue(controller.handle(.dateFilter))
        let before = pasteboard.changeCount
        XCTAssertTrue(controller.handle(.copyText), "consumed while the picker is open")
        XCTAssertEqual(pasteboard.changeCount, before)
    }

    // MARK: Waiting (`pending`) and the late-copy rule

    func testAWaitingCopyHappensWhenTheRowIsRead() async throws {
        try start()
        defer { close() }
        let row = try await show(status: .pending)
        XCTAssertEqual(controller.model.state.copyTextBadge, .reading)
        XCTAssertTrue(controller.handle(.copyText))
        XCTAssertNil(controller.model.pill)
        try index.setRecognizedText(.text("Order #A-20417"), recognizedBy: "test", id: row.id, ifContentHash: row.contentHash)
        let copied = await waitUntil { self.pasteboard.string(forType: .string) == "Order #A-20417" }
        XCTAssertTrue(copied, "the row's `.updated` change refreshed the panel and the copy happened")
        XCTAssertEqual(controller.model.pill, .textCopied)
        XCTAssertEqual(announced, ["Text copied"])
        XCTAssertEqual(controller.model.state.copyTextBadge, .copyText)
    }

    /// Story 37: the user copied something else while the row was read; their clipboard is left alone.
    func testAWaitingCopyLeavesANewerClipboardAlone() async throws {
        try start()
        defer { close() }
        let row = try await show(status: .pending)
        XCTAssertTrue(controller.handle(.copyText))
        pasteboard.clearContents()
        pasteboard.setString("copied meanwhile", forType: .string)
        try index.setRecognizedText(.text("Order #A-20417"), recognizedBy: "test", id: row.id, ifContentHash: row.contentHash)
        let refreshed = await waitUntil { self.controller.model.state.copyTextBadge == .copyText }
        XCTAssertTrue(refreshed)
        XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile")
        XCTAssertNil(controller.model.pill)
        XCTAssertEqual(announced, [])
        XCTAssertNil(controller.model.state.waitingTextCopy)
    }

    func testHidingThePanelDropsAWaitingCopy() async throws {
        try start()
        defer { close() }
        let row = try await show(status: .pending)
        XCTAssertTrue(controller.handle(.copyText))
        let before = pasteboard.changeCount
        controller.hide()
        try index.setRecognizedText(.text("Order #A-20417"), recognizedBy: "test", id: row.id, ifContentHash: row.contentHash)
        controller.model.refresh()
        await controller.model.waitForPendingSearch()
        XCTAssertEqual(pasteboard.changeCount, before)
    }

    // MARK: The badge's mouse handling

    /// A press on the badge is the badge's: no click reported to the image (so no double-click opens the file), and a
    /// release on it runs Copy Text. The next press on the image is not counted as its double-click.
    func testAClickOnTheBadgeIsNotAClickOnTheImage() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 220), styleMask: .borderless,
                              backing: .buffered, defer: false)
        let view = FileDragView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))
        window.contentView = view
        view.badgeFrame = CGRect(x: 270, y: 184, width: 120, height: 26)  // bottom-right, inset 10 (top-left origin)
        var clicks: [Int] = []
        var badgeClicks = 0
        view.onMouseDown = { clicks.append($0) }
        view.onBadgeClick = { badgeClicks += 1 }
        func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, clickCount: Int) throws -> NSEvent {
            // Window coordinates have their origin at the bottom left.
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 220 - y), modifierFlags: [],
                                             timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: clickCount, pressure: 1))
        }

        view.mouseDown(with: try event(.leftMouseDown, x: 300, y: 196, clickCount: 2))
        view.mouseUp(with: try event(.leftMouseUp, x: 300, y: 196, clickCount: 2))
        XCTAssertEqual(badgeClicks, 1)
        XCTAssertEqual(clicks, [], "the image never sees a press on the badge")

        view.mouseDown(with: try event(.leftMouseDown, x: 300, y: 196, clickCount: 1))
        view.mouseUp(with: try event(.leftMouseUp, x: 100, y: 100, clickCount: 1))
        XCTAssertEqual(badgeClicks, 1, "released off the badge: no action")

        view.mouseDown(with: try event(.leftMouseDown, x: 100, y: 100, clickCount: 2))
        view.mouseUp(with: try event(.leftMouseUp, x: 100, y: 100, clickCount: 2))
        XCTAssertEqual(clicks, [1], "a press right after the badge is a single click")
        view.mouseDown(with: try event(.leftMouseDown, x: 100, y: 100, clickCount: 2))
        XCTAssertEqual(clicks, [1, 2], "a real double-click on the image still opens it")

        view.badgeFrame = nil
        view.mouseDown(with: try event(.leftMouseDown, x: 300, y: 196, clickCount: 1))
        XCTAssertEqual(clicks, [1, 2, 1], "no badge: the corner is image")
    }
}
