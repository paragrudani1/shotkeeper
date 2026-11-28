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
        XCTAssertNil(SearchKeyMap.command(keyCode: 8, modifiers: [.command, .shift], characters: "c"))
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
}
