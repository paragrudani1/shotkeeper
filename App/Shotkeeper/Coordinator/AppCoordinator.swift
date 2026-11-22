import Foundation
import Observation
import ShotkeeperCore

/// Wires core to the platform: settings file, index, undo log, the active analyzer, processing queue, folder
/// watcher, and the managed local model server. Everything the menu, setup, settings and search UI do goes through here.
///
/// `startServices()` is separate from `init` so unit tests can build a coordinator (temp folder, in-memory
/// credentials) without watching folders or registering anything with the system.
@MainActor
@Observable
final class AppCoordinator {
    let supportDirectory: URL
    let physicalMemoryBytes: UInt64

    private(set) var settings: AppSettings
    private(set) var queueStatus: QueueStatus = .idle
    private(set) var runtimePhase: RuntimePhase = .notInstalled
    /// Set when the index could not be opened; the app keeps running but does not process.
    private(set) var startupError: String?
    /// Why the index could not be opened, as short readable text (the search window's error state).
    @ObservationIgnored private(set) var indexProblem: UserFacingProblem?
    /// Last user-facing result (undo, process existing, errors from settings changes). Expires after 30 s or
    /// when the next action succeeds (core `ExpiringMessage`), so the menu never shows stale text.
    var lastMessage: String? {
        get { message.visibleText(at: Date()) }
        set {
            message.set(newValue, at: Date())
            scheduleMessageExpiry()
        }
    }
    private var message = ExpiringMessage()
    private(set) var watchedFolder: URL?
    /// The folder watcher runs. It starts only once the backend is usable (core `BackendGate`): nothing is queued,
    /// and later uploaded, before the user chose where screenshots go. Once started it keeps running for the
    /// session, so a token removed later shows the "Needs attention" hold instead of silently ignoring screenshots.
    private(set) var isWatching = false
    /// Whether the chosen backend may analyze screenshots now. Updated on every settings or secret change.
    private(set) var readiness: BackendReadiness = .notConfigured("Starting")
    /// The menu's "Recent" rows (last 5 processed), the "Undo: <title>" target and the index count.
    private(set) var recentItems: [RecentItem] = []
    private(set) var undoCandidate: UndoRecord?
    private(set) var indexedCount: Int?
    /// Bumped after each rename; the menu bar icon pulses when it changes.
    private(set) var renamePulse = 0
    /// Bumped when a secret changes so views re-read `hasSecret`.
    private(set) var credentialsRevision = 0
    /// Bytes, speed and time left while the local model downloads (nil otherwise).
    private(set) var downloadStats: DownloadStats?
    /// Why the last "Install and Download" did not start or failed (Settings → Model shows it under the button).
    private(set) var localInstallProblem: String?
    /// The search shortcut registered with the system now (nil when none could be registered). The menu and setup
    /// show this one.
    private(set) var activeSearchShortcut: HotKeyShortcut?
    /// Why the saved search shortcut could not be registered at launch (Settings shows it at the recorder).
    private(set) var searchShortcutProblem: String?
    /// Registers a search shortcut with the system (set by the app delegate; nil in unit tests). Returns the
    /// problem when it was refused; the old shortcut then keeps working.
    @ObservationIgnored var registerSearchShortcut: ((HotKeyShortcut) -> HotKeyProblem?)?

