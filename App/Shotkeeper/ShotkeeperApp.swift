import AppKit
import ShotkeeperCore
import SwiftUI

@main
struct ShotkeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(coordinator: appDelegate.coordinator,
                           showSearch: { appDelegate.showSearch() },
                           showSettings: { appDelegate.showSettings() },
                           showSetup: { appDelegate.showSetup() })
        } label: {
            Image(systemName: StatusText.symbol(for: appDelegate.coordinator.queueStatus))
        }
    }
}

struct MenuBarContent: View {
    let coordinator: AppCoordinator
    let showSearch: () -> Void
    let showSettings: () -> Void
    let showSetup: () -> Void

    var body: some View {
        Text(coordinator.statusLine)
        if let watched = coordinator.watchedFolder {
            Text("Watching \(watched.lastPathComponent)")
        }
        if let message = coordinator.lastMessage {
            Text(message)
        }
        if case .error = coordinator.queueStatus {
            Button("Fix Settings…", action: showSettings)
        }
        if !coordinator.settings.hasSeenPrivacyNotice {
            Button("Finish Setup…", action: showSetup)
        }
        Divider()
        Button("Pause for 10 Minutes") { coordinator.pause(minutes: 10) }
        if coordinator.isPaused {
            Button("Resume") { coordinator.resume() }
        } else {
            Button("Pause") { coordinator.pauseIndefinitely() }
        }
        Button("Undo Last Rename") { coordinator.undoLastRename() }
        Button("Process Existing Screenshots") {
            Task { _ = await coordinator.processExistingScreenshots() }
        }
        Divider()
        Button("Search…", action: showSearch)
            .keyboardShortcut("s", modifiers: [.option, .command])
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Divider()
        Button("Quit Shotkeeper") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Builds the coordinator, the search panel and the windows; starts services at launch, stops them at quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator
    private var hotKey: GlobalHotKey?
    private let windows = WindowPresenter()
    private lazy var searchPanel = SearchPanelController(model: makeSearchModel())

    override init() {
        if RuntimeEnvironment.isRunningUnitTests {
            // Tests run hosted in this app: never touch the user's settings, index or Keychain.
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("ShotkeeperTestHost-\(UUID().uuidString)", isDirectory: true)
            coordinator = AppCoordinator(supportDirectory: scratch, credentials: InMemoryCredentialStore(),
                                         applicationSupport: scratch, logDirectory: scratch)
        } else {
            coordinator = AppCoordinator(credentials: KeychainCredentialStore())
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app (TEST_HOST); do not grab the hotkey or watch folders then.
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        coordinator.startServices()
        do {
            hotKey = try GlobalHotKey(shortcut: .defaultSearch) { [weak self] in self?.searchPanel.toggle() }
        } catch {
            coordinator.lastMessage = "Hotkey \(GlobalHotKey.Shortcut.defaultSearch.displayString) unavailable"
        }
        if !coordinator.settings.hasSeenPrivacyNotice { showSetup() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stopServices()
        ManagedProcess.terminateAllRunning()
    }

    func showSearch() {
        searchPanel.show()
    }

    func showSettings() {
        windows.show(id: "settings", title: "Shotkeeper Settings", size: NSSize(width: 640, height: 560)) {
            SettingsView(coordinator: coordinator, showSetup: { [weak self] in self?.showSetup() })
        }
    }

    func showSetup() {
        windows.close(id: "setup")
        windows.show(id: "setup", title: "Set up Shotkeeper", size: NSSize(width: 600, height: 680)) {
            SetupView(coordinator: coordinator, onDone: { [weak self] in self?.windows.close(id: "setup") })
        }
    }

    private func makeSearchModel() -> SearchViewModel {
        let index = coordinator.index
        return SearchViewModel { query in
            guard let index else { return [] }
            return try index.search(query, limit: 50)
        }
    }
}

enum RuntimeEnvironment {
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
