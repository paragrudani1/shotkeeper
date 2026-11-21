import Foundation

public enum SkipReason: Equatable, Sendable {
    /// The file is gone (deleted or moved before we got to it).
    case missing
    case excluded(ExcludeRules.Rule)
    case paused(until: Date)
    /// Same fingerprint already processed (`done`/`skipped`) at this or another path.
    case alreadyIndexed
}

public enum ProcessingOutcome: Equatable, Sendable {
    /// Analyzed and indexed. `finalURL` is where the file is now.
    case processed(finalURL: URL, renamed: Bool, moved: Bool)
    case skipped(SkipReason)
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

        let hash = try ContentFingerprint.compute(for: url)
        let rowAtPath = try index.lookup(byPath: url.path)
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
            do { try undoLog.append(from: url, to: finalURL, at: now()) }
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

    /// Undo the most recent rename/move and point the index back at the original path.
    @discardableResult
    public func undoLast() throws -> UndoRecord {
        let record = try undoLog.undoLast(at: now())
        _ = try? index.updatePath(from: record.to, to: record.from)
        return record
    }

    @discardableResult
    public func undo(id: UUID) throws -> UndoRecord {
        let record = try undoLog.undo(id: id, at: now())
        _ = try? index.updatePath(from: record.to, to: record.from)
        return record
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

extension ProcessingStatus {
    /// Rows that should not be processed again.
    var isFinal: Bool { self == .done || self == .skipped }
}
