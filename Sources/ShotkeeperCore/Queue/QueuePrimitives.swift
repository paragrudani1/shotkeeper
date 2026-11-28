import Foundation

/// Time source for the queue and runtime policies. Tests inject a fake whose `sleep` returns at once.
public protocol QueueClock: Sendable {
    func now() -> Date
    func sleep(seconds: Double) async throws
}

public struct SystemQueueClock: QueueClock {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(seconds: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// Exponential backoff with symmetric jitter: `min(maxDelay, initialDelay * multiplier^(attempt-1)) * (1 ± jitter)`.
public struct BackoffPolicy: Sendable, Equatable {
    public var initialDelay: Double
    public var multiplier: Double
    public var maxDelay: Double
    /// 0...1: fraction of the delay added or removed at random.
    public var jitter: Double

    public init(initialDelay: Double = 2, multiplier: Double = 2, maxDelay: Double = 120, jitter: Double = 0.2) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    /// `attempt` is 1-based (delay after the first failure is `initialDelay`). `random` is in [0, 1).
    public func delay(forAttempt attempt: Int, random: Double) -> Double {
        let exponent = Double(max(0, attempt - 1))
        let base = min(maxDelay, initialDelay * pow(multiplier, exponent))
        let factor = 1 + jitter * (2 * min(max(random, 0), 1) - 1)
        return max(0, base * factor)
    }
}

/// Token bucket for "N requests per minute" with a small burst.
public struct TokenBucket: Sendable, Equatable {
    public let capacity: Double
    public let refillPerSecond: Double
    private var tokens: Double
    private var lastRefill: Date?

    /// `requestsPerMinute <= 0` disables limiting.
    public init(requestsPerMinute: Int, burst: Int = 3) {
        capacity = Double(max(1, burst))
        refillPerSecond = Double(max(0, requestsPerMinute)) / 60
        tokens = capacity
    }

    /// Takes one token and returns how many seconds to wait before using it (0 when one was available).
    /// Tokens can go negative: callers that reserve while waiting queue up behind each other.
    public mutating func reserve(at now: Date) -> Double {
        guard refillPerSecond > 0 else { return 0 }
        if let last = lastRefill {
            tokens = min(capacity, tokens + max(0, now.timeIntervalSince(last)) * refillPerSecond)
        }
        lastRefill = now
        tokens -= 1
        return tokens >= 0 ? 0 : -tokens / refillPerSecond
    }
}

/// One unit of work for `ProcessingQueue`. Two jobs are the same (and the second is ignored) only when kind and key
/// match: `.process(a)` and `.reanalyze` of the row at `a` are different jobs.
public enum QueueJob: Hashable, Sendable {
    /// Process this file: a new screenshot, a "Process Existing Screenshots…" candidate, or interrupted work.
    case process(URL)
    /// Analyze this indexed row again ("Analyze Again"). The row is looked up when the job runs.
    case reanalyze(rowID: Int64)

    /// File URLs compare standardized, so `/a/./b.png` and `/a/b.png` are one job.
    var standardized: QueueJob {
        if case .process(let url) = self { return .process(url.standardizedFileURL) }
        return self
    }

    /// The file of a `.process` job; nil for `.reanalyze`.
    var fileURL: URL? {
        if case .process(let url) = self { return url }
        return nil
    }
}

/// Where a queued or running job is, for per-row UI (Analyze Again: "Waiting to analyze…", "Analyzing…", held).
public enum QueueJobState: Equatable, Sendable {
    /// Waiting its turn.
    case queued
    /// Started: an attempt is being sent, or it is waiting between attempts (rate limit, 429/5xx backoff).
    case running
    /// The queue is held; the job waits for it. An attempt already sent when the user paused stays `.running`.
    case held(QueueHold)
}

/// Why the queue is held (the same reasons `QueueStatus` shows in the menu).
public enum QueueHold: Equatable, Sendable {
    /// Bad credentials, backend not configured, account state: "Needs attention" with readable text until `resume()`.
    case needsAttention(String)
    /// Paused by the user; nil = until resumed.
    case paused(until: Date?)
    /// The backend is unreachable; the queue probes with backoff.
    case offline
}

/// Why a job failed in the queue itself rather than in its handler.
public enum QueueJobError: Error, Equatable, Sendable {
    /// A `.reanalyze` job reached a queue built with a file-only `Handler`.
    case noReanalyzeHandler
}

/// What the menu bar shows.
public enum QueueStatus: Equatable, Sendable {
    case idle
    /// `remaining` counts queued and other in-flight jobs, not `current`. `current` is the file of the job shown
    /// (the running one, else the next); nil when that job is a `.reanalyze`, which has no file until it runs.
    case processing(current: URL?, remaining: Int)
    /// Paused by the user; nil = until resumed.
    case paused(until: Date?)
    /// The backend is unreachable; the queue is held and probing with backoff.
    case offline
    /// Held on an error that needs the user (bad credentials, backend not configured). `resume()` retries.
    case error(String)
}
