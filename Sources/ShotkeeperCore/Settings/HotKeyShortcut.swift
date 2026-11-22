import Foundation

/// A global keyboard shortcut: a physical key + modifiers (Settings → General → "Search shortcut").
///
/// `keyCode` is a macOS virtual key code (`kVK_*` in Carbon `HIToolbox/Events.h`): a key position, the same on every
/// keyboard layout, which is what `RegisterEventHotKey` takes. Names are those of the US (ANSI) layout.
public struct HotKeyShortcut: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// "⌃⌥⇧⌘": the held modifiers in the macOS menu order.
        public var symbols: String {
            var text = ""
            if contains(.control) { text += "⌃" }
            if contains(.option) { text += "⌥" }
            if contains(.shift) { text += "⇧" }
            if contains(.command) { text += "⌘" }
            return text
        }
    }

    public var keyCode: Int
    public var modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌥⌘S (spec).
    public static let defaultSearch = HotKeyShortcut(keyCode: KeyCode.s, modifiers: [.option, .command])

    /// "⌥⌘S": modifiers in the macOS menu order ⌃⌥⇧⌘, then the key.
    public var displayString: String {
        modifiers.symbols + KeyCode.symbol(keyCode)
    }

    /// "Option Command S" for VoiceOver.
    public var spokenName: String {
        var words: [String] = []
        if modifiers.contains(.control) { words.append("Control") }
        if modifiers.contains(.option) { words.append("Option") }
        if modifiers.contains(.shift) { words.append("Shift") }
        if modifiers.contains(.command) { words.append("Command") }
        return (words + [KeyCode.spokenName(keyCode)]).joined(separator: " ")
    }
}

/// macOS virtual key codes (Carbon `HIToolbox/Events.h`, `kVK_ANSI_*` and the layout-independent `kVK_*`).
public enum KeyCode {
    public static let a = 0x00, s = 0x01, d = 0x02, f = 0x03, h = 0x04, g = 0x05, z = 0x06, x = 0x07, c = 0x08
    public static let v = 0x09, b = 0x0B, q = 0x0C, w = 0x0D, e = 0x0E, r = 0x0F, y = 0x10, t = 0x11
    public static let o = 0x1F, u = 0x20, i = 0x22, p = 0x23, l = 0x25, j = 0x26, k = 0x28, n = 0x2D, m = 0x2E
    public static let one = 0x12, two = 0x13, three = 0x14, four = 0x15, six = 0x16, five = 0x17, nine = 0x19
    public static let seven = 0x1A, eight = 0x1C, zero = 0x1D
    public static let returnKey = 0x24, tab = 0x30, space = 0x31, delete = 0x33, escape = 0x35, grave = 0x32
    public static let slash = 0x2C, forwardDelete = 0x75, home = 0x73, end = 0x77, pageUp = 0x74, pageDown = 0x79
    public static let leftArrow = 0x7B, rightArrow = 0x7C, downArrow = 0x7D, upArrow = 0x7E
    public static let f1 = 0x7A, f2 = 0x78, f3 = 0x63, f4 = 0x76, f5 = 0x60, f6 = 0x61, f7 = 0x62, f8 = 0x64
    public static let f9 = 0x65, f10 = 0x6D, f11 = 0x67, f12 = 0x6F, f13 = 0x69, f14 = 0x6B, f15 = 0x71
    public static let f16 = 0x6A, f17 = 0x40, f18 = 0x4F, f19 = 0x50, f20 = 0x5A

    private static let characters: [Int: String] = [
        a: "A", s: "S", d: "D", f: "F", h: "H", g: "G", z: "Z", x: "X", c: "C", v: "V", b: "B", q: "Q", w: "W",
        e: "E", r: "R", y: "Y", t: "T", o: "O", u: "U", i: "I", p: "P", l: "L", j: "J", k: "K", n: "N", m: "M",
        one: "1", two: "2", three: "3", four: "4", five: "5", six: "6", seven: "7", eight: "8", nine: "9", zero: "0",
        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",", slash: "/",
        0x2F: ".", grave: "`", 0x0A: "§",
    ]

