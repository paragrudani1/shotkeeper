import Foundation
import ShotkeeperCore

/// Menu-bar wording for `QueueStatus`, and user-facing text for errors. Pure, unit-tested.
enum StatusText {
    static func line(for status: QueueStatus, now: Date = Date(), calendar: Calendar = .current,
                     locale: Locale = .current) -> String {
        switch status {
        case .idle:
            return "Idle: watching for screenshots"
        case .processing(_, let remaining):
            let left = remaining + 1
            return "Processing: \(left) left"
        case .paused(let until?):
            if until <= now { return "Resuming…" }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = calendar.isDate(until, inSameDayAs: now) ? .none : .short
            formatter.timeStyle = .short
            return "Paused until \(formatter.string(from: until))"
        case .paused(nil):
            return "Paused"
        case .offline:
            return "Offline: waiting for the model backend"
        case .error(let message):
            return "Needs attention: \(message)"
        }
    }

    /// SF Symbol for the menu-bar icon.
    static func symbol(for status: QueueStatus) -> String {
        switch status {
        case .idle: return "camera.viewfinder"
        case .processing: return "arrow.triangle.2.circlepath.camera"
        case .paused: return "pause.circle"
        case .offline: return "wifi.slash"
        case .error: return "exclamationmark.triangle"
        }
    }

    /// Short, secret-free description for the UI. Analyzer errors never include credentials (core redacts them).
    static func describe(_ error: any Error) -> String {
        if let error = error as? AnalyzerError {
            switch error {
            case .unreachable(let message): return "Could not reach the model backend (\(message))."
            case .rateLimited(let retryAfter):
                return retryAfter.map { "Rate limited; retry in \(Int($0.rounded())) s." } ?? "Rate limited; try again shortly."
            case .serverError(let status, let message): return "Server error \(status): \(message)"
            case .unauthorized(let message):
                return "Not authorized (\(message)). Check the account ID and that the token has Workers AI Read + Edit."
            case .badRequest(let status, let message): return "Request rejected (\(status)): \(message)"
            case .invalidResponse(let message): return "Unexpected response: \(message)"
            case .notConfigured(let message): return message
            }
        }
        if let error = error as? UndoError { return "Cannot undo: \(error)" }
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return String(describing: error)
    }
}

/// "Process existing screenshots": screenshots in the watched folder (top level only, like the watcher) that
/// the index does not already hold as done/skipped.
enum ExistingScreenshotScanner {
    static func candidates(in folder: URL, detector: ScreenshotDetector,
                           isIndexed: (URL) -> Bool, fileManager: FileManager = .default) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey]
        guard let items = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles]) else { return [] }
        let screenshots = items.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return false }
            return detector.isScreenshot(url) && !isIndexed(url)
        }
        // Oldest first, so the queue works through them in capture order.
        func created(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
        }
        return screenshots.sorted { (created($0), $0.lastPathComponent) < (created($1), $1.lastPathComponent) }
    }

    /// `isIndexed` backed by the real index: a row at this path with a final status.
    static func indexedCheck(_ index: ScreenshotIndex) -> (URL) -> Bool {
        { url in
            guard let row = try? index.lookup(byPath: url.standardizedFileURL.path) else { return false }
            return row.status == .done || row.status == .skipped
        }
    }
}
