import AppKit
import Carbon.HIToolbox
import ServiceManagement
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

@MainActor
final class GlobalHotKeyTests: XCTestCase {
    func testCarbonModifiersAndKeyCodesMatchHIToolbox() {
        XCTAssertEqual(GlobalHotKey.carbonModifiers(HotKeyShortcut.defaultSearch.modifiers), UInt32(optionKey | cmdKey))
        XCTAssertEqual(GlobalHotKey.carbonModifiers([.control, .shift]), UInt32(controlKey | shiftKey))
        XCTAssertEqual(HotKeyShortcut.defaultSearch.keyCode, kVK_ANSI_S)
        XCTAssertEqual(KeyCode.k, kVK_ANSI_K)
        XCTAssertEqual(KeyCode.space, kVK_Space)
        XCTAssertEqual(KeyCode.escape, kVK_Escape)
        XCTAssertEqual(KeyCode.f5, kVK_F5)
        XCTAssertEqual(KeyCode.upArrow, kVK_UpArrow)
        XCTAssertEqual(KeyCode.slash, kVK_ANSI_Slash)
        XCTAssertEqual(HotKeyRules.eventHotKeyExistsErr, Int32(eventHotKeyExistsErr))
        XCTAssertEqual(GlobalHotKey.modifiers(from: [.command, .option, .capsLock]), [.command, .option])
    }

    /// A refused shortcut leaves the old one registered and working.
    func testSearchHotKeyKeepsTheOldShortcutUntilANewOneRegisters() {
        var registered: [HotKeyShortcut] = []
        let taken = HotKeyShortcut(keyCode: KeyCode.k, modifiers: [.control, .option])
        let hotKey = SearchHotKey(action: {}, register: { shortcut, _ in
            if shortcut == taken { throw GlobalHotKeyError.registerFailed(OSStatus(eventHotKeyExistsErr)) }
            registered.append(shortcut)
            return nil
        })
        XCTAssertNil(hotKey.use(.defaultSearch))
        XCTAssertEqual(hotKey.active, .defaultSearch)
        XCTAssertEqual(hotKey.use(taken), .registrationFailed(inUseByAnotherApp: true))
        XCTAssertEqual(hotKey.active, .defaultSearch, "the old shortcut still works")
        XCTAssertEqual(hotKey.use(HotKeyShortcut(keyCode: KeyCode.c, modifiers: [.command])), .usedByApps)
        XCTAssertNil(hotKey.use(.defaultSearch), "the same shortcut again is a no-op")
        XCTAssertEqual(registered, [.defaultSearch])
    }
}

