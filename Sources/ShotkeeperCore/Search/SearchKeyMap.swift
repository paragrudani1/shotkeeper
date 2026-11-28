import Foundation

/// What a key does in the search window (spec PR 2). The app performs it (`SearchPanelController.handle`).
public enum SearchKey: Hashable, Sendable {
    case up, down, open, close, space, copyImage, reveal, quickLook, chip(SearchChip)
    /// ⌘D: open or close the date picker (design §6).
    case dateFilter
    /// ⌫: clears the date when the date list is open; otherwise it deletes in the field (the app passes it on).
    case deleteBackward
    /// ⇧⌘C: Copy Text for the selected result (spec "Which key copies the text"; `SearchWindowState.copyTextOutcome`).
    case copyText
}

/// A key of the search window, as `SearchKeyMap` matches it.
public enum SearchKeyTrigger: Hashable, Sendable {
    /// Pressed without ⌘⌥⌃⇧, by macOS virtual key code (`KeyCode`). The panel sees these in `sendEvent`.
    case plain(keyCode: Int)
    /// ⌘ plus a lower-case ASCII letter or digit. The panel sees these in `performKeyEquivalent`
    /// (docs/wiki/appkit-gotchas.md: ⌘ keys never reach `sendEvent` reliably).
    case command(Character)
    /// ⇧⌘ plus a lower-case ASCII letter, matched like `command` (seen in `performKeyEquivalent`). Only ⇧⌘C is bound:
    /// ⇧⌘ plus a digit types a symbol on most layouts, and Shift is otherwise left to the field.
    case shiftCommand(Character)
}

/// One row of the search window's key table.
public struct SearchKeyBinding: Hashable, Sendable {
    public var trigger: SearchKeyTrigger
    public var key: SearchKey

    public init(_ trigger: SearchKeyTrigger, _ key: SearchKey) {
        self.trigger = trigger
        self.key = key
    }
}

/// The search window's key → action table and its lookup. Pure, so ⌘ assignments are tested on Linux
/// (`SearchKeyMapTests`: no two actions share a key, every ⌘ key works on non-Latin layouts, the field's editing keys
/// stay free). The app only translates an `NSEvent` into `plain(keyCode:modifiers:)` / `command(keyCode:modifiers:characters:)`.
///
/// To add a shortcut: add a binding here and a case to `SearchKey`, then handle it in the app's `SearchPanelController`.
public enum SearchKeyMap {
    public static let bindings: [SearchKeyBinding] = [
        SearchKeyBinding(.plain(keyCode: KeyCode.upArrow), .up),
        SearchKeyBinding(.plain(keyCode: KeyCode.downArrow), .down),
        SearchKeyBinding(.plain(keyCode: KeyCode.returnKey), .open),
        SearchKeyBinding(.plain(keyCode: KeyCode.keypadEnter), .open),
        SearchKeyBinding(.plain(keyCode: KeyCode.escape), .close),
        SearchKeyBinding(.plain(keyCode: KeyCode.space), .space),  // Quick Look or a typed space (SearchWindowState)
        SearchKeyBinding(.plain(keyCode: KeyCode.delete), .deleteBackward),  // only the open date list takes it
        SearchKeyBinding(.command("c"), .copyImage),               // a selection in the field keeps ⌘C for its text
        SearchKeyBinding(.command("r"), .reveal),
        SearchKeyBinding(.command("y"), .quickLook),               // ⌘Y, the Finder shortcut
        SearchKeyBinding(.command("d"), .dateFilter),              // D for date (design §6)
        SearchKeyBinding(.shiftCommand("c"), .copyText),           // "Copy, variant" (spec); ⌘C stays Copy Image
    ] + SearchChip.allCases.map { chip in
        SearchKeyBinding(.command(Character(String(chip.shortcutNumber))), .chip(chip))  // ⌘1…⌘7
    }

    /// ⌘ keys that belong to the search field or to macOS: Select All, Paste, Cut, Undo, Hide, Minimize, Quit.
    /// (⌘C is taken on purpose: the panel gives it back to the field when the field has selected text.)
    public static let reservedCommandCharacters: Set<Character> = ["a", "v", "x", "z", "h", "m", "q"]

    /// An unmodified key (↑/↓/Return/Esc/Space). Any of ⌘⌥⌃⇧ held: nil (⇧↑ extends the text selection, ⇧Space types).
    public static func plain(keyCode: Int, modifiers: HotKeyShortcut.Modifiers) -> SearchKey? {
        guard modifiers.isEmpty else { return nil }
        return plainKeys[keyCode]
    }

    /// A ⌘ or ⇧⌘ shortcut. The key is the typed character, lowercased, when it is an ASCII letter or digit (QWERTY,
    /// Dvorak, …; with Shift held AppKit reports "C"), else the physical key (Cyrillic or Greek layouts type other
    /// letters; AZERTY types "&" for 1).
    public static func command(keyCode: Int, modifiers: HotKeyShortcut.Modifiers, characters: String?) -> SearchKey? {
        let table: [Character: SearchKey]
        switch modifiers {
        case [.command]: table = commandKeys
        case [.command, .shift]: table = shiftCommandKeys
        default: return nil
        }
        let typed = characters?.lowercased()
        let ascii = typed.flatMap { $0.count == 1 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } ? $0 : nil }
        guard let character = ascii?.first ?? physicalCharacter(keyCode) else { return nil }
        return table[character]
    }

    /// "⌘C" for `.copyImage`, "⇧⌘C" for `.copyText`; nil for a key without a ⌘ shortcut.
    public static func commandShortcutText(for key: SearchKey) -> String? {
        for binding in bindings where binding.key == key {
            switch binding.trigger {
            case .command(let character): return "⌘" + String(character).uppercased()
            case .shiftCommand(let character): return "⇧⌘" + String(character).uppercased()
            case .plain: continue
            }
        }
        return nil
    }

    /// The character the ANSI (US) layout prints on the physical key `keyCode`, lower-cased: "c" for `KeyCode.c`.
    public static func physicalCharacter(_ keyCode: Int) -> Character? {
        guard KeyCode.isCharacterKey(keyCode) else { return nil }
        let symbol = KeyCode.symbol(keyCode).lowercased()
        return symbol.count == 1 ? symbol.first : nil
    }

    private static let plainKeys: [Int: SearchKey] = {
        var table: [Int: SearchKey] = [:]
        for binding in bindings {
            if case .plain(let keyCode) = binding.trigger, table[keyCode] == nil { table[keyCode] = binding.key }
        }
        return table
    }()

    private static let commandKeys: [Character: SearchKey] = {
        var table: [Character: SearchKey] = [:]
        for binding in bindings {
            if case .command(let character) = binding.trigger, table[character] == nil { table[character] = binding.key }
        }
        return table
    }()

    private static let shiftCommandKeys: [Character: SearchKey] = {
        var table: [Character: SearchKey] = [:]
        for binding in bindings {
            if case .shiftCommand(let character) = binding.trigger, table[character] == nil { table[character] = binding.key }
        }
        return table
    }()
}
