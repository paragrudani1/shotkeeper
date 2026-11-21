import Foundation

/// When to stop the managed local model server to give memory back.
public struct IdlePolicy: Sendable, Equatable {
    /// Seconds without work before stopping; `<= 0` = never stop.
    public var timeout: TimeInterval

    public init(timeout: TimeInterval) { self.timeout = timeout }
    public init(idleTimeoutMinutes: Int) { self.timeout = TimeInterval(idleTimeoutMinutes) * 60 }

    /// Stop when nothing is in flight and the last activity is at least `timeout` ago.
    public func shouldStop(lastActivity: Date, now: Date, inFlight: Int) -> Bool {
        timeout > 0 && inFlight == 0 && now.timeIntervalSince(lastActivity) >= timeout
    }

    /// When to check again (nil = never).
    public func nextCheck(lastActivity: Date) -> Date? {
        timeout > 0 ? lastActivity.addingTimeInterval(timeout) : nil
    }
}

/// Crash handling for the managed server: restart with backoff, give up after `maxCrashes` within `window`.
public struct RestartPolicy: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        case restart(after: TimeInterval)
        /// Stop restarting; show the error and let the user retry (call `reset()`).
        case giveUp
    }

    public var maxCrashes: Int
    public var window: TimeInterval
    public var backoff: BackoffPolicy
    public private(set) var crashes: [Date] = []

    public init(maxCrashes: Int = 3, window: TimeInterval = 600,
                backoff: BackoffPolicy = BackoffPolicy(initialDelay: 2, multiplier: 2, maxDelay: 60, jitter: 0)) {
        self.maxCrashes = maxCrashes
        self.window = window
        self.backoff = backoff
    }

    /// Record an unexpected exit at `now` and decide what to do.
    public mutating func recordCrash(at now: Date) -> Decision {
        crashes = crashes.filter { now.timeIntervalSince($0) < window } + [now]
        if crashes.count >= maxCrashes { return .giveUp }
        return .restart(after: backoff.delay(forAttempt: crashes.count, random: 0.5))
    }

    /// After the user retries, or after a clean stop.
    public mutating func reset() { crashes = [] }
}
