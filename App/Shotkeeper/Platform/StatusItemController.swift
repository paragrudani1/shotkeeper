import AppKit
import Observation
import ShotkeeperCore
import SwiftUI

/// Borderless, non-activating panel for the menu bar menu. It takes key (for ↑/↓/Return/Esc and ⌘ shortcuts)
/// without activating Shotkeeper, and closes when it loses key, like a menu.
final class MenuPanel: NSPanel {
    var onDismiss: (() -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?

    convenience init(contentSize: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: contentSize), styleMask: [.nonactivatingPanel, .borderless],
                  backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    override func resignKey() {
        super.resignKey()
        if isVisible { dismiss() }
    }

    func dismiss() {
        orderOut(nil)
        onDismiss?()
    }
}

/// Keys the menu handles. Pure mapping (unit-tested).
enum MenuKey: Equatable {
    case up, down, activate(reveal: Bool), close, shortcut(MenuRowID)

    static func from(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> MenuKey? {
        let mods = modifiers.intersection([.command, .option, .control, .shift])
        switch (keyCode, mods) {
        case (126, []): return .up
        case (125, []): return .down
        case (36, []), (76, []), (49, []): return .activate(reveal: false)  // Return, keypad Enter, Space
        case (36, [.option]), (76, [.option]): return .activate(reveal: true)
        case (53, []): return .close
        default: break
        }
        guard mods == [.command] else { return nil }
        switch characters?.lowercased() {
        case "z": return .shortcut(.undo)
        case ",": return .shortcut(.settings)
        case "q": return .shortcut(.quit)
        default: return nil
        }
    }
}

/// Pure placement for the menu panel (unit-tested): right below the status item, kept on screen.
enum MenuPlacement {
    static func frame(size: NSSize, below button: NSRect, visibleFrame: NSRect) -> NSRect {
        let x = min(max(button.minX, visibleFrame.minX + 4), visibleFrame.maxX - 4 - size.width)
        return NSRect(x: x, y: button.minY - 2 - size.height, width: size.width, height: size.height)
    }
}

/// The status item: the template glyph (idle) or today's state symbols, a short pulse after a rename, and the
/// menu panel on click.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: AppCoordinator
    private let perform: (MenuRowID, Bool) -> Void
    private let highlight = MenuHighlight()
    private var panel: MenuPanel?
    private var hosting: NSHostingView<MenuRootView>?
    private var lastPulse = 0
    private var pulseTask: Task<Void, Never>?

    /// - Parameter perform: runs a row's action (after the menu closed). `reveal` = ⌥ for recent rows.
    init(coordinator: AppCoordinator, perform: @escaping (MenuRowID, Bool) -> Void) {
        self.coordinator = coordinator
        self.perform = perform
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleMenu(_:))
            _ = button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityLabel("Shotkeeper")
        }
        lastPulse = coordinator.renamePulse
        updateIcon()
        observe()
    }

    // MARK: Icon

    private func observe() {
        withObservationTracking {
            _ = coordinator.queueStatus
            _ = coordinator.renamePulse
            _ = coordinator.startupError
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.observe()
            }
        }
    }

    private func updateIcon() {
        if coordinator.renamePulse != lastPulse {
            lastPulse = coordinator.renamePulse
            pulse()
        }
        guard pulseTask == nil, let button = statusItem.button else { return }
        button.image = Self.icon(for: coordinator.queueStatus)
        let summary = MenuText.status(queue: coordinator.queueStatus, watchedFolderName: coordinator.capture.watchedFolder?.lastPathComponent,
                                      indexedCount: coordinator.indexedCount, failure: coordinator.failureText, now: Date())
        button.toolTip = "Shotkeeper: \(summary.detail)"
    }

    /// Idle shows the brand glyph; other states keep the symbols they had before PR 1 (processing, paused,
    /// offline, needs attention).
    static func icon(for status: QueueStatus) -> NSImage {
        if case .idle = status { return MenuBarGlyph.image() }
        let image = NSImage(systemSymbolName: StatusText.symbol(for: status), accessibilityDescription: "Shotkeeper")
            ?? MenuBarGlyph.image()
        image.isTemplate = true
        return image
    }

    /// Four frames (big, normal, big, normal sparkle) over about half a second.
    private func pulse() {
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            for frame in [MenuBarGlyph.Variant.pulse, .normal, .pulse, .normal] {
                guard let self, !Task.isCancelled else { return }
                self.statusItem.button?.image = MenuBarGlyph.image(frame)
                try? await Task.sleep(nanoseconds: 130_000_000)
            }
            self?.pulseTask = nil
            self?.updateIcon()
        }
    }

    // MARK: Menu

    @objc private func toggleMenu(_ sender: Any?) {
        if let panel, panel.isVisible { panel.dismiss() } else { showMenu() }
    }

    func showMenu() {
        let panel = self.panel ?? makePanel()
        highlight.row = nil
        coordinator.refreshHistory()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        DispatchQueue.main.async { [weak self] in if let self, let panel = self.panel { self.position(panel) } }
    }

    private func makePanel() -> MenuPanel {
        let actions = MenuActions { [weak self] row, reveal in self?.run(row, reveal: reveal) }
        let root = MenuRootView(coordinator: coordinator, actions: actions, highlight: highlight)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = MaterialContainerView.roundedMask(radius: 10)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        let panel = MenuPanel(contentSize: NSSize(width: MenuContentView.width, height: 300))
        panel.contentView = effect
        panel.onDismiss = { [weak self] in self?.statusItem.button?.highlight(false) }
        panel.keyHandler = { [weak self] event in
            guard let self, let key = MenuKey.from(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                                   characters: event.charactersIgnoringModifiers) else { return false }
            return self.handle(key)
        }
        self.hosting = hosting
        self.panel = panel
        return panel
    }

    private func handle(_ key: MenuKey) -> Bool {
        let rows = MenuViewState.make(from: coordinator).rows
        switch key {
        case .up: highlight.move(-1, in: rows)
        case .down: highlight.move(1, in: rows)
        case .activate(let reveal):
            guard let row = highlight.row, rows.contains(row) else { return true }
            run(row, reveal: reveal)
        case .close: panel?.dismiss()
        case .shortcut(let row):
            guard rows.contains(row) else { return true }
            run(row, reveal: false)
        }
        return true
    }

    private func run(_ row: MenuRowID, reveal: Bool) {
        panel?.dismiss()
        perform(row, reveal)
    }

    private func position(_ panel: MenuPanel) {
        guard let hosting, let button = statusItem.button, let buttonWindow = button.window else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = NSSize(width: MenuContentView.width, height: hosting.fittingSize.height)
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? buttonFrame
        panel.setFrame(MenuPlacement.frame(size: size, below: buttonFrame, visibleFrame: visible), display: true)
        panel.invalidateShadow()
    }
}
