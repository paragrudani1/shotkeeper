import Foundation
import ShotkeeperCore

/// What the setup/settings UI shows for the local backend.
enum RuntimePhase: Equatable, Sendable {
    /// The Python env or the model weights are missing.
    case notInstalled
    case installing(String)
    /// 0...1; estimate from `DownloadProgress`.
    case downloading(Double)
    /// Installed; server not running (it starts on the first screenshot).
    case ready
    case starting
    case running(port: Int)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .installing, .downloading, .starting: return true
        default: return false
        }
    }
}

enum LocalRuntimeError: LocalizedError, Equatable {
    case noPython
    case commandFailed(step: String, exit: String)
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .noPython:
            return "Needs uv or Python 3.11+. Install uv with `brew install uv` (or from astral.sh/uv), then try again."
        case .commandFailed(let step, let exit):
            return "\(step) failed (\(exit)). Details: ~/Library/Logs/Shotkeeper/."
        case .alreadyRunning:
            return "An install is already running."
        }
    }
}

/// Owns the optional on-device backend: installs mlx-lm into a private venv, downloads the pinned model, runs
/// `mlx_lm.server` on a free loopback port, stops it when idle (`IdlePolicy`), restarts it after crashes
/// (`RestartPolicy`), and records it in a pid file so a server orphaned by an app crash is killed at next launch.
/// Every command comes from core's `MLXRuntimePlan` and runs without a shell.
actor LocalModelRuntime: LocalModelServing {
    static let downloadCompleteMarker = ".shotkeeper-download-complete"

    private let applicationSupport: URL
    private let logDirectory: URL
    private let pidFile: ServerPIDFile
    private let onPhase: @Sendable (RuntimePhase) -> Void
    /// Paths only; the install step builds its own plan with the uv/python it finds.
    private let pathsPlan: MLXRuntimePlan

    private(set) var phase: RuntimePhase = .notInstalled
    private var idlePolicy: IdlePolicy
    private var restartPolicy = RestartPolicy()
    private var giveUpMessage: String?

    private var server: ManagedProcess?
    private var serverVariant: ModelVariant?
    private var serverPort: Int?
    private var startTask: Task<URL, Error>?
    private var stopping = false
    private var inFlight = 0
    private var lastActivity = Date()
    private var idleTask: Task<Void, Never>?
    /// Delayed restart after a crash; `stop()` cancels it so a backend switch or quit cannot relaunch the server.
    private var restartTask: Task<Void, Never>?
    private var installTask: Task<Void, Error>?

    init(applicationSupport: URL = AppPaths.applicationSupport, logDirectory: URL = LogLocation.directory,
         idleTimeoutMinutes: Int, onPhase: @escaping @Sendable (RuntimePhase) -> Void) {
        self.applicationSupport = applicationSupport
        self.logDirectory = logDirectory
        self.onPhase = onPhase
        self.idlePolicy = IdlePolicy(idleTimeoutMinutes: idleTimeoutMinutes)
        self.pathsPlan = MLXRuntimePlan(applicationSupport: applicationSupport, uvPath: nil)
        self.pidFile = ServerPIDFile(url: pathsPlan.runtimeDirectory.appendingPathComponent("server.pid"))
    }

    // MARK: LocalModelServing

    nonisolated func modelArgument(for variant: ModelVariant) -> String {
        pathsPlan.localModelDirectory(for: variant).path
    }

    func beginRequest(for variant: ModelVariant) async throws -> URL {
        inFlight += 1
        lastActivity = Date()
        do {
            return try await ensureRunning(variant)
        } catch {
            inFlight -= 1
            throw error
        }
    }

    func endRequest() {
        inFlight = max(0, inFlight - 1)
        lastActivity = Date()
        scheduleIdleCheck()
    }

    // MARK: Lifecycle

    /// Call once at app launch: kills a server left running by a crashed previous instance.
    func cleanUpAfterPreviousRun() {
        pidFile.killLeftover()
    }

    /// Refreshes `phase` from disk for the selected variant (unless something is in progress).
    func refresh(for variant: ModelVariant) {
        guard !phase.isBusy, server == nil else { return }
        setPhase(isInstalled(variant) ? .ready : .notInstalled)
    }

    func setIdleTimeout(minutes: Int) {
        idlePolicy = IdlePolicy(idleTimeoutMinutes: minutes)
        scheduleIdleCheck()
    }

    func isInstalled(_ variant: ModelVariant) -> Bool {
        let marker = pathsPlan.localModelDirectory(for: variant).appendingPathComponent(Self.downloadCompleteMarker)
        let hasServer = FileManager.default.isExecutableFile(atPath: pathsPlan.serverExecutable)
        let hasModel = FileManager.default.fileExists(atPath: marker.path)
        return hasServer && hasModel
    }

    /// Clears a "gave up after repeated crashes" state so the next request starts the server again.
    func retryAfterFailure() {
        restartPolicy.reset()
        giveUpMessage = nil
        setPhase(.ready)
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
        startTask?.cancel()
        startTask = nil
        restartTask?.cancel()
        restartTask = nil
        guard let server else {
            // A crash restart may have been pending ("starting" with no process).
            serverVariant = nil
            if phase == .starting { setPhase(.ready) }
            return
        }
        stopping = true
        server.terminate()
        self.server = nil
        serverVariant = nil
        serverPort = nil
        pidFile.remove()
        restartPolicy.reset()
        setPhase(.ready)
    }

    // MARK: Install + download

    /// Creates the venv (skipped when it already has `mlx_lm.server` and `hf`), then downloads the model (resumable).
    func install(_ variant: ModelVariant) async throws {
        guard installTask == nil else { throw LocalRuntimeError.alreadyRunning }
        let task = Task { try await self.performInstall(variant) }
        installTask = task
        defer { installTask = nil }
        do {
            try await task.value
            setPhase(.ready)
        } catch is CancellationError {
            setPhase(isInstalled(variant) ? .ready : .notInstalled)
            throw CancellationError()
        } catch {
            setPhase(.failed(StatusText.describe(error)))
            throw error
        }
    }

    func cancelInstall() {
        installTask?.cancel()
    }

    private func performInstall(_ variant: ModelVariant) async throws {
        // FileManager is not Sendable: no local `fm` captured by `&&`'s autoclosure inside the actor.
        let hasServer = FileManager.default.isExecutableFile(atPath: pathsPlan.serverExecutable)
        let hasHF = FileManager.default.isExecutableFile(atPath: pathsPlan.hfExecutable)
        if !(hasServer && hasHF) {
            setPhase(.installing("Finding Python…"))
            let plan = try await installPlan()
            try FileManager.default.createDirectory(at: plan.runtimeDirectory, withIntermediateDirectories: true)
            let commands = plan.installCommands
            for (offset, command) in commands.enumerated() {
                try Task.checkCancellation()
                let step = "Installing the model runtime (step \(offset + 1) of \(commands.count))"
                setPhase(.installing(step + "…"))
                try await run(command, logName: "runtime-install", step: step)
            }
        }

        let directory = pathsPlan.localModelDirectory(for: variant)
        let marker = directory.appendingPathComponent(Self.downloadCompleteMarker)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        setPhase(.downloading(0))
        let parsed = LockedValue<Double?>(nil)
        let tail = LockedValue("")
        let poller = Task { [weak self] in
            while !Task.isCancelled {
                let bytes = DownloadProgress.bytesOnDisk(in: directory)
                let fraction = DownloadProgress.estimate(parsed: parsed.value, bytesOnDisk: bytes,
                                                         expectedGB: variant.approxDownloadGB)
                await self?.setPhase(.downloading(fraction))
                try? await Task.sleep(for: .seconds(1))
            }
        }
        defer { poller.cancel() }
        try await run(pathsPlan.downloadCommand(for: variant), logName: "model-download",
                      step: "Downloading \(variant.displayName)") { chunk in
            // Keep the last few KB: tqdm redraws one line with \r.
            let text = tail.withValue { buffer -> String in
                buffer = String((buffer + String(decoding: chunk, as: UTF8.self)).suffix(4096))
                return buffer
            }
            if let fraction = DownloadProgress.fetchingFraction(in: text) { parsed.value = fraction }
        }
        try Data().write(to: marker)
    }

    private func installPlan() async throws -> MLXRuntimePlan {
        if let uv = Self.findUV() {
            return MLXRuntimePlan(applicationSupport: applicationSupport, uvPath: uv)
        }
        for python in Self.pythonCandidates() {
            if let version = try? await Self.output(of: python, ["--version"]),
               MLXRuntimePlan.isSupportedPython(versionOutput: version) {
                return MLXRuntimePlan(applicationSupport: applicationSupport, uvPath: nil, python3Path: python)
            }
        }
        throw LocalRuntimeError.noPython
    }

    static func findUV(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let candidates = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv",
                          home.appendingPathComponent(".local/bin/uv").path,
                          home.appendingPathComponent(".cargo/bin/uv").path]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Homebrew pythons first. `/usr/bin/python3` only when the Command Line Tools are installed: otherwise
    /// running it pops the "install developer tools" dialog.
    static func pythonCandidates() -> [String] {
        var list = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        if FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/python3") {
            list.append("/usr/bin/python3")
        }
        return list.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func output(of executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func run(_ command: RuntimeCommand, logName: String, step: String,
                     onOutput: (@Sendable (Data) -> Void)? = nil) async throws {
        let spec = ProcessSpec(executable: URL(fileURLWithPath: command.executable), arguments: command.arguments,
                               environment: command.environment.isEmpty ? nil : command.environment, logName: logName)
        let process = try ManagedProcess(spec: spec, logDirectory: logDirectory)
        process.onOutput = onOutput
        try process.start()
        let exit = await withTaskCancellationHandler {
            await process.waitForExit()
        } onCancel: {
            process.terminate()
        }
        try Task.checkCancellation()
        guard exit == .exited(0) else {
            throw LocalRuntimeError.commandFailed(step: step, exit: "\(exit)")
        }
    }

    // MARK: Server

    private func ensureRunning(_ variant: ModelVariant) async throws -> URL {
        if let server, server.isRunning, serverVariant == variant, let serverPort {
            return Self.baseURL(port: serverPort)
        }
        if let startTask { return try await startTask.value }
        if server != nil, serverVariant != variant { stop() }
        if let giveUpMessage { throw AnalyzerError.notConfigured(giveUpMessage) }
        guard isInstalled(variant) else {
            throw AnalyzerError.notConfigured("The local model is not installed. Open Settings → Model to install it.")
        }
        let task = Task { try await self.startServer(variant) }
        startTask = task
        defer { startTask = nil }
        return try await task.value
    }

    private func startServer(_ variant: ModelVariant) async throws -> URL {
        pidFile.killLeftover()
        setPhase(.starting)
        let port: Int
        do { port = Int(try FreePort.find()) } catch {
            setPhase(.failed("No free port"))
            throw AnalyzerError.unreachable("No free local port: \(error)")
        }
        let command = pathsPlan.serverCommand(model: modelArgument(for: variant), port: port)
        let spec = ProcessSpec(executable: URL(fileURLWithPath: command.executable), arguments: command.arguments,
                               environment: command.environment, logName: "mlx-server")
        let process = try ManagedProcess(spec: spec, logDirectory: logDirectory)
        let processID = ObjectIdentifier(process)
        process.onExit = { [weak self] status in
            Task { await self?.serverExited(processID, status: status) }
        }
        stopping = false
        do {
            try process.start()
        } catch {
            setPhase(.failed("Could not launch the model server"))
            throw AnalyzerError.unreachable("Could not launch mlx_lm.server: \(error)")
        }
        server = process
        serverVariant = variant
        serverPort = port
        if let pid = process.processIdentifier, let started = ProcessInfoReader.startTime(of: pid) {
            try? pidFile.write(.init(pid: pid, startTime: started, port: port))
        }

        // Loading ~10 GB of weights can take minutes on first start. Give up early if the process dies.
        let probe = HealthProbe(url: MLXRuntimePlan.healthURL(port: port), timeout: .seconds(2),
                                interval: .milliseconds(250))
        let deadline = ContinuousClock.now.advanced(by: .seconds(600))
        while true {
            try Task.checkCancellation()
            guard process.isRunning else {
                throw AnalyzerError.unreachable("The local model server exited while starting (see ~/Library/Logs/Shotkeeper/mlx-server.log)")
            }
            do {
                try await probe.waitUntilHealthy()
                break
            } catch is HealthProbeError {
                if ContinuousClock.now >= deadline {
                    stop()
                    throw AnalyzerError.unreachable("The local model server did not become ready in 10 minutes")
                }
            }
        }
        setPhase(.running(port: port))
        lastActivity = Date()
        scheduleIdleCheck()
        return Self.baseURL(port: port)
    }

    private func serverExited(_ id: ObjectIdentifier, status: ProcessExit) {
        guard let server, ObjectIdentifier(server) == id else { return }
        self.server = nil
        serverPort = nil
        pidFile.remove()
        if stopping { return }
        switch restartPolicy.recordCrash(at: Date()) {
        case .restart(let delay):
            guard let variant = serverVariant else { return }
            setPhase(.starting)
            restartTask?.cancel()
            restartTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self.restartAfterCrash(variant)
            }
        case .giveUp:
            serverVariant = nil
            giveUpMessage = "The local model server keeps crashing (\(status)). See ~/Library/Logs/Shotkeeper/mlx-server.log, then retry in Settings."
            setPhase(.failed(giveUpMessage ?? ""))
        }
    }

    private func restartAfterCrash(_ variant: ModelVariant) async {
        restartTask = nil
        _ = try? await ensureRunning(variant)
    }

    /// Test hook: true while a crash restart is scheduled.
    var hasPendingRestart: Bool { restartTask != nil }

    private func scheduleIdleCheck() {
        idleTask?.cancel()
        guard server != nil, let next = idlePolicy.nextCheck(lastActivity: lastActivity) else { return }
        idleTask = Task { [weak self] in
            let wait = max(1, next.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle()
        }
    }

    private func stopIfIdle() {
        if idlePolicy.shouldStop(lastActivity: lastActivity, now: Date(), inFlight: inFlight) {
            stop()
        } else {
            scheduleIdleCheck()
        }
    }

    private func setPhase(_ phase: RuntimePhase) {
        self.phase = phase
        onPhase(phase)
    }

    static func baseURL(port: Int) -> URL { URL(string: "http://127.0.0.1:\(port)")! }
}

/// Minimal lock-protected box for values shared with `@Sendable` callbacks.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.withLock { body(&stored) }
    }
}
