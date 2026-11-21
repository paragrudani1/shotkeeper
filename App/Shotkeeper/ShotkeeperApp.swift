import AppKit
import SwiftUI

@main
struct ShotkeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Shotkeeper", systemImage: "camera.viewfinder") {
            MenuBarContent(status: appDelegate.status, showSearch: { appDelegate.showSearch() })
        }
    }
}

/// Text shown at the top of the menu. Phase 2 drives it from the processing queue.
@MainActor
@Observable
final class AppStatus {
    var line: String = "Starting…"
}

struct MenuBarContent: View {
    let status: AppStatus
    let showSearch: () -> Void

    var body: some View {
        Text(status.line)
        Divider()
        Button("Search Screenshots…", action: showSearch)
            .keyboardShortcut("s", modifiers: [.option, .command])
        Divider()
        Button("Quit Shotkeeper") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Kept minimal: wires platform services at launch, tears down child processes at quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let status = AppStatus()
    private var hotKey: GlobalHotKey?
    private lazy var searchPanel = SearchPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app (TEST_HOST); do not grab the hotkey or touch user state then.
        guard !RuntimeEnvironment.isRunningUnitTests else {
            status.line = "Running tests"
            return
        }
        let location = ScreenshotLocation.current()
        status.line = "Watching \(location.folder.path)"
        do {
            hotKey = try GlobalHotKey(shortcut: .defaultSearch) { [weak self] in self?.searchPanel.toggle() }
        } catch {
            status.line = "Hotkey \(GlobalHotKey.Shortcut.defaultSearch.displayString) unavailable"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ManagedProcess.terminateAllRunning()
    }

    func showSearch() {
        searchPanel.show()
    }
}

enum RuntimeEnvironment {
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
