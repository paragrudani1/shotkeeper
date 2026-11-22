import Foundation
import Security
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

    /// Short, secret-free, readable text for any error the UI shows. Never `String(describing:)`, a server's
    /// response body, or an OSStatus alone: core errors go through `UserFacingError`, app errors are mapped here.
    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as AnalyzerError:
            if case .notConfigured(let reason) = error { return reason }
            return UserFacingError.problem(for: error).sentence
        case is UndoError:
            return "Cannot undo: \(UserFacingError.message(for: error))."
        case let error as LocalRuntimeError:
            return error.errorDescription ?? "The local model could not be installed."
        case let error as KeychainError:
            return keychain(error)
        case let error as ManagedProcessError:
            switch error {
            case .alreadyStarted: return "The local model server is already running."
            case .launchFailed: return "The local model runtime could not be started. Install it again in Settings → Model."
            }
        case let error as CocoaError where error.isFileError:
            return error.code == .fileWriteOutOfSpace ? "The disk is full." : "A file could not be read or written."
        default:
            return UserFacingError.problem(for: error).sentence
        }
    }

    static let launchAtLoginFailed = "Could not change Open at Login. Move Shotkeeper to /Applications and try again."

    private static func keychain(_ error: KeychainError) -> String {
        switch error {
        case .status(_, let status) where status == errSecUserCanceled || status == errSecAuthFailed:
            return "The Keychain did not allow access. Try again and choose Allow."
        case .status(_, let status) where status == errSecInteractionNotAllowed:
            return "The Keychain is locked. Unlock the Mac and try again."
        default:
            return "The Keychain could not save the token."
        }
    }
}

/// "Process existing screenshots": screenshots in the watched folder (top level only, like the watcher) that
/// the index does not already hold as done/skipped, and whose data is on this Mac. Files evicted by iCloud Drive
/// ("Desktop & Documents") or another File Provider are skipped: reading them would download the whole backlog.
enum ExistingScreenshotScanner {
    static func candidates(in folder: URL, detector: ScreenshotDetector,
                           isIndexed: (URL) -> Bool, isStoredLocally: (URL) -> Bool = ExistingScreenshotScanner.isStoredLocally,
                           fileManager: FileManager = .default) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey]
        guard let items = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles]) else { return [] }
        let screenshots = items.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return false }
            return detector.isScreenshot(url) && !isIndexed(url) && isStoredLocally(url)
        }
        // Oldest first, so the queue works through them in capture order.
        func created(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
        }
        return screenshots.sorted { (created($0), $0.lastPathComponent) < (created($1), $1.lastPathComponent) }
    }

    /// False for a dataless placeholder: iCloud says `.notDownloaded`, or `st_flags` has `SF_DATALESS`
    /// (0x40000000 in <sys/stat.h>; set on evicted iCloud Drive and File Provider files).
    static func isStoredLocally(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           values.ubiquitousItemDownloadingStatus == .notDownloaded { return false }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return true }
        return info.st_flags & 0x4000_0000 == 0
    }

    /// `isIndexed` backed by the real index: a row at this path with a final status.
    static func indexedCheck(_ index: ScreenshotIndex) -> (URL) -> Bool {
        { url in
            guard let row = try? index.lookup(byPath: url.standardizedFileURL.path) else { return false }
            return row.status == .done || row.status == .skipped
        }
    }
}
