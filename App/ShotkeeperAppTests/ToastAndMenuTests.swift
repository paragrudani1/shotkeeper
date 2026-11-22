import AppKit
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

@MainActor
final class ToastPanelTests: XCTestCase {
    func testPanelIsNonActivatingFloatingAndTakesKeyOnlyWhileEditing() {
        let panel = ToastPanel(contentSize: NSSize(width: ToastView.width, height: 120))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.canBecomeKey, "a toast never takes the keyboard from the front app")
        XCTAssertFalse(panel.canBecomeMain)
        panel.allowsKey = true
        XCTAssertTrue(panel.canBecomeKey, "the name field needs key while editing")
    }

    func testPlacementIsBottomRightOfTheVisibleFrameWithSixteenPointMargins() {
        let visible = NSRect(x: 1440, y: 80, width: 1920, height: 1000)  // a second screen, Dock at the bottom
        let frame = ToastPlacement.frame(size: NSSize(width: 308, height: 110), visibleFrame: visible)
        XCTAssertEqual(frame, NSRect(x: 1440 + 1920 - 16 - 308, y: 96, width: 308, height: 110))
    }

    func testScreenUnderThePointerIsChosen() {
        let frames = [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: 1440, y: -200, width: 2560, height: 1440)]
        XCTAssertEqual(ToastPlacement.screenIndex(containing: NSPoint(x: 2000, y: 100), screenFrames: frames), 1)
        XCTAssertEqual(ToastPlacement.screenIndex(containing: NSPoint(x: 10, y: 10), screenFrames: frames), 0)
        XCTAssertNil(ToastPlacement.screenIndex(containing: NSPoint(x: -50, y: 10), screenFrames: frames))
    }

    func testControllerShowsReplacesAndDismisses() {
        let controller = ToastController(handlers: .init(undo: { _ in .restored(RestoredToast(restoredPaths: ["/a.png"])) },
                                                         rename: { toast, _ in .success(toast) },
                                                         viewInSearch: { _ in }, fixSettings: {}))
        controller.show(.renamed(Fixtures.renamed), on: NSScreen.main)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.model.countdown?.isRunning, true)
        controller.show(.batch(Fixtures.batch(excluded: 0)), on: nil)
        guard case .batch? = controller.model.content else { return XCTFail("a new toast replaces the old") }
        controller.undo()
        guard case .restored? = controller.model.content else { return XCTFail("undo shows the restored toast") }
        controller.dismiss()
        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(controller.model.content)
    }

    func testEditingPausesTheTimerAndHoldsBackANewToast() {
        var renamedTo: String?
        let controller = ToastController(handlers: .init(
            undo: { _ in .restored(RestoredToast(restoredPaths: [])) },
            rename: { toast, name in
                renamedTo = name
                return .success(toast.edited(to: URL(fileURLWithPath: "/d/\(name).png"), undoRecordID: UUID()))
            },
            viewInSearch: { _ in }, fixSettings: {}))
        controller.show(.renamed(Fixtures.renamed), on: NSScreen.main)
        controller.beginEdit()
        XCTAssertTrue(controller.model.isEditing)
        XCTAssertEqual(controller.model.editText, "Tweet semiconductor flashcards")
        XCTAssertEqual(controller.model.countdown?.isRunning, false)

        controller.show(.batch(Fixtures.batch(excluded: 0)), on: nil)
        guard case .renamed? = controller.model.content else { return XCTFail("typing is not interrupted") }

        controller.model.editText = "Semiconductor flashcards"
        controller.saveEdit()
        XCTAssertEqual(renamedTo, "Semiconductor flashcards")
        XCTAssertFalse(controller.model.isEditing)
        guard case .batch? = controller.model.content else { return XCTFail("the held toast shows after the edit") }
        controller.dismiss()
    }

    func testFailedSaveKeepsEditingWithAReadableProblem() {
        let controller = ToastController(handlers: .init(
            undo: { _ in .restored(RestoredToast(restoredPaths: [])) },
            rename: { _, _ in .failure(UserFacingError.problem(for: ManualRenameError.unusableName("..."))) },
            viewInSearch: { _ in }, fixSettings: {}))
        controller.show(.renamed(Fixtures.renamed), on: NSScreen.main)
        controller.beginEdit()
        controller.saveEdit()
        XCTAssertTrue(controller.model.isEditing)
        XCTAssertEqual(controller.model.editProblem, "That name cannot be used as a file name.")
        controller.cancelEdit()
        XCTAssertFalse(controller.model.isEditing)
        XCTAssertEqual(controller.model.countdown?.isRunning, true)
        controller.dismiss()
    }
}

