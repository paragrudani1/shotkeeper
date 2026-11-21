import Foundation

/// What the rename toast shows. The app renders it; all wording lives here so it is tested on Linux.
public enum ToastContent: Equatable, Sendable {
    case renamed(RenamedToast)
    case restored(RestoredToast)
    case batch(BatchToast)
    case error(ErrorToast)
}

/// One screenshot renamed (and/or moved).
public struct RenamedToast: Equatable, Sendable {
    /// Where the file was before Shotkeeper touched it.
    public var originalURL: URL
    /// Where it is now (after the pipeline, or after "Edit name").
    public var currentURL: URL
    /// Undo records to revert, oldest first: the pipeline's rename, then any "Edit name" renames.
    public var undoRecordIDs: [UUID]
    /// False when only the folder changed (rename off, move on).
    public var renamed: Bool

    public init(originalURL: URL, currentURL: URL, undoRecordIDs: [UUID], renamed: Bool = true) {
        self.originalURL = originalURL
        self.currentURL = currentURL
        self.undoRecordIDs = undoRecordIDs
        self.renamed = renamed
    }

    public var label: String { renamed ? "Renamed" : "Moved" }
    /// The new name without extension (also the text the edit field starts with, fully selected).
    public var name: String { Self.stem(currentURL) }
    public var subline: String { "was: \(Self.stem(originalURL))" }
    public var undoTitle: String { "Undo" }
    public var editTitle: String { "Edit name" }
    public var canUndo: Bool { !undoRecordIDs.isEmpty }

    /// After "Edit name" saved: the file has a new name and one more undo record.
    public func edited(to url: URL, undoRecordID: UUID?) -> RenamedToast {
        var copy = self
        copy.currentURL = url
        copy.renamed = true
        if let undoRecordID { copy.undoRecordIDs.append(undoRecordID) }
        return copy
    }

    static func stem(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }
}

/// After Undo / Undo All.
public struct RestoredToast: Equatable, Sendable {
    /// Paths the files are back at.
    public var restoredPaths: [String]
    /// Files that could not be put back (moved, renamed, or their old name is taken).
    public var failedCount: Int

    public init(restoredPaths: [String], failedCount: Int = 0) {
        self.restoredPaths = restoredPaths
        self.failedCount = failedCount
    }

    private var isSingle: Bool { restoredPaths.count == 1 && failedCount == 0 }

    public var label: String { isSingle ? "Original name restored" : "Original names restored" }
    public var title: String {
        if isSingle { return RenamedToast.stem(URL(fileURLWithPath: restoredPaths[0])) }
        let total = restoredPaths.count + failedCount
        return failedCount == 0 ? "Restored \(MenuText.screenshots(total))"
            : "Restored \(restoredPaths.count) of \(MenuText.screenshots(total))"
    }
    public var subline: String {
        if failedCount > 0 { return "\(failedCount) could not be restored: moved, renamed or name taken" }
        return isSingle ? "Shotkeeper will not rename this file again" : "Shotkeeper will not rename these files again"
    }
}

/// One summary for a burst (more than 3 files within 10 s) or a "Process existing screenshots" run.
public struct BatchToast: Equatable, Sendable {
    public var renamedCount: Int
    /// Skipped by exclude rules (privacy: never sent, renamed or indexed).
    public var excludedCount: Int
    /// Current paths of the renamed files, in processing order ("View in Search", thumbnails).
    public var renamedPaths: [String]
    /// Undo records of the renamed files, in processing order ("Undo All").
    public var undoRecordIDs: [UUID]

    public init(renamedCount: Int = 0, excludedCount: Int = 0, renamedPaths: [String] = [], undoRecordIDs: [UUID] = []) {
        self.renamedCount = renamedCount
        self.excludedCount = excludedCount
        self.renamedPaths = renamedPaths
        self.undoRecordIDs = undoRecordIDs
    }

    /// "Renamed 37 screenshots"
    public var title: String { "Renamed \(MenuText.screenshots(renamedCount))" }
    /// "2 skipped by your exclude rules", nil when none were skipped.
    public var subline: String? { excludedCount > 0 ? "\(excludedCount) skipped by your exclude rules" : nil }
    /// The newest three, for the stacked thumbnails (back to front).
    public var thumbnailPaths: [String] { Array(renamedPaths.suffix(3)) }
    public var primaryTitle: String { "View in Search" }
    public var undoTitle: String { "Undo All" }
    public var canUndo: Bool { !undoRecordIDs.isEmpty }
}

public struct ErrorToast: Equatable, Sendable {
    public enum Action: String, Equatable, Sendable { case rename, undo }

    public var action: Action
    public var problem: UserFacingProblem

    public init(_ action: Action, _ problem: UserFacingProblem) {
        self.action = action
        self.problem = problem
    }

    /// "Could not rename: Cloudflare API token is not set"
    public var title: String {
        switch action {
        case .rename: return "Could not rename: \(problem.message)"
        case .undo: return "Could not undo: \(problem.message)"
        }
    }
    /// "Fix Settings…" when the fix is in Settings, else nil.
    public var fixTitle: String? { problem.needsSettings ? "Fix Settings…" : nil }
}

