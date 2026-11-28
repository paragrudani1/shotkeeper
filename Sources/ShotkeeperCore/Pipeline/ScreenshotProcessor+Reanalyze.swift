import Foundation

/// Why Analyze Again did not run. Nothing was sent and nothing was written.
public enum ReanalysisRefusal: Equatable, Sendable {
    /// No row with that id, or no file at the row's path.
    case missing
    /// The file matches an exclude rule.
    case excluded(ExcludeRules.Rule)
    /// Shotkeeper is paused.
    case paused(until: Date)
}

/// Why Analyze Again was skipped (not an error, nothing written).
public enum ReanalysisSkipReason: Equatable, Sendable {
    /// `UploadConsent.decide` refused on the job's own snapshot (see `SkipReason.awaitingConsent`).
    case awaitingConsent
}

/// Why the file kept its name after Analyze Again (the panel's wording comes from this, design §5.3).
public enum TitleKeptReason: Equatable, Sendable {
    /// The user typed the name (`TitleSource.user`); the model's title is in `suggestedTitle`.
    case yourName
    /// The user restored the name with Undo: the index is updated, the file is neither renamed nor moved.
    case restoredByUndo
    /// The new title's confidence is below `minTitleConfidence`.
    case lowConfidence
    /// Renaming is off in Settings.
    case renameOff
    /// The model gave no title, or one that gives no usable file name.
    case unusable
    /// The rename (or move) failed in `FileOrganizer`; the file stays where it was and the row's note says why.
    case renameFailed
}

/// What `ScreenshotProcessor.reanalyze(rowID:request:)` did.
public enum ReanalysisOutcome: Equatable, Sendable {
    /// Analyzed and the row updated. `finalURL` is where the file is now. `titleKept` is nil when the name follows
    /// the new title: then `renamed == false` means the new title gives the same name as before ("The title is the
    /// same as before"). `suggestedTitle` is the model's title when the user's name was kept (`.yourName`); it is
    /// not stored ("Use This Name" passes it to `rename(_:to:asSuggestedTitle: true)`).
    case updated(finalURL: URL, renamed: Bool, moved: Bool, titleKept: TitleKeptReason?, suggestedTitle: String?)
    case refused(ReanalysisRefusal)
    case skipped(ReanalysisSkipReason)
}

extension ScreenshotProcessor {
    /// The note a re-analysis adds to the row.
    static let analyzedAgainNote = "analyzed again"

    /// Analyze Again (spec "Analyze Again (core)"): analyzes one indexed screenshot again, the only way past
    /// `.alreadyIndexed`. Keyed on the row id; the row's current path is read at every call, so a rename made while
    /// the job waited does not lose the file.
    ///
    /// Look up the row (`.refused(.missing)`) → exclude rules and Pause (`.refused`, nothing sent) → fingerprint and
    /// prepare → `UploadConsent.decide` on the snapshot read once right before `analyze`, with `request`
    /// (`.skipped(.awaitingConsent)`, nothing written) → `analyze` with the pipeline's `AnalysisContext` → apply to a
    /// copy of the row → name (restored by Undo, then the user's name, then the pipeline's rename rule) → place (the
    /// pipeline's move rule with today's settings, not for restored rows) → undo record → Finder → `updatePath` →
    /// `save`.
    ///
    /// If fingerprinting, preparing or analyzing throws, nothing has been written: the row stays exactly as it was
    /// (still `done`, still in search) and the error is rethrown for `ProcessingQueue`'s retry rules.
    /// - Parameter request: the user's request to send this file ("Analyze Again" while its destination was selected
    ///   and allowed, `UserUploadRequests.authorization(for:)`). It lifts only "taken before the grant", never
    ///   "destination not allowed".
    public func reanalyze(rowID: Int64, request: UserUploadAuthorization? = nil) async throws -> ReanalysisOutcome {
        // 1. The row and its file, at the path the row has now.
        guard let row = try index.lookup(id: rowID) else { return .refused(.missing) }
        let url = URL(fileURLWithPath: row.path).standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .refused(.missing) }

