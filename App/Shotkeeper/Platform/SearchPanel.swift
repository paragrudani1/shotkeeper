import AppKit
import SwiftUI

/// Floating Spotlight-style panel. `.nonactivatingPanel` keeps the frontmost app active (the menu-bar app never
/// steals activation), while `canBecomeKey` lets the search field take keyboard focus anyway.
final class SearchPanel: NSPanel {
    /// Called when the panel hides itself (Esc, or it lost key status).
    var onDismiss: (() -> Void)?

    /// Convenience (not designated) so NSWindow's designated/coder initializers stay inherited.
    convenience init(size: NSSize = NSSize(width: 640, height: 420)) {
        self.init(contentRect: NSRect(origin: .zero, size: size),
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

/// Placeholder row; phase 2 fills it from the FTS index.
struct SearchResultRow: Identifiable, Equatable, Sendable {
    var id: String { path }
    var path: String
    var title: String
    var snippet: String
}

@MainActor
@Observable
final class SearchModel {
    var query: String = ""
    var results: [SearchResultRow] = []
}

struct SearchView: View {
    @Bindable var model: SearchModel
    var onClose: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search screenshots", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($fieldFocused)
                    .onExitCommand(perform: onClose)
            }
            .padding(14)
            Divider()
            if model.results.isEmpty {
                ContentUnavailableView(model.query.isEmpty ? "Type to search" : "No results yet",
                                       systemImage: "photo.on.rectangle.angled",
                                       description: Text("Indexed screenshots will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.results) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.headline)
                        Text(row.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 480, minHeight: 280)
        .background(.regularMaterial)
        .onAppear { fieldFocused = true }
    }
}

/// Owns the panel; the hotkey and the menu call `toggle()` / `show()`.
@MainActor
final class SearchPanelController {
    let model = SearchModel()
    private(set) lazy var panel: SearchPanel = makePanel()

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.dismiss()
    }

    private func makePanel() -> SearchPanel {
        let panel = SearchPanel()
        panel.contentView = NSHostingView(rootView: SearchView(model: model, onClose: { [weak panel] in
            panel?.dismiss()
        }))
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
