import Foundation

public enum SkipReason: Equatable, Sendable {
    /// The file is gone (deleted or moved before we got to it).
    case missing
    case excluded(ExcludeRules.Rule)
    case paused(until: Date)
    /// Same fingerprint already processed (`done`/`skipped`) at this or another path.
    case alreadyIndexed
    /// The user restored this file's original name with Undo; Shotkeeper leaves it alone from then on.
    case restoredByUndo
}

public enum ProcessingOutcome: Equatable, Sendable {
    /// Analyzed and indexed. `finalURL` is where the file is now.
    case processed(finalURL: URL, renamed: Bool, moved: Bool)
    case skipped(SkipReason)
}

/// What `ScreenshotProcessor.processWithReport(_:)` did to one file: enough for the rename toast and its Undo.
public struct ProcessingReport: Equatable, Sendable {
    /// The path the screenshot had when it was handed to the processor.
    public var originalURL: URL
    public var outcome: ProcessingOutcome
    /// The undo record written for the rename/move, if any.
    public var undoRecordID: UUID?

    public init(originalURL: URL, outcome: ProcessingOutcome, undoRecordID: UUID? = nil) {
        self.originalURL = originalURL
        self.outcome = outcome
        self.undoRecordID = undoRecordID
    }
}

/// Result of a rename the user typed (the toast's "Edit name").
public struct ManualRenameResult: Equatable, Sendable {
    public var finalURL: URL
    /// Nil when the name did not change (nothing was moved, nothing to undo).
    public var undoRecordID: UUID?

    public init(finalURL: URL, undoRecordID: UUID?) {
        self.finalURL = finalURL
        self.undoRecordID = undoRecordID
    }
}

public enum ManualRenameError: Error, Equatable, Sendable {
    /// `FilenameSanitizer` left nothing usable (empty, only punctuation, or a generic "Screenshot" name).
    case unusableName(String)
}

/// Result of undoing several records at once ("Undo All").
public struct UndoBatchResult: Equatable, Sendable {
    public var restored: [UndoRecord]
    public var failed: [UUID]
}

/// One screenshot through the whole pipeline:
/// skip if missing/excluded/paused/already indexed → prepare image → analyze → rename/move when allowed →
/// undo record → Finder tags/comment → index row.
///
/// The file is never lost: nothing touches it before the analysis succeeds, and renames/moves go through
/// `FileOrganizer` (no-replace). On an analyzer/preparer error the row is saved as `failed` with `lastError`, and the
/// error is rethrown so `ProcessingQueue` can decide whether to retry. A rename failure keeps the name and is noted.
/// The undo record is appended right after a successful move (before index/Finder writes) so a later failure can
/// never leave a move that cannot be undone.
public final class ScreenshotProcessor: Sendable {
    private let analyzer: @Sendable () -> any ScreenshotAnalyzer
    private let imagePreparer: any ImagePreparer
    private let metadataWriter: any FileMetadataWriter
    private let index: ScreenshotIndex
    private let organizer: FileOrganizer
    private let undoLog: UndoLog
    private let settings: @Sendable () -> AppSettings
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - analyzer: called per screenshot, so a backend switch in settings takes effect without rebuilding.
    ///   - settings: read once per screenshot.
    public init(analyzer: @escaping @Sendable () -> any ScreenshotAnalyzer,
                imagePreparer: any ImagePreparer,
                metadataWriter: any FileMetadataWriter = NoopFileMetadataWriter(),
                index: ScreenshotIndex,
                organizer: FileOrganizer = FileOrganizer(),
                undoLog: UndoLog,
                settings: @escaping @Sendable () -> AppSettings,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.analyzer = analyzer
        self.imagePreparer = imagePreparer
        self.metadataWriter = metadataWriter
        self.index = index
        self.organizer = organizer
        self.undoLog = undoLog
        self.settings = settings
        self.now = now
    }

    public convenience init(analyzer: any ScreenshotAnalyzer, imagePreparer: any ImagePreparer,
                            metadataWriter: any FileMetadataWriter = NoopFileMetadataWriter(), index: ScreenshotIndex,
                            organizer: FileOrganizer = FileOrganizer(), undoLog: UndoLog,
                            settings: @escaping @Sendable () -> AppSettings, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(analyzer: { analyzer }, imagePreparer: imagePreparer, metadataWriter: metadataWriter, index: index,
                  organizer: organizer, undoLog: undoLog, settings: settings, now: now)
    }