    @ObservationIgnored let settingsStore: SettingsStore
    @ObservationIgnored let credentials: any CredentialStore
    @ObservationIgnored let localRuntime: LocalModelRuntime
    @ObservationIgnored private(set) var index: ScreenshotIndex?
    @ObservationIgnored private var undoLog: UndoLog?
    @ObservationIgnored private var processor: ScreenshotProcessor?
    @ObservationIgnored private(set) var queue: ProcessingQueue?
    /// The analyzer and the settings it was built from, replaced together on every rebuild. The processor reads this
    /// pair once right before `analyze` and decides consent on it (`UploadConsent.decide`), so a rebuild while a job
    /// prepares its image cannot send that job to a backend the decision did not cover.
    @ObservationIgnored private let analyzerBox: LockedValue<AnalyzerSnapshot>
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var detector = ScreenshotDetector()
    @ObservationIgnored private var servicesStarted = false
    @ObservationIgnored private var messageExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var toastBatcher = ToastBatcher()
    @ObservationIgnored private var lastSoundAt: Date?
    @ObservationIgnored private let eventSink = LockedValue<(@MainActor @Sendable (ScreenshotEvent) -> Void)?>(nil)
    /// Issues "Process Existing Screenshots…" requests (the destination selected at the click). The queue carries each
    /// with its job for the whole job; all are invalidated when the backend, endpoint or grants change.
    @ObservationIgnored let processExistingRequests = ProcessExistingRequests()
    /// Called on the main actor after Process Existing's folder scan (tests change the destination here).
    @ObservationIgnored var afterProcessExistingScan: (() -> Void)?
    /// Extra listeners for pipeline events (setup's "Try it now" step), keyed by the id `addEventObserver` returned.
    @ObservationIgnored private var eventObservers: [UUID: @MainActor (ScreenshotEvent) -> Void] = [:]
    /// Shows a toast (set by the app delegate; nil in unit tests unless a test sets it).
    @ObservationIgnored var onToast: ((ToastContent) -> Void)?
    /// Plays the rename sound (only called when `playRenameSound` is on).
    @ObservationIgnored var onRenameSound: (() -> Void)?
    /// At most one rename sound per this many seconds, so a batch is not a drum roll.
    static let renameSoundSpacing: TimeInterval = 2

    init(supportDirectory: URL = AppPaths.supportDirectory, credentials: any CredentialStore,
         physicalMemoryBytes: UInt64 = SystemInfo.physicalMemoryBytes,
         applicationSupport: URL = AppPaths.applicationSupport, logDirectory: URL = LogLocation.directory) {
        self.supportDirectory = supportDirectory
        self.credentials = credentials
        self.physicalMemoryBytes = physicalMemoryBytes
        let store = SettingsStore(fileURL: AppPaths.settingsFile(in: supportDirectory))
        self.settingsStore = store
        self.settings = store.current
        self.analyzerBox = LockedValue(AnalyzerSnapshot(analyzer: UnconfiguredAnalyzer(backendID: "none", reason: "Starting"),
                                                        settings: store.current))

        let phaseSink = LockedValue<(@MainActor @Sendable (RuntimePhase) -> Void)?>(nil)
        let bytesSink = LockedValue<(@MainActor @Sendable (Int64) -> Void)?>(nil)
        self.localRuntime = LocalModelRuntime(applicationSupport: applicationSupport, logDirectory: logDirectory,
                                              idleTimeoutMinutes: store.current.idleTimeoutMinutes,
                                              onPhase: { phase in Task { @MainActor in phaseSink.value?(phase) } },
                                              onDownloadBytes: { bytes in Task { @MainActor in bytesSink.value?(bytes) } })
        phaseSink.value = { [weak self] phase in self?.applyRuntimePhase(phase) }
        bytesSink.value = { [weak self] bytes in self?.recordDownloadBytes(bytes) }

        openStorage()
        rebuildAnalyzer()
        eventSink.value = { [weak self] event in self?.handle(event) }
        buildQueue()
        refreshHistory()
        Task { await localRuntime.refresh(for: localVariant) }
    }

    // MARK: Local model download

    /// Internal so tests and snapshots can show a download without running one.
    func applyRuntimePhase(_ phase: RuntimePhase) {
        runtimePhase = phase
        if case .downloading = phase { return }
        downloadStats = nil
    }

    func recordDownloadBytes(_ bytes: Int64, at time: Date = Date()) {
        guard case .downloading = runtimePhase else { return }
        var stats = downloadStats ?? DownloadStats(totalBytes: Int64(localVariant.approxDownloadGB * 1_000_000_000))
        stats.record(bytes: bytes, at: time)
        downloadStats = stats
    }

    // MARK: Derived state

    /// The analyzer the processor will use for the next screenshot.
    var currentAnalyzer: any ScreenshotAnalyzer { analyzerBox.value.analyzer }

    var localVariant: ModelVariant { AnalyzerFactory.localVariant(for: settings, physicalMemoryBytes: physicalMemoryBytes) }

    var recommendation: BackendRecommendation {
        BackendRecommender.recommend(physicalMemoryBytes: physicalMemoryBytes)
    }

    /// The menu's second line while the folder is not watched because no backend is usable ("Not watching yet"),
    /// nil while watching or about to start.
    var notWatchingReason: String? {
        isWatching ? nil : BackendGate.statusReason(for: readiness)
    }