/// What the pipeline reports to the toast.
public enum ScreenshotEvent: Equatable, Sendable {
    case processed(ProcessingReport)
    /// A processing error worth telling the user about (see `UserFacingError.shouldNotify`).
    case failed(originalURL: URL, problem: UserFacingProblem)
}

/// Decides which toast (if any) to show for each pipeline event: one toast per rename, but ONE summary when more
/// than `burstThreshold` files arrive within `burstWindow` seconds, or for every file of an explicit "Process
/// existing screenshots" run. Renamed/moved and excluded files count; already-indexed, missing, paused,
/// kept-name and restored files do not (and show no toast on their own).
public struct ToastBatcher: Sendable {
    public static let burstWindow: TimeInterval = 10
    /// More than this many counted files within `burstWindow` → summary.
    public static let burstThreshold = 3

    private struct Counted: Sendable {
        var at: Date
        var report: ProcessingReport
    }

    private var window: [Counted] = []
    private var burst: BatchToast?
    private var lastBurstEvent: Date?
    private var run: (pending: Set<String>, toast: BatchToast)?

    public init() {}

    /// Starts an explicit run: every listed file's event goes into one summary, however slowly they arrive.
    public mutating func beginRun(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        run = (Set(urls.map { $0.standardizedFileURL.path }), BatchToast())
    }

    /// Returns the toast to show now (replacing the current one), or nil to leave the current toast alone.
    public mutating func record(_ event: ScreenshotEvent, at now: Date) -> ToastContent? {
        switch event {
        case .failed(let url, let problem):
            finishRunItem(url.standardizedFileURL.path)
            return .error(ErrorToast(.rename, problem))
        case .processed(let report):
            let counts = Self.counts(report.outcome)
            let path = report.originalURL.standardizedFileURL.path
            if var current = run, current.pending.contains(path) {
                current.pending.remove(path)
                guard counts else {
                    run = current.pending.isEmpty ? nil : current
                    return nil
                }
                Self.add(report, to: &current.toast)
                run = current.pending.isEmpty ? nil : current
                return .batch(current.toast)
            }
            guard counts else { return nil }

            if var toast = burst, let last = lastBurstEvent, now.timeIntervalSince(last) <= Self.burstWindow {
                Self.add(report, to: &toast)
                burst = toast
                lastBurstEvent = now
                return .batch(toast)
            }
            burst = nil
            window = window.filter { now.timeIntervalSince($0.at) <= Self.burstWindow } + [Counted(at: now, report: report)]
            if window.count > Self.burstThreshold {
                var toast = BatchToast()
                for item in window { Self.add(item.report, to: &toast) }
                window = []
                burst = toast
                lastBurstEvent = now
                return .batch(toast)
            }
            guard case .processed(let finalURL, let renamed, _) = report.outcome else { return nil } // excluded alone: no toast
            return .renamed(RenamedToast(originalURL: report.originalURL, currentURL: finalURL,
                                         undoRecordIDs: report.undoRecordID.map { [$0] } ?? [], renamed: renamed))
        }
    }

    private mutating func finishRunItem(_ path: String) {
        guard var current = run, current.pending.remove(path) != nil else { return }
        run = current.pending.isEmpty ? nil : current
    }

    private static func counts(_ outcome: ProcessingOutcome) -> Bool {
        switch outcome {
        case .processed(_, let renamed, let moved): return renamed || moved
        case .skipped(.excluded): return true
        case .skipped: return false
        }
    }

    private static func add(_ report: ProcessingReport, to toast: inout BatchToast) {
        switch report.outcome {
        case .processed(let finalURL, _, _):
            toast.renamedCount += 1
            toast.renamedPaths.append(finalURL.standardizedFileURL.path)
            if let id = report.undoRecordID { toast.undoRecordIDs.append(id) }
        case .skipped(.excluded):
            toast.excludedCount += 1
        case .skipped:
            break
        }
    }
}

/// The toast's 4-second auto-close timer. Paused while the pointer is over the toast or while the user edits the
/// name; on resume it continues with what was left, but with at least `minimumAfterResume` so the toast does not
/// vanish the instant the pointer leaves.
public struct ToastCountdown: Equatable, Sendable {
    public static let defaultDuration: TimeInterval = 4
    public static let minimumAfterResume: TimeInterval = 1.5

    public let duration: TimeInterval
    private var remainingWhenPaused: TimeInterval
    /// Set while running: the moment it would reach zero.
    private var deadline: Date?

    public init(duration: TimeInterval = ToastCountdown.defaultDuration, startingAt now: Date) {
        self.duration = duration
        remainingWhenPaused = duration
        deadline = now.addingTimeInterval(duration)
    }

    public var isRunning: Bool { deadline != nil }

    public func remaining(at now: Date) -> TimeInterval {
        guard let deadline else { return remainingWhenPaused }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// 1 = full bar, 0 = closing.
    public func fraction(at now: Date) -> Double {
        duration > 0 ? remaining(at: now) / duration : 0
    }

    public func isExpired(at now: Date) -> Bool { isRunning && remaining(at: now) <= 0 }

    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        remainingWhenPaused = remaining(at: now)
        deadline = nil
    }

    public mutating func resume(at now: Date) {
        guard !isRunning else { return }
        let left = max(remainingWhenPaused, min(Self.minimumAfterResume, duration))
        remainingWhenPaused = left
        deadline = now.addingTimeInterval(left)
    }
}