@MainActor
final class MenuTests: XCTestCase {
    func testMenuPanelTakesKeyWithoutActivating() {
        let panel = MenuPanel(contentSize: NSSize(width: 300, height: 300))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }

    func testPlacementBelowTheStatusItemStaysOnScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let button = NSRect(x: 1400, y: 876, width: 24, height: 24)
        let frame = MenuPlacement.frame(size: NSSize(width: 300, height: 400), below: button, visibleFrame: visible)
        XCTAssertEqual(frame.maxX, 1436, "pushed left to stay on screen")
        XCTAssertEqual(frame.maxY, 874)
        let left = MenuPlacement.frame(size: NSSize(width: 300, height: 400), below: NSRect(x: 600, y: 876, width: 24, height: 24),
                                       visibleFrame: visible)
        XCTAssertEqual(left.minX, 600)
    }

    func testKeys() {
        XCTAssertEqual(MenuKey.from(keyCode: 125, modifiers: [], characters: nil), .down)
        XCTAssertEqual(MenuKey.from(keyCode: 126, modifiers: [], characters: nil), .up)
        XCTAssertEqual(MenuKey.from(keyCode: 36, modifiers: [], characters: "\r"), .activate(reveal: false))
        XCTAssertEqual(MenuKey.from(keyCode: 36, modifiers: [.option], characters: "\r"), .activate(reveal: true))
        XCTAssertEqual(MenuKey.from(keyCode: 53, modifiers: [], characters: nil), .close)
        XCTAssertEqual(MenuKey.from(keyCode: 6, modifiers: [.command], characters: "z"), .shortcut(.undo))
        XCTAssertEqual(MenuKey.from(keyCode: 43, modifiers: [.command], characters: ","), .shortcut(.settings))
        XCTAssertEqual(MenuKey.from(keyCode: 12, modifiers: [.command], characters: "q"), .shortcut(.quit))
        XCTAssertNil(MenuKey.from(keyCode: 6, modifiers: [.command, .shift], characters: "z"))
    }

    func testHighlightWrapsAround() {
        let highlight = MenuHighlight()
        let rows: [MenuRowID] = [.recent(1), .undo, .quit]
        highlight.move(1, in: rows)
        XCTAssertEqual(highlight.row, .recent(1))
        highlight.move(-1, in: rows)
        XCTAssertEqual(highlight.row, .quit)
        highlight.move(1, in: rows)
        XCTAssertEqual(highlight.row, .recent(1))
    }

    func testRowsHideWhatDoesNotApply() {
        var state = MenuViewState(status: MenuStatusSummary(dot: .green, headline: "", detail: ""), now: Date(),
                                  undoTitle: "Undo", canUndo: false, isPaused: false, searchShortcut: "⌥⌘S", version: "1")
        XCTAssertEqual(state.rows, [.pause, .processExisting, .search, .settings, .about, .quit])
        state.isPaused = true
        state.canUndo = true
        state.recents = [RecentItem(id: 9, path: "/a.png", title: "a", source: nil, date: Date())]
        state.showsFixSettings = true
        XCTAssertEqual(state.rows, [.fixSettings, .recent(9), .undo, .resume, .processExisting, .search, .settings, .about, .quit])
    }

    func testStatusIconsAreTemplates() {
        for status: QueueStatus in [.idle, .processing(current: URL(fileURLWithPath: "/a"), remaining: 0),
                                    .paused(until: nil), .offline, .error("x")] {
            XCTAssertTrue(StatusItemController.icon(for: status).isTemplate, "\(status)")
        }
        let glyph = MenuBarGlyph.image()
        XCTAssertTrue(glyph.isTemplate)
        XCTAssertEqual(glyph.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(glyph.accessibilityDescription, "Shotkeeper")
    }
}

