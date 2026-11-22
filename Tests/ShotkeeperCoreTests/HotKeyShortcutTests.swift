import XCTest
@testable import ShotkeeperCore

final class HotKeyShortcutTests: XCTestCase {
    private func key(_ code: Int, _ mods: HotKeyShortcut.Modifiers) -> HotKeyShortcut {
        HotKeyShortcut(keyCode: code, modifiers: mods)
    }

    func testDefaultIsOptionCommandS() {
        XCTAssertEqual(AppSettings().searchShortcut, .defaultSearch)
        XCTAssertEqual(HotKeyShortcut.defaultSearch.displayString, "⌥⌘S")
        XCTAssertEqual(HotKeyShortcut.defaultSearch.spokenName, "Option Command S")
        XCTAssertNil(HotKeyRules.problem(with: .defaultSearch))
    }

    func testDisplayUsesTheMenuOrderAndKeySymbols() {
        XCTAssertEqual(key(KeyCode.k, [.command, .shift, .option, .control]).displayString, "⌃⌥⇧⌘K")
        XCTAssertEqual(key(KeyCode.space, [.control, .option]).displayString, "⌃⌥Space")
        XCTAssertEqual(key(KeyCode.f5, [.command, .shift]).displayString, "⇧⌘F5")
        XCTAssertEqual(key(KeyCode.upArrow, [.control, .command]).displayString, "⌃⌘↑")
        XCTAssertEqual(key(KeyCode.upArrow, [.control, .command]).spokenName, "Control Command Up Arrow")
        XCTAssertEqual(key(KeyCode.one, [.option, .command]).displayString, "⌥⌘1")
        XCTAssertEqual(key(0x2B, [.control, .command]).displayString, "⌃⌘,")
        XCTAssertEqual(key(0x99, [.command]).displayString, "⌘Key 153")
        XCTAssertEqual(HotKeyShortcut.Modifiers([.shift, .control]).symbols, "⌃⇧", "held modifiers while recording")
    }

    func testNeedsCommandOrControl() {
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.s, [])), .needsCommandOrControl)
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.s, [.option])), .needsCommandOrControl, "⌥S types ß")
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.s, [.shift, .option])), .needsCommandOrControl)
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.f6, [])), .needsCommandOrControl)
        XCTAssertNil(HotKeyRules.problem(with: key(KeyCode.s, [.control, .option])))
        XCTAssertNil(HotKeyRules.problem(with: key(KeyCode.k, [.control, .command])))
    }

    func testCommandAloneIsLeftToApps() {
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.c, [.command])), .usedByApps)
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.n, [.shift, .command])), .usedByApps)
        XCTAssertEqual(HotKeyRules.problem(with: key(0x2B, [.command])), .usedByApps, "⌘, is Settings everywhere")
        XCTAssertNil(HotKeyRules.problem(with: key(KeyCode.f6, [.command])), "⌘F6 is not a menu shortcut")
    }

    func testControlWithALetterIsLeftToTextFields() {
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.a, [.control])), .textEditingKey)
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.k, [.control, .shift])), .textEditingKey)
        XCTAssertNil(HotKeyRules.problem(with: key(KeyCode.k, [.control, .option])))
        XCTAssertNil(HotKeyRules.problem(with: key(KeyCode.one, [.control])), "⌃1 is not a text-editing key")
        XCTAssertEqual(HotKeyProblem.textEditingKey.message(for: key(KeyCode.e, [.control])),
                       "⌃E moves the cursor or edits text in text fields. Add ⌥ or ⌘.")
    }

    func testLayoutNamesReplaceOnlyCharacterKeys() {
        XCTAssertEqual(key(KeyCode.z, [.option, .command]).displayString(keyName: "Y"), "⌥⌘Y", "QWERTZ")
        XCTAssertEqual(key(KeyCode.f5, [.control, .command]).displayString(keyName: "x"), "⌃⌘F5")
        XCTAssertEqual(key(KeyCode.space, [.control, .option]).displayString(keyName: " "), "⌃⌥Space")
        XCTAssertEqual(HotKeyProblem.usedByApps.message(for: key(KeyCode.z, [.command]), display: "⌘Y"),
                       "⌘Y is a menu shortcut in many apps. Add ⌥ or ⌃.")
    }

    func testKnownSystemShortcutsAreRejectedWithTheirName() {
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.space, [.command])), .system(name: "Spotlight"))
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.four, [.shift, .command])), .system(name: "screenshots"))
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.q, [.control, .command])), .system(name: "Lock Screen"))
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.upArrow, [.control])), .system(name: "Mission Control"))
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.space, [.control, .command])), .system(name: "Emoji & Symbols"))
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.escape, [.option, .command])), .unsupportedKey,
                       "Esc cancels recording")
        XCTAssertEqual(HotKeyRules.problem(with: key(KeyCode.space, [.option, .command])),
                       .system(name: "a Finder search window"))
        XCTAssertEqual(HotKeyProblem.system(name: "Spotlight").message(for: key(KeyCode.space, [.command])),
                       "⌘Space is the macOS shortcut for Spotlight. Choose another one.")
    }

    func testRegistrationFailureMessages() {
        let shortcut = key(KeyCode.k, [.control, .option])
        XCTAssertEqual(HotKeyRules.registrationProblem(status: -9878), .registrationFailed(inUseByAnotherApp: true))
        XCTAssertEqual(HotKeyRules.registrationProblem(status: -50), .registrationFailed(inUseByAnotherApp: false))
        XCTAssertEqual(HotKeyRules.registrationProblem(status: -9878).message(for: shortcut),
                       "Another app already uses ⌃⌥K. Choose another shortcut.")
        XCTAssertEqual(HotKeyProblem.needsCommandOrControl.message(for: shortcut),
                       "Add ⌘ or ⌃ to the shortcut. Keys with only ⌥ or ⇧ type characters.")
    }

    func testStoredShortcutRoundTripsAndABadOneFallsBack() throws {
        var settings = AppSettings()
        settings.searchShortcut = key(KeyCode.k, [.control, .option])
        XCTAssertEqual(AppSettings.decode(try settings.encoded()).searchShortcut, key(KeyCode.k, [.control, .option]))

        let notAllowed = #"{"searchShortcut":{"keyCode":8,"modifiers":8}}"#  // ⌘C
        XCTAssertEqual(AppSettings.decode(Data(notAllowed.utf8)).searchShortcut, .defaultSearch)
        let garbage = #"{"searchShortcut":"cmd-s"}"#
        XCTAssertEqual(AppSettings.decode(Data(garbage.utf8)).searchShortcut, .defaultSearch)
    }
}
