import AppKit
import ShotkeeperCore
import SwiftUI

/// Floating Spotlight-style panel. `.nonactivatingPanel` keeps the frontmost app active (the menu-bar app never
/// steals activation), while `canBecomeKey` lets the search field take keyboard focus anyway.
final class SearchPanel: NSPanel {
    /// Called when the panel hides itself (Esc, or it lost key status).
    var onDismiss: (() -> Void)?
    /// Sees every key-down first (except while an input method is composing). Return true to consume it
    /// (↑/↓/Return/⌘C/⌘R never reach the text field then).
    var keyHandler: ((NSEvent) -> Bool)?

    static let defaultContentSize = NSSize(width: 680, height: 460)

    /// Convenience (not designated) so NSWindow's designated/coder initializers stay inherited.
    /// The label has no default on purpose: `SearchPanel()` would silently pick NSWindow's inherited `init()`
    /// and skip all of this configuration (that bug shipped in phase 1 and was caught by the tests in CI).
    convenience init(contentSize: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: contentSize),
                  styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                  backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isComposingText, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    /// True while an input method (Japanese, Chinese, Korean…) holds uncommitted marked text in the focused field.
    /// ↑/↓/Return/Esc then belong to the input method (pick a candidate, commit, cancel), not to the result list.
    var isComposingText: Bool {
        (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }

    /// Esc (when the field editor does not consume it).
    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    /// Clicking elsewhere hides it, like Spotlight.
    override func resignKey() {
        super.resignKey()
        if isVisible { dismiss() }
    }

    func dismiss() {
        orderOut(nil)
        onDismiss?()
    }
}

/// Keys the panel handles itself. Pure mapping, unit-tested.
enum SearchKey: Equatable {
    case up, down, open, close, copyImage, reveal

    static func from(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> SearchKey? {
        let mods = modifiers.intersection([.command, .option, .control, .shift])
        switch (keyCode, mods) {
        case (126, []): return .up            // ↑
        case (125, []): return .down          // ↓
        case (36, []), (76, []): return .open // Return, keypad Enter
        case (53, []): return .close          // Esc
        default: break
        }
        guard mods == [.command] else { return nil }
        switch characters?.lowercased() {
        case "c": return .copyImage
        case "r": return .reveal
        default: return nil
        }
    }
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

    /// The image itself plus its file URL, so both image editors and Finder/Mail accept the paste.
    @discardableResult
    static func copyImage(_ url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        pasteboard.clearContents()
        let items: [any NSPasteboardWriting] = [image, url as NSURL]
        return pasteboard.writeObjects(items)
    }
}

struct SearchView: View {
    let model: SearchViewModel
    var onClose: () -> Void
    var onOpen: (URL) -> Void
    var onReveal: (URL) -> Void
    var onCopy: (URL) -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search screenshots", text: Binding(get: { model.query }, set: { model.setQuery($0) }))
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($fieldFocused)
                    .onExitCommand(perform: onClose)
            }
            .padding(14)
            Divider()
            if let error = model.errorMessage {
                ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.results.isEmpty {
                ContentUnavailableView(model.query.isEmpty ? "No screenshots indexed yet" : "No results",
                                       systemImage: "photo.on.rectangle.angled",
                                       description: Text(model.query.isEmpty
                                                         ? "New screenshots appear here once they are processed."
                                                         : "Try other words from the title, text or tags."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(model.results.enumerated()), id: \.element.path) { offset, row in
                            SearchResultRowView(row: row, isSelected: offset == model.selectedIndex)
                                .id(row.path)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { onOpen(URL(fileURLWithPath: row.path)) }
                                .onTapGesture { model.select(offset) }
                                .listRowBackground(offset == model.selectedIndex
                                                   ? Color.accentColor.opacity(0.25) : Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: model.selectedIndex) { _, index in
                        guard let index, model.results.indices.contains(index) else { return }
                        proxy.scrollTo(model.results[index].path)
                    }
                }
            }
            Divider()
            HStack(spacing: 14) {
                Text("↑↓ select   ↩ open   ⌘C copy image   ⌘R reveal   esc close")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reveal in Finder") { if let url = model.selectedURL { onReveal(url) } }
                    .disabled(model.selectedURL == nil)
                Button("Copy Image") { if let url = model.selectedURL { onCopy(url) } }
                    .disabled(model.selectedURL == nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 520, minHeight: 320)
        .background(.regularMaterial)
        .onAppear { fieldFocused = true }
    }
}

struct SearchResultRowView: View {
    let row: IndexedScreenshot
    let isSelected: Bool
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var displayScale

    private static let side: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .frame(width: Self.side, height: Self.side)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(row.title ?? URL(fileURLWithPath: row.path).deletingPathExtension().lastPathComponent)
                        .font(.headline).lineLimit(1)
                    Spacer()
                    if let date = row.capturedAt ?? row.processedAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let description = row.description, !description.isEmpty {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if !row.tags.isEmpty {
                    Text(row.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.tint).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .task(id: row.path) {
            thumbnail = ThumbnailCache.shared.cached(path: row.path, side: Self.side)
            if thumbnail == nil {
                thumbnail = await ThumbnailCache.shared.thumbnail(path: row.path, side: Self.side, scale: displayScale)
            }
        }
    }
}

/// Owns the panel; the hotkey and the menu call `toggle()` / `show()`.
@MainActor
final class SearchPanelController {
    let model: SearchViewModel
    private(set) lazy var panel: SearchPanel = makePanel()

    init(model: SearchViewModel = SearchViewModel(search: { _ in [] })) {
        self.model = model
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        positionOnActiveScreen()
        model.refresh()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.dismiss()
    }

    /// Returns true when the key was handled.
    func handle(_ key: SearchKey) -> Bool {
        switch key {
        case .up: model.moveSelection(by: -1)
        case .down: model.moveSelection(by: 1)
        case .close: hide()
        case .open:
            guard let url = model.selectedURL else { return false }
            SearchActions.open(url)
            hide()
        case .copyImage:
            guard let url = model.selectedURL else { return false }
            SearchActions.copyImage(url)
        case .reveal:
            guard let url = model.selectedURL else { return false }
            SearchActions.reveal(url)
            hide()
        }
        return true
    }

    private func makePanel() -> SearchPanel {
        let panel = SearchPanel(contentSize: SearchPanel.defaultContentSize)
        panel.contentView = NSHostingView(rootView: SearchView(
            model: model,
            onClose: { [weak panel] in panel?.dismiss() },
            onOpen: { [weak self] url in SearchActions.open(url); self?.hide() },
            onReveal: { [weak self] url in SearchActions.reveal(url); self?.hide() },
            onCopy: { url in SearchActions.copyImage(url) }))
        panel.keyHandler = { [weak self] event in
            guard let self,
                  let key = SearchKey.from(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                           characters: event.charactersIgnoringModifiers) else { return false }
            return MainActor.assumeIsolated { self.handle(key) }
        }
        return panel
    }

    /// Upper third of the screen that has the mouse pointer.
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.66 - size.height / 2)
        panel.setFrameOrigin(origin)
    }
}
