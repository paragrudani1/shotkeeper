import AppKit
import Quartz
import ShotkeeperCore
import SwiftUI
import UniformTypeIdentifiers

/// Floating Raycast-style panel: borderless (no traffic lights), `.nonactivatingPanel` so the frontmost app stays
/// active (the menu-bar app never steals activation), while `canBecomeKey` lets the search field take the keyboard.
final class SearchPanel: NSPanel {
    /// Called when the panel hides itself (Esc, or focus loss).
    var onDismiss: (() -> Void)?
    /// Sees every key-down first (except while an input method is composing). Return true to consume it
    /// (↑/↓/Return/Esc/Space never reach the text field then).
    var keyHandler: ((NSEvent) -> Bool)?
    /// Sees ⌘ shortcuts (⌘C, ⌘R, ⌘Y, ⌘1…⌘7) in `performKeyEquivalent`, before the main menu's Edit > Copy can take
    /// them (except while an input method is composing). Return true to consume.
    var commandKeyHandler: ((NSEvent) -> Bool)?
    /// Quick Look asks the responder chain who controls it; the key panel answers with this.
    var quickLook: SearchQuickLook?

    static let defaultContentSize = NSSize(width: SearchView.size.width, height: SearchView.size.height)

    /// Convenience (not designated) so NSWindow's designated/coder initializers stay inherited.
    /// The label has no default on purpose: `SearchPanel()` would silently pick NSWindow's inherited `init()`
    /// and skip all of this configuration (that bug shipped in phase 1 and was caught by the tests in CI).
    convenience init(contentSize: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: contentSize),
                  styleMask: [.nonactivatingPanel, .borderless],
                  backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false  // a drag on a result drags the file, not the window
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isComposingText, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    /// AppKit routes ⌘ keys through key equivalents (and the main menu), not through `sendEvent`'s key-down path.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, !isComposingText, commandKeyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// True while an input method (Japanese, Chinese, Korean…) holds uncommitted marked text in the focused field.
    /// ↑/↓/Return/Esc/Space then belong to the input method (pick a candidate, commit, cancel), not to the list.
    var isComposingText: Bool {
        (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }

    /// The search field (its field editor) has the keyboard. When a button has it instead (Full Keyboard Access),
    /// Space and Return press that button.
    var fieldHasFocus: Bool { firstResponder is NSTextView }

    /// The search field has selected text: ⌘C then copies that text instead of the image.
    var fieldHasSelectedText: Bool {
        guard let editor = firstResponder as? NSTextView else { return false }
        return editor.selectedRange().length > 0
    }

    /// Esc when the key handler did not take it.
    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    /// Focus loss hides it, like Spotlight. Checked on the next turn of the run loop, when the new key window is
    /// known: Quick Look's panel taking the keyboard (a click in it) is not a focus loss.
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in self?.dismissUnlessFocusStayed() }
    }

    func dismissUnlessFocusStayed() {
        guard isVisible, !isKeyWindow else { return }
        if let key = NSApp.keyWindow, key is QLPreviewPanel { return }
        dismiss()
    }

    func dismiss() {
        orderOut(nil)
        onDismiss?()
    }

    // MARK: Quick Look (informal QLPreviewPanelController protocol, a category on NSObject)
    // The category is not main-actor annotated; Quick Look calls these on the main thread.

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { quickLook != nil }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            let preview = QLPreviewPanel.shared()
            preview?.dataSource = quickLook
            preview?.delegate = quickLook
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            let preview = QLPreviewPanel.shared()
            preview?.dataSource = nil
            preview?.delegate = nil
        }
    }
}

/// Keys the panel handles itself. Pure mapping, unit-tested.
enum SearchKey: Equatable {
    case up, down, open, close, space, copyImage, reveal, quickLook, chip(SearchChip)

