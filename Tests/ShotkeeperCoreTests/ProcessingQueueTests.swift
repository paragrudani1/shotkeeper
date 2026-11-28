import XCTest
@testable import ShotkeeperCore

final class QueuePrimitivesTests: XCTestCase {
    func testBackoffGrowsCapsAndJitters() {
        let policy = BackoffPolicy(initialDelay: 2, multiplier: 2, maxDelay: 10, jitter: 0.2)
        XCTAssertEqual(policy.delay(forAttempt: 1, random: 0.5), 2)
        XCTAssertEqual(policy.delay(forAttempt: 2, random: 0.5), 4)
        XCTAssertEqual(policy.delay(forAttempt: 3, random: 0.5), 8)
        XCTAssertEqual(policy.delay(forAttempt: 4, random: 0.5), 10)
        XCTAssertEqual(policy.delay(forAttempt: 9, random: 0.5), 10)
        XCTAssertEqual(policy.delay(forAttempt: 1, random: 0), 1.6, accuracy: 1e-9)
        XCTAssertEqual(policy.delay(forAttempt: 1, random: 1), 2.4, accuracy: 1e-9)
    }

    func testTokenBucket() {
        let t0 = Date(timeIntervalSince1970: 0)
        var bucket = TokenBucket(requestsPerMinute: 60, burst: 2)
        XCTAssertEqual(bucket.reserve(at: t0), 0)
        XCTAssertEqual(bucket.reserve(at: t0), 0)
        XCTAssertEqual(bucket.reserve(at: t0), 1, accuracy: 1e-9)
        XCTAssertEqual(bucket.reserve(at: t0), 2, accuracy: 1e-9, "waiters queue up")
        XCTAssertEqual(bucket.reserve(at: t0.addingTimeInterval(10)), 0, "refilled (capped at burst)")
        XCTAssertEqual(bucket.reserve(at: t0.addingTimeInterval(10)), 0)
        XCTAssertEqual(bucket.reserve(at: t0.addingTimeInterval(10)), 1, accuracy: 1e-9)

        var unlimited = TokenBucket(requestsPerMinute: 0)
        for _ in 0..<100 { XCTAssertEqual(unlimited.reserve(at: t0), 0) }
    }
}

final class ProcessingQueueTests: XCTestCase {
    let a = URL(fileURLWithPath: "/shots/a.png")
    let b = URL(fileURLWithPath: "/shots/b.png")
    let c = URL(fileURLWithPath: "/shots/c.png")

    /// Handler that throws the scripted errors in order, then succeeds.
    private func scripted(_ errors: [Error]) -> (handler: ProcessingQueue.Handler, calls: Locked<[URL]>) {
        let script = Locked(errors)
        let calls = Locked<[URL]>([])
        return ({ url in
            calls.mutate { $0.append(url) }
            if let error = script.mutate({ $0.isEmpty ? nil : $0.removeFirst() }) { throw error }
        }, calls)
    }

    private func makeQueue(_ handler: @escaping ProcessingQueue.Handler, clock: FakeClock, maxAttempts: Int = 5,
                           rpm: Int = 0, burst: Int = 3, probe: (@Sendable () async -> Bool)? = nil) -> ProcessingQueue {
        ProcessingQueue(configuration: .init(maxAttempts: maxAttempts, requestsPerMinute: rpm, burst: burst),
                        clock: clock, random: { 0.5 }, probe: probe, handler: handler)
    }

    private func waitForStatus(_ queue: ProcessingQueue, _ predicate: (QueueStatus) -> Bool) async -> QueueStatus {
        for _ in 0..<2000 {
            let status = await queue.status
            if predicate(status) { return status }
            await Task.yield()
        }
        return await queue.status
    }

