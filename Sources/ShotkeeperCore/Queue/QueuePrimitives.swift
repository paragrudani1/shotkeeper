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

/// What the menu bar shows.
public enum QueueStatus: Equatable, Sendable {
    case idle
    /// `remaining` counts queued and other in-flight jobs, not `current`.
    case processing(current: URL, remaining: Int)
    /// Paused by the user; nil = until resumed.
    case paused(until: Date?)
    /// The backend is unreachable; the queue is held and probing with backoff.
    case offline
    /// Held on an error that needs the user (bad credentials, backend not configured). `resume()` retries.
    case error(String)
}
