import AppKit
import Observation
import ShotkeeperCore

/// What the setup window needs from the app. `live` wires it to the coordinator; snapshot tests pass fixed values.
/// Every closure runs on the main actor.
struct SetupServices {
    var physicalMemoryBytes: UInt64
    var settings: @MainActor () -> AppSettings
    var hasSavedToken: @MainActor () -> Bool
    /// Changes whenever a secret changes; `hasSavedToken` (a Keychain read) is re-read only then.
    var credentialsRevision: @MainActor () -> Int
    /// The login item's real state for a re-run (nil when unknown).
    var loginItemEnabled: @MainActor () -> Bool?
    var runtimePhase: @MainActor () -> RuntimePhase
    var readiness: @MainActor () -> BackendReadiness
    var isPaused: @MainActor () -> Bool
    /// Step 2 "I Agree".
    var acceptConsent: @MainActor () -> Void
    /// Step 3 "Continue" with Clairic: the token goes to the Keychain here (empty = keep the saved one).
    var saveClairic: @MainActor (_ accountID: String, _ token: String) -> Void
    /// Step 3 "Continue" with the local model.
    var chooseLocal: @MainActor (ModelVariant) -> Void
    var refreshLocal: @MainActor (ModelVariant) async -> Void
    var installLocal: @MainActor (ModelVariant) async -> Void
    var cancelInstall: @MainActor () async -> Void
    /// Test Connection with the typed (unsaved) account ID and token; sends only the generated test image.
    var testClairic: @MainActor (_ accountID: String, _ token: String) async -> Result<String, AnalyzerFailure>
    var addEventObserver: @MainActor (@escaping @MainActor (ScreenshotEvent) -> Void) -> UUID?
    var removeEventObserver: @MainActor (UUID) -> Void
    var indexEntry: @MainActor (_ path: String) -> IndexedScreenshot?
    /// Step 5 "Change Shortcut…": Settings, where the shortcut lives (the recorder is PR 4).
    var openShortcutSettings: @MainActor () -> Void
    /// Step 5 "Finish": apply "Open Shotkeeper when I log in" (every time), then close the window.
    var finish: @MainActor (_ openAtLogin: Bool) -> Void
    /// The setup window, for VoiceOver announcements (nil in tests and snapshots).
    var window: @MainActor () -> NSWindow? = { nil }

    @MainActor
    static func live(coordinator: AppCoordinator, openShortcutSettings: @escaping @MainActor () -> Void,
                     close: @escaping @MainActor () -> Void) -> SetupServices {
        SetupServices(
            physicalMemoryBytes: coordinator.physicalMemoryBytes,
            settings: { coordinator.settings },
            hasSavedToken: { coordinator.hasSecret(.cloudflareAPIToken) },
            credentialsRevision: { coordinator.credentialsRevision },
            loginItemEnabled: { RuntimeEnvironment.isRunningUnitTests ? nil : LaunchAtLogin.status == .enabled },
            runtimePhase: { coordinator.runtimePhase },
            readiness: { coordinator.readiness },
            isPaused: { coordinator.isPaused },
            acceptConsent: { coordinator.acceptUploadConsent() },
            saveClairic: { account, token in coordinator.saveClairicSetup(accountID: account, token: token) },
            chooseLocal: { coordinator.chooseLocalBackend($0) },
            refreshLocal: { await coordinator.localRuntime.refresh(for: $0) },
            installLocal: { await coordinator.installLocalModel($0) },
            cancelInstall: { await coordinator.localRuntime.cancelInstall() },
            testClairic: { account, token in
                var candidate = coordinator.settings
                candidate.backend = .clairic
                candidate.clairicAccountID = account
                return await coordinator.testConnection(settings: candidate, secrets: [.cloudflareAPIToken: token])
            },
            addEventObserver: { coordinator.addEventObserver($0) },
            removeEventObserver: { coordinator.removeEventObserver($0) },
            indexEntry: { coordinator.indexEntry(atPath: $0) },
            openShortcutSettings: openShortcutSettings,
            finish: { openAtLogin in
                coordinator.setLaunchAtLogin(openAtLogin)
                close()
            },
            window: { NSApp.windows.first { $0.title == SetupView.windowTitle && $0.isVisible } })
    }
}

/// Step 3's Test Connection line.
enum ConnectionTestState: Equatable {
    case idle
    case running
    case succeeded
    case failed(String)
}

/// The setup window's state: core `SetupFlow` plus what only the app holds (the typed token, the test, tasks).
@MainActor
@Observable
final class SetupModel {
    var flow: SetupFlow
    /// The typed API token. Never logged, never saved before step 3's Continue.
    var tokenDraft = "" {
        didSet {
            flow.inputs.hasTokenDraft = !tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if tokenDraft != oldValue { resetTest() }
        }
    }
    var accountID: String {
        get { flow.inputs.accountID }
        set {
            guard newValue != flow.inputs.accountID else { return }
            flow.inputs.accountID = newValue
            resetTest()
        }
    }
    var test: ConnectionTestState = .idle
    @ObservationIgnored let services: SetupServices
    /// Identifies the running Test Connection; editing the inputs drops it, so a late "Connected" for old input
    /// never shows.
    @ObservationIgnored private var testRun: UUID?
    @ObservationIgnored private var savedTokenCache: (revision: Int, value: Bool)?
    @ObservationIgnored private var observerID: UUID?
    private var installTask: Task<Void, Never>?

