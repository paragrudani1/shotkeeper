import AppKit
import Quartz
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
    private let settingsNavigation = SettingsNavigation()
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
        let coordinator = self.coordinator
        let undo: ([UUID]) -> ToastContent = { ids in coordinator.undoFromToast(ids: ids) }
        let rename: (RenamedToast, String) -> Result<RenamedToast, UserFacingProblem> = { toast, name in
            coordinator.renameFromToast(toast, to: name)
        }
        let viewInSearch: ([String]) -> Void = { [weak self] paths in self?.searchPanel.showBatch(paths) }
        let fixSettings: () -> Void = { [weak self] in self?.showSettings() }
        let toast = ToastController(handlers: ToastController.Handlers(undo: undo, rename: rename,
                                                                       viewInSearch: viewInSearch, fixSettings: fixSettings))
        self.toast = toast
        coordinator.onToast = { content in toast.show(content, on: ToastPlacement.screenForNewScreenshot()) }
        coordinator.onRenameSound = { NSSound(named: "Pop")?.play() }
        statusItem = StatusItemController(coordinator: coordinator,
                                          searchShortcut: GlobalHotKey.Shortcut.defaultSearch.displayString) { [weak self] row, reveal in
            self?.perform(row, reveal: reveal)
        }
        searchPanel.onProcessExisting = { Task { _ = await coordinator.processExistingScreenshots() } }
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

    /// - Parameter tab: switch to this tab, also when the window is already open (setup's "Change Shortcut…").
    func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsNavigation.tab = tab }
        windows.show(id: "settings", title: "Shotkeeper Settings", size: NSSize(width: 640, height: 560)) {
            SettingsView(coordinator: coordinator, navigation: settingsNavigation,
                         showSetup: { [weak self] in self?.showSetup() })
        }
    }

    /// First launch, the menu's "Finish Setup…" and Settings' "Run setup again…": always a fresh flow at step 1.
    func showSetup() {
        windows.close(id: "setup")
        let services = SetupServices.live(
            coordinator: coordinator,
            // The shortcut recorder is PR 4; until then the shortcut is shown in General, where it will live.
            openShortcutSettings: { [weak self] in self?.showSettings(tab: .general) },
            close: { [weak self] in self?.windows.close(id: "setup") })
        let model = SetupModel(services: services)
        windows.show(id: "setup", title: "Set Up Shotkeeper",
                     size: NSSize(width: SetupView.size.width, height: SetupView.size.height), resizable: false) {
            SetupView(model: model)
        }
    }

    // MARK: Quick Look controller (informal QLPreviewPanelController protocol)
    // When the user clicks into Quick Look's panel it becomes key, and the search panel (never main) is no longer in
    // the responder chain Quick Look searches; the app delegate is, so it hands control to the search panel.
    // Not main-actor annotated in the SDK; Quick Look calls these on the main thread.

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { searchPanel.acceptsQuickLookControl }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { searchPanel.beginQuickLookControl() }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { searchPanel.endQuickLookControl() }
    }

    private func makeSearchModel() -> SearchViewModel {
        let index = coordinator.index
        // The index opens once at launch; when it failed, search shows the error state, never the empty state.
        let problem = coordinator.indexProblem ?? UserFacingProblem(message: "the index is not open")
        return SearchViewModel { query, limit in
            guard let index else { throw IndexUnavailableError(problem: problem) }
            return try index.search(query, limit: limit)
        }
    }
}

enum RuntimeEnvironment {
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