    /// Unmodified keys, seen in `sendEvent` (↑/↓/Return/Esc/Space).
    static func plain(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> SearchKey? {
        guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
        switch keyCode {
        case 126: return .up            // ↑
        case 125: return .down          // ↓
        case 36, 76: return .open       // Return, keypad Enter
        case 53: return .close          // Esc
        case 49: return .space          // Space (Quick Look or a typed space, see SearchWindowState)
        default: return nil
        }
    }

    /// ⌘ shortcuts, seen in `performKeyEquivalent`. The key is the typed character when it is an ASCII letter or
    /// digit (QWERTY, Dvorak, …), else the physical key (Cyrillic or Greek layouts type other letters; AZERTY types
    /// "&" for 1).
    static func command(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> SearchKey? {
        guard modifiers.intersection([.command, .option, .control, .shift]) == [.command] else { return nil }
        let typed = characters?.lowercased()
        let key = typed.flatMap { $0.count == 1 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } ? $0 : nil }
            ?? physicalKeys[keyCode]
        switch key ?? "" {
        case "c": return .copyImage
        case "r": return .reveal
        case "y": return .quickLook           // ⌘Y, the Finder shortcut
        case let digit:
            return Int(digit).flatMap(SearchChip.forShortcut).map { .chip($0) }
        }
    }

    /// ANSI virtual key codes (Carbon `kVK_ANSI_*`) for the shortcut keys.
    private static let physicalKeys: [UInt16: String] = [
        8: "c", 15: "r", 16: "y", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
    ]
}

/// Open / copy / reveal for a result.
@MainActor
enum SearchActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// One pasteboard item with the image as PNG (the file's own bytes when it is a PNG) and its file URL, so image
    /// editors and chat apps paste the picture and Finder/Mail paste the file. False when the file cannot be read.
    @discardableResult
    static func copyImage(_ url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let png: Data
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .png) == true {
            png = data
        } else if let rep = NSBitmapImageRep(data: data), let converted = rep.representation(using: .png, properties: [:]) {
            png = converted  // JPEG/HEIC/TIFF screenshots (a `defaults write com.apple.screencapture type` choice)
        } else {
            return false
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString(url.absoluteString, forType: .fileURL)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

/// Quick Look data source for the selected result. `@preconcurrency`: Quick Look calls these on the main thread.
@MainActor
final class SearchQuickLook: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    var selectedURL: () -> URL?
    /// Keys pressed while Quick Look's panel is key (↑/↓ move the selection, Esc/Space close it).
    var keyHandler: (NSEvent) -> Bool
    /// Quick Look's panel lost the keyboard (the search panel then checks for focus loss).
    var onResignKey: () -> Void = {}

    init(selectedURL: @escaping () -> URL?, keyHandler: @escaping (NSEvent) -> Bool) {
        self.selectedURL = selectedURL
        self.keyHandler = keyHandler
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        selectedURL() == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let url = selectedURL() else { return nil }
        return url as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return keyHandler(event)
    }

    func windowDidResignKey(_ notification: Notification) {
        onResignKey()
    }
}

/// Where the panel goes: horizontally centered on the screen, its center on the line one third down from the top
/// of the visible frame (the upper third), moved down or up only as far as needed to stay on screen.
enum SearchPlacement {
    static func origin(size: NSSize, visibleFrame: NSRect) -> NSPoint {
        let x = visibleFrame.midX - size.width / 2
        let centerY = visibleFrame.maxY - visibleFrame.height / 3
        let y = min(max(centerY - size.height / 2, visibleFrame.minY), visibleFrame.maxY - size.height)
        return NSPoint(x: x.rounded(), y: y.rounded())
    }
}

/// Owns the panel; the hotkey, the menu and the batch toast call `toggle()` / `show()` / `showBatch(_:)`.
@MainActor
final class SearchPanelController {
    let model: SearchViewModel
    /// "Process Existing Screenshots…" in the empty state (the app delegate starts the scan).
    var onProcessExisting: () -> Void = {}
    private(set) lazy var panel: SearchPanel = makePanel()
    /// The app that was in front when the panel opened. A click into Quick Look activates Shotkeeper (Quick Look's
    /// panel is a normal panel); hiding the search window gives the focus back to this app.
    private var previousApp: NSRunningApplication?
    private lazy var quickLook = SearchQuickLook(
        selectedURL: { [weak self] in self?.model.selectedURL },
        keyHandler: { [weak self] event in self?.handleQuickLookKey(event) ?? false })

    init(model: SearchViewModel = SearchViewModel(search: { _, _ in ScreenshotSearchResult(rows: [], matchCount: 0, totalCount: 0) })) {
        self.model = model
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        rememberFrontApp()
        positionOnActiveScreen()
        model.refresh()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.requestFocus()
    }

    /// The batch toast's "View in Search": that batch's files, newest first.
    func showBatch(_ paths: [String]) {
        rememberFrontApp()
        model.showBatch(paths)
        if !panel.isVisible { positionOnActiveScreen() }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.requestFocus()
    }

    func hide() {
        panel.dismiss()
    }

    private func rememberFrontApp() {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
    }

    /// Returns true when the key was handled.
    func handle(_ key: SearchKey) -> Bool {
        switch key {
        case .up, .down:
            model.moveSelection(by: key == .up ? -1 : 1)
            reloadQuickLook()
        case .close:
            if isQuickLookVisible {
                closeQuickLook()
            } else if model.escape() {
                hide()
            }
        case .open:
            guard panel.fieldHasFocus, let url = model.selectedURL else { return false }
            open(url)
        case .copyImage:
            // Selected text in the field: let ⌘C copy the text.
            guard !panel.fieldHasSelectedText, let url = model.selectedURL else { return false }
            copy(url)
        case .reveal:
            guard let url = model.selectedURL else { return false }
            reveal(url)
        case .space:
            guard panel.fieldHasFocus else { return false }
            if isQuickLookVisible {
                closeQuickLook()
            } else if model.state.spaceOpensQuickLook {
                openQuickLook()
            } else {
                return false  // a typed space
            }
        case .quickLook:
            guard model.selectedURL != nil else { return false }
            toggleQuickLook()
        case .chip(let chip):
            model.selectChip(chip)
        }
        return true
    }

