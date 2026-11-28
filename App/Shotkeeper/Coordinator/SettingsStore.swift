import Foundation
import ShotkeeperCore

/// Where the app keeps its state: `~/Library/Application Support/Shotkeeper/`.
enum AppPaths {
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var supportDirectory: URL {
        applicationSupport.appendingPathComponent("Shotkeeper", isDirectory: true)
    }

    static func settingsFile(in directory: URL) -> URL { directory.appendingPathComponent("settings.json") }
    static func indexFile(in directory: URL) -> URL { directory.appendingPathComponent("index.sqlite") }
    static func undoLogFile(in directory: URL) -> URL { directory.appendingPathComponent("undo.jsonl") }
}

/// `AppSettings` persisted as JSON. Thread-safe: the pipeline reads `current` from background tasks
/// (once per screenshot) while the UI writes on the main actor.
///
/// - A missing file gives defaults. A file that does not decode gives defaults too (core's `AppSettings.decode`), and
///   is copied to `settings.json.unreadable` before the next save overwrites it, so the user's old settings are not lost.
/// - Writes are atomic (temp file + rename).
final class SettingsStore: @unchecked Sendable {
    let fileURL: URL
    private let lock = NSLock()
    private var value: AppSettings

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.value = SettingsStore.load(from: fileURL)
    }

    var current: AppSettings { lock.withLock { value } }

    /// Replaces the settings and writes them to disk. The in-memory value changes even if the write fails.
    func save(_ settings: AppSettings) throws {
        lock.withLock { value = settings }
        try write(settings)
    }

    /// Read-modify-write under the lock; returns the new settings.
    @discardableResult
    func update(_ body: (inout AppSettings) -> Void) throws -> AppSettings {
        let updated = lock.withLock { () -> AppSettings in
            body(&value)
            return value
        }
        try write(updated)
        return updated
    }

    private func write(_ settings: AppSettings) throws {
        let data = try settings.encoded()
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    static func load(from url: URL) -> AppSettings {
        guard let data = try? Data(contentsOf: url) else { return AppSettings() }
        if (try? JSONSerialization.jsonObject(with: data)) == nil {
            // Not JSON at all: keep a copy for the user before defaults replace it on the next save.
            let backup = url.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: backup)  // lint-allow: file-op (our previous backup)
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        return AppSettings.decode(data)
    }
}
