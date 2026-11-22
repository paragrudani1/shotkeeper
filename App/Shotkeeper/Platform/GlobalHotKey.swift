import AppKit
import Carbon.HIToolbox
import Foundation
import ShotkeeperCore

enum GlobalHotKeyError: Error, Equatable {
    case installHandlerFailed(OSStatus)
    /// `eventHotKeyExistsErr` (-9878): another app registered it exclusively first; other codes: the system refused.
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
    /// While true, hotkey presses are ignored (the shortcut recorder is listening).
    static var isSuspended = false

    let shortcut: HotKeyShortcut
    private let id: UInt32
    // nonisolated(unsafe): read in the nonisolated deinit; otherwise only touched on the main actor.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?

    /// Registers exclusively (`kEventHotKeyExclusive`), so a shortcut another app already holds fails with
    /// `eventHotKeyExistsErr` instead of being shared silently.
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
        guard !isSuspended else { return }
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