    init(services: SetupServices, flow: SetupFlow? = nil) {
        self.services = services
        let settings = services.settings()
        let customHost = settings.backend == .customEndpoint ? AppSettings.normalizedHost(settings.customEndpointURL) : nil
        let cards = SetupCards.make(physicalMemoryBytes: services.physicalMemoryBytes,
                                    clairicLongSide: settings.maxImageLongSide, customEndpointHost: customHost)
        self.flow = flow ?? SetupFlow(settings: settings, cards: cards, loginItemEnabled: services.loginItemEnabled())
    }

    /// The Keychain is read once per credentials change, not on every render.
    private var hasSavedToken: Bool {
        let revision = services.credentialsRevision()
        if let cache = savedTokenCache, cache.revision == revision { return cache.value }
        let value = services.hasSavedToken()
        savedTokenCache = (revision, value)
        return value
    }

    var cards: SetupCards { flow.cards }

    /// The flow with live inputs (saved token, local runtime) and step 4's waiting line. Views render this.
    var current: SetupFlow {
        var current = flow
        current.inputs.hasSavedToken = hasSavedToken
        current.inputs.localModel = Self.localModelState(services.runtimePhase())
        if current.step == .tryIt { current.tryIt = TryIt.withNote(waitingNote, in: current.tryIt) }
        return current
    }

    static func localModelState(_ phase: RuntimePhase) -> SetupLocalModelState {
        switch phase {
        case .notInstalled: return .notInstalled
        case .installing, .downloading: return .installing
        case .ready, .starting, .running: return .installed
        case .failed: return .failed
        }
    }

    /// Download/install progress of the chosen local model, or the pause, while step 4 waits.
    private var waitingNote: String? {
        let phase = services.runtimePhase()
        let isLocal = services.settings().backend == .localInkling
        var download: (fraction: Double, totalGB: Double)?
        if isLocal, case .downloading(let fraction) = phase {
            download = (fraction, cards.local.model?.approxDownloadGB ?? 0)
        }
        let installing: Bool = { if case .installing = phase { return isLocal } else { return false } }()
        return TryIt.waitingNote(localDownload: download, isInstalling: installing, isPaused: services.isPaused())
    }

    // MARK: Lifecycle

    /// Starts listening to pipeline events (step 4 reacts to the next real screenshot).
    func start() {
        guard observerID == nil else { return }
        observerID = services.addEventObserver { [weak self] event in self?.receive(event) }
    }

    func stop() {
        if let observerID { services.removeEventObserver(observerID) }
        observerID = nil
    }

    // MARK: Buttons

    /// The primary button and Return.
    func pressPrimary() {
        guard let action = current.primaryAction() else { return }
        switch action {
        case .next, .skipConnection:
            break
        case .acceptConsent:
            services.acceptConsent()
        case .saveConnection(.clairic):
            services.saveClairic(flow.inputs.accountID, tokenDraft)
            tokenDraft = ""
        case .saveConnection(.localInkling):
            if let model = cards.local.model { services.chooseLocal(model) }
        case .saveConnection(.customEndpoint):
            break // keeps the endpoint configured in Settings
        case .finish:
            stop()
            services.finish(flow.openAtLogin)
            return
        }
        flow.advance(now: Date())
        if flow.step == .tryIt { flow.tryIt = TryIt.initialState(readiness: services.readiness()) }
    }

    /// Back and Esc.
    func goBack() {
        flow.back()
    }

    func choose(_ backend: AppSettings.Backend) {
        flow.choose(backend)
    }

    func chooseNext() {
        flow.chooseNext()
    }

    func runTest() {
        guard test != .running else { return }
        test = .running
        let run = UUID()
        testRun = run
        let account = flow.inputs.accountID
        let token = tokenDraft
        Task {
            let result = await services.testClairic(account, token)
            // Dropped when the inputs changed meanwhile (`resetTest`) or another run started.
            guard testRun == run, account == flow.inputs.accountID, token == tokenDraft else { return }
            testRun = nil
            switch result {
            case .success: test = .succeeded
            case .failure(let failure): test = .failed(failure.message)
            }
        }
    }

    /// Edited inputs make any shown or running test result stale.
    private func resetTest() {
        testRun = nil
        test = .idle
    }

    var isInstalling: Bool { installTask != nil }

    func install() {
        guard installTask == nil, let model = cards.local.model else { return }
        installTask = Task {
            await services.installLocal(model)
            installTask = nil
        }
    }

    func cancelInstall() {
        Task { await services.cancelInstall() }
    }

    func refreshLocal() async {
        if let model = cards.local.model { await services.refreshLocal(model) }
    }

    // MARK: Step 4

    func receive(_ event: ScreenshotEvent) {
        guard flow.step == .tryIt else { return }
        var entry: IndexedScreenshot?
        var fileURL: URL?
        switch event {
        case .processed(let report):
            if case .processed(let finalURL, _, _) = report.outcome {
                entry = services.indexEntry(finalURL.path)
                fileURL = finalURL
            } else {
                fileURL = report.originalURL
            }
        case .failed(let originalURL, _):
            fileURL = originalURL
        }
        let created = fileURL.flatMap { try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate }
        let before = flow.tryIt
        flow.tryIt = TryIt.apply(event, entry: entry, fileCreatedAt: created, openedAt: flow.tryItOpenedAt, to: before)
        guard flow.tryIt != before else { return }
        switch flow.tryIt {
        case .result(let result): announce(result.accessibilityLabel)
        case .problem(let text): announce(text)
        case .waiting, .notConnected: break
        }
    }

    /// Posted to the setup window (after ⌘⇧4 another app is usually key, so `keyWindow` is nil), else to the app.
    private func announce(_ text: String) {
        let element: Any
        if let window = services.window() { element = window } else { element = NSApplication.shared }
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
