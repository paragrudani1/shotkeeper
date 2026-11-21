import CoreServices
import Foundation

/// A file that appeared in the watched folder (after debouncing).
struct FolderEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case created
        /// macOS screenshots arrive this way: a hidden temp file is renamed to its final name.
        case renamed
    }

    var url: URL
    var kind: Kind
}

/// Coalesces bursts of events per path; a path is "due" once it has been quiet for `interval`.
/// Pure and clock-injected so it is unit-testable.
struct EventDebouncer {
    private struct Pending {
        var kind: FolderEvent.Kind
        var lastSeen: Date
    }

    let interval: TimeInterval
    private var pending: [String: Pending] = [:]

    init(interval: TimeInterval) {
        self.interval = interval
    }

    var isEmpty: Bool { pending.isEmpty }

    mutating func record(path: String, kind: FolderEvent.Kind, at date: Date) {
        // A rename anywhere in the burst wins: it is the signal that the file reached its final name.
        let mergedKind: FolderEvent.Kind = (pending[path]?.kind == .renamed || kind == .renamed) ? .renamed : .created
        pending[path] = Pending(kind: mergedKind, lastSeen: date)
    }

    /// Removes and returns paths quiet for at least `interval`, sorted for determinism.
    mutating func takeDue(at now: Date) -> [(path: String, kind: FolderEvent.Kind)] {
        let due = pending.filter { now.timeIntervalSince($0.value.lastSeen) >= interval }
        for key in due.keys { pending.removeValue(forKey: key) }
        return due.map { (path: $0.key, kind: $0.value.kind) }.sorted { $0.path < $1.path }
    }
}

/// Watches one folder with an FSEventStream (`kFSEventStreamCreateFlagFileEvents`) and emits created/renamed
/// regular files that are direct, non-hidden children of the folder, once each has been quiet for `debounce`.
///
/// Tolerates the folder not existing: it polls until the folder appears, and goes back to polling if the
/// folder is deleted or moved (`kFSEventStreamEventFlagRootChanged`).
///
/// All mutable state is confined to `queue`; the FSEvents callback is delivered on that queue too.
final class FolderWatcher: @unchecked Sendable {
    let folder: URL
    let events: AsyncStream<FolderEvent>

    private let continuation: AsyncStream<FolderEvent>.Continuation
    private let latency: CFTimeInterval
    private let pollInterval: TimeInterval
    private let queue = DispatchQueue(label: "dev.shotkeeper.FolderWatcher")
    private var debouncer: EventDebouncer
    private var stream: FSEventStreamRef?
    private var pollTimer: DispatchSourceTimer?
    private var isStarted = false
    private var flushScheduled = false
    /// `realpath` of the folder; FSEvents reports real paths (e.g. /private/var/... for /var/...).
    private var resolvedFolderPath: String

    init(folder: URL, debounce: TimeInterval = 0.5, latency: TimeInterval = 0.2, pollInterval: TimeInterval = 2) {
        self.folder = folder.standardizedFileURL
        self.latency = latency
        self.pollInterval = pollInterval
        self.debouncer = EventDebouncer(interval: debounce)
        self.resolvedFolderPath = FolderWatcher.realPath(folder.standardizedFileURL)
        (events, continuation) = AsyncStream.makeStream(of: FolderEvent.self, bufferingPolicy: .unbounded)
    }

    deinit {
        // Synchronous teardown: the stream's context holds an unretained pointer to self.
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        pollTimer?.cancel()
        continuation.finish()
    }

    func start() {
        queue.sync {
            guard !isStarted else { return }
            isStarted = true
            attachOrPoll()
        }
    }

    func stop() {
        queue.sync {
            isStarted = false
            tearDownStream()
            pollTimer?.cancel()
            pollTimer = nil
        }
    }

    // MARK: - Queue-confined

    private func attachOrPoll() {
        guard isStarted else { return }
        if folderExists() {
            pollTimer?.cancel()
            pollTimer = nil
            resolvedFolderPath = FolderWatcher.realPath(folder)
            if !createStream() { startPolling() }
        } else {
            startPolling()
        }
    }

    /// `realpath(3)`, not `resolvingSymlinksInPath()`: Foundation strips `/private`, but FSEvents reports it.
    static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func folderExists() -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.isStarted, self.folderExists() else { return }
            self.attachOrPoll()
        }
        pollTimer = timer
        timer.resume()
    }

    private func createStream() -> Bool {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, folderWatcherCallback, &context,
                                               [resolvedFolderPath] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency, flags) else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    private func tearDownStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard isStarted else { return }
        let now = Date()
        for (path, flag) in zip(paths, flags) {
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                // Folder deleted/moved: drop the stream and wait for it to come back.
                tearDownStream()
                startPolling()
                return
            }
            guard flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 else { continue }
            let renamed = flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0
            let created = flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0
            guard renamed || created else { continue }
            let url = URL(fileURLWithPath: path)
            guard url.deletingLastPathComponent().path == resolvedFolderPath,
                  !url.lastPathComponent.hasPrefix(".") else { continue }
            debouncer.record(path: path, kind: renamed ? .renamed : .created, at: now)
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled, !debouncer.isEmpty else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + debouncer.interval) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            for item in self.debouncer.takeDue(at: Date()) {
                // A rename also fires for the old name; only report files that exist now.
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else { continue }
                self.continuation.yield(FolderEvent(url: URL(fileURLWithPath: item.path), kind: item.kind))
            }
            self.scheduleFlush()
        }
    }
}

/// Nonisolated C callback; runs on the watcher's queue (FSEventStreamSetDispatchQueue).
private func folderWatcherCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
    // kFSEventStreamCreateFlagUseCFTypes: eventPaths is a CFArray of CFString.
    let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray) as? [String] ?? []
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
    watcher.handle(paths: paths, flags: flags)
}
