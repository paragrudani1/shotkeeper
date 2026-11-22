import Foundation

/// Bytes, speed and time left for the local model download (Settings → Model), from samples of the bytes on disk.
///
/// Speed is measured over the last `window` seconds, so it follows the current rate instead of the average since
/// the start (a resumed download starts with gigabytes already on disk). A drop in bytes (files replaced, a new
/// download) starts the measurement again.
public struct DownloadStats: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public var time: Date
        public var bytes: Int64
    }

    public let totalBytes: Int64
    public let window: TimeInterval
    public private(set) var samples: [Sample] = []

    public init(totalBytes: Int64, window: TimeInterval = 10) {
        self.totalBytes = max(0, totalBytes)
        self.window = window
    }

    public mutating func record(bytes: Int64, at time: Date) {
        if let last = samples.last, bytes < last.bytes || time < last.time { samples.removeAll() }
        samples.append(Sample(time: time, bytes: bytes))
        // Keep one sample older than the window, so the window is always covered.
        while samples.count > 2, time.timeIntervalSince(samples[1].time) >= window { samples.removeFirst() }
    }

    public var bytesDone: Int64 { min(samples.last?.bytes ?? 0, totalBytes) }

    /// Bytes per second; nil until two samples at least 1 s apart.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let seconds = last.time.timeIntervalSince(first.time)
        guard seconds >= 1 else { return nil }
        return max(0, Double(last.bytes - first.bytes) / seconds)
    }

    /// Nil while the speed is unknown or zero (stalled: no honest estimate).
    public var secondsRemaining: TimeInterval? {
        guard let speed = bytesPerSecond, speed > 0 else { return nil }
        return Double(max(0, totalBytes - bytesDone)) / speed
    }

    /// "4.1 of 9.1 GB" (spec); "350 MB of 9.1 GB" below 1 GB.
    public var bytesText: String {
        let done = Double(bytesDone)
        let total = Self.gigabytes(Double(totalBytes))
        if done < 1_000_000_000 { return "\(Int((done / 1_000_000).rounded())) MB of \(total) GB" }
        return "\(Self.gigabytes(done)) of \(total) GB"
    }

    /// "12.3 MB/s", "850 KB/s"; nil while unknown.
    public var speedText: String? {
        guard let speed = bytesPerSecond else { return nil }
        if speed >= 1_000_000 { return String(format: "%.1f MB/s", speed / 1_000_000) }
        return "\(Int((speed / 1_000).rounded())) KB/s"
    }

    /// "About 6 min left", "About 1 h 20 min left", "Less than a minute left"; "Stalled" when nothing arrives.
    public var timeLeftText: String? {
        guard let speed = bytesPerSecond else { return nil }
        guard speed > 0, let seconds = secondsRemaining else { return "Stalled" }
        if seconds < 60 { return "Less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "About \(minutes) min left" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "About \(hours) h left" : "About \(hours) h \(rest) min left"
    }

    /// "4.1 of 9.1 GB · 12.3 MB/s · About 6 min left" (parts that are known).
    public var summary: String {
        ([bytesText] + [speedText, timeLeftText].compactMap { $0 }).joined(separator: " · ")
    }

    /// One decimal, decimal gigabytes (10^9 bytes, like the catalog and Finder).
    static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f", bytes / 1_000_000_000)
    }
}

/// Whether there is room for the local model before its download starts.
public enum DiskSpaceCheck {
    /// The Python environment with mlx-lm (estimate: mlx, transformers and their dependencies, about 1 GB).
    public static let runtimeEnvironmentBytes: Int64 = 1_000_000_000
    /// Kept free after the download, so the Mac does not run out of space (screenshots, swap).
    public static let safetyMarginBytes: Int64 = 2_000_000_000

    public enum Verdict: Equatable, Sendable {
        case enough
        /// `neededBytes` is what the install still writes plus the margin.
        case notEnough(neededBytes: Int64, availableBytes: Int64)

        /// "Not enough disk space: the download needs about 12.4 GB free, and this Mac has 6.2 GB. Free up 6.2 GB and
        /// try again."
        public var message: String? {
            guard case .notEnough(let needed, let available) = self else { return nil }
            let short = max(needed - available, 100_000_000)
            return "Not enough disk space: the download needs about \(DownloadStats.gigabytes(Double(needed))) GB free, "
                + "and this Mac has \(DownloadStats.gigabytes(Double(max(0, available)))) GB. "
                + "Free up \(DownloadStats.gigabytes(Double(short))) GB and try again."
        }
    }

    /// - Parameters:
    ///   - availableBytes: free space on the volume of the runtime folder; nil when it could not be read (the
    ///     download is then allowed: `hf download` itself fails cleanly when the disk fills up).
    ///   - downloadBytes: the model's size (catalog).
    ///   - alreadyOnDisk: bytes of this model already downloaded (a resumed download needs only the rest).
    ///   - needsRuntime: the Python environment is not installed yet.
    public static func evaluate(availableBytes: Int64?, downloadBytes: Int64, alreadyOnDisk: Int64,
                                needsRuntime: Bool) -> Verdict {
        guard let availableBytes else { return .enough }
        let remaining = max(0, downloadBytes - max(0, alreadyOnDisk))
        let needed = remaining + (needsRuntime ? runtimeEnvironmentBytes : 0) + safetyMarginBytes
        return availableBytes >= needed ? .enough : .notEnough(neededBytes: needed, availableBytes: availableBytes)
    }
}
