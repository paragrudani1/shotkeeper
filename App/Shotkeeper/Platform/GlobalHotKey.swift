import AppKit
import Carbon.HIToolbox
import Foundation
import ShotkeeperCore

enum GlobalHotKeyError: Error, Equatable {
    case installHandlerFailed(OSStatus)
    /// `eventHotKeyExistsErr` (-9878): the shortcut is already registered and cannot be shared; other codes: the
    /// system refused it.
    case registerFailed(OSStatus)
}

/// A system-wide shortcut via Carbon `RegisterEventHotKey` (still the supported way without Accessibility
/// permission). The action runs on the main actor. Unregisters on `unregister()` or deinit.
@MainActor
final class GlobalHotKey {
    /// "SHKP"
    private static let signature: OSType = 0x5348_4B50
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?
    /// While true and Shotkeeper is the active app, hotkey presses are ignored (the shortcut recorder is listening).
    /// Checked together with `NSApp.isActive`, so a recorder that never got the keyboard cannot disable the shortcut
    /// in other apps.
    static var isSuspended = false

    let shortcut: HotKeyShortcut
    private let id: UInt32
    // nonisolated(unsafe): read in the nonisolated deinit; otherwise only touched on the main actor.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?

    /// Registers with `kEventHotKeyExclusive` (Carbon `CarbonEvents.h`: no other registration may share it). If the
    /// shortcut is already registered so that it cannot be shared, this fails with `eventHotKeyExistsErr`. A shortcut
    /// another app registered without that option, or one an app handles itself (a menu key equivalent), may still
    /// register here and then reach only one of the two: `RegisterEventHotKey` cannot detect every conflict, which is
    /// why the recorder also checks the known macOS shortcuts and says "Shortcuts another app uses may not register."
    init(shortcut: HotKeyShortcut, action: @escaping @MainActor () -> Void) throws {
        try Self.installHandlerIfNeeded()
        self.shortcut = shortcut
        self.id = Self.nextID
        Self.nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers), hotKeyID,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        guard status == OSStatus(noErr), let ref else { throw GlobalHotKeyError.registerFailed(status) }
        hotKeyRef = ref
        Self.actions[id] = action
    }

    deinit {
        // Owners release hotkeys on the main actor (AppDelegate), where Carbon expects it.
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        Self.actions[id] = nil
    }

    /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey` in `HIToolbox/Events.h`).
    static func carbonModifiers(_ modifiers: HotKeyShortcut.Modifiers) -> UInt32 {
        var mask = 0
        if modifiers.contains(.command) { mask |= cmdKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        return UInt32(mask)
    }

    /// The shortcut's modifiers from an AppKit event (the recorder).
    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKeyShortcut.Modifiers {
        var modifiers: HotKeyShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    fileprivate static func fire(id: UInt32) {
        guard !(isSuspended && NSApp.isActive) else { return }
        actions[id]?()
    }

    private static func installHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handler: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &handler)
        guard status == OSStatus(noErr) else { throw GlobalHotKeyError.installHandlerFailed(status) }
        eventHandler = handler
    }
}

/// The search shortcut as registered with the system. A new shortcut replaces the old one only once it registered,
/// so a refused shortcut leaves the old one working.
@MainActor
final class SearchHotKey {
    private var hotKey: GlobalHotKey?
    private let action: @MainActor () -> Void
    /// Test seam: registers a shortcut or throws `GlobalHotKeyError`.
    private let register: @MainActor (HotKeyShortcut, @escaping @MainActor () -> Void) throws -> GlobalHotKey?

    /// The shortcut that works now (nil when none registered).
    private(set) var active: HotKeyShortcut?

    init(action: @escaping @MainActor () -> Void,
         register: @escaping @MainActor (HotKeyShortcut, @escaping @MainActor () -> Void) throws -> GlobalHotKey? = {
             try GlobalHotKey(shortcut: $0, action: $1)
         }) {
        self.action = action
        self.register = register
    }

    /// Registers `shortcut` and then releases the old one. Returns the problem when it cannot be used; the old
    /// shortcut then stays registered.
    func use(_ shortcut: HotKeyShortcut) -> HotKeyProblem? {
        if let problem = HotKeyRules.problem(with: shortcut) { return problem }
        if shortcut == active { return nil }
        do {
            let new = try register(shortcut, action)
            hotKey?.unregister()
            hotKey = new
            active = shortcut
            return nil
        } catch GlobalHotKeyError.registerFailed(let status) {
            return HotKeyRules.registrationProblem(status: status)
        } catch {
            return .registrationFailed(inUseByAnotherApp: false)
        }
    }
}

/// Nonisolated C callback. Carbon delivers application-target events on the main thread.
private func hotKeyEventHandler(_ call: EventHandlerCallRef?, _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == OSStatus(noErr), hotKeyID.signature == 0x5348_4B50 else { return OSStatus(eventNotHandledErr) }
    let id = hotKeyID.id
    Task { @MainActor in GlobalHotKey.fire(id: id) }
    return OSStatus(noErr)
}

/// Key names from the current keyboard layout ("Y" for the Z key on a German layout), so shortcuts show the
/// letters printed on the user's keyboard. Falls back to the US names (`KeyCode.symbol`).
@MainActor
enum KeyboardLayout {
    static func name(for keyCode: Int) -> String? {
        guard KeyCode.isCharacterKey(keyCode) else { return nil }
        for source in [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()] {
            guard let source = source?.takeRetainedValue(),
                  let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            if let name = translate(keyCode, layout: data) { return name }
        }
        return nil
    }

    private static func translate(_ keyCode: Int, layout: Data) -> String? {
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { buffer -> OSStatus in
            guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(pointer, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count,
                                  &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length).uppercased()
        let printable = text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespaces.contains($0) }
        return printable && !text.isEmpty ? text : nil
    }
}

extension HotKeyShortcut {
    /// "⌥⌘S" with the current keyboard layout's key name.
    @MainActor var display: String { displayString(keyName: KeyboardLayout.name(for: keyCode)) }

    /// "Option Command S" with the current layout's key name.
    @MainActor var spokenDisplay: String {
        guard let name = KeyboardLayout.name(for: keyCode) else { return spokenName }
        return modifiers.symbols.isEmpty ? name : spokenName.split(separator: " ").dropLast().joined(separator: " ") + " " + name
    }
}

extension HotKeyProblem {
    @MainActor func displayMessage(for shortcut: HotKeyShortcut) -> String {
        message(for: shortcut, display: shortcut.display)
    }
}