    private static let functionKeys: [Int: Int] = [
        f1: 1, f2: 2, f3: 3, f4: 4, f5: 5, f6: 6, f7: 7, f8: 8, f9: 9, f10: 10, f11: 11, f12: 12, f13: 13, f14: 14,
        f15: 15, f16: 16, f17: 17, f18: 18, f19: 19, f20: 20,
    ]

    /// (symbol, spoken name) of keys that are not characters.
    private static let specialKeys: [Int: (String, String)] = [
        returnKey: ("↩", "Return"), tab: ("⇥", "Tab"), space: ("Space", "Space"), delete: ("⌫", "Delete"),
        escape: ("⎋", "Escape"), forwardDelete: ("⌦", "Forward Delete"), home: ("↖", "Home"), end: ("↘", "End"),
        pageUp: ("⇞", "Page Up"), pageDown: ("⇟", "Page Down"), leftArrow: ("←", "Left Arrow"),
        rightArrow: ("→", "Right Arrow"), downArrow: ("↓", "Down Arrow"), upArrow: ("↑", "Up Arrow"),
    ]

    public static func isFunctionKey(_ code: Int) -> Bool { functionKeys[code] != nil }

    /// Whether the shortcut recorder accepts this key at all (letters, digits, punctuation, F-keys, Space, arrows…).
    public static func isKnown(_ code: Int) -> Bool {
        characters[code] != nil || functionKeys[code] != nil || specialKeys[code] != nil
    }

    public static func symbol(_ code: Int) -> String {
        if let character = characters[code] { return character }
        if let number = functionKeys[code] { return "F\(number)" }
        if let special = specialKeys[code] { return special.0 }
        return "Key \(code)"
    }

    public static func spokenName(_ code: Int) -> String {
        if let special = specialKeys[code] { return special.1 }
        return symbol(code)
    }
}

/// Why a shortcut cannot be the search shortcut. `message` is a sentence for the recorder.
public enum HotKeyProblem: Equatable, Sendable {
    /// Without ⌘ or ⌃ the keys type text (⌥S is "ß", ⇧S is "S") or are plain keys.
    case needsCommandOrControl
    /// ⌘ (with or without ⇧) + a key: a menu shortcut in most apps (⌘C, ⇧⌘N), which a global hotkey would take away.
    case usedByApps
    /// A macOS shortcut (Spotlight, screenshots, Mission Control…). `name` says what it does.
    case system(name: String)
    /// A key the recorder does not handle (Esc cancels recording; unknown keys cannot be shown).
    case unsupportedKey
    /// `RegisterEventHotKey` failed: another app holds it (`eventHotKeyExistsErr`) or the system refused it.
    case registrationFailed(inUseByAnotherApp: Bool)

    public func message(for shortcut: HotKeyShortcut) -> String {
        let keys = shortcut.displayString
        switch self {
        case .needsCommandOrControl:
            return "Add ⌘ or ⌃ to the shortcut. Keys with only ⌥ or ⇧ type characters."
        case .usedByApps:
            return "\(keys) is a menu shortcut in many apps. Add ⌥ or ⌃."
        case .system(let name):
            return "\(keys) is the macOS shortcut for \(name). Choose another one."
        case .unsupportedKey:
            return "That key cannot be used in a shortcut. Choose a letter, a number or a function key."
        case .registrationFailed(let inUse):
            return inUse ? "Another app already uses \(keys). Choose another shortcut."
                         : "macOS did not accept \(keys). Choose another shortcut."
        }
    }
}

/// The rules for the search shortcut that need no system call. Registration conflicts (another app already holds
/// the shortcut) are found by `RegisterEventHotKey` in the app and reported as `.registrationFailed`.
public enum HotKeyRules {
    /// `eventHotKeyExistsErr` (Carbon `CarbonEvents.h`): the hotkey is registered by another process.
    public static let eventHotKeyExistsErr: Int32 = -9878

    public static func registrationProblem(status: Int32) -> HotKeyProblem {
        .registrationFailed(inUseByAnotherApp: status == eventHotKeyExistsErr)
    }

