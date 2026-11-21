import AppKit
import ShotkeeperCore
import SwiftUI

/// Borderless, non-activating floating panel for the rename toast. It never activates Shotkeeper, so the front
/// app keeps focus. It refuses key status except while the user edits the name (`allowsKey`); then it becomes
/// key without activating the app (that is what `.nonactivatingPanel` allows), so the text field gets the keys.
final class ToastPanel: NSPanel {
    /// True only while editing the name.
    var allowsKey = false
    /// Sees key-downs first (except during input-method composition). Return true to consume.
    var keyHandler: ((NSEvent) -> Bool)?

    /// Label without a default on purpose (see SearchPanel: `ToastPanel()` would pick NSWindow's `init()`).
    convenience init(contentSize: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: contentSize),
                  styleMask: [.nonactivatingPanel, .borderless],
                  backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        let composing = (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
        if event.type == .keyDown, !composing, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// A rounded behind-window material (`.active`, so it does not dim while the panel is not key) with a hosting
/// view on top. Shared by the toast and the search panel.
class MaterialContainerView: NSView {
    let hostingView: NSView

    init(hostingView: NSView, cornerRadius: CGFloat, material: NSVisualEffectView.Material = .popover) {
        self.hostingView = hostingView
        super.init(frame: .zero)
        let effect = NSVisualEffectView()
        effect.material = material
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: cornerRadius)
        for view in [effect, hostingView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The toast's material background plus a tracking area that reports hover even though the app is never active.
final class ToastContainerView: MaterialContainerView {
    var onHoverChange: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // `.activeAlways`: Shotkeeper is never the active app while a toast shows.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}

/// The toast is never key, so the first click must reach the SwiftUI buttons instead of being swallowed.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Pure placement math (unit-tested).
enum ToastPlacement {
    static let margin: CGFloat = 16

    /// Bottom-right of the screen's visible frame (above the Dock, below the menu bar), 16 pt from the edges.
    static func frame(size: NSSize, visibleFrame: NSRect) -> NSRect {
        NSRect(x: visibleFrame.maxX - margin - size.width, y: visibleFrame.minY + margin,
               width: size.width, height: size.height)
    }

    /// macOS does not record which display a screenshot was taken on (nothing in the file, no API), so the toast
    /// goes to the screen under the pointer: after ⌘⇧4 or ⌘⇧5 the pointer is on the screen just captured. Returns
    /// the index into `screenFrames`, nil if the point is on none (the caller then uses the main screen).
    static func screenIndex(containing point: NSPoint, screenFrames: [NSRect]) -> Int? {
        screenFrames.firstIndex { NSMouseInRect(point, $0, false) }
    }

    @MainActor
    static func screenForNewScreenshot() -> NSScreen? {
        let screens = NSScreen.screens
        let index = screenIndex(containing: NSEvent.mouseLocation, screenFrames: screens.map(\.frame))
        return index.map { screens[$0] } ?? NSScreen.main
    }
}

/// Shows one toast at a time; a new one replaces the old (except while the user is typing a name: the newest
/// waits until the edit ends). Runs the 4 s countdown, paused while hovered or editing.
@MainActor
final class ToastController {
    struct Handlers {
        var undo: (_ ids: [UUID]) -> ToastContent
        var rename: (_ toast: RenamedToast, _ name: String) -> Result<RenamedToast, UserFacingProblem>
        var viewInSearch: (_ paths: [String]) -> Void
        var fixSettings: () -> Void
    }

    let model = ToastModel()
    private let handlers: Handlers
    private var panel: ToastPanel?
    private var container: ToastContainerView?
    private var screen: NSScreen?
    private var tickTask: Task<Void, Never>?
    private var hovering = false
    private var waiting: (content: ToastContent, screen: NSScreen?)?

    init(handlers: Handlers) {
        self.handlers = handlers
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// - Parameter screen: the screen the screenshot was taken on; nil keeps the current one (or the main screen).
    func show(_ content: ToastContent, on screen: NSScreen?) {
        if model.isEditing {
            waiting = (content, screen)
            return
        }
        if let screen { self.screen = screen }
        model.content = content
        model.editProblem = nil
        var countdown = ToastCountdown(startingAt: Date())
        if hovering { countdown.pause(at: Date()) }
        model.countdown = countdown
        let panel = self.panel ?? makePanel()
        relayout()
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in self?.relayout() } // after SwiftUI applied the new content
        startTicking()
    }

    func dismiss() {
        tickTask?.cancel()
        tickTask = nil
        if model.isEditing { endEditing(keepWaiting: false) }
        panel?.orderOut(nil)
        model.content = nil
        model.countdown = nil
        hovering = false
        waiting = nil
    }

    // MARK: Actions

    var actions: ToastActions {
        ToastActions(close: { [weak self] in self?.dismiss() },
                     undo: { [weak self] in self?.undo() },
                     beginEdit: { [weak self] in self?.beginEdit() },
                     saveEdit: { [weak self] in self?.saveEdit() },
                     cancelEdit: { [weak self] in self?.cancelEdit() },
                     viewInSearch: { [weak self] in self?.viewInSearch() },
                     fixSettings: { [weak self] in
                         self?.dismiss()
                         self?.handlers.fixSettings()
                     })
    }

    func undo() {
        let ids: [UUID]
        switch model.content {
        case .renamed(let toast)?: ids = toast.undoRecordIDs
        case .batch(let toast)?: ids = toast.undoRecordIDs
        default: return
        }
        guard !ids.isEmpty else { return }
        show(handlers.undo(ids), on: nil)
    }

    func beginEdit() {
        guard case .renamed(let toast)? = model.content, let panel else { return }
        model.editText = toast.name
        model.editProblem = nil
        model.isEditing = true
        model.countdown?.pause(at: Date())
        panel.allowsKey = true
        panel.makeKey()  // key without activating Shotkeeper (non-activating panel)
        relayout()
        DispatchQueue.main.async { [weak self] in self?.relayout() }
    }

    func saveEdit() {
        guard model.isEditing, case .renamed(let toast)? = model.content else { return }
        switch handlers.rename(toast, model.editText) {
        case .success(let updated):
            model.content = .renamed(updated)
            endEditing(keepWaiting: true)
        case .failure(let problem):
            model.editProblem = problem.sentence
            relayout()
            DispatchQueue.main.async { [weak self] in self?.relayout() }
        }
    }

    func cancelEdit() {
        guard model.isEditing else { return }
        endEditing(keepWaiting: true)
    }

    func viewInSearch() {
        guard case .batch(let toast)? = model.content else { return }
        dismiss()
        handlers.viewInSearch(toast.renamedPaths)
    }

    // MARK: Private

    private func endEditing(keepWaiting: Bool) {
        model.isEditing = false
        model.editProblem = nil
        if let panel {
            panel.allowsKey = false
            if panel.isKeyWindow {
                // Hand the keyboard back to the front app: ordering the key panel out lets the window server
                // make that app's window key again; then show the toast again without taking key.
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
        if !hovering { model.countdown?.resume(at: Date()) }
        relayout()
        DispatchQueue.main.async { [weak self] in self?.relayout() }
        if keepWaiting, let next = waiting {
            waiting = nil
            show(next.content, on: next.screen)
        }
    }

    private func setHovering(_ value: Bool) {
        hovering = value
        guard !model.isEditing else { return }
        if value { model.countdown?.pause(at: Date()) } else { model.countdown?.resume(at: Date()) }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, !Task.isCancelled else { return }
                if let countdown = self.model.countdown, countdown.isExpired(at: Date()) {
                    self.dismiss()
                    return
                }
            }
        }
    }

    private func makePanel() -> ToastPanel {
        let hosting = FirstMouseHostingView(rootView: ToastView(model: model, actions: actions))
        hosting.sizingOptions = [.intrinsicContentSize]
        let container = ToastContainerView(hostingView: hosting, cornerRadius: ToastView.cornerRadius)
        container.onHoverChange = { [weak self] in self?.setHovering($0) }
        let panel = ToastPanel(contentSize: NSSize(width: ToastView.width, height: 120))
        panel.contentView = container
        panel.keyHandler = { [weak self] event in
            guard let self, self.model.isEditing, event.keyCode == 53 else { return false } // Esc
            self.cancelEdit()
            return true
        }
        self.container = container
        self.panel = panel
        return panel
    }

    private func relayout() {
        guard let panel, let container else { return }
        container.hostingView.layoutSubtreeIfNeeded()
        let fitting = container.hostingView.fittingSize
        let size = NSSize(width: ToastView.width, height: max(40, fitting.height))
        let visible = (screen ?? panel.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(ToastPlacement.frame(size: size, visibleFrame: visible), display: true)
        panel.invalidateShadow()
    }
}
