import AppKit
import Observation
import ShotkeeperCore
import SwiftUI

/// The search shortcut recorder (Settings → General). "Change Shortcut…" starts recording; the next key with
/// modifiers is checked (core `HotKeyRules`), registered with the system, and saved only once it registered
/// (`AppCoordinator.changeSearchShortcut`). On a problem it keeps recording and shows why; the old shortcut keeps
/// working. Esc or "Cancel" stops.
@MainActor
@Observable
final class ShortcutRecorderModel {
    enum Phase: Equatable {
        case idle
        case recording
    }

    /// Internal setters: snapshots show each state without a key event.
    var phase: Phase = .idle
    /// Modifiers held while recording ("⌃⌥…").
    var heldModifiers: HotKeyShortcut.Modifiers = []
    /// Why the last recorded shortcut was refused (readable sentence).
    var problem: String?

    @ObservationIgnored private let commit: (HotKeyShortcut) -> HotKeyProblem?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    init(commit: @escaping (HotKeyShortcut) -> HotKeyProblem?) {
        self.commit = commit
    }

    func start() {
        problem = nil
        heldModifiers = []
        phase = .recording
        // The current shortcut must not open Search while the user records a new one.
        GlobalHotKey.isSuspended = true
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                // Local monitors run on the main thread.
                let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return swallow ? nil : event
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
        Self.announce("Recording. Press the new shortcut, or Escape to cancel.")
    }

    private static func announce(_ text: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        GlobalHotKey.isSuspended = false
        heldModifiers = []
        phase = .idle
    }

    /// A key while recording. Returns true to swallow the event (no menu shortcut, no typing).
    func handle(_ event: NSEvent) -> Bool {
        guard phase == .recording else { return false }
        let modifiers = GlobalHotKey.modifiers(from: event.modifierFlags)
        if event.type == .flagsChanged {
            heldModifiers = modifiers
            return false
        }
        if Int(event.keyCode) == KeyCode.escape, modifiers.isEmpty {
            stop()
            return true
        }
        receive(HotKeyShortcut(keyCode: Int(event.keyCode), modifiers: modifiers))
        return true
    }

    /// Tries `shortcut`; on success recording ends, else the problem shows and recording goes on.
    func receive(_ shortcut: HotKeyShortcut) {
        if let refused = commit(shortcut) {
            problem = refused.message(for: shortcut)
            heldModifiers = []
            Self.announce(problem ?? "")
        } else {
            problem = nil
            stop()
        }
    }
}

/// The recorder row: a keycap with the current shortcut (or "Type shortcut" while recording), the buttons that
/// apply, and the error or the hint under it.
struct ShortcutRecorderView: View {
    @Bindable var model: ShortcutRecorderModel
    let current: HotKeyShortcut
    /// Why the saved shortcut could not be registered at launch (shown until a new one registers).
    var launchProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                HStack(spacing: 8) {
                    keycap
                    if model.phase == .recording {
                        Button("Cancel") { model.stop() }
                    } else {
                        Button("Change Shortcut…") { model.start() }
                            .help("Record a new shortcut for Search")
                        if current != .defaultSearch {
                            Button("Use \(HotKeyShortcut.defaultSearch.displayString)") { model.receive(.defaultSearch) }
                                .help("Go back to the default shortcut")
                        }
                    }
                }
            } label: {
                Text("Open Search")
            }
            if let problem = model.problem ?? launchProblem {
                Label {
                    Text(problem).foregroundStyle(Brand.errorText).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.errorText)
                }
                .font(.callout)
            } else if model.phase == .recording {
                Text("Press the new shortcut with ⌘ or ⌃. Esc cancels.")
                    .font(.callout).foregroundStyle(Brand.secondaryText)
            }
        }
    }

    private var keycap: some View {
        let recording = model.phase == .recording
        let text: String = {
            guard recording else { return current.displayString }
            let held = model.heldModifiers.symbols
            return held.isEmpty ? "Type shortcut" : held + "…"
        }()
        return Text(text)
            .font(.system(size: 13, weight: recording ? .regular : .semibold))
            .foregroundStyle(recording && model.heldModifiers.isEmpty ? Brand.secondaryText : Color.primary)
            .padding(.horizontal, 8)
            .frame(minWidth: 92, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: recording ? 2 : 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recording ? "Recording a new shortcut" : "Search shortcut, \(current.spokenName)")
    }
}