        // 2. Exclude rules and Pause, as `process` checks them.
        let early = snapshot().settings
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        let capturedAt = row.capturedAt ?? (attributes?[.creationDate] as? Date)
            ?? (attributes?[.modificationDate] as? Date) ?? now()
        switch early.excludeRules.exclusion(for: url, capturedAt: capturedAt, now: now()) {
        case .paused(let until)?: return .refused(.paused(until: until))
        case .rule(let rule)?: return .refused(.excluded(rule))
        case nil: break
        }
        // For consent, the earliest the file can claim. A renamed file has lost the time in its name, so the original
        // name and the stored capture time count too (earlier is the stricter side: it fails closed).
        var consentCapturedAt = min(UploadConsent.effectiveCaptureTime(of: url, timeZone: timeZone),
                                    UploadConsent.effectiveCaptureTime(
                                        creationDate: row.capturedAt,
                                        nameDate: ScreenshotDetector.captureDate(fromFilename: row.originalFilename,
                                                                                 timeZone: timeZone)))
        // Early out only, as in `process`; the decision that counts is the one right before `analyze`.
        guard UploadConsent.decide(settings: early, capturedAt: consentCapturedAt, userRequest: request) == .allow
        else { return .skipped(.awaitingConsent) }

        // 3. Fingerprint and prepare. Nothing is written before the analysis succeeds.
        let hash = try ContentFingerprint.compute(for: url)
        let payload = try imagePreparer.prepare(url)
        consentCapturedAt = min(consentCapturedAt, UploadConsent.effectiveCaptureTime(of: url, timeZone: timeZone))

        // 4. THE consent decision, on the pair this job then uses.
        guard let job = consentedJob(capturedAt: consentCapturedAt, userRequest: request)
        else { return .skipped(.awaitingConsent) }
        let settings = job.settings

        // 5. The pipeline's context: the original name and the capture time, never recognized text.
        let context = AnalysisContext(originalFilename: row.originalFilename, capturedAt: capturedAt)
        let analysis = try await send(payload, context: context, with: job)

        // 6. Apply to a copy of the row.
        var entry = row
        entry.apply(analysis)
        entry.status = .done
        entry.lastError = nil
        entry.processedAt = now()
        if hash != row.contentHash {
            entry.contentHash = hash
            entry.textStatus = .pending
        }
        var notes: [String] = []

        // 7. Name. Restored by Undo is checked before the user's name: Undo after a hand rename leaves
        // `title_source = user` while the file is back at the model's name (wiki, review of PR #20).
        var titleKept: TitleKeptReason?
        var suggestedTitle: String?
        var stem: String?
        if row.restoredByUndo {
            titleKept = .restoredByUndo
        } else if row.titleSource == .user {
            titleKept = .yourName
            suggestedTitle = analysis.title.flatMap { title in
                settings.filenameStyle.stem(from: title, capturedAt: nil, timeZone: timeZone) == nil ? nil : title
            }
        } else if !settings.renameEnabled {
            titleKept = .renameOff
        } else if let title = analysis.title, analysis.titleConfidence >= settings.minTitleConfidence {
            stem = settings.filenameStyle.stem(from: title, capturedAt: capturedAt, timeZone: timeZone)
            if stem == nil { titleKept = .unusable }
        } else {
            titleKept = analysis.title == nil ? .unusable : .lowConfidence
        }
        if titleKept != nil && titleKept != .renameOff {
            // The file keeps its name, so the row keeps the title that goes with it.
            entry.title = row.title
            entry.titleConfidence = row.titleConfidence
        }

        // 8–9. Place, undo record, Finder, index. A restored file is not touched (index only).
        var finalURL = url
        if !row.restoredByUndo {
            let placed = place(url, stem: stem, into: destinationFolder(for: analysis, settings: settings), notes: &notes)
            finalURL = placed.url
            if placed.failed && stem != nil {
                titleKept = .renameFailed
                entry.title = row.title
                entry.titleConfidence = row.titleConfidence
            }
            writeFinderMetadata(analysis, to: finalURL, settings: settings, notes: &notes)
        }

        let earlier = (row.note?.components(separatedBy: "; ") ?? []).filter { $0 != Self.analyzedAgainNote }
        entry.note = (earlier + notes + [Self.analyzedAgainNote]).joined(separator: "; ")
        if finalURL != url {
            try index.updatePath(from: url.path, to: finalURL.path)
            entry.path = finalURL.path
        }
        try index.save(entry)

        let renamed = finalURL.lastPathComponent != url.lastPathComponent
        let moved = finalURL.deletingLastPathComponent().path != url.deletingLastPathComponent().path
        return .updated(finalURL: finalURL, renamed: renamed, moved: moved, titleKept: titleKept,
                        suggestedTitle: suggestedTitle)
    }
}