    /// Suitable as a `ProcessingQueue` handler: `{ _ = try await processor.process($0) }`.
    public func process(_ url: URL) async throws -> ProcessingOutcome {
        try await processWithReport(url).outcome
    }

    /// `process(_:)` plus the original path and the undo record id (for the rename toast).
    public func processWithReport(_ url: URL) async throws -> ProcessingReport {
        let original = url.standardizedFileURL
        var undoRecordID: UUID?
        let outcome = try await process(original, undoRecordID: &undoRecordID)
        return ProcessingReport(originalURL: original, outcome: outcome, undoRecordID: undoRecordID)
    }

    private func process(_ url: URL, undoRecordID: inout UUID?) async throws -> ProcessingOutcome {
        let url = url.standardizedFileURL
        let settings = self.settings()
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .skipped(.missing) }

        let attributes = try? fm.attributesOfItem(atPath: url.path)
        let capturedAt = (attributes?[.creationDate] as? Date) ?? (attributes?[.modificationDate] as? Date) ?? now()
        switch settings.excludeRules.exclusion(for: url, capturedAt: capturedAt, now: now()) {
        case .paused(let until)?: return .skipped(.paused(until: until))
        case .rule(let rule)?: return .skipped(.excluded(rule))
        case nil: break
        }

        let rowAtPath = try index.lookup(byPath: url.path)
        if rowAtPath?.restoredByUndo == true { return .skipped(.restoredByUndo) }
        let hash = try ContentFingerprint.compute(for: url)
        if let rowAtPath, rowAtPath.contentHash == hash, rowAtPath.status.isFinal { return .skipped(.alreadyIndexed) }
        if let previous = try index.lookup(byHash: hash), previous.status.isFinal, previous.path != url.path {
            // The file we processed was moved by the user: follow it. A second copy is simply not re-analyzed.
            if !fm.fileExists(atPath: previous.path), rowAtPath == nil {
                _ = try? index.updatePath(from: previous.path, to: url.path)
            }
            return .skipped(.alreadyIndexed)
        }

        var entry = IndexedScreenshot(id: rowAtPath?.id ?? 0, path: url.path,
                                      originalFilename: rowAtPath?.originalFilename ?? url.lastPathComponent,
                                      contentHash: hash, capturedAt: capturedAt, status: .pending)
        try index.save(entry)

        let analysis: ScreenshotAnalysis
        do {
            let payload = try imagePreparer.prepare(url)
            let context = AnalysisContext(originalFilename: entry.originalFilename, capturedAt: capturedAt)
            analysis = try await analyzer().analyze(payload, context: context)
        } catch {
            entry.status = .failed
            entry.lastError = String(describing: error)
            entry.processedAt = now()
            _ = try? index.save(entry)
            throw error
        }

        entry.apply(analysis)
        entry.status = .done
        entry.lastError = nil
        entry.processedAt = now()
        var notes: [String] = []

        var stem: String?
        if settings.renameEnabled {
            if let title = analysis.title, analysis.titleConfidence >= settings.minTitleConfidence {
                stem = FilenameSanitizer.stem(from: title)
                if stem == nil { notes.append("kept name: title not usable as a filename") }
            } else if analysis.title == nil {
                notes.append("kept name: no title")
            } else {
                notes.append("kept name: title confidence \(Self.format(analysis.titleConfidence)) < \(Self.format(settings.minTitleConfidence))")
            }
        }
        let folder = settings.moveEnabled ? settings.organizedFolder : nil

        var finalURL = url
        if stem != nil || folder != nil {
            do {
                finalURL = try organizer.organize(url, stem: stem, into: folder)
            } catch {
                notes.append("kept name: rename failed (\(error))")
            }
        }
        if finalURL != url {
            do { undoRecordID = try undoLog.append(from: url, to: finalURL, at: now()).id }
            catch { notes.append("undo record not written (\(error))") }
        }

