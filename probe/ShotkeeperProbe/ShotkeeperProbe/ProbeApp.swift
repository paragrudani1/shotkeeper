// THROWAWAY probe (2026-11-28). Never merge to main. See probe/ShotkeeperProbe/project.yml.
import AppKit

@main
@MainActor
enum ProbeMain {
    // NSApplication.delegate is weak; keep the delegate alive for the whole run.
    private static let delegate = ProbeAppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("ShotkeeperProbe launched")
    }
}

/// A small non-activating floating panel, like Shotkeeper's search panel, that says "ShotkeeperProbe".
@MainActor
final class ProbePanel {
    static let shared = ProbePanel()

    private var panel: NSPanel?

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "ShotkeeperProbe"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let label = NSTextField(labelWithString: "ShotkeeperProbe")
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        panel.contentView = content
        return panel
    }
}
