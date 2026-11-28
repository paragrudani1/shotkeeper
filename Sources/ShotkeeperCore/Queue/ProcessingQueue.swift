import Foundation

/// Runs jobs through a handler: `.process(url)` for a new or existing file (usually `ScreenshotProcessor.process`),
/// `.reanalyze(rowID:)` for Analyze Again on an indexed row.
///
/// - Concurrency 1 by default. A job equal to one already queued or in flight (same kind and key) is ignored.
/// - Every attempt first takes a token from a requests-per-minute `TokenBucket`.
/// - `AnalyzerError.rateLimited` / `.serverError`: retry after `retryAfter` (when given) or exponential backoff with
///   jitter, up to `maxAttempts` calls; then the job fails (the processor has already recorded the error in the index).
/// - `AnalyzerError.unreachable`: the queue goes `.offline` and holds; it waits with its own backoff and probes
///   (`probe`, or by retrying the job). Offline time does not use up attempts.
/// - `AnalyzerError.unauthorized` / `.notConfigured`: the queue holds in `.error(message)` until `resume()`;
///   the job is kept, not failed, so nothing is lost while the user fixes credentials.
/// - Any other error fails the job at once.
/// - A job may carry a `UserUploadRequest` (`enqueue(_:atFront:userRequest:)`): every attempt of that job gets it,
///   retries and holds included, and it is dropped when the job ends.
/// - `status` summarises the queue for the menu bar; `jobStates` / `jobStateUpdates()` say where each job is.
public actor ProcessingQueue {
    public struct Configuration: Sendable, Equatable {
        public var concurrency: Int = 1
        public var maxAttempts: Int = 5
        public var requestsPerMinute: Int = 30
        public var burst: Int = 3
        public var backoff = BackoffPolicy()
        public var offlineBackoff = BackoffPolicy(initialDelay: 5, multiplier: 2, maxDelay: 300, jitter: 0.2)

        public init(concurrency: Int = 1, maxAttempts: Int = 5, requestsPerMinute: Int = 30, burst: Int = 3) {
            self.concurrency = concurrency
            self.maxAttempts = maxAttempts
            self.requestsPerMinute = requestsPerMinute
            self.burst = burst
        }
    }

    /// A handler for queues that only process files: a `.reanalyze` job fails at once.
    public typealias Handler = @Sendable (URL) async throws -> Void
    /// A handler that dispatches on the job's kind and also gets its user upload request (nil for watcher jobs).
    public typealias JobHandler = @Sendable (QueueJob, UserUploadRequest?) async throws -> Void

    public private(set) var configuration: Configuration
    private let clock: QueueClock
    private let random: @Sendable () -> Double
    private let probe: (@Sendable () async -> Bool)?
    private let handler: JobHandler

    private var pending: [QueueJob] = []
    /// Waiting jobs added `atFront`; they sit at the head of `pending`, in the order they were added.
    private var frontJobs: Set<QueueJob> = []
    /// The user upload request each pending or running job carries, for the whole job.
    private var carried: [QueueJob: UserUploadRequest] = [:]
    private var inFlight: [QueueJob] = []
    /// Running jobs whose handler is executing right now (an attempt was sent); a pause lets it finish.
    private var attempting: Set<QueueJob> = []
    private var activeWorkers = 0
    private var bucket: TokenBucket
    private var userPaused = false
    private var pausedUntil: Date?
    private var pauseGeneration = 0
    private var holdMessage: String?
    private var offline = false
    private var offlineStreak = 0
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var subscribers: [UUID: AsyncStream<QueueStatus>.Continuation] = [:]
    private var jobSubscribers: [UUID: AsyncStream<[QueueJob: QueueJobState]>.Continuation] = [:]

    public private(set) var status: QueueStatus = .idle
    /// Every queued or running job and where it is. Jobs that ended are absent: their handler saw the result.
    public private(set) var jobStates: [QueueJob: QueueJobState] = [:]
    public private(set) var succeededCount = 0
    public private(set) var failedCount = 0
    /// Last permanent failure of a `.process` job, for the menu bar ("last error"). A `.reanalyze` job's outcome
    /// reaches the app through its handler.
    public private(set) var lastFailure: (url: URL, message: String)?

    /// - Parameters:
    ///   - probe: optional cheap reachability check (e.g. GET the local server's `/health`). Without it the queue
    ///     retries the job itself after each offline wait.
    ///   - random: [0, 1) source for jitter; inject a constant in tests.
    public init(configuration: Configuration = Configuration(), clock: QueueClock = SystemQueueClock(),
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
                probe: (@Sendable () async -> Bool)? = nil, handler: @escaping Handler) {
        self.init(configuration: configuration, clock: clock, random: random, probe: probe,
                  jobHandler: { job, _ in
            guard case .process(let url) = job else { throw QueueJobError.noReanalyzeHandler }
            try await handler(url)
        })
    }

    public init(configuration: Configuration = Configuration(), clock: QueueClock = SystemQueueClock(),
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
                probe: (@Sendable () async -> Bool)? = nil, jobHandler: @escaping JobHandler) {
        self.configuration = configuration
        self.clock = clock
        self.random = random
        self.probe = probe
        self.handler = jobHandler
        self.bucket = TokenBucket(requestsPerMinute: configuration.requestsPerMinute, burst: configuration.burst)
    }

    // MARK: - Public API

    /// Adds a job unless the same job (kind and key) is already queued or running.
    /// - Parameters:
    ///   - atFront: place it after other front jobs but before every other waiting job (Analyze Again ahead of a
    ///     Process Existing run). It never pre-empts a running job and still takes a rate-limit token. A job already
    ///     waiting keeps its place.
    ///   - userRequest: the user's request to send this file (`UserUploadRequest`). A job still waiting takes it on; a
    ///     running job does not (its attempts already started without it), and nothing is kept for later.
    public func enqueue(_ job: QueueJob, atFront: Bool = false, userRequest: UserUploadRequest? = nil) {
        let job = job.standardized
        guard !inFlight.contains(job) else { return }
        if let userRequest { carried[job] = userRequest }
        guard !pending.contains(job) else { return }
        if atFront {
            pending.insert(job, at: pending.prefix(while: frontJobs.contains).count)
            frontJobs.insert(job)
        } else {
            pending.append(job)
        }
        spawnWorkers()
        publish()
    }

    /// User upload requests carried by queued or running jobs (tests).
    public var carriedRequestCount: Int { carried.count }

    public var queuedCount: Int { pending.count + inFlight.count }

    /// Stops starting new jobs (the current one finishes). `until == nil` pauses until `resume()`.
    public func pause(until: Date? = nil) {
        userPaused = true
        pausedUntil = until
        pauseGeneration += 1
        if let until {
            let generation = pauseGeneration
            let clock = self.clock
            Task {
                let wait = until.timeIntervalSince(clock.now())
                if wait > 0 { try? await clock.sleep(seconds: wait) }
                self.autoResume(generation: generation)
            }
        }
        publish()
    }

    /// Changes the request rate in place. Queued jobs, pause and hold state are kept: rebuilding the queue instead
    /// would have to hand its jobs over, and resuming the old queue to drain them would bypass a user pause.
    public func setRequestsPerMinute(_ requestsPerMinute: Int) {
        guard requestsPerMinute != configuration.requestsPerMinute else { return }
        configuration.requestsPerMinute = requestsPerMinute
        bucket = TokenBucket(requestsPerMinute: requestsPerMinute, burst: configuration.burst)
    }

    /// Clears a user pause and an `.error` hold.
    public func resume() {
        userPaused = false
        pausedUntil = nil
        pauseGeneration += 1
        holdMessage = nil
        openGate()
        publish()
    }

    /// A new stream per caller; it starts with the current status.
    public func statusUpdates() -> AsyncStream<QueueStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: QueueStatus.self, bufferingPolicy: .bufferingNewest(32))
        let id = UUID()
        subscribers[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { _ in Task { await self.removeSubscriber(id) } }
        return stream
    }

    /// A new stream per caller of `jobStates`, starting with the current value; yields on every change.
    public func jobStateUpdates() -> AsyncStream<[QueueJob: QueueJobState]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [QueueJob: QueueJobState].self,
                                                            bufferingPolicy: .bufferingNewest(32))
        let id = UUID()
        jobSubscribers[id] = continuation
        continuation.yield(jobStates)
        continuation.onTermination = { _ in Task { await self.removeSubscriber(id) } }
        return stream
    }

    /// Returns when nothing is queued or running. While paused or held with jobs queued, it waits for that to clear.
    public func waitUntilIdle() async {
        if pending.isEmpty && inFlight.isEmpty && activeWorkers == 0 { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    // MARK: - Workers

    private func spawnWorkers() {
        while activeWorkers < max(1, configuration.concurrency), activeWorkers < pending.count + inFlight.count {
            activeWorkers += 1
            Task { await self.workerLoop() }
        }
    }

    private func workerLoop() async {
        while !pending.isEmpty {
            await waitForGate()
            guard !pending.isEmpty else { break }
            let job = pending.removeFirst()
            frontJobs.remove(job)
            inFlight.append(job)
            publish()
            await run(job)
            carried[job] = nil // the job ended (done, failed or given up): its request goes with it
            inFlight.removeAll { $0 == job }
            publish()
        }
        activeWorkers -= 1
        if activeWorkers == 0, pending.isEmpty, inFlight.isEmpty {
            let waiters = idleWaiters
            idleWaiters = []
            waiters.forEach { $0.resume() }
        }
        publish()
    }

    private func run(_ job: QueueJob) async {
        var failures = 0
        while true {
            await waitForGate()
            let wait = bucket.reserve(at: clock.now())
            if wait > 0 { try? await clock.sleep(seconds: wait) }
            do {
                try await attempt(job)
                offlineStreak = 0
                succeededCount += 1
                return
            } catch let error as AnalyzerError {
                switch error {
                case .unreachable:
                    await holdOffline()
                case .unauthorized, .notConfigured, .accountState:
                    // Shown in the menu: readable text, never the server's response body.
                    holdMessage = UserFacingError.problem(for: error).message
                    publish()
                case .rateLimited, .serverError:
                    failures += 1
                    if failures >= configuration.maxAttempts {
                        fail(job, "gave up after \(failures) attempts: \(error)")
                        return
                    }
                    let delay: Double
                    if case .rateLimited(let retryAfter?) = error, retryAfter >= 0 {
                        delay = retryAfter
                    } else {
                        delay = configuration.backoff.delay(forAttempt: failures, random: random())
                    }
                    try? await clock.sleep(seconds: delay)
                case .badRequest, .invalidResponse:
                    fail(job, "\(error)")
                    return
                }
            } catch {
                fail(job, "\(error)")
                return
            }
        }
    }

    /// One call of the handler. The job counts as attempting only while it runs, so a hold that follows shows.
    private func attempt(_ job: QueueJob) async throws {
        attempting.insert(job)
        publish()
        defer { attempting.remove(job) }
        try await handler(job, carried[job])
    }

    private func holdOffline() async {
        offline = true
        publish()
        while true {
            offlineStreak += 1
            try? await clock.sleep(seconds: configuration.offlineBackoff.delay(forAttempt: offlineStreak, random: random()))
            guard let probe else { break }
            if await probe() { break }
        }
        offline = false
        openGate()
        publish()
    }

    private func fail(_ job: QueueJob, _ message: String) {
        failedCount += 1
        if case .process(let url) = job { lastFailure = (url, message) }
    }

    // MARK: - Gate and status

    private var gateOpen: Bool { !userPaused && holdMessage == nil && !offline }

    private func waitForGate() async {
        while !gateOpen {
            await withCheckedContinuation { gateWaiters.append($0) }
        }
    }

    private func openGate() {
        let waiters = gateWaiters
        gateWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func autoResume(generation: Int) {
        guard generation == pauseGeneration, userPaused else { return }
        userPaused = false
        pausedUntil = nil
        openGate()
        publish()
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
        jobSubscribers[id] = nil
    }

    /// What holds the queue, in the order the menu shows it.
    private var hold: QueueHold? {
        if let holdMessage { return .needsAttention(holdMessage) }
        if userPaused { return .paused(until: pausedUntil) }
        if offline { return .offline }
        return nil
    }

    private func publish() {
        publishJobStates()
        let next: QueueStatus
        if let hold {
            switch hold {
            case .needsAttention(let message): next = .error(message)
            case .paused(let until): next = .paused(until: until)
            case .offline: next = .offline
            }
        } else if let current = inFlight.last ?? pending.first {
            next = .processing(current: current.fileURL, remaining: pending.count + inFlight.count - 1)
        } else {
            next = .idle
        }
        guard next != status else { return }
        status = next
        for continuation in subscribers.values { continuation.yield(next) }
    }

    private func publishJobStates() {
        let hold = self.hold
        var next: [QueueJob: QueueJobState] = [:]
        for job in pending { next[job] = hold.map(QueueJobState.held) ?? .queued }
        for job in inFlight { next[job] = attempting.contains(job) ? .running : hold.map(QueueJobState.held) ?? .running }
        guard next != jobStates else { return }
        jobStates = next
        for continuation in jobSubscribers.values { continuation.yield(next) }
    }
}