@MainActor
final class CoordinatorFeedbackTests: TempDirectoryTestCase {
    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(supportDirectory: directory.appendingPathComponent("support"), credentials: InMemoryCredentialStore(),
                       physicalMemoryBytes: 16 * 1_073_741_824, applicationSupport: directory,
                       logDirectory: directory.appendingPathComponent("logs"))
    }

    private func renamedEvent(_ n: Int) -> ScreenshotEvent {
        .processed(ProcessingReport(originalURL: URL(fileURLWithPath: "/d/Screenshot \(n).png"),
                                    outcome: .processed(finalURL: URL(fileURLWithPath: "/d/Title \(n).png"),
                                                        renamed: true, moved: false),
                                    undoRecordID: UUID()))
    }

    func testRenameShowsAToastPulsesAndPlaysTheSoundOnlyWhenEnabled() {
        let coordinator = makeCoordinator()
        var toasts: [ToastContent] = []
        var sounds = 0
        coordinator.onToast = { toasts.append($0) }
        coordinator.onRenameSound = { sounds += 1 }
        let t0 = Date()
        coordinator.handle(renamedEvent(1), now: t0)
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(sounds, 0, "sound is off by default")
        XCTAssertEqual(coordinator.renamePulse, 1)

        coordinator.updateSettings { $0.playRenameSound = true; $0.showRenameToast = false }
        coordinator.handle(renamedEvent(2), now: t0.addingTimeInterval(20))
        coordinator.handle(renamedEvent(3), now: t0.addingTimeInterval(20.5))
        XCTAssertEqual(toasts.count, 1, "toasts off")
        XCTAssertEqual(sounds, 1, "at most one sound per \(AppCoordinator.renameSoundSpacing) s")
        XCTAssertEqual(coordinator.renamePulse, 3)

        coordinator.handle(.failed(originalURL: URL(fileURLWithPath: "/d/x.png"),
                                   problem: UserFacingProblem(message: "Cloudflare API token is not set", needsSettings: true)))
        guard case .error? = toasts.last else { return XCTFail("errors still show with rename toasts off") }
    }

    func testSuccessClearsTheLastMessage() {
        let coordinator = makeCoordinator()
        coordinator.lastMessage = "Queued 3 screenshots"
        XCTAssertEqual(coordinator.lastMessage, "Queued 3 screenshots")
        coordinator.handle(renamedEvent(1))
        XCTAssertNil(coordinator.lastMessage)
    }

    func testRenameAndUndoFromTheToastGoThroughCore() throws {
        let coordinator = makeCoordinator()
        let desktop = directory.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let file = desktop.appendingPathComponent("Tweet.png")
        try Data("png".utf8).write(to: file)
        let toast = RenamedToast(originalURL: desktop.appendingPathComponent("Screenshot 1.png"), currentURL: file,
                                 undoRecordIDs: [])

        guard case .failure(let problem) = coordinator.renameFromToast(toast, to: "///") else { return XCTFail() }
        XCTAssertEqual(problem.message, "that name cannot be used as a file name")

        guard case .success(let edited) = coordinator.renameFromToast(toast, to: "Tweet: semiconductor flashcards") else {
            return XCTFail()
        }
        XCTAssertEqual(edited.currentURL.lastPathComponent, "Tweet - semiconductor flashcards.png")
        XCTAssertEqual(edited.undoRecordIDs.count, 1)
        XCTAssertEqual(coordinator.undoCandidate?.id, edited.undoRecordIDs.first)
        XCTAssertEqual(MenuText.undoItem(for: coordinator.undoCandidate), "Undo: Tweet - semiconductor flashcards")

        guard case .restored(let restored) = coordinator.undoFromToast(ids: edited.undoRecordIDs) else { return XCTFail() }
        XCTAssertEqual(restored.title, "Tweet")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(coordinator.undoCandidate)

        guard case .error(let error) = coordinator.undoFromToast(ids: edited.undoRecordIDs) else { return XCTFail() }
        XCTAssertEqual(error.title, "Could not undo: that rename was already undone")
    }

    func testMenuStateFromCoordinator() {
        let coordinator = makeCoordinator()
        let state = MenuViewState.make(from: coordinator, searchShortcut: "⌥⌘S", version: "0.1.0")
        // A fresh install watches nothing until setup chose a usable backend.
        XCTAssertEqual(state.status, MenuStatusSummary(dot: .orange, headline: "Not watching yet",
                                                       detail: "Cloudflare account ID is not set"))
        XCTAssertEqual(state.undoTitle, "Undo")
        XCTAssertFalse(state.canUndo)
        XCTAssertTrue(state.showsFinishSetup)
        XCTAssertNil(state.download)

        // Consent given but the backend step skipped: still "Finish Setup…".
        coordinator.acceptPrivacyStep()
        XCTAssertTrue(MenuViewState.make(from: coordinator, searchShortcut: "⌥⌘S").showsFinishSetup)

        coordinator.saveClairicSetup(accountID: "acct", token: "tok")
        let ready = MenuViewState.make(from: coordinator, searchShortcut: "⌥⌘S", version: "0.1.0")
        XCTAssertEqual(ready.status.dot, .green)
        XCTAssertEqual(ready.status.detail, "Idle · 0 screenshots in the index")
        XCTAssertFalse(ready.showsFinishSetup)
    }
}
