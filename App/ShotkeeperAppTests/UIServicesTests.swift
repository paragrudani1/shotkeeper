import AppKit
import Carbon.HIToolbox
import ServiceManagement
import XCTest
@testable import Shotkeeper

@MainActor
final class GlobalHotKeyTests: XCTestCase {
    func testDefaultShortcutIsOptionCommandS() {
        let shortcut = GlobalHotKey.Shortcut.defaultSearch
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_S))
        XCTAssertEqual(shortcut.modifiers, UInt32(optionKey | cmdKey))
        XCTAssertEqual(shortcut.displayString, "⌥⌘S")
    }

    func testDisplayStringOrdersModifiersLikeMacOS() {
        let shortcut = GlobalHotKey.Shortcut(keyCode: UInt32(kVK_Space),
                                             modifiers: UInt32(cmdKey | shiftKey | controlKey | optionKey))
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘Space")
    }
}

@MainActor
final class SearchPanelTests: XCTestCase {
    func testPanelIsNonActivatingFloatingAndCanTakeKeyboardFocus() {
        let panel = SearchPanel(contentSize: SearchPanel.defaultContentSize)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
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
