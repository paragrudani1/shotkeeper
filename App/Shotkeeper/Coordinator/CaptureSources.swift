import Foundation
import Observation
import ShotkeeperCore

/// What `CaptureSources` needs from the coordinator.
@MainActor
protocol CaptureSourcesHost: AnyObject {
    var settings: AppSettings { get }
    var readiness: BackendReadiness { get }
    var index: ScreenshotIndex? { get }
    var queue: ProcessingQueue? { get }
    var processExistingRequests: ProcessExistingRequests { get }
    /// The menu's last message.
    var lastMessage: String? { get set }
    /// Process Existing queued `files`: the toast summarizes them as one run.
    func beginProcessExistingRun(_ files: [URL])
}

/// Where screenshots come from: the watched folder (FSEvents) and "Process Existing Screenshots…". Each source hands
/// files to the coordinator's `ProcessingQueue`; the queue and `ScreenshotProcessor` decide the rest (exclusions,
/// consent). A new source (clipboard, screen recordings) goes here, not into `AppCoordinator`.
@MainActor
@Observable
final class CaptureSources {
    /// The folder being watched (nil until watching starts). The menu shows its name.
    private(set) var watchedFolder: URL?
    /// The folder watcher runs. It starts only once the backend is usable (core `BackendGate`): nothing is queued,
    /// and later uploaded, before the user chose where screenshots go. Once started it keeps running for the
    /// session, so a token removed later shows the "Needs attention" hold instead of silently ignoring screenshots.
    private(set) var isWatching = false
    /// Called on the main actor after Process Existing's folder scan (tests change the destination here).
    @ObservationIgnored var afterProcessExistingScan: (() -> Void)?
    @ObservationIgnored weak var host: (any CaptureSourcesHost)?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var detector = ScreenshotDetector()

    // MARK: Watched folder

    /// Starts the watcher once and re-queues interrupted (`pending`) work. The coordinator calls this when services
    /// run and the backend is ready.
    func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        restartWatcher()
        if let index = host?.index, let queue = host?.queue, let pending = try? index.entries(withStatus: .pending) {
            Task { for entry in pending { await queue.enqueue(URL(fileURLWithPath: entry.path)) } }
        }
    }

    /// The watched-folder setting changed: watch the new folder (only while watching).
    func watchedFolderSettingChanged() {
        if isWatching { restartWatcher() }
    }

    func stop() {
        watchTask?.cancel()
        watcher?.stop()
    }

    private func currentWatchedFolder() -> (folder: URL, prefix: String?) {
        let location = ScreenshotLocation.current()
        let prefix = location.namePrefix == ScreenshotLocation.defaultNamePrefix ? nil : location.namePrefix
        return (host?.settings.watchedFolderOverride ?? location.folder, prefix)
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
                guard self.detector.isScreenshot(event.url), let queue = self.host?.queue else { continue }
                await queue.enqueue(event.url)
            }
        }
    }

    // MARK: Process Existing

    /// Queues every screenshot in the watched folder that the index does not hold yet.
    func processExistingScreenshots() async -> Int {
        guard let host, let index = host.index, let queue = host.queue else { return 0 }
        // Queued files would be analyzed (uploaded) as soon as a backend became usable: not before setup.
        guard host.readiness == .ready else {
            if case .notConfigured(let reason) = host.readiness {
                host.lastMessage = "Finish setup first: \(reason)"
            } else {
                host.lastMessage = "Finish setup first"
            }
            return 0
        }
        // The destination the user is asking for: the one selected now, at the click.
        let target = UploadTarget(settings: host.settings)
        let requests = host.processExistingRequests
        let generation = requests.generation
        let folder = watchedFolder ?? currentWatchedFolder().folder
        let detector = self.detector
        let candidates = await Task.detached {
            ExistingScreenshotScanner.candidates(in: folder, detector: detector,
                                                 isIndexed: ExistingScreenshotScanner.indexedCheck(index))
        }.value
        afterProcessExistingScan?()
        // The processor honours it only while that destination is selected and allowed. A backend, endpoint or grant
        // change during the scan: nothing is queued, the user asks again for the destination now selected.
        guard let request = requests.request(for: target, madeIn: generation) else {
            host.lastMessage = "The destination changed. Run Process Existing again."
            return 0
        }
        host.beginProcessExistingRun(candidates)
        for url in candidates { await queue.enqueue(url, processExisting: request) }
        host.lastMessage = candidates.isEmpty ? "No unprocessed screenshots in \(folder.lastPathComponent)"
            : "Queued \(candidates.count) screenshot\(candidates.count == 1 ? "" : "s")"
        return candidates.count
    }
}