    // MARK: Actions

    var actions: SearchViewActions {
        SearchViewActions(open: { [weak self] in self?.open($0) },
                          copy: { [weak self] in self?.copy($0) },
                          reveal: { [weak self] in self?.reveal($0) },
                          quickLook: { [weak self] in self?.toggleQuickLook() },
                          processExisting: { [weak self] in
                              self?.hide()
                              self?.onProcessExisting()
                          })
    }

    private func open(_ url: URL) {
        guard fileStillExists(url) else { return }
        SearchActions.open(url)
        hide()
    }

    private func reveal(_ url: URL) {
        guard fileStillExists(url) else { return }
        SearchActions.reveal(url)
        hide()
    }

    private func copy(_ url: URL) {
        guard fileStillExists(url) else { return }
        guard SearchActions.copyImage(url) else {
            report(SearchWindowState.copyFailedMessage)
            return
        }
        model.showCopied()
        announce("Copied")
    }

    /// A file moved or deleted after it was indexed: say so instead of failing silently; the panel stays open.
    private func fileStillExists(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            report(SearchWindowState.missingFileMessage)
            return false
        }
        return true
    }

    private func report(_ message: String) {
        model.showProblem(message)
        announce(message)
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: Quick Look

    private var isQuickLookVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func toggleQuickLook() {
        if isQuickLookVisible { closeQuickLook() } else { openQuickLook() }
    }

    private func openQuickLook() {
        guard model.selectedURL != nil, let preview = QLPreviewPanel.shared() else { return }
        // Above our floating panel; ordered front without taking the keyboard, so ↑/↓/Space/Esc keep coming here.
        preview.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        preview.updateController()
        preview.reloadData()
        preview.orderFrontRegardless()  // Shotkeeper is not the active app
    }

    /// Quick Look asks the responder chain for a controller. While its own panel is key (the user clicked into it),
    /// the search panel is not in that chain, so the app delegate answers through these.
    var acceptsQuickLookControl: Bool { panel.isVisible }

    func beginQuickLookControl() {
        let preview = QLPreviewPanel.shared()
        preview?.dataSource = quickLook
        preview?.delegate = quickLook
    }

    func endQuickLookControl() {
        let preview = QLPreviewPanel.shared()
        preview?.dataSource = nil
        preview?.delegate = nil
    }

    private func closeQuickLook() {
        guard isQuickLookVisible else { return }
        QLPreviewPanel.shared().orderOut(nil)
        if panel.isVisible { panel.makeKey() }
    }

    private func reloadQuickLook() {
        if isQuickLookVisible { QLPreviewPanel.shared().reloadData() }
    }

    /// Keys while Quick Look's own panel is key (the user clicked into it).
    private func handleQuickLookKey(_ event: NSEvent) -> Bool {
        guard let key = SearchKey.plain(keyCode: event.keyCode, modifiers: event.modifierFlags)
                ?? SearchKey.command(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                     characters: event.charactersIgnoringModifiers) else { return false }
        switch key {
        case .up, .down:
            return handle(key)
        case .open:
            guard let url = model.selectedURL else { return false }
            open(url)
            return true
        case .close, .space, .quickLook:
            closeQuickLook()
            return true
        case .copyImage:
            guard let url = model.selectedURL else { return false }
            copy(url)
            return true
        case .reveal, .chip:
            return handle(key)
        }
    }

    // MARK: Panel

    private func makePanel() -> SearchPanel {
        let panel = SearchPanel(contentSize: SearchPanel.defaultContentSize)
        let hosting = NSHostingView(rootView: SearchView(model: model, actions: actions))
        panel.contentView = MaterialContainerView(hostingView: hosting, cornerRadius: SearchView.cornerRadius)
        panel.quickLook = quickLook
        quickLook.onResignKey = { [weak panel] in
            DispatchQueue.main.async { panel?.dismissUnlessFocusStayed() }
        }
        panel.onDismiss = { [weak self] in
            guard let self else { return }
            if self.isQuickLookVisible { QLPreviewPanel.shared().orderOut(nil) }
            self.model.windowHidden()
            // Only when Shotkeeper became active (a click into Quick Look); otherwise the front app still has focus.
            if NSApp.isActive, let previous = self.previousApp, !previous.isTerminated {
                previous.activate(options: [])
            }
            self.previousApp = nil
        }
        panel.keyHandler = { [weak self] event in
            guard let self, let key = SearchKey.plain(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
                return false
            }
            return MainActor.assumeIsolated { self.handle(key) }
        }
        panel.commandKeyHandler = { [weak self] event in
            guard let self, let key = SearchKey.command(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                                        characters: event.charactersIgnoringModifiers) else {
                return false
            }
            return MainActor.assumeIsolated { self.handle(key) }
        }
        return panel
    }

    /// The screen with the mouse pointer (where the user is working when they press the hotkey).
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(SearchPlacement.origin(size: panel.frame.size, visibleFrame: visible))
    }
}
