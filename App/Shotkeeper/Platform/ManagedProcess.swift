import Darwin
import Foundation

/// Size-capped log file: when `maxBytes` would be exceeded, `name.log` → `name.1.log` → … → `name.<keep>.log`.
/// Thread-safe.
final class RotatingLogFile: @unchecked Sendable {
    let url: URL
    let maxBytes: Int
    let keep: Int

    private let lock = NSLock()
    private var handle: FileHandle?
    private var size: Int = 0

    init(url: URL, maxBytes: Int = 5_000_000, keep: Int = 3) throws {
        precondition(maxBytes > 0 && keep >= 0)
        self.url = url
        self.maxBytes = maxBytes
        self.keep = keep
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lock.withLock { try openForAppend() }
    }

    deinit {
        try? handle?.close()
    }

    /// The rotated file for `index` (1 = most recent rotation).
    func rotatedURL(_ index: Int) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "log" : url.pathExtension
        return url.deletingLastPathComponent().appendingPathComponent("\(base).\(index).\(ext)")
    }

    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            if size > 0, size + data.count > maxBytes { rotate() }
            guard let handle else { return }
            do {
                try handle.write(contentsOf: data)
                size += data.count
            } catch {
                // Logging must never take the app down; drop the chunk.
            }
        }
    }

    func write(_ line: String) {
        write(Data(line.utf8))
    }

    func close() {
        lock.withLock {
            try? handle?.close()
            handle = nil
        }
    }

    // MARK: Lock held

    private func openForAppend() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        size = Int(try handle.seekToEnd())
        self.handle = handle
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        if keep == 0 {
            try? fm.removeItem(at: url)
        } else {
            try? fm.removeItem(at: rotatedURL(keep))
            if keep > 1 {
                for index in stride(from: keep - 1, through: 1, by: -1) where fm.fileExists(atPath: rotatedURL(index).path) {
                    try? fm.moveItem(at: rotatedURL(index), to: rotatedURL(index + 1))
                }
            }
            try? fm.moveItem(at: url, to: rotatedURL(1))
        }
        try? openForAppend()
    }
}

/// What to run.
struct ProcessSpec: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    /// nil inherits the app's environment; otherwise these values are merged over it.
    var environment: [String: String]?
    var workingDirectory: URL?
    /// Log file stem under the log directory, e.g. "mlx-server" → `mlx-server.log`.
    var logName: String

    init(executable: URL, arguments: [String] = [], environment: [String: String]? = nil,
         workingDirectory: URL? = nil, logName: String) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.logName = logName
    }
}

enum ProcessExit: Equatable, Sendable {
    case exited(Int32)
    case signaled(Int32)
}

enum ManagedProcessError: Error, Equatable {
    case alreadyStarted
    case launchFailed(String)
}

enum LogLocation {
    /// `~/Library/Logs/Shotkeeper/`
    static var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Shotkeeper", isDirectory: true)
    }
}

/// A long-running child process (phase 2: `mlx_lm.server`). stdout and stderr go to a rotating log file;
/// exit is reported via `onExit` and `waitForExit()`. Every running instance is terminated by
/// `terminateAllRunning()`, which the app delegate calls from `applicationWillTerminate`.
///
/// Limitation: a hard crash of the app cannot run that hook, so the child may outlive it. Phase 2 should kill a
/// stale server on launch (e.g. by a pid file) before starting a new one.
final class ManagedProcess: @unchecked Sendable {
    let spec: ProcessSpec
    let log: RotatingLogFile
    /// Called once, on a background thread, after the process exited and its output was drained.
    var onExit: (@Sendable (ProcessExit) -> Void)? {
        get { lock.withLock { _onExit } }
        set { lock.withLock { _onExit = newValue } }
    }

    private let lock = NSLock()
    private var process: Process?
    private var exitStatus: ProcessExit?
    private var waiters: [CheckedContinuation<ProcessExit, Never>] = []
    private var _onExit: (@Sendable (ProcessExit) -> Void)?