        if settings.writeFinderMetadata {
            do {
                try FinderMetadata.apply(tags: analysis.tags, comment: analysis.description, to: finalURL, using: metadataWriter)
            } catch {
                notes.append("Finder metadata not written (\(error))")
            }
        }

        entry.note = notes.isEmpty ? nil : notes.joined(separator: "; ")
        if finalURL != url {
            try index.updatePath(from: url.path, to: finalURL.path)
            entry.path = finalURL.path
        }
        try index.save(entry)

        let renamed = finalURL.lastPathComponent != url.lastPathComponent
        let moved = finalURL.deletingLastPathComponent().path != url.deletingLastPathComponent().path
        return .processed(finalURL: finalURL, renamed: renamed, moved: moved)
    }

    /// Undo the most recent rename/move, point the index back at the original path, and flag the file so it is
    /// never processed again.
    @discardableResult
    public func undoLast() throws -> UndoRecord {
        let record = try undoLog.undoLast(at: now())
        recordRestored(record)
        return record
    }

    @discardableResult
    public func undo(id: UUID) throws -> UndoRecord {
        let record = try undoLog.undo(id: id, at: now())
        recordRestored(record)
        return record
    }

    /// Undoes `ids` newest first (the reverse of the given order), so a rename made on top of an earlier one is
    /// undone before it. Keeps going after a failure; the failed ids are returned.
    public func undo(ids: [UUID]) -> UndoBatchResult {
        var result = UndoBatchResult(restored: [], failed: [])
        for id in ids.reversed() {
            do { result.restored.append(try undo(id: id)) } catch { result.failed.append(id) }
        }
        return result
    }

    /// The most recent rename/move that can still be undone (for "Undo: <title>" in the menu).
    public func lastUndoable() -> UndoRecord? {
        (try? undoLog.records())?.last
    }

    /// Renames `url` to a name the user typed, with the pipeline's rules: `FilenameSanitizer`, the original
    /// extension, no-replace "Name 2.png" collisions via `FileOrganizer`. Writes an undo record and moves the index
    /// row (whose title becomes the new name, so search finds it).
    public func rename(_ url: URL, to proposedName: String) throws -> ManualRenameResult {
        let url = url.standardizedFileURL
        guard let stem = FilenameSanitizer.stem(from: proposedName) else {
            throw ManualRenameError.unusableName(proposedName)
        }
        if stem == url.deletingPathExtension().lastPathComponent { return ManualRenameResult(finalURL: url, undoRecordID: nil) }
        let finalURL = try organizer.organize(url, stem: stem, into: nil)
        guard finalURL != url else { return ManualRenameResult(finalURL: url, undoRecordID: nil) }
        let record: UndoRecord
        do {
            record = try undoLog.append(from: url, to: finalURL, at: now())
        } catch {
            // Never leave a rename that cannot be undone: put the file back (no-replace) and report the failure.
            try? organizer.move(finalURL, to: url)
            throw error
        }
        _ = try? index.updatePath(from: url.path, to: finalURL.path)
        if var row = try? index.lookup(byPath: finalURL.path) {
            row.title = stem
            row.note = [row.note, "renamed by the user"].compactMap { $0 }.joined(separator: "; ")
            _ = try? index.save(row)
        }
        return ManualRenameResult(finalURL: finalURL, undoRecordID: record.id)
    }

    /// After an undo: the index follows the file back, and the file is flagged so neither the watcher (which sees
    /// the restored name appear) nor "Process existing" nor a later launch processes it again.
    private func recordRestored(_ record: UndoRecord) {
        _ = try? index.updatePath(from: record.to, to: record.from)
        if (try? index.markRestoredByUndo(path: record.from)) == true { return }
        // No row (e.g. the index was reset): add a minimal one so the flag still persists.
        let url = URL(fileURLWithPath: record.from)
        guard let hash = try? ContentFingerprint.compute(for: url) else { return }
        _ = try? index.save(IndexedScreenshot(path: record.from, originalFilename: url.lastPathComponent,
                                              contentHash: hash, processedAt: now(), status: .skipped,
                                              restoredByUndo: true))
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

extension ProcessingStatus {
    /// Rows that should not be processed again.
    var isFinal: Bool { self == .done || self == .skipped }
}
