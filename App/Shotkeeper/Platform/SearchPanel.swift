import AppKit
import Quartz
import ShotkeeperCore
import SwiftUI

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

/// AppKit → core key translation. The table and its rules are core's `SearchKeyMap` (tested on Linux); this only reads
/// the event's key code, modifiers and characters.
extension SearchKeyMap {
    /// Unmodified keys, seen in `sendEvent` (↑/↓/Return/Esc/Space). `.function`/`.numericPad` (arrow keys carry them)
    /// do not count as modifiers.
    static func plain(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> SearchKey? {
        plain(keyCode: Int(keyCode), modifiers: GlobalHotKey.modifiers(from: flags))
    }

    /// ⌘ shortcuts, seen in `performKeyEquivalent`.
    static func command(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> SearchKey? {
        command(keyCode: Int(keyCode), modifiers: GlobalHotKey.modifiers(from: flags), characters: characters)
    }

    static func plain(_ event: NSEvent) -> SearchKey? {
        plain(keyCode: event.keyCode, flags: event.modifierFlags)
    }

    static func command(_ event: NSEvent) -> SearchKey? {
        command(keyCode: event.keyCode, flags: event.modifierFlags, characters: event.charactersIgnoringModifiers)
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
    /// ⌘S while the Source pill is disabled (design §6). Replaced in tests.
    var beep: () -> Void = { NSSound.beep() }
    private(set) lazy var panel: SearchPanel = makePanel()
    /// The app that was in front when the panel opened. A click into Quick Look activates Shotkeeper (Quick Look's
    /// panel is a normal panel); hiding the search window gives the focus back to this app.
    private var previousApp: NSRunningApplication?
    private lazy var quickLook = SearchQuickLook(
        selectedURL: { [weak self] in self?.model.selectedURL },
        keyHandler: { [weak self] event in self?.handleQuickLookKey(event) ?? false })

    /// Open / copy / reveal on the selected result (the search-panel action set; features add theirs there).
    let resultActions: SearchResultActions
    /// The index's change feed (`ScreenshotIndex.changes()`); nil when the index never opened. While the panel is
    /// shown, an `.updated` change of a listed row refreshes the search, so the Copy Text badge follows the row's
    /// text status and a waiting Copy Text resolves.
    var indexChanges: (() -> AsyncStream<IndexChange>)?
    private var changesTask: Task<Void, Never>?

    init(model: SearchViewModel = SearchViewModel(search: { _, _, _, _ in ScreenshotSearchResult(rows: [], matchCount: 0, totalCount: 0) })) {
        self.model = model
        self.resultActions = SearchResultActions(model: model)
        resultActions.hidePanel = { [weak self] in self?.hide() }
        resultActions.announce = { [weak self] text in self?.announce(text) }
        model.announce = { [weak self] text in self?.announce(text) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        rememberFrontApp()
        positionOnActiveScreen()
        model.refresh()
        model.reloadSources()  // the source list is loaded each time the panel opens (wave 1 spec)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.requestFocus()
        watchIndexChanges()
    }

    /// The batch toast's "View in Search": that batch's files, newest first.
    func showBatch(_ paths: [String]) {
        rememberFrontApp()
        model.showBatch(paths)
        if !panel.isVisible {
            positionOnActiveScreen()
            model.reloadSources()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.requestFocus()
        watchIndexChanges()
    }

    /// Subscribes while the panel is shown (cancelled on dismiss, which ends the subscription).
    private func watchIndexChanges() {
        guard changesTask == nil, let changes = indexChanges?() else { return }
        changesTask = Task { [weak self] in
            for await change in changes {
                guard let self else { return }
                if change.kind == .updated, self.model.state.items.contains(where: { $0.id == change.id }) {
                    self.model.refresh()
                }
            }
        }
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
        if let picker = model.state.datePicker { return handleInDatePicker(key, picker) }
        if let picker = model.state.sourcePicker { return handleInSourcePicker(key, picker) }
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
            resultActions.open(url)
        case .copyImage:
            // Selected text in the field: let ⌘C copy the text.
            guard !panel.fieldHasSelectedText, let url = model.selectedURL else { return false }
            resultActions.copy(url)
        case .reveal:
            guard let url = model.selectedURL else { return false }
            resultActions.reveal(url)
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
        case .dateFilter:
            model.toggleDatePicker()
        case .sourceFilter:
            toggleSourcePicker()
        case .deleteBackward:
            return false  // deletes in the field
        case .copyText:
            return resultActions.copyText()
        }
        return true
    }

    /// ⌘S: opens or closes the source picker (closing the date picker), or beeps when the pill is disabled.
    private func toggleSourcePicker() {
        if !model.toggleSourcePicker() { beep() }
    }

    /// Keys while the date picker is open (design §6). The list takes ↑/↓/↩/⌫; while the custom range is shown, ↑/↓,
    /// ⌫ and Space belong to the focused date field and ↩ is Apply. Esc closes the picker (core's Esc order).
    private func handleInDatePicker(_ key: SearchKey, _ picker: DatePickerState) -> Bool {
        switch key {
        case .up, .down:
            guard picker.takesArrowKeys else { return false }
            model.moveDateHighlight(by: key == .up ? -1 : 1)
        case .open:
            model.chooseHighlightedDate()
        case .close:
            _ = model.escape()
        case .deleteBackward:
            guard picker.takesArrowKeys else { return false }
            model.clearDateFromPicker()
        case .dateFilter:
            model.toggleDatePicker()
        case .sourceFilter:
            toggleSourcePicker()  // switches to the source picker
        case .space:
            return picker.takesArrowKeys  // nothing to type into in the list
        case .copyImage:
            return false  // ⌘C copies a date field's selected text, never the image behind the picker
        case .reveal, .quickLook, .chip, .copyText:
            break  // ignored while a picker is open
        }
        return true
    }

    /// Keys while the source picker is open (design §6). Its narrow field has the focus: letters, Space and ⌫ with
    /// text edit it; ↑/↓ move the highlight, ↩ chooses, ⌫ in an empty field clears the source, Esc closes. While an
    /// input method is composing in the narrow field, the panel doesn't call this at all (`SearchPanel.isComposingText`),
    /// so ↩ in the candidate list commits the text and never chooses a source.
    private func handleInSourcePicker(_ key: SearchKey, _ picker: SourcePickerState) -> Bool {
        switch key {
        case .up, .down:
            model.moveSourceHighlight(by: key == .up ? -1 : 1)
        case .open:
            model.chooseHighlightedSource()
        case .close:
            _ = model.escape()
        case .deleteBackward:
            guard picker.deleteClearsSource else { return false }  // deletes in the narrow field
            model.clearSourceFromPicker()
        case .sourceFilter:
            toggleSourcePicker()  // closes it
        case .dateFilter:
            model.toggleDatePicker()  // switches to the date picker
        case .space, .copyImage:
            return false  // a typed space; ⌘C copies the narrow field's selected text, never the image
        case .reveal, .quickLook, .chip, .copyText:
            break  // ignored while a picker is open
        }
        return true
    }

    // MARK: Actions

    var actions: SearchViewActions {
        SearchViewActions(open: { [weak self] in self?.resultActions.open($0) },
                          copy: { [weak self] in self?.resultActions.copy($0) },
                          copyText: { [weak self] in self?.resultActions.copyText() },
                          reveal: { [weak self] in self?.resultActions.reveal($0) },
                          quickLook: { [weak self] in self?.toggleQuickLook() },
                          processExisting: { [weak self] in
                              self?.hide()
                              self?.onProcessExisting()
                          })
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
        guard let key = SearchKeyMap.plain(event) ?? SearchKeyMap.command(event) else { return false }
        switch key {
        case .up, .down:
            return handle(key)
        case .open:
            guard let url = model.selectedURL else { return false }
            resultActions.open(url)
            return true
        case .close, .space, .quickLook:
            closeQuickLook()
            return true
        case .copyImage:
            guard let url = model.selectedURL else { return false }
            resultActions.copy(url)
            return true
        case .reveal, .chip, .copyText:
            return handle(key)
        case .dateFilter, .sourceFilter, .deleteBackward:
            return false
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
            self.changesTask?.cancel()
            self.changesTask = nil
            self.model.windowHidden()
            // Only when Shotkeeper became active (a click into Quick Look); otherwise the front app still has focus.
            if NSApp.isActive, let previous = self.previousApp, !previous.isTerminated {
                previous.activate(options: [])
            }
            self.previousApp = nil
        }
        panel.keyHandler = { [weak self] event in
            guard let self, let key = SearchKeyMap.plain(event) else { return false }
            return MainActor.assumeIsolated { self.handle(key) }
        }
        panel.commandKeyHandler = { [weak self] event in
            guard let self, let key = SearchKeyMap.command(event) else { return false }
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
