import XCTest
@testable import ShotkeeperCore

/// The search window's key table (moved from the app on 2026-11-28 so ⌘ assignments are tested on Linux).
final class SearchKeyMapTests: XCTestCase {
    // MARK: Table rules (new shortcuts must keep these)

    func testNoTwoActionsShareAKey() {
        var seen: [SearchKeyTrigger: SearchKey] = [:]
        for binding in SearchKeyMap.bindings {
            if let other = seen[binding.trigger] {
                XCTFail("\(binding.trigger) is bound to both \(other) and \(binding.key)")
            }
            seen[binding.trigger] = binding.key
        }
    }

    func testCommandKeysAreLowerCaseASCIILettersOrDigits() {
        for binding in SearchKeyMap.bindings {
            guard case .command(let character) = binding.trigger else { continue }
            XCTAssertTrue(character.isASCII && (character.isLowercase || character.isNumber), "⌘\(character)")
        }
    }

    /// A ⌘ key with no ANSI physical key would do nothing on a Russian or Greek layout.
    func testEveryCommandKeyHasAPhysicalKey() {
        for binding in SearchKeyMap.bindings {
            guard case .command(let character) = binding.trigger else { continue }
            let keyCodes = (0..<128).filter { SearchKeyMap.physicalCharacter($0) == character }
            XCTAssertEqual(keyCodes.count, 1, "⌘\(character) needs exactly one physical key, found \(keyCodes)")
        }
    }

    func testTheFieldsEditingKeysStayFree() {
        for binding in SearchKeyMap.bindings {
            guard case .command(let character) = binding.trigger else { continue }
            XCTAssertFalse(SearchKeyMap.reservedCommandCharacters.contains(character),
                           "⌘\(character) belongs to the search field or macOS")
        }
    }

    func testEveryChipHasItsNumberAndTheTooltipSaysSo() {
        for chip in SearchChip.allCases {
            XCTAssertEqual(SearchKeyMap.commandShortcutText(for: .chip(chip)), "⌘\(chip.shortcutNumber)")
            XCTAssertTrue(chip.help.hasSuffix("(⌘\(chip.shortcutNumber))"), chip.help)
        }
    }

    func testCommandShortcutText() {
        XCTAssertEqual(SearchKeyMap.commandShortcutText(for: .copyImage), "⌘C")
        XCTAssertEqual(SearchKeyMap.commandShortcutText(for: .reveal), "⌘R")
        XCTAssertEqual(SearchKeyMap.commandShortcutText(for: .quickLook), "⌘Y")
        XCTAssertNil(SearchKeyMap.commandShortcutText(for: .open))
    }

    // MARK: Lookup (was the app's SearchKeyTests)

    func testPlainKeys() {
        XCTAssertEqual(SearchKeyMap.plain(keyCode: 126, modifiers: []), .up)
        XCTAssertEqual(SearchKeyMap.plain(keyCode: 125, modifiers: []), .down)
        XCTAssertEqual(SearchKeyMap.plain(keyCode: 36, modifiers: []), .open)
        XCTAssertEqual(SearchKeyMap.plain(keyCode: 76, modifiers: []), .open)
        XCTAssertEqual(SearchKeyMap.plain(keyCode: 53, modifiers: []), .close)
        XCTAssertEqual(SearchKeyMap.plain(keyCode: 49, modifiers: []), .space)
        XCTAssertNil(SearchKeyMap.plain(keyCode: 8, modifiers: []), "plain c is typing")
        XCTAssertNil(SearchKeyMap.plain(keyCode: 126, modifiers: [.shift]), "⇧↑ extends the text selection")
        XCTAssertNil(SearchKeyMap.plain(keyCode: 49, modifiers: [.shift]), "⇧Space is typing")
        XCTAssertNil(SearchKeyMap.plain(keyCode: 8, modifiers: [.command]), "⌘ keys go through performKeyEquivalent")
    }

    func testCommandKeys() {
        XCTAssertEqual(SearchKeyMap.command(keyCode: 8, modifiers: [.command], characters: "c"), .copyImage)
        XCTAssertEqual(SearchKeyMap.command(keyCode: 15, modifiers: [.command], characters: "r"), .reveal)
        XCTAssertEqual(SearchKeyMap.command(keyCode: 16, modifiers: [.command], characters: "y"), .quickLook)
        XCTAssertEqual(SearchKeyMap.command(keyCode: 18, modifiers: [.command], characters: "1"), .chip(.all))
        XCTAssertEqual(SearchKeyMap.command(keyCode: 26, modifiers: [.command], characters: "7"), .chip(.design))
        XCTAssertEqual(SearchKeyMap.command(keyCode: 8, modifiers: [.command], characters: "C"), .copyImage, "Caps Lock")
        XCTAssertNil(SearchKeyMap.command(keyCode: 28, modifiers: [.command], characters: "8"))
        XCTAssertNil(SearchKeyMap.command(keyCode: 8, modifiers: [.command, .option], characters: "c"))
        XCTAssertNil(SearchKeyMap.command(keyCode: 8, modifiers: [], characters: "c"))
    }

