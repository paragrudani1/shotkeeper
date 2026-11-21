import AppKit
import ShotkeeperCore
import SwiftUI

@main
struct ShotkeeperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item is an AppKit NSStatusItem (`StatusItemController`): its menu needs a status dot,
        // thumbnails and a progress bar, which a MenuBarExtra menu cannot show. Windows are opened by the delegate.
        Settings { EmptyView() }
    }
}

/// Builds the coordinator, the search panel and the windows; starts services at launch, stops them at quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator
    private var hotKey: GlobalHotKey?
    private var statusItem: StatusItemController?
    private var toast: ToastController?
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
        let toast = ToastController(handlers: .init(
            undo: { [weak self] ids in self?.coordinator.undoFromToast(ids: ids) ?? .restored(RestoredToast(restoredPaths: [])) },
            rename: { [weak self] toast, name in
                self?.coordinator.renameFromToast(toast, to: name) ?? .failure(UserFacingProblem(message: "Shotkeeper is quitting"))
            },
            viewInSearch: { [weak self] _ in self?.showSearch() },  // PR 2 filters search to the batch
            fixSettings: { [weak self] in self?.showSettings() }))
        self.toast = toast
        coordinator.onToast = { content in toast.show(content, on: ToastPlacement.screenForNewScreenshot()) }
        coordinator.onRenameSound = { NSSound(named: "Pop")?.play() }
        statusItem = StatusItemController(coordinator: coordinator,
                                          searchShortcut: GlobalHotKey.Shortcut.defaultSearch.displayString) { [weak self] row, reveal in
            self?.perform(row, reveal: reveal)
        }
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

    private func perform(_ row: MenuRowID, reveal: Bool) {
        switch row {
        case .fixSettings, .settings: showSettings()
        case .finishSetup: showSetup()
        case .recent(let id):
            guard let item = coordinator.recentItems.first(where: { $0.id == id }) else { return }
            let url = URL(fileURLWithPath: item.path)
            if reveal { SearchActions.reveal(url) } else { SearchActions.open(url) }
        case .undo: coordinator.undoLastRename()
        case .pause: coordinator.pause(minutes: 10)
        case .resume: coordinator.resume()
        case .processExisting: Task { _ = await coordinator.processExistingScreenshots() }
        case .search: showSearch()
        case .about:
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        case .quit: NSApplication.shared.terminate(nil)
        }
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
