import AppKit
import SwiftUI

/// Plain NSWindows hosting SwiftUI, one per id. A menu-bar (LSUIElement) app has no main menu or Dock icon, so the
/// windows are shown explicitly and the app is activated to bring them in front of the current app.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Closes and forgets the window, so the next `show` builds fresh content.
    func close(id: String) {
        windows[id]?.close()
        windows[id] = nil
    }
}