    func testCommandKeysWorkOnOtherLayouts() {
        // Russian: the C key types "с" (Cyrillic); the physical key decides.
        XCTAssertEqual(SearchKeyMap.command(keyCode: 8, modifiers: [.command], characters: "с"), .copyImage)
        // AZERTY: the 1 key types "&" without Shift.
        XCTAssertEqual(SearchKeyMap.command(keyCode: 18, modifiers: [.command], characters: "&"), .chip(.all))
        // Dvorak: the key labelled C is a different physical key; the typed letter decides.
        XCTAssertEqual(SearchKeyMap.command(keyCode: 34, modifiers: [.command], characters: "c"), .copyImage)
        XCTAssertNil(SearchKeyMap.command(keyCode: 8, modifiers: [.command], characters: "j"), "Dvorak J on the QWERTY C key")
        // No characters at all: the physical key.
        XCTAssertEqual(SearchKeyMap.command(keyCode: 15, modifiers: [.command], characters: nil), .reveal)
    }

    // MARK: Date filter (wave 1 ticket 02)

    func testCommandDOpensTheDatePickerOnEveryLayout() {
        XCTAssertEqual(SearchKeyMap.command(keyCode: 2, modifiers: [.command], characters: "d"), .dateFilter)
        // Russian: the D key types "в"; the physical key decides.
        XCTAssertEqual(SearchKeyMap.command(keyCode: 2, modifiers: [.command], characters: "в"), .dateFilter)
        // Dvorak: D is on the QWERTY H key; the typed letter decides.
        XCTAssertEqual(SearchKeyMap.command(keyCode: 4, modifiers: [.command], characters: "d"), .dateFilter)
        XCTAssertNil(SearchKeyMap.command(keyCode: 2, modifiers: [.command, .shift], characters: "d"))
        XCTAssertEqual(SearchKeyMap.commandShortcutText(for: .dateFilter), "⌘D")
        XCTAssertTrue(SearchWindowState().datePillHelp.hasSuffix("(⌘D)"), "the pill's tooltip names the key")
    }

    // MARK: Copy Text (wave 1 ticket 06)

    /// ⇧⌘C copies the text; ⌘C still copies the image. AppKit's `charactersIgnoringModifiers` keeps Shift ("C"), so
    /// the character is lowercased; a non-ASCII one falls back to the physical key, as for ⌘ keys.
    func testShiftCommandCCopiesTheTextOnEveryLayout() {
        XCTAssertEqual(SearchKeyMap.command(keyCode: 8, modifiers: [.command, .shift], characters: "C"), .copyText)
        XCTAssertEqual(SearchKeyMap.command(keyCode: 8, modifiers: [.command, .shift], characters: "c"), .copyText)
        // Russian: Shift on the C key types "С" (Cyrillic); the physical key decides.
        XCTAssertEqual(SearchKeyMap.command(keyCode: 8, modifiers: [.command, .shift], characters: "С"), .copyText)
        // Dvorak: C is on the QWERTY I key; the typed letter decides.
        XCTAssertEqual(SearchKeyMap.command(keyCode: 34, modifiers: [.command, .shift], characters: "C"), .copyText)
        XCTAssertNil(SearchKeyMap.command(keyCode: 8, modifiers: [.command, .shift], characters: "J"), "Dvorak J")
        XCTAssertEqual(SearchKeyMap.command(keyCode: 8, modifiers: [.command, .shift], characters: nil), .copyText)
        XCTAssertEqual(SearchKeyMap.command(keyCode: 8, modifiers: [.command], characters: "c"), .copyImage, "⌘C unchanged")
        XCTAssertNil(SearchKeyMap.command(keyCode: 8, modifiers: [.command, .shift, .option], characters: "C"))
        XCTAssertEqual(SearchKeyMap.commandShortcutText(for: .copyText), "⇧⌘C")
    }

    /// Shift is accepted for C only: ⇧⌘R, ⇧⌘D and ⇧⌘1 do nothing (⇧⌘ plus a digit types a symbol on most layouts).
    func testShiftIsAcceptedForCopyTextOnly() {
        XCTAssertNil(SearchKeyMap.command(keyCode: 15, modifiers: [.command, .shift], characters: "R"))
        XCTAssertNil(SearchKeyMap.command(keyCode: 2, modifiers: [.command, .shift], characters: "D"))
        XCTAssertNil(SearchKeyMap.command(keyCode: 18, modifiers: [.command, .shift], characters: "!"))
        let shiftKeys = SearchKeyMap.bindings.compactMap { binding -> Character? in
            if case .shiftCommand(let character) = binding.trigger { return character }
            return nil
        }
        XCTAssertEqual(shiftKeys, ["c"])
    }

    /// The table rules for ⌘ keys hold for ⇧⌘ keys too: lower-case ASCII, one physical key, not a field key.
    func testShiftCommandKeysFollowTheCommandKeyRules() {
        for binding in SearchKeyMap.bindings {
            guard case .shiftCommand(let character) = binding.trigger else { continue }
            XCTAssertTrue(character.isASCII && character.isLowercase, "⇧⌘\(character)")
            let keyCodes = (0..<128).filter { SearchKeyMap.physicalCharacter($0) == character }
            XCTAssertEqual(keyCodes.count, 1, "⇧⌘\(character) needs exactly one physical key, found \(keyCodes)")
            XCTAssertFalse(SearchKeyMap.reservedCommandCharacters.contains(character))
        }
    }

    func testDeleteIsAPlainKey() {
        XCTAssertEqual(SearchKeyMap.plain(keyCode: 51, modifiers: []), .deleteBackward)
        XCTAssertNil(SearchKeyMap.plain(keyCode: 51, modifiers: [.option]), "⌥⌫ deletes a word in the field")
        XCTAssertNil(SearchKeyMap.plain(keyCode: 51, modifiers: [.command]))
    }
}
