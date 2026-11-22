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
    /// `UploadConsent.decide` refused: the job's backend sends screenshots off this Mac and its destination is not
    /// allowed, or the file was taken before it was (and no Process Existing request for that destination covers
    /// it). Skipped like Pause, not held, and decided on every run, so neither a resumed queue nor a later file event
    /// uploads a screenshot taken before the consent.
    case awaitingConsent
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
/// skip if missing/excluded/paused/already indexed → prepare image → consent decision → analyze → rename/move when
/// allowed → undo record → Finder tags/comment → index row.
///
/// Consent (CODING_STANDARDS #2) is decided here and only here, by `UploadConsent.decide`, on the `AnalyzerSnapshot`
/// whose analyzer then gets the image: the snapshot is read once, after the image is prepared, and nothing the app
/// changes afterwards affects this job. An early check on the snapshot at the start only avoids reading and indexing
/// a file that cannot go anywhere.
///
/// The file is never lost: nothing touches it before the analysis succeeds, and renames/moves go through
/// `FileOrganizer` (no-replace). On an analyzer/preparer error the row is saved as `failed` with `lastError`, and the
/// error is rethrown so `ProcessingQueue` can decide whether to retry. A rename failure keeps the name and is noted.
/// The undo record is appended right after a successful move (before index/Finder writes) so a later failure can
/// never leave a move that cannot be undone.
public final class ScreenshotProcessor: Sendable {
    private let snapshot: @Sendable () -> AnalyzerSnapshot
    private let imagePreparer: any ImagePreparer
    private let metadataWriter: any FileMetadataWriter
    private let index: ScreenshotIndex
    private let organizer: FileOrganizer
    private let undoLog: UndoLog
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - snapshot: the analyzer and the settings it was built from, read together (the app keeps them in one
    ///     locked value). Read at the start of a job for its early checks, and once more right before `analyze`:
    ///     that second pair is what the job uses (consent decision, analyzer, rename/move/Finder settings).
    ///   - timeZone: for the time in screenshot names (`ScreenshotDetector.captureDate`).
    public init(snapshot: @escaping @Sendable () -> AnalyzerSnapshot,
                imagePreparer: any ImagePreparer,
                metadataWriter: any FileMetadataWriter = NoopFileMetadataWriter(),
                index: ScreenshotIndex,
                organizer: FileOrganizer = FileOrganizer(),
                undoLog: UndoLog,
                now: @escaping @Sendable () -> Date = { Date() },
                timeZone: TimeZone = .autoupdatingCurrent) {
        self.snapshot = snapshot
        self.imagePreparer = imagePreparer
        self.metadataWriter = metadataWriter
        self.index = index
        self.organizer = organizer
        self.undoLog = undoLog
        self.now = now
        self.timeZone = timeZone
    }

    /// A fixed analyzer with changing settings (tests, the CLI): the analyzer does not depend on the settings.
    public convenience init(analyzer: any ScreenshotAnalyzer, imagePreparer: any ImagePreparer,
                            metadataWriter: any FileMetadataWriter = NoopFileMetadataWriter(), index: ScreenshotIndex,
                            organizer: FileOrganizer = FileOrganizer(), undoLog: UndoLog,
                            settings: @escaping @Sendable () -> AppSettings, now: @escaping @Sendable () -> Date = { Date() },
                            timeZone: TimeZone = .autoupdatingCurrent) {
        self.init(snapshot: { AnalyzerSnapshot(analyzer: analyzer, settings: settings()) }, imagePreparer: imagePreparer,
                  metadataWriter: metadataWriter, index: index, organizer: organizer, undoLog: undoLog, now: now,
                  timeZone: timeZone)
    }

    /// Suitable as a `ProcessingQueue` handler: `{ _ = try await processor.process($0) }`.
    public func process(_ url: URL, processExisting: ProcessExistingAuthorization? = nil) async throws -> ProcessingOutcome {
        try await processWithReport(url, processExisting: processExisting).outcome
    }

    /// `process(_:)` plus the original path and the undo record id (for the rename toast).
    /// - Parameter processExisting: the user's "Process Existing Screenshots…" request for this file, with the
    ///   destination selected when they asked. It lets a file taken before that destination was allowed be sent,
    ///   only while that destination is still the job's and still allowed (`UploadConsent.decide`).
    public func processWithReport(_ url: URL, processExisting: ProcessExistingAuthorization? = nil) async throws -> ProcessingReport {
        let original = url.standardizedFileURL
        var undoRecordID: UUID?
        let outcome = try await process(original, processExisting: processExisting, undoRecordID: &undoRecordID)
        return ProcessingReport(originalURL: original, outcome: outcome, undoRecordID: undoRecordID)
    }

    private func process(_ url: URL, processExisting: ProcessExistingAuthorization?,
                         undoRecordID: inout UUID?) async throws -> ProcessingOutcome {
        let url = url.standardizedFileURL
        let early = self.snapshot().settings
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .skipped(.missing) }

        let attributes = try? fm.attributesOfItem(atPath: url.path)
        // For the index, the toast and Pause: a best guess, now() when nothing can be read.
        let capturedAt = (attributes?[.creationDate] as? Date) ?? (attributes?[.modificationDate] as? Date) ?? now()
        // For consent: the earliest the file can claim, `.distantPast` when unknown (fails closed).
        var consentCapturedAt = UploadConsent.effectiveCaptureTime(of: url, timeZone: timeZone)
        switch early.excludeRules.exclusion(for: url, capturedAt: capturedAt, now: now()) {
        case .paused(let until)?: return .skipped(.paused(until: until))
        case .rule(let rule)?: return .skipped(.excluded(rule))
        case nil: break
        }
        // Early out only (no file read, no index row); the decision that counts is the one right before `analyze`.
        guard UploadConsent.decide(settings: early, capturedAt: consentCapturedAt, processExisting: processExisting) == .allow
        else { return .skipped(.awaitingConsent) }

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
        func recordFailure(_ error: Error) {
            entry.status = .failed
            entry.lastError = String(describing: error)
            entry.processedAt = now()
            _ = try? index.save(entry)
        }

        let payload: ImagePayload
        do { payload = try imagePreparer.prepare(url) } catch {
            recordFailure(error)
            throw error
        }

        // The file may have been replaced while it was prepared: judge it by the earlier of both reads of its dates.
        consentCapturedAt = min(consentCapturedAt, UploadConsent.effectiveCaptureTime(of: url, timeZone: timeZone))
        // THE consent decision (CODING_STANDARDS #2): on the pair this job uses, read once, right before `analyze`.
        let job = self.snapshot()
        let settings = job.settings
        guard UploadConsent.decide(settings: settings, capturedAt: consentCapturedAt,
                                   processExisting: processExisting) == .allow else { return .skipped(.awaitingConsent) }

        try index.save(entry)
        let analysis: ScreenshotAnalysis
        do {
            let context = AnalysisContext(originalFilename: entry.originalFilename, capturedAt: capturedAt)
            analysis = try await job.analyzer.analyze(payload, context: context)
        } catch {
            recordFailure(error)
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
