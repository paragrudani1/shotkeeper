import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: Error, Equatable {
    case installHandlerFailed(OSStatus)
    /// Usually `eventHotKeyExistsErr`: another app already owns this shortcut.
    case registerFailed(OSStatus)
}

/// A system-wide shortcut via Carbon `RegisterEventHotKey` (still the supported way without Accessibility
/// permission). The action runs on the main actor. Unregisters on `unregister()` or deinit.
@MainActor
final class GlobalHotKey {
    struct Shortcut: Equatable, Sendable {
        /// Virtual key code (`kVK_*`).
        var keyCode: UInt32
        /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
        var modifiers: UInt32

        /// ⌥⌘S
        static let defaultSearch = Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | cmdKey))

        var displayString: String {
            var result = ""
            if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
            return result + (Self.keyNames[keyCode] ?? "key \(keyCode)")
        }

        private static let keyNames: [UInt32: String] = [
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_F): "F", UInt32(kVK_ANSI_K): "K", UInt32(kVK_Space): "Space",
        ]
    }

    /// "SHKP"
    private static let signature: OSType = 0x5348_4B50
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    let shortcut: Shortcut
    private let id: UInt32
    // nonisolated(unsafe): read in the nonisolated deinit; otherwise only touched on the main actor.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?

    init(shortcut: Shortcut, action: @escaping @MainActor () -> Void) throws {
        try Self.installHandlerIfNeeded()
        self.shortcut = shortcut
        self.id = Self.nextID
        Self.nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
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

    fileprivate static func fire(id: UInt32) {
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
