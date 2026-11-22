import Foundation

/// Runs jobs (screenshot URLs) through a handler, usually `ScreenshotProcessor.process`.
///
/// - Concurrency 1 by default. Duplicate URLs already queued or in flight are ignored.
/// - Every attempt first takes a token from a requests-per-minute `TokenBucket`.
/// - `AnalyzerError.rateLimited` / `.serverError`: retry after `retryAfter` (when given) or exponential backoff with
///   jitter, up to `maxAttempts` calls; then the job fails (the processor has already recorded the error in the index).
/// - `AnalyzerError.unreachable`: the queue goes `.offline` and holds; it waits with its own backoff and probes
///   (`probe`, or by retrying the job). Offline time does not use up attempts.
/// - `AnalyzerError.unauthorized` / `.notConfigured`: the queue holds in `.error(message)` until `resume()`;
///   the job is kept, not failed, so nothing is lost while the user fixes credentials.
/// - Any other error fails the job at once.
/// - A job may carry a `ProcessExistingRequest` (`enqueue(_:processExisting:)`): every attempt of that job gets it,
///   retries and holds included, and it is dropped when the job ends.
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

    public typealias Handler = @Sendable (URL) async throws -> Void
    /// A handler that also gets the job's Process Existing request (nil for watcher jobs).
    public typealias JobHandler = @Sendable (URL, ProcessExistingRequest?) async throws -> Void

    public private(set) var configuration: Configuration
    private let clock: QueueClock
    private let random: @Sendable () -> Double
    private let probe: (@Sendable () async -> Bool)?
    private let handler: JobHandler

    private var pending: [URL] = []
    /// The Process Existing request each pending or running job carries, for the whole job.
    private var carried: [URL: ProcessExistingRequest] = [:]
    private var inFlight: [URL] = []
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

    public private(set) var status: QueueStatus = .idle
    public private(set) var succeededCount = 0
    public private(set) var failedCount = 0
    /// Last permanent failure, for the menu bar ("last error").
    public private(set) var lastFailure: (url: URL, message: String)?

    /// - Parameters:
    ///   - probe: optional cheap reachability check (e.g. GET the local server's `/health`). Without it the queue
    ///     retries the job itself after each offline wait.
    ///   - random: [0, 1) source for jitter; inject a constant in tests.
    public init(configuration: Configuration = Configuration(), clock: QueueClock = SystemQueueClock(),
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
                probe: (@Sendable () async -> Bool)? = nil, handler: @escaping Handler) {
        self.init(configuration: configuration, clock: clock, random: random, probe: probe,
                  jobHandler: { url, _ in try await handler(url) })
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

    /// Adds a job unless the URL is already queued or running.
    /// - Parameter processExisting: the user's Process Existing request for this file. A job still waiting takes it
    ///   on; a running job does not (its attempts already started without it), and nothing is kept for later.
    public func enqueue(_ url: URL, processExisting: ProcessExistingRequest? = nil) {
        let url = url.standardizedFileURL
        guard !inFlight.contains(url) else { return }
        if let processExisting { carried[url] = processExisting }
        guard !pending.contains(url) else { return }
        pending.append(url)
        spawnWorkers()
        publish()
    }

    /// Process Existing requests carried by queued or running jobs (tests).
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
            let url = pending.removeFirst()
            inFlight.append(url)
            publish()
            await run(url)
            carried[url] = nil // the job ended (done, failed or given up): its request goes with it
            inFlight.removeAll { $0 == url }
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

    private func run(_ url: URL) async {
        var failures = 0
        while true {
            await waitForGate()
            let wait = bucket.reserve(at: clock.now())
            if wait > 0 { try? await clock.sleep(seconds: wait) }
            do {
                try await handler(url, carried[url])
                offlineStreak = 0
                succeededCount += 1
                return
            } catch let error as AnalyzerError {
                switch error {
                case .unreachable:
                    await holdOffline()
                case .unauthorized, .notConfigured:
                    // Shown in the menu: readable text, never the server's response body.
                    holdMessage = UserFacingError.problem(for: error).message
                    publish()
                case .rateLimited, .serverError:
                    failures += 1
                    if failures >= configuration.maxAttempts {
                        fail(url, "gave up after \(failures) attempts: \(error)")
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
                    fail(url, "\(error)")
                    return
                }
            } catch {
                fail(url, "\(error)")
                return
            }
        }
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

    private func fail(_ url: URL, _ message: String) {
        failedCount += 1
        lastFailure = (url, message)
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
    }

    private func publish() {
        let next: QueueStatus
        if let holdMessage {
            next = .error(holdMessage)
        } else if userPaused {
            next = .paused(until: pausedUntil)
        } else if offline {
            next = .offline
        } else if let current = inFlight.last ?? pending.first {
            next = .processing(current: current, remaining: pending.count + inFlight.count - 1)
        } else {
            next = .idle
        }
        guard next != status else { return }
        status = next
        for continuation in subscribers.values { continuation.yield(next) }
    }
}