    func testProcessesInOrderAndDeduplicates() async {
        let (handler, calls) = scripted([])
        let queue = makeQueue(handler, clock: FakeClock())
        await queue.pause()  // keep jobs queued so the duplicate arrives while `a` is still pending
        await queue.enqueue(.process(a))
        await queue.enqueue(.process(b))
        await queue.enqueue(.process(a))
        let queued = await queue.queuedCount
        XCTAssertEqual(queued, 2)
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get, [a, b])
        let status = await queue.status
        XCTAssertEqual(status, .idle)
        let succeeded = await queue.succeededCount
        XCTAssertEqual(succeeded, 2)
    }

    func testRetryableErrorsBackOffExponentially() async {
        let clock = FakeClock()
        let (handler, calls) = scripted([AnalyzerError.serverError(status: 503, message: "busy"),
                                         AnalyzerError.serverError(status: 500, message: "oops")])
        let queue = makeQueue(handler, clock: clock)
        await queue.enqueue(.process(a))
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get.count, 3)
        XCTAssertEqual(clock.sleeps, [2, 4])
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 0)
    }

    func testRateLimitedRespectsRetryAfter() async {
        let clock = FakeClock()
        let (handler, calls) = scripted([AnalyzerError.rateLimited(retryAfter: 7), AnalyzerError.rateLimited(retryAfter: nil)])
        let queue = makeQueue(handler, clock: clock)
        await queue.enqueue(.process(a))
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get.count, 3)
        XCTAssertEqual(clock.sleeps, [7, 4], "retryAfter used as-is, then backoff for attempt 2")
    }

    func testGivesUpAfterMaxAttempts() async {
        let clock = FakeClock()
        let (handler, calls) = scripted(Array(repeating: AnalyzerError.serverError(status: 500, message: "x"), count: 10))
        let queue = makeQueue(handler, clock: clock, maxAttempts: 3)
        await queue.enqueue(.process(a))
        await queue.enqueue(.process(b))
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get, [a, a, a, b, b, b])
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 2)
        let lastFailure = await queue.lastFailure
        XCTAssertEqual(lastFailure?.url, b)
    }

    func testPermanentErrorsFailImmediately() async {
        let clock = FakeClock()
        let (handler, calls) = scripted([AnalyzerError.badRequest(status: 400, message: "no"),
                                         AnalyzerError.invalidResponse("junk"), CocoaError(.fileNoSuchFile)])
        let queue = makeQueue(handler, clock: clock)
        for url in [a, b, c] { await queue.enqueue(.process(url)) }
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get, [a, b, c])
        XCTAssertEqual(clock.sleeps, [])
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 3)
    }

    func testTokenBucketSpacesRequests() async {
        let clock = FakeClock()
        let (handler, calls) = scripted([])
        let queue = makeQueue(handler, clock: clock, rpm: 60, burst: 1)
        for url in [a, b, c] { await queue.enqueue(.process(url)) }
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get.count, 3)
        XCTAssertEqual(clock.sleeps, [1, 1])
    }

    func testPauseHoldsUntilResume() async {
        let (handler, calls) = scripted([])
        let queue = makeQueue(handler, clock: FakeClock())
        await queue.pause()
        await queue.enqueue(.process(a))
        await queue.enqueue(.process(b))
        await settle()
        XCTAssertEqual(calls.get, [])
        let status = await queue.status
        XCTAssertEqual(status, .paused(until: nil))
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get, [a, b])
    }

    func testTimedPauseResumesByItself() async {
        let clock = FakeClock()
        let (handler, calls) = scripted([])
        let queue = makeQueue(handler, clock: clock)
        await queue.pause(until: clock.now().addingTimeInterval(600))
        await queue.enqueue(.process(a))
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get, [a])
        XCTAssertEqual(clock.sleeps, [600])
    }

    func testOfflineHoldsWithoutUsingAttempts() async {
        let clock = FakeClock()
        let (handler, calls) = scripted([AnalyzerError.unreachable("refused"), AnalyzerError.unreachable("refused")])
        let queue = makeQueue(handler, clock: clock, maxAttempts: 1)
        let seen = Locked<[QueueStatus]>([])
        let updates = await queue.statusUpdates()
        let watcher = Task { for await status in updates { seen.mutate { $0.append(status) } } }
        await queue.enqueue(.process(a))
        await queue.waitUntilIdle()
        await settle()
        watcher.cancel()
        XCTAssertEqual(calls.get.count, 3, "offline retries do not count against maxAttempts=1")
        XCTAssertEqual(clock.sleeps, [5, 10], "offline backoff")
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 0)
        XCTAssertTrue(seen.get.contains(.offline), "\(seen.get)")
        XCTAssertEqual(seen.get.first, .idle)
        XCTAssertEqual(seen.get.last, .idle)
    }

    func testOfflineProbesBeforeRetrying() async {
        let clock = FakeClock()
        let probes = Locked([false, false, true])
        let (handler, calls) = scripted([AnalyzerError.unreachable("down")])
        let queue = makeQueue(handler, clock: clock, probe: { probes.mutate { $0.removeFirst() } })
        await queue.enqueue(.process(a))
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get.count, 2, "the job is retried only once the probe succeeds")
        XCTAssertEqual(clock.sleeps, [5, 10, 20])
    }

    func testUnauthorizedHoldsInErrorUntilResume() async {
        let (handler, calls) = scripted([AnalyzerError.unauthorized("HTTP 401: {\"errors\":[{\"message\":\"bad token\"}]}")])
        let queue = makeQueue(handler, clock: FakeClock())
        await queue.enqueue(.process(a))
        await queue.enqueue(.process(b))
        let held = QueueStatus.error("the model backend rejected the token")
        let status = await waitForStatus(queue) { $0 == held }
        XCTAssertEqual(status, held, "the menu shows readable text, never the server's response body")
        await settle()
        XCTAssertEqual(calls.get, [a], "held: nothing else runs")
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get, [a, a, b])
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 0)
    }

    /// Out of credits / a spending limit (OpenRouter 402 without Retry-After, 403 budget): an account state the user
    /// fixes on the provider's site. The queue holds with Shotkeeper's own text and Resume continues.
    func testAccountStateHoldsUntilResume() async {
        for text in [OpenRouterBackend.outOfCreditsText, OpenRouterBackend.spendingLimitText] {
            let (handler, calls) = scripted([AnalyzerError.accountState(text)])
            let queue = makeQueue(handler, clock: FakeClock())
            await queue.enqueue(.process(a))
            await queue.enqueue(.process(b))
            let held = QueueStatus.error(text)
            let status = await waitForStatus(queue) { $0 == held }
            XCTAssertEqual(status, held)
            await settle()
            XCTAssertEqual(calls.get, [a], "held: nothing else runs, nothing is marked failed")
            await queue.resume()
            await queue.waitUntilIdle()
            XCTAssertEqual(calls.get, [a, a, b])
            let failed = await queue.failedCount
            XCTAssertEqual(failed, 0)
        }
        XCTAssertEqual(OpenRouterBackend.outOfCreditsText, "OpenRouter is out of credits. Add credits, then choose Resume")
    }

    /// Changing the rate must not drop or release queued jobs: a paused queue stays paused with its jobs.
    func testSetRequestsPerMinuteKeepsPauseAndJobsAndAppliesTheNewRate() async {
        let (handler, calls) = scripted([])
        let clock = FakeClock()
        let queue = makeQueue(handler, clock: clock, rpm: 60, burst: 1)
        await queue.pause()
        await queue.enqueue(.process(a))
        await queue.enqueue(.process(b))
        await queue.setRequestsPerMinute(6)
        await settle()
        XCTAssertEqual(calls.get, [], "still paused")
        let status = await queue.status
        XCTAssertEqual(status, .paused(until: nil))
        let rate = await queue.configuration.requestsPerMinute
        XCTAssertEqual(rate, 6)
        let queued = await queue.queuedCount
        XCTAssertEqual(queued, 2)
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get, [a, b])
        XCTAssertTrue(clock.sleeps.contains { abs($0 - 10) < 0.01 }, "6/min, burst 1: second job waits 10 s; \(clock.sleeps)")
    }

    func testProcessingStatusReportsRemaining() async {
        let gate = Locked<CheckedContinuation<Void, Never>?>(nil)
        let queue = ProcessingQueue(configuration: .init(requestsPerMinute: 0), clock: FakeClock()) { _ in
            await withCheckedContinuation { gate.set($0) }
        }
        await queue.enqueue(.process(a))
        await queue.enqueue(.process(b))
        let status = await waitForStatus(queue) { _ in gate.get != nil }
        XCTAssertEqual(status, .processing(current: a, remaining: 1))
        gate.mutate { let k = $0; $0 = nil; return k }?.resume()
        _ = await waitForStatus(queue) { _ in gate.get != nil }
        let second = await queue.status
        XCTAssertEqual(second, .processing(current: b, remaining: 0))
        gate.mutate { let k = $0; $0 = nil; return k }?.resume()
        await queue.waitUntilIdle()
    }

    /// Rendezvous instead of timing: the first job waits until a second job is running at the same time. With
    /// concurrency 1 the fallback releases it after 5 s and `peak` stays 1. (Was `settle(50)`, which was flaky on a
    /// 2-core CI runner: the first job could finish its yields before the second worker started.)
    func testConcurrencyRunsJobsInParallel() async {
        struct Rendezvous { var arrived = 0; var waiter: CheckedContinuation<Void, Never>?; var released = false }
        let running = Locked(0)
        let peak = Locked(0)
        let state = Locked(Rendezvous())
        @Sendable func release() {
            state.mutate { s -> CheckedContinuation<Void, Never>? in
                s.released = true
                defer { s.waiter = nil }
                return s.waiter
            }?.resume()
        }
        let fallback = Task { try? await Task.sleep(nanoseconds: 5_000_000_000); release() }
        let queue = ProcessingQueue(configuration: .init(concurrency: 2, requestsPerMinute: 0), clock: FakeClock()) { _ in
            let now = running.mutate { $0 += 1; return $0 }
            peak.mutate { $0 = max($0, now) }
            let arrival = state.mutate { $0.arrived += 1; return $0.arrived }
            if arrival == 1 {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let releasedAlready = state.mutate { s -> Bool in
                        if s.released { return true }
                        s.waiter = continuation
                        return false
                    }
                    if releasedAlready { continuation.resume() }
                }
            } else if arrival == 2 {
                release()
            }
            running.mutate { $0 -= 1 }
        }
        for url in [a, b, c] { await queue.enqueue(.process(url)) }
        await queue.waitUntilIdle()
        fallback.cancel()
        XCTAssertEqual(peak.get, 2)
    }

    // MARK: User upload requests carried by jobs (review 4 S1, S2)

    func testARequestIsGivenToEveryAttemptOfItsJobAndDroppedAfterIt() async throws {
        let request = UserUploadRequest(authorization: .init(target: .cloudflare), generation: 0)
        let seen = Locked<[UserUploadRequest?]>([])
        let failures = Locked(2)
        let queue = ProcessingQueue(configuration: .init(requestsPerMinute: 0), clock: FakeClock(), random: { 0.5 },
                                    jobHandler: { _, carried in
            seen.mutate { $0.append(carried) }
            if failures.mutate({ $0 -= 1; return $0 >= 0 }) { throw AnalyzerError.serverError(status: 503, message: "busy") }
        })
        await queue.enqueue(.process(a), userRequest: request)
        await queue.waitUntilIdle()
        XCTAssertEqual(seen.get, [request, request, request])
        let carried = await queue.carriedRequestCount
        XCTAssertEqual(carried, 0)
        await queue.enqueue(.process(a)) // a later file event for the same path
        await queue.waitUntilIdle()
        XCTAssertEqual(seen.get.last, .some(nil), "nothing left for a later job")
    }

    /// Review 4 S2: Process Existing twice while the file is in flight left a request behind for a later run.
    func testARequestForARunningJobIsNotKeptForLater() async throws {
        let request = UserUploadRequest(authorization: .init(target: .cloudflare), generation: 0)
        let seen = Locked<[UserUploadRequest?]>([])
        let started = Locked(false)
        let release = Locked(false)
        let queue = ProcessingQueue(configuration: .init(requestsPerMinute: 0), clock: FakeClock(), random: { 0.5 },
                                    jobHandler: { _, carried in
            seen.mutate { $0.append(carried) }
            started.set(true)
            while !release.get { try await Task.sleep(nanoseconds: 1_000_000) }
        })
        await queue.enqueue(.process(a), userRequest: request)
        for _ in 0..<2_000 where !started.get { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(started.get)
        await queue.enqueue(.process(a), userRequest: request) // the second Process Existing while in flight
        let carriedWhileRunning = await queue.carriedRequestCount
        XCTAssertEqual(carriedWhileRunning, 1, "only the running job's own request")
        release.set(true)
        await queue.waitUntilIdle()
        let carried = await queue.carriedRequestCount
        XCTAssertEqual(carried, 0, "nothing stale")
        await queue.enqueue(.process(a))
        await queue.waitUntilIdle()
        XCTAssertEqual(seen.get, [request, nil], "a later run gets the normal time rule")
    }

    func testAWaitingJobTakesOnALaterRequest() async throws {
        let request = UserUploadRequest(authorization: .init(target: .cloudflare), generation: 0)
        let seen = Locked<[UserUploadRequest?]>([])
        let queue = ProcessingQueue(configuration: .init(requestsPerMinute: 0), clock: FakeClock(), random: { 0.5 },
                                    jobHandler: { _, carried in seen.mutate { $0.append(carried) } })
        await queue.pause()
        await queue.enqueue(.process(a)) // the watcher
        await queue.enqueue(.process(a), userRequest: request) // then Process Existing, before it ran
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(seen.get, [request])
    }

    // MARK: Job kinds (wave 2 ticket 03: Analyze Again runs through the queue)

    /// Records every attempt's job and request; `block` holds the first attempt of `blockedJob` until released.
    private final class JobRecorder: @unchecked Sendable {
        let calls = Locked<[QueueJob]>([])
        let requests = Locked<[UserUploadRequest?]>([])
        let errors: Locked<[Error]>
        private let gate = Locked<(job: QueueJob?, waiter: CheckedContinuation<Void, Never>?, released: Bool)>((nil, nil, false))

        init(errors: [Error] = [], blocking job: QueueJob? = nil) {
            self.errors = Locked(errors)
            gate.mutate { $0.job = job }
        }

        var handler: ProcessingQueue.JobHandler {
            { job, request in
                self.calls.mutate { $0.append(job) }
                self.requests.mutate { $0.append(request) }
                if self.gate.get.job == job, !self.gate.get.released {
                    await withCheckedContinuation { continuation in
                        let releasedAlready = self.gate.mutate { g -> Bool in
                            if g.released { return true }
                            g.waiter = continuation
                            return false
                        }
                        if releasedAlready { continuation.resume() }
                    }
                }
                if let error = self.errors.mutate({ $0.isEmpty ? nil : $0.removeFirst() }) { throw error }
            }
        }

        var isBlocked: Bool { gate.get.waiter != nil }

        func release() {
            gate.mutate { g -> CheckedContinuation<Void, Never>? in
                g.released = true
                defer { g.waiter = nil }
                return g.waiter
            }?.resume()
        }
    }

    private func jobQueue(_ recorder: JobRecorder, clock: FakeClock = FakeClock(), maxAttempts: Int = 5, rpm: Int = 0,
                          burst: Int = 3) -> ProcessingQueue {
        ProcessingQueue(configuration: .init(maxAttempts: maxAttempts, requestsPerMinute: rpm, burst: burst),
                        clock: clock, random: { 0.5 }, jobHandler: recorder.handler)
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<2_000 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func testAProcessJobAndAReanalyzeJobOfTheRowAtThatURLAreDifferentJobs() async {
        let recorder = JobRecorder()
        let queue = jobQueue(recorder)
        await queue.pause()
        await queue.enqueue(.process(a))
        await queue.enqueue(.reanalyze(rowID: 7)) // row 7 is the screenshot at `a`
        let queued = await queue.queuedCount
        XCTAssertEqual(queued, 2)
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.calls.get, [.process(a), .reanalyze(rowID: 7)])
    }

    func testASecondReanalyzeOfAQueuedRowDoesNothing() async {
        let recorder = JobRecorder()
        let queue = jobQueue(recorder)
        await queue.pause()
        await queue.enqueue(.reanalyze(rowID: 7))
        await queue.enqueue(.reanalyze(rowID: 8))
        await queue.enqueue(.reanalyze(rowID: 7))
        let queued = await queue.queuedCount
        XCTAssertEqual(queued, 2)
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.calls.get, [.reanalyze(rowID: 7), .reanalyze(rowID: 8)])
    }

    func testASecondReanalyzeOfARunningRowDoesNothing() async {
        let recorder = JobRecorder(blocking: .reanalyze(rowID: 7))
        let queue = jobQueue(recorder)
        await queue.enqueue(.reanalyze(rowID: 7))
        await waitUntil { recorder.isBlocked }
        XCTAssertTrue(recorder.isBlocked)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        let queued = await queue.queuedCount
        XCTAssertEqual(queued, 1, "only the running job")
        recorder.release()
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.calls.get, [.reanalyze(rowID: 7)], "analyzed once, not charged twice (story 63)")
    }

    /// Story 52: Analyze Again goes ahead of a long Process Existing run, without pre-empting the running file, and
    /// still takes a rate-limit token.
    func testAFrontJobBehindFiftyWaitingJobsRunsNextAndStillTakesAToken() async {
        let files = (0...50).map { URL(fileURLWithPath: "/shots/\($0).png") }
        let recorder = JobRecorder(blocking: .process(files[0]))
        let clock = FakeClock()
        let queue = jobQueue(recorder, clock: clock, rpm: 60, burst: 1)
        for file in files { await queue.enqueue(.process(file)) }
        await waitUntil { recorder.isBlocked }
        XCTAssertTrue(recorder.isBlocked, "the first file is running")
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        recorder.release()
        await queue.waitUntilIdle()
        let calls = recorder.calls.get
        XCTAssertEqual(calls.count, 52)
        XCTAssertEqual(Array(calls.prefix(3)), [.process(files[0]), .reanalyze(rowID: 7), .process(files[1])],
                       "the running file finished first; the re-analysis ran next")
        XCTAssertEqual(Array(calls.dropFirst(2)), files.dropFirst().map { .process($0) }, "the rest keep their order")
        XCTAssertEqual(clock.sleeps, Array(repeating: 1, count: 51), "60/min, burst 1: every job after the first, the re-analysis too, waits for a token")
    }

    func testFrontJobsKeepTheOrderTheyWereAskedIn() async {
        let recorder = JobRecorder()
        let queue = jobQueue(recorder)
        await queue.pause()
        await queue.enqueue(.process(a))
        await queue.enqueue(.reanalyze(rowID: 1), atFront: true)
        await queue.enqueue(.reanalyze(rowID: 2), atFront: true)
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.calls.get, [.reanalyze(rowID: 1), .reanalyze(rowID: 2), .process(a)])
    }

    // The user request of an Analyze Again job lives as long as the job (review 4 rule, as for Process Existing).

    private let request = UserUploadRequest(authorization: .init(target: .cloudflare), generation: 3)

    /// After the job ends, a new job for the same row (Analyze Again pressed later without a request) gets none.
    private func assertDroppedAfterTheJob(_ queue: ProcessingQueue, _ recorder: JobRecorder,
                                          file: StaticString = #filePath, line: UInt = #line) async {
        let carried = await queue.carriedRequestCount
        XCTAssertEqual(carried, 0, "dropped when the job ended", file: file, line: line)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.requests.get.last, .some(nil), "nothing left for a later job", file: file, line: line)
    }

    func testAReanalyzeJobKeepsItsRequestThroughRetries() async {
        let recorder = JobRecorder(errors: [AnalyzerError.rateLimited(retryAfter: 2),
                                            AnalyzerError.serverError(status: 503, message: "busy")])
        let queue = jobQueue(recorder)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true, userRequest: request)
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.calls.get, Array(repeating: .reanalyze(rowID: 7), count: 3))
        XCTAssertEqual(recorder.requests.get, [request, request, request])
        await assertDroppedAfterTheJob(queue, recorder)
    }

    func testAReanalyzeJobKeepsItsRequestThroughAnOfflineHold() async {
        let recorder = JobRecorder(errors: [AnalyzerError.unreachable("refused")])
        let queue = jobQueue(recorder, maxAttempts: 1)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true, userRequest: request)
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.requests.get, [request, request])
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 0)
        await assertDroppedAfterTheJob(queue, recorder)
    }

    func testAReanalyzeJobKeepsItsRequestThroughANeedsAttentionHold() async {
        let recorder = JobRecorder(errors: [AnalyzerError.unauthorized("HTTP 401")])
        let queue = jobQueue(recorder)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true, userRequest: request)
        _ = await waitForStatus(queue) { if case .error = $0 { return true } else { return false } }
        let carriedWhileHeld = await queue.carriedRequestCount
        XCTAssertEqual(carriedWhileHeld, 1, "held, not failed: the request stays")
        await queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.requests.get, [request, request])
        await assertDroppedAfterTheJob(queue, recorder)
    }

    func testAFailedReanalyzeJobDropsItsRequest() async {
        let recorder = JobRecorder(errors: [AnalyzerError.badRequest(status: 400, message: "no")])
        let queue = jobQueue(recorder)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true, userRequest: request)
        await queue.waitUntilIdle()
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 1)
        await assertDroppedAfterTheJob(queue, recorder)
    }

    // MARK: Per-job state (the app maps a row id to queued / analyzing / held)

    func testJobStatesReportQueuedAndRunningAndForgetEndedJobs() async {
        let recorder = JobRecorder(blocking: .process(a))
        let queue = jobQueue(recorder)
        await queue.enqueue(.process(a))
        await queue.enqueue(.process(b))
        await waitUntil { recorder.isBlocked }
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        let states = await queue.jobStates
        XCTAssertEqual(states, [.process(a): .running, .reanalyze(rowID: 7): .queued, .process(b): .queued])
        recorder.release()
        await queue.waitUntilIdle()
        let after = await queue.jobStates
        XCTAssertEqual(after, [:], "done and failed jobs are no longer the queue's: the app has their result")
    }

    func testJobStatesReportTheHoldReason() async {
        let recorder = JobRecorder(errors: [AnalyzerError.unauthorized("HTTP 401")])
        let queue = jobQueue(recorder)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        await queue.enqueue(.process(a))
        _ = await waitForStatus(queue) { if case .error = $0 { return true } else { return false } }
        let hold = QueueHold.needsAttention("the model backend rejected the token")
        let held = await queue.jobStates
        XCTAssertEqual(held, [.reanalyze(rowID: 7): .held(hold), .process(a): .held(hold)])
        await queue.resume()
        await queue.waitUntilIdle()

        await queue.pause()
        await queue.enqueue(.reanalyze(rowID: 8), atFront: true)
        let paused = await queue.jobStates
        XCTAssertEqual(paused, [.reanalyze(rowID: 8): .held(.paused(until: nil))])
        await queue.resume()
        await queue.waitUntilIdle()
    }

    func testJobStatesReportAnOfflineHold() async {
        let online = Locked(false)
        let recorder = JobRecorder(errors: [AnalyzerError.unreachable("refused")])
        let queue = ProcessingQueue(configuration: .init(requestsPerMinute: 0), clock: FakeClock(), random: { 0.5 },
                                    probe: { await Task.yield(); return online.get }, jobHandler: recorder.handler)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        _ = await waitForStatus(queue) { $0 == .offline }
        let held = await queue.jobStates
        XCTAssertEqual(held, [.reanalyze(rowID: 7): .held(.offline)])
        online.set(true)
        await queue.waitUntilIdle()
        XCTAssertEqual(recorder.calls.get.count, 2)
    }

    /// Pause stops new attempts; the one already sent finishes, so it is still analyzing, not held.
    func testARunningAttemptIsStillRunningWhileTheQueueIsPaused() async {
        let recorder = JobRecorder(blocking: .reanalyze(rowID: 7))
        let queue = jobQueue(recorder)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        await queue.enqueue(.process(a))
        await waitUntil { recorder.isBlocked }
        await queue.pause()
        let states = await queue.jobStates
        XCTAssertEqual(states, [.reanalyze(rowID: 7): .running, .process(a): .held(.paused(until: nil))])
        recorder.release()
        await queue.resume()
        await queue.waitUntilIdle()
    }

    func testJobStateUpdatesStreamEachChange() async {
        let recorder = JobRecorder(blocking: .reanalyze(rowID: 7))
        let queue = jobQueue(recorder)
        let seen = Locked<[QueueJobState?]>([])
        let updates = await queue.jobStateUpdates()
        let watcher = Task {
            for await states in updates {
                seen.mutate { if $0.last != states[.reanalyze(rowID: 7)] { $0.append(states[.reanalyze(rowID: 7)]) } }
            }
        }
        await queue.pause()
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        await queue.resume()
        await waitUntil { recorder.isBlocked }
        recorder.release()
        await queue.waitUntilIdle()
        await waitUntil { seen.get.last == .some(nil) && seen.get.count > 1 }
        watcher.cancel()
        XCTAssertEqual(seen.get, [nil, .held(.paused(until: nil)), .queued, .running, nil])
    }

    func testAFileOnlyQueueFailsAReanalyzeJobAtOnce() async {
        let (handler, calls) = scripted([])
        let clock = FakeClock()
        let queue = makeQueue(handler, clock: clock)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        await queue.enqueue(.process(a))
        await queue.waitUntilIdle()
        XCTAssertEqual(calls.get, [a], "the file handler never sees a row")
        XCTAssertEqual(clock.sleeps, [], "not retried")
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 1)
        let lastFailure = await queue.lastFailure
        XCTAssertNil(lastFailure, "the menu's last error names files; a re-analysis reports through its handler")
    }

    func testProcessingStatusHasNoFileWhileAReanalyzeJobIsShown() async {
        let recorder = JobRecorder(blocking: .reanalyze(rowID: 7))
        let queue = jobQueue(recorder)
        await queue.enqueue(.reanalyze(rowID: 7), atFront: true)
        await queue.enqueue(.process(a))
        await waitUntil { recorder.isBlocked }
        let status = await queue.status
        XCTAssertEqual(status, .processing(current: nil, remaining: 1))
        recorder.release()
        await queue.waitUntilIdle()
    }
}