    /// Nil when `shortcut` may be registered.
    public static func problem(with shortcut: HotKeyShortcut) -> HotKeyProblem? {
        guard KeyCode.isKnown(shortcut.keyCode), shortcut.keyCode != KeyCode.escape else { return .unsupportedKey }
        if let name = systemShortcutName(shortcut) { return .system(name: name) }
        let mods = shortcut.modifiers
        guard mods.contains(.command) || mods.contains(.control) else { return .needsCommandOrControl }
        if mods.subtracting(.shift) == .command, !KeyCode.isFunctionKey(shortcut.keyCode) { return .usedByApps }
        return nil
    }

    /// The macOS default shortcuts a global hotkey must not take. Source: Apple, "Mac keyboard shortcuts"
    /// (support.apple.com/102650) and System Settings → Keyboard → Keyboard Shortcuts defaults (macOS 14/15).
    public static func systemShortcutName(_ shortcut: HotKeyShortcut) -> String? {
        systemShortcuts.first { $0.0 == shortcut }?.1
    }

    private static let systemShortcuts: [(HotKeyShortcut, String)] = {
        func key(_ code: Int, _ mods: HotKeyShortcut.Modifiers) -> HotKeyShortcut { HotKeyShortcut(keyCode: code, modifiers: mods) }
        return [
            (key(KeyCode.space, [.command]), "Spotlight"),
            (key(KeyCode.space, [.option, .command]), "a Finder search window"),
            (key(KeyCode.space, [.control]), "switching the input source"),
            (key(KeyCode.space, [.control, .option]), "switching the input source"),
            (key(KeyCode.space, [.control, .command]), "Emoji & Symbols"),
            (key(KeyCode.tab, [.command]), "switching apps"),
            (key(KeyCode.tab, [.shift, .command]), "switching apps"),
            (key(KeyCode.grave, [.command]), "switching windows"),
            (key(KeyCode.three, [.shift, .command]), "screenshots"),
            (key(KeyCode.four, [.shift, .command]), "screenshots"),
            (key(KeyCode.five, [.shift, .command]), "screenshots"),
            (key(KeyCode.six, [.shift, .command]), "screenshots"),
            (key(KeyCode.three, [.control, .shift, .command]), "screenshots"),
            (key(KeyCode.four, [.control, .shift, .command]), "screenshots"),
            (key(KeyCode.escape, [.option, .command]), "Force Quit"),
            (key(KeyCode.q, [.control, .command]), "Lock Screen"),
            (key(KeyCode.q, [.shift, .command]), "Log Out"),
            (key(KeyCode.q, [.option, .shift, .command]), "Log Out"),
            (key(KeyCode.d, [.option, .command]), "showing and hiding the Dock"),
            (key(KeyCode.d, [.control, .command]), "Look Up"),
            (key(KeyCode.f, [.control, .command]), "full screen"),
            (key(KeyCode.h, [.option, .command]), "Hide Others"),
            (key(KeyCode.m, [.option, .command]), "minimizing all windows"),
            (key(KeyCode.slash, [.shift, .command]), "the Help menu"),
            (key(KeyCode.upArrow, [.control]), "Mission Control"),
            (key(KeyCode.downArrow, [.control]), "App Exposé"),
            (key(KeyCode.leftArrow, [.control]), "moving between Spaces"),
            (key(KeyCode.rightArrow, [.control]), "moving between Spaces"),
            (key(KeyCode.f2, [.control]), "moving the focus to the menu bar"),
            (key(KeyCode.f3, [.control]), "moving the focus to the Dock"),
            (key(KeyCode.f4, [.control]), "moving the focus to the next window"),
            (key(KeyCode.f5, [.control]), "moving the focus to the toolbar"),
            (key(KeyCode.f6, [.control]), "moving the focus to a floating window"),
            (key(KeyCode.f7, [.control]), "keyboard navigation"),
            (key(KeyCode.f8, [.control]), "moving the focus to the status menus"),
            (key(KeyCode.f5, [.command]), "VoiceOver"),
            (key(KeyCode.f5, [.option, .command]), "Accessibility Shortcuts"),
        ]
    }()
}
