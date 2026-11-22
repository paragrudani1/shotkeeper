import AppKit
import SwiftUI

/// Plain NSWindows hosting SwiftUI, one per id. A menu-bar (LSUIElement) app has no main menu or Dock icon, so the
/// windows are shown explicitly and the app is activated to bring them in front of the current app.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: NSSize, resizable: Bool = true,
                             @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = title
        window.styleMask = resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func isShown(id: String) -> Bool { windows[id]?.isVisible == true }

    /// Closes and forgets the window, so the next `show` builds fresh content.
    func close(id: String) {
        windows[id]?.close()
        windows[id] = nil
    }
}

/// Opens the SwiftUI `Settings` scene from AppKit code (the status item menu, the toast's "Fix Settings…", setup's
/// "Change Shortcut…" and "Run setup again…"'s way back).
///
/// Since macOS 14 the `showSettingsWindow:` action no longer opens a SwiftUI Settings scene (it logs "Please use
/// SettingsLink for opening the Settings scene."); only `SettingsLink` and the `openSettings` environment action do,
/// and both need a SwiftUI view. So `prepare()` hosts a 1×1 transparent view in an off-screen helper window once,
/// captures `openSettings`, and orders the helper out. CI probe runs 44981832999 and 44982578002 (macOS 26.7) showed
/// that the captured action opens the scene's window ("General", toolbar tabs) from AppKit code, also after the helper
/// was ordered out and after the Settings window was closed and opened again (docs/wiki/ui-polish.md, PR 4).
@MainActor
final class SettingsOpener {
    /// The identifier SwiftUI gives the Settings scene's window (seen in the CI probe).
    static let windowIdentifier = "com_apple_SwiftUI_Settings_window"

    private var action: OpenSettingsAction?
    private var helper: NSWindow?
    private var openWhenReady = false

    /// Captures the `openSettings` action (once, at launch).
    func prepare() {
        guard action == nil, helper == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        window.contentView = NSHostingView(rootView: OpenSettingsCapture { [weak self] action in self?.captured(action) })
        helper = window
        window.orderFrontRegardless()
    }

    /// Activates the app (an LSUIElement app's windows otherwise open behind the front app) and opens Settings.
    func open() {
        NSApp.activate()
        guard let action else {
            openWhenReady = true
            prepare()
            return
        }
        action()
        DispatchQueue.main.async {
            NSApp.activate()
            Self.window?.makeKeyAndOrderFront(nil)
        }
    }

    static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == windowIdentifier }
    }

    private func captured(_ action: OpenSettingsAction) {
        guard self.action == nil else { return }
        self.action = action
        helper?.orderOut(nil)  // kept (not closed): the probe used the action with its view still alive
        if openWhenReady {
            openWhenReady = false
            open()
        }
    }
}

private struct OpenSettingsCapture: View {
    @Environment(\.openSettings) private var openSettings
    let capture: (OpenSettingsAction) -> Void

    var body: some View {
        Color.clear.frame(width: 1, height: 1).onAppear { capture(openSettings) }
    }
}