    init(spec: ProcessSpec, logDirectory: URL = LogLocation.directory, maxLogBytes: Int = 5_000_000,
         keptLogs: Int = 3) throws {
        self.spec = spec
        self.log = try RotatingLogFile(url: logDirectory.appendingPathComponent("\(spec.logName).log"),
                                       maxBytes: maxLogBytes, keep: keptLogs)
    }

    var isRunning: Bool { lock.withLock { process?.isRunning ?? false } }
    var processIdentifier: Int32? { lock.withLock { process.map(\.processIdentifier) } }
    var lastExit: ProcessExit? { lock.withLock { exitStatus } }

    func start() throws {
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        if let overrides = spec.environment {
            process.environment = ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }
        }
        if let workingDirectory = spec.workingDirectory { process.currentDirectoryURL = workingDirectory }
        process.standardInput = FileHandle.nullDevice

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output // one interleaved stream, in order

        let drained = DispatchGroup()
        drained.enter()
        let log = self.log
        let reader = output.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                drained.leave()
            } else {
                log.write(chunk)
            }
        }

        process.terminationHandler = { [weak self] finished in
            // Wait briefly for the pipe to hit EOF so the log is complete; a grandchild holding the pipe
            // open must not delay the exit report forever.
            _ = drained.wait(timeout: .now() + 1)
            let status: ProcessExit = finished.terminationReason == .uncaughtSignal
                ? .signaled(finished.terminationStatus) : .exited(finished.terminationStatus)
            self?.finish(status)
        }

        try lock.withLock {
            guard self.process == nil else { throw ManagedProcessError.alreadyStarted }
            log.write("--- \(Date()) starting \(spec.executable.path) \(spec.arguments.joined(separator: " "))\n")
            // Register before launch so a child that exits instantly is removed again by `finish`.
            ManagedProcess.registry.add(self)
            do {
                try process.run()
            } catch {
                reader.readabilityHandler = nil
                ManagedProcess.registry.remove(self)
                throw ManagedProcessError.launchFailed(error.localizedDescription)
            }
            self.process = process
        }
    }

    /// SIGTERM, then SIGKILL if still alive after `gracePeriod`. Blocks the caller for at most `gracePeriod`.
    func terminate(gracePeriod: TimeInterval = 3) {
        guard let process = lock.withLock({ self.process }), process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(gracePeriod)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    func waitForExit() async -> ProcessExit {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if let exitStatus {
                    continuation.resume(returning: exitStatus)
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    private func finish(_ status: ProcessExit) {
        let (waiters, onExit) = lock.withLock { () -> ([CheckedContinuation<ProcessExit, Never>], (@Sendable (ProcessExit) -> Void)?) in
            exitStatus = status
            let pending = self.waiters
            self.waiters = []
            return (pending, _onExit)
        }
        log.write("--- \(Date()) exited: \(status)\n")
        ManagedProcess.registry.remove(self)
        for waiter in waiters { waiter.resume(returning: status) }
        onExit?(status)
    }

    // MARK: Registry for app quit

    private static let registry = Registry()

    /// Terminates every running child concurrently; blocks for at most about `gracePeriod`.
    static func terminateAllRunning(gracePeriod: TimeInterval = 2) {
        let all = registry.snapshot()
        DispatchQueue.concurrentPerform(iterations: all.count) { index in
            all[index].terminate(gracePeriod: gracePeriod)
        }
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ObjectIdentifier: ManagedProcess] = [:]
        func add(_ process: ManagedProcess) { lock.withLock { items[ObjectIdentifier(process)] = process } }
        func remove(_ process: ManagedProcess) { _ = lock.withLock { items.removeValue(forKey: ObjectIdentifier(process)) } }
        func snapshot() -> [ManagedProcess] { lock.withLock { Array(items.values) } }
    }
}