@MainActor
final class SearchPanelTests: XCTestCase {
    func testPanelIsNonActivatingFloatingAndCanTakeKeyboardFocus() {
        let panel = SearchPanel(contentSize: SearchPanel.defaultContentSize)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled), "no title bar, no traffic lights")
        XCTAssertEqual(panel.frame.size, NSSize(width: 880, height: 540))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    func testEscapeDismisses() {
        let panel = SearchPanel(contentSize: SearchPanel.defaultContentSize)
        var dismissed = 0
        panel.onDismiss = { dismissed += 1 }
        panel.orderFrontRegardless()
        XCTAssertTrue(panel.isVisible)
        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(dismissed, 1)
    }

    func testKeysGoToTheInputMethodWhileComposing() throws {
        let panel = SearchPanel(contentSize: SearchPanel.defaultContentSize)
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        panel.contentView?.addSubview(field)
        XCTAssertTrue(panel.makeFirstResponder(field))
        var handled = 0
        panel.keyHandler = { _ in handled += 1; return true }
        let returnKey = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                       windowNumber: panel.windowNumber, context: nil, characters: "\r",
                                                       charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))

        XCTAssertFalse(panel.isComposingText)
        panel.sendEvent(returnKey)
        XCTAssertEqual(handled, 1, "no composition: the panel handles Return")

        field.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0),
                            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(panel.isComposingText)
        panel.sendEvent(returnKey)
        XCTAssertEqual(handled, 1, "Return commits the composition; it must not open a result")
        field.unmarkText()
        XCTAssertFalse(panel.isComposingText)
    }

    func testEscapeClearsTheQueryBeforeClosing() {
        let controller = SearchPanelController(model: SearchViewModel(debounce: .zero) { _, _ in
            ScreenshotSearchResult(rows: [], matchCount: 0, totalCount: 0)
        })
        controller.show()
        controller.model.setText("receipt")
        XCTAssertTrue(controller.handle(.close))
        XCTAssertTrue(controller.isVisible, "the first esc only clears the query")
        XCTAssertEqual(controller.model.state.text, "")
        XCTAssertTrue(controller.handle(.close))
        XCTAssertFalse(controller.isVisible)
    }

    func testSpaceTypesWhenTheFieldDoesNotHaveFocusOrNothingIsSelected() {
        let controller = SearchPanelController()
        controller.show()
        XCTAssertFalse(controller.handle(.space), "no selection: Space is not consumed")
        controller.hide()
    }

    func testCommandKeysArriveThroughPerformKeyEquivalent() throws {
        let panel = SearchPanel(contentSize: SearchPanel.defaultContentSize)
        var seen: [UInt16] = []
        panel.commandKeyHandler = { event in seen.append(event.keyCode); return true }
        let commandC = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                                      timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                      characters: "c", charactersIgnoringModifiers: "c",
                                                      isARepeat: false, keyCode: 8))
        XCTAssertTrue(panel.performKeyEquivalent(with: commandC))
        XCTAssertEqual(seen, [8])
    }

    func testChipShortcutSelectsTheChip() {
        let controller = SearchPanelController()
        XCTAssertTrue(controller.handle(.chip(.receipt)))
        XCTAssertEqual(controller.model.state.chip, .receipt)
    }

    func testControllerTogglesVisibility() {
        let controller = SearchPanelController()
        XCTAssertFalse(controller.isVisible)
        controller.toggle()
        XCTAssertTrue(controller.isVisible)
        controller.toggle()
        XCTAssertFalse(controller.isVisible)
        XCTAssertNotNil(controller.panel.contentView)
    }
}

final class SearchPlacementTests: XCTestCase {
    func testCenteredInTheUpperThirdAndKeptOnScreen() {
        let size = NSSize(width: 880, height: 540)
        let big = NSRect(x: 0, y: 0, width: 2560, height: 1415)
        let origin = SearchPlacement.origin(size: size, visibleFrame: big)
        XCTAssertEqual(origin.x, 840)
        XCTAssertEqual(origin.y + size.height / 2, (big.maxY - big.height / 3).rounded(), accuracy: 1)
        // A small screen: the panel moves down only as far as needed to stay below the menu bar.
        let small = NSRect(x: 0, y: 0, width: 1280, height: 700)
        XCTAssertEqual(SearchPlacement.origin(size: size, visibleFrame: small).y, 160)
        // A second screen to the left, with a negative origin.
        let left = NSRect(x: -1920, y: 0, width: 1920, height: 1050)
        let leftOrigin = SearchPlacement.origin(size: size, visibleFrame: left)
        XCTAssertEqual(leftOrigin.x, -1400)
        XCTAssertTrue(left.contains(NSRect(origin: leftOrigin, size: size)))
    }
}

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testStatusIsReadable() {
        // Registering from a test host would add a real login item, so only the status mapping is exercised.
        let status = LaunchAtLogin.status
        XCTAssertTrue([.enabled, .disabled, .requiresApproval, .notFound].contains(status))
        XCTAssertEqual(LaunchAtLogin.Status(.notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLogin.Status(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLogin.Status(.requiresApproval), .requiresApproval)
        XCTAssertEqual(LaunchAtLogin.Status(.notFound), .notFound)
    }
}