    /// Watching, but the selected backend's destination is not allowed: new screenshots are skipped.
    var isSkippingForConsent: Bool { isWatching && readiness == .needsConsent }

    var statusLine: String {
        if let startupError { return "Error: \(startupError)" }
        return StatusText.line(for: queueStatus)
    }

    var isPaused: Bool {
        if case .paused = queueStatus { return true }
        return false
    }

    /// A hard failure for the menu's red dot: the index did not open, or the local server gave up.
    var failureText: String? {
        if let startupError { return startupError }
        if settings.backend == .localInkling, case .failed(let message) = runtimePhase { return message }
        return nil
    }

    func hasSecret(_ key: CredentialKey) -> Bool {
        _ = credentialsRevision
        return ((try? credentials.secret(for: key)) ?? nil)?.isEmpty == false
    }

    // MARK: Startup

    private func openStorage() {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let index = try ScreenshotIndex(fileURL: AppPaths.indexFile(in: supportDirectory))
            let undoLog = UndoLog(fileURL: AppPaths.undoLogFile(in: supportDirectory))
            let store = settingsStore
            let box = analyzerBox
            self.index = index
            self.undoLog = undoLog
            self.processor = ScreenshotProcessor(
                snapshot: { box.value },
                imagePreparer: SettingsDrivenImagePreparer(settings: { store.current }),
                metadataWriter: XattrMetadataWriter(),
                index: index, undoLog: undoLog)
        } catch {
            indexProblem = UserFacingError.problem(for: error)
            startupError = "Could not open the index: \(StatusText.describe(error))"
        }
    }

    /// Watching, login item, leftover-server cleanup, and re-queueing interrupted work. Not called by unit tests.
    func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true
        Task { await localRuntime.cleanUpAfterPreviousRun() }
        startWatchingIfReady()
    }

    /// Starts the watcher (and re-queues interrupted work) once services run and the backend is usable.
    private func startWatchingIfReady() {
        guard servicesStarted, !isWatching, readiness == .ready else { return }
        isWatching = true
        restartWatcher()
        if let index, let queue, let pending = try? index.entries(withStatus: .pending) {
            Task { for entry in pending { await queue.enqueue(URL(fileURLWithPath: entry.path)) } }
        }
    }

    func stopServices() {
        watchTask?.cancel()
        watcher?.stop()
        Task { await localRuntime.stop() }
    }

    // MARK: Settings

    /// Persists `new` and applies whatever changed.
    func updateSettings(_ new: AppSettings) {
        let old = settings
        guard new != old else { return }
        settings = new
        do { try settingsStore.save(new) } catch { lastMessage = "Could not save settings: \(StatusText.describe(error))" }

        let destinationChanged = new.backend != old.backend || new.customEndpointURL != old.customEndpointURL
            || new.uploadGrants != old.uploadGrants
        // A Process Existing request was for the destination selected then: never carried to another one.
        if destinationChanged { processExistingRequests.invalidateAll() }
        if destinationChanged || new.clairicAccountID != old.clairicAccountID || new.customModelName != old.customModelName
            || new.localModelVariantID != old.localModelVariantID { // consent un-holds cloud backends
            rebuildAnalyzer()
            Task { await localRuntime.refresh(for: localVariant) }
            if new.backend != .localInkling, old.backend == .localInkling { Task { await localRuntime.stop() } }
        } else {
            // Same analyzer; the pair carries the new rename/move/Finder settings (nothing here changes consent).
            analyzerBox.withValue { $0 = AnalyzerSnapshot(analyzer: $0.analyzer, settings: new) }
        }
        if new.requestsPerMinute != old.requestsPerMinute, let queue {
            // In place: a rebuilt queue had to resume the old one to drain it, which ran held jobs during a pause.
            let rate = max(1, new.requestsPerMinute)
            Task { await queue.setRequestsPerMinute(rate) }
        }
        if new.watchedFolderOverride != old.watchedFolderOverride, isWatching { restartWatcher() }
        if new.idleTimeoutMinutes != old.idleTimeoutMinutes {
            let minutes = new.idleTimeoutMinutes
            Task { await localRuntime.setIdleTimeout(minutes: minutes) }
        }
        if new.launchAtLogin != old.launchAtLogin, servicesStarted {
            do { try LaunchAtLogin.setEnabled(new.launchAtLogin) } catch {
                lastMessage = StatusText.launchAtLoginFailed
            }
        }
    }

    func updateSettings(_ body: (inout AppSettings) -> Void) {
        var copy = settings
        body(&copy)
        updateSettings(copy)
    }

    func setSecret(_ value: String, for key: CredentialKey) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty { try credentials.removeSecret(for: key) } else { try credentials.setSecret(trimmed, for: key) }
        } catch {
            lastMessage = StatusText.describe(error)
        }
        credentialsRevision += 1
        rebuildAnalyzer()
    }

    // MARK: Analyzer and queue

    func rebuildAnalyzer() {
        let analyzer = AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: localRuntime,
                                            physicalMemoryBytes: physicalMemoryBytes)
        analyzerBox.value = AnalyzerSnapshot(analyzer: analyzer, settings: settings)
        readiness = BackendGate.readiness(settings: settings, hasClairicToken: hasSecret(.cloudflareAPIToken))
        // A queue held on "not configured"/"unauthorized" retries with the new analyzer.
        if case .error = queueStatus, let queue { Task { await queue.resume() } }
        startWatchingIfReady()
    }

    /// Built once: rate changes go through `ProcessingQueue.setRequestsPerMinute`, so queued jobs and pause/hold
    /// state never have to move between queues.
    private func buildQueue() {
        guard let processor, queue == nil else { return }
        let configuration = ProcessingQueue.Configuration(concurrency: 1,
                                                          requestsPerMinute: max(1, settings.requestsPerMinute))
        let sink = eventSink
        let requests = processExistingRequests
        let queue = ProcessingQueue(configuration: configuration, jobHandler: { url, request in
            // Checked on every attempt: a destination change since the click makes it count as none.
            let processExisting = requests.authorization(for: request)
            do {
                let report = try await processor.processWithReport(url, processExisting: processExisting)
                await MainActor.run { sink.value?(.processed(report)) }
            } catch {
                if UserFacingError.shouldNotify(error) {
                    let event = ScreenshotEvent.failed(originalURL: url.standardizedFileURL,
                                                       problem: UserFacingError.problem(for: error))
                    await MainActor.run { sink.value?(event) }
                }
                throw error
            }
        })
        self.queue = queue
        statusTask = Task { [weak self] in
            for await status in await queue.statusUpdates() {
                guard !Task.isCancelled else { break }
                self?.queueStatus = status
            }
        }
    }

    // MARK: Menu actions

    func pause(minutes: Int, now: Date = Date()) {
        let until = now.addingTimeInterval(TimeInterval(minutes) * 60)
        // Skip (not just hold) screenshots captured in the window: that is what "pause" promises for privacy.
        updateSettings { $0.excludeRules.pause(for: TimeInterval(minutes) * 60, from: now) }
        if let queue { Task { await queue.pause(until: until) } }
    }

    /// Holds the queue until `resume()`; screenshots taken meanwhile are processed afterwards.
    func pauseIndefinitely() {
        if let queue { Task { await queue.pause(until: nil) } }
    }

    func resume() {
        updateSettings { $0.excludeRules.resume() }
        if let queue { Task { await queue.resume() } }
    }

    /// The menu's "Undo: <title>" (⌘Z): the most recent rename. Shows the "restored" toast.
    func undoLastRename() {
        guard let processor else { return }
        do {
            let record = try processor.undoLast()
            message.clearAfterSuccess()
            refreshHistory()
            showToast(.restored(RestoredToast(restoredPaths: [record.from])))
        } catch {
            lastMessage = StatusText.describe(error)
        }
    }

    /// The toast's Undo / Undo All. Returns the toast to show next.
    func undoFromToast(ids: [UUID]) -> ToastContent {
        guard let processor else { return .error(ErrorToast(.undo, UserFacingProblem(message: "the index is not open"))) }
        defer { refreshHistory() }
        if ids.count == 1 {
            do {
                let record = try processor.undo(id: ids[0])
                message.clearAfterSuccess()
                return .restored(RestoredToast(restoredPaths: [record.from]))
            } catch {
                return .error(ErrorToast(.undo, UserFacingError.problem(for: error)))
            }
        }
        let result = processor.undo(ids: ids)
        if result.restored.isEmpty {
            return .error(ErrorToast(.undo, UserFacingProblem(message: "the files were moved or renamed since")))
        }
        message.clearAfterSuccess()
        return .restored(RestoredToast(restoredPaths: result.restored.map(\.from), failedCount: result.failed.count))
    }

    /// The toast's "Edit name": rename through the pipeline's rules, update the index, write an undo record.
    func renameFromToast(_ toast: RenamedToast, to name: String) -> Result<RenamedToast, UserFacingProblem> {
        guard let processor else { return .failure(UserFacingProblem(message: "the index is not open")) }
        do {
            let result = try processor.rename(toast.currentURL, to: name)
            message.clearAfterSuccess()
            refreshHistory()
            return .success(toast.edited(to: result.finalURL, undoRecordID: result.undoRecordID))
        } catch {
            return .failure(UserFacingError.problem(for: error))
        }
    }

    // MARK: Pipeline events (toast, recents, sound, pulse)

    /// One pipeline event, on the main actor. Internal so tests can drive it without a model.
    func handle(_ event: ScreenshotEvent, now: Date = Date()) {
        for observer in eventObservers.values { observer(event) }
        if case .processed(let report) = event, case .processed = report.outcome {
            message.clearAfterSuccess()
            refreshHistory()
        }
        guard let content = toastBatcher.record(event, at: now) else { return }
        switch content {
        case .renamed, .batch:
            renamePulse += 1
            if settings.playRenameSound, lastSoundAt.map({ now.timeIntervalSince($0) >= Self.renameSoundSpacing }) ?? true {
                lastSoundAt = now
                onRenameSound?()
            }
            if settings.showRenameToast { onToast?(content) }
        case .error, .restored:
            // Errors are shown even with rename toasts off: the setting is about confirmations, not problems.
            onToast?(content)
        }
    }

    private func showToast(_ content: ToastContent) {
        if settings.showRenameToast { onToast?(content) } else if case .restored(let restored) = content {
            lastMessage = "\(restored.label): \(restored.title)"
        }
    }

    /// Re-reads the recent list, the undo target and the index count.
    func refreshHistory() {
        guard let index else { return }
        recentItems = RecentItems.make(from: (try? index.recentProcessed(limit: RecentItems.limit)) ?? [])
        indexedCount = (try? index.stats())?.done
        undoCandidate = processor?.lastUndoable()
    }

    private func scheduleMessageExpiry() {
        messageExpiryTask?.cancel()
        guard message.text != nil else { return }
        messageExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ExpiringMessage.lifetime * 1_000_000_000) + 50_000_000)
            guard !Task.isCancelled else { return }
            self?.message.expire(at: Date())
        }
    }

    /// Queues every screenshot in the watched folder that the index does not hold yet.
    func processExistingScreenshots() async -> Int {
        guard let index, let queue else { return 0 }
        // Queued files would be analyzed (uploaded) as soon as a backend became usable: not before setup.
        guard readiness == .ready else {
            if case .notConfigured(let reason) = readiness {
                lastMessage = "Finish setup first: \(reason)"
            } else {
                lastMessage = "Finish setup first"
            }
            return 0
        }
        // The destination the user is asking for: the one selected now, at the click.
        let target = UploadTarget(settings: settings)
        let generation = processExistingRequests.generation
        let folder = watchedFolder ?? currentWatchedFolder().folder
        let detector = self.detector
        let candidates = await Task.detached {
            ExistingScreenshotScanner.candidates(in: folder, detector: detector,
                                                 isIndexed: ExistingScreenshotScanner.indexedCheck(index))
        }.value
        afterProcessExistingScan?()
        // The processor honours it only while that destination is selected and allowed. A backend, endpoint or grant
        // change during the scan: nothing is queued, the user asks again for the destination now selected.
        guard let request = processExistingRequests.request(for: target, madeIn: generation) else {
            lastMessage = "The destination changed. Run Process Existing again."
            return 0
        }
        toastBatcher.beginRun(candidates)
        for url in candidates { await queue.enqueue(url, processExisting: request) }
        lastMessage = candidates.isEmpty ? "No unprocessed screenshots in \(folder.lastPathComponent)"
            : "Queued \(candidates.count) screenshot\(candidates.count == 1 ? "" : "s")"
        return candidates.count
    }

    // MARK: Watching

    private func currentWatchedFolder() -> (folder: URL, prefix: String?) {
        let location = ScreenshotLocation.current()
        let prefix = location.namePrefix == ScreenshotLocation.defaultNamePrefix ? nil : location.namePrefix
        return (settings.watchedFolderOverride ?? location.folder, prefix)
    }

    private func restartWatcher() {
        watchTask?.cancel()
        watcher?.stop()
        let (folder, prefix) = currentWatchedFolder()
        detector = ScreenshotDetector(customPrefix: prefix)
        watchedFolder = folder
        let watcher = FolderWatcher(folder: folder)
        self.watcher = watcher
        watcher.start()
        watchTask = Task { [weak self] in
            for await event in watcher.events {
                guard !Task.isCancelled, let self else { break }
                guard self.detector.isScreenshot(event.url), let queue = self.queue else { continue }
                await queue.enqueue(event.url)
            }
        }
    }

    // MARK: Setup helpers

    /// Setup step 2 "I Agree": records that the privacy step was accepted (setup no longer opens at launch). It
    /// grants nothing: Cloudflare is allowed when step 3 then saves Clairic (`saveClairicSetup`).
    func acceptPrivacyStep() {
        updateSettings { $0.hasSeenPrivacyNotice = true }
    }

    /// Settings → Model's confirmation (`BackendGate.consentRequest`) for the selected backend's destination, from
    /// now on. `endpoint` is the one the dialog named: if the configured endpoint changed meanwhile, nothing is
    /// granted.
    func allowUploads(to destination: AppSettings.UploadDestination, endpoint: CustomEndpointIdentity?) {
        updateSettings { $0 = BackendGate.granting(destination, expectedEndpoint: endpoint, in: $0) }
    }

    /// Setup step 5 "Finish": saves the choice and applies it to the login item every time, so a login item that
    /// was removed in System Settings (or never registered) is fixed even when the setting did not change.
    func setLaunchAtLogin(_ enabled: Bool) {
        let unchanged = settings.launchAtLogin == enabled
        updateSettings { $0.launchAtLogin = enabled } // applies it when it changed (and services run)
        guard unchanged, servicesStarted else { return }
        do { try LaunchAtLogin.apply(enabled) } catch {
            lastMessage = StatusText.launchAtLoginFailed
        }
    }

    // MARK: Search shortcut

    /// At launch: registers the saved search shortcut. If the system refuses it, Settings shows why at the recorder
    /// and the menu shows no shortcut.
    func startSearchShortcut() {
        guard let registerSearchShortcut else { return }
        let shortcut = settings.searchShortcut
        if let problem = registerSearchShortcut(shortcut) {
            searchShortcutProblem = problem.message(for: shortcut)
            lastMessage = "Search shortcut: \(problem.message(for: shortcut))"
        } else {
            activeSearchShortcut = shortcut
            searchShortcutProblem = nil
        }
    }

    /// The shortcut recorder: checks the rules, registers the new shortcut, and saves it only once it registered.
    /// On a problem nothing changes and the old shortcut keeps working.
    func changeSearchShortcut(to shortcut: HotKeyShortcut) -> HotKeyProblem? {
        if let problem = HotKeyRules.problem(with: shortcut) { return problem }
        if let registerSearchShortcut {
            if let problem = registerSearchShortcut(shortcut) { return problem }
            activeSearchShortcut = shortcut
        }
        searchShortcutProblem = nil
        updateSettings { $0.searchShortcut = shortcut }
        return nil
    }

    /// Setup step 3 "Continue" with Clairic: the token goes to the Keychain now (never while typing), then the
    /// backend and account ID are saved, and Cloudflare is allowed from now on when `agreedThisRun` (step 2's
    /// "I Agree" in this setup run, not a flag saved by an earlier one). An empty token keeps the saved one.
    func saveClairicSetup(accountID: String, token: String, agreedThisRun: Bool) {
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { setSecret(token, for: .cloudflareAPIToken) }
        let account = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSettings {
            $0.backend = .clairic
            $0.clairicAccountID = account.isEmpty ? nil : account
            if agreedThisRun { $0 = BackendGate.granting(.cloudflare, in: $0) }
        }
    }

    /// Setup step 3 "Continue" with the local model.
    func chooseLocalBackend(_ variant: ModelVariant) {
        updateSettings {
            $0.backend = .localInkling
            $0.localModelVariantID = variant.id
        }
    }

    /// Calls `observer` with every pipeline event (the same ones the toast gets) until `removeEventObserver`.
    func addEventObserver(_ observer: @escaping @MainActor (ScreenshotEvent) -> Void) -> UUID {
        let id = UUID()
        eventObservers[id] = observer
        return id
    }

    func removeEventObserver(_ id: UUID) {
        eventObservers[id] = nil
    }

    /// The index row at `path` (setup's result card reads its tags).
    func indexEntry(atPath path: String) -> IndexedScreenshot? {
        try? index?.lookup(byPath: path)
    }

    /// Runs one analysis of a generated image with the given (unsaved) settings and secrets.
    func testConnection(settings candidate: AppSettings, secrets: [CredentialKey: String]) async -> Result<String, AnalyzerFailure> {
        let store = InMemoryCredentialStore()
        for key in [CredentialKey.cloudflareAPIToken, .customEndpointAPIKey] {
            let override = secrets[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let override, !override.isEmpty {
                try? store.setSecret(override, for: key)
            } else if let saved = (try? credentials.secret(for: key)) ?? nil {
                try? store.setSecret(saved, for: key)
            }
        }
        // Only a generated image is sent here, never a user file, so the consent gate does not apply. The grants
        // live on this copy only; nothing is saved.
        var candidate = candidate
        candidate = BackendGate.granting(.cloudflare, in: candidate, at: .distantPast)
        candidate = BackendGate.granting(.customEndpoint, expectedEndpoint: CustomEndpointIdentity(url: candidate.customEndpointURL),
                                         in: candidate, at: .distantPast)
        let analyzer = AnalyzerFactory.make(settings: candidate, credentials: store, localRuntime: localRuntime,
                                            physicalMemoryBytes: physicalMemoryBytes)
        do {
            let payload = try ConnectionTestImage.payload()
            let analysis = try await analyzer.analyze(payload, context: ConnectionTestImage.context)
            return .success(ConnectionTestImage.summary(analysis))
        } catch {
            return .failure(AnalyzerFailure(message: ConnectionTestText.failure(error, backend: candidate.backend)))
        }
    }

    /// Free space on the volume of `url` (or its nearest existing parent), nil when unknown.
    nonisolated static func freeDiskBytes(near url: URL) -> Int64? {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.pathComponents.count > 1 {
            candidate = candidate.deletingLastPathComponent()
        }
        let values = try? candidate.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Test seam for the disk check (real free space otherwise).
    @ObservationIgnored var availableDiskBytes: (URL) -> Int64? = { AppCoordinator.freeDiskBytes(near: $0) }

    /// "Install and Download": checks the free disk space first (core `DiskSpaceCheck`), then installs.
    func installLocalModel(_ variant: ModelVariant) async {
        localInstallProblem = nil
        let needs = await localRuntime.diskNeeds(for: variant)
        let verdict = DiskSpaceCheck.evaluate(availableBytes: availableDiskBytes(localRuntime.runtimeDirectory),
                                              downloadBytes: Int64(variant.approxDownloadGB * 1_000_000_000),
                                              alreadyOnDisk: needs.alreadyOnDisk, needsRuntime: needs.needsRuntime)
        if let message = verdict.message {
            localInstallProblem = message
            lastMessage = message
            return
        }
        do {
            try await localRuntime.install(variant)
            lastMessage = "\(variant.displayName) is installed."
            rebuildAnalyzer() // un-holds a queue that stopped on "not installed"
        } catch is CancellationError {
            lastMessage = "Install cancelled."
        } catch {
            localInstallProblem = StatusText.describe(error)
            lastMessage = StatusText.describe(error)
        }
    }

    /// "Remove model" (after the user confirmed): deletes the downloaded files of `variant`.
    func removeLocalModel(_ variant: ModelVariant) async {
        do {
            try await localRuntime.removeModel(variant)
            localInstallProblem = nil
            lastMessage = "\(variant.displayName) was removed from this Mac."
            rebuildAnalyzer()
        } catch {
            lastMessage = StatusText.describe(error)
        }
    }
}

extension AppCoordinator {
    /// After the local server gave up on repeated crashes: clear that state and let held screenshots retry.
    func retryLocalRuntime() async {
        await localRuntime.retryAfterFailure()
        rebuildAnalyzer()
    }
}

struct AnalyzerFailure: Error, Equatable {
    var message: String
}
