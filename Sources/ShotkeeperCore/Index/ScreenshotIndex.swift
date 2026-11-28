import Foundation

public enum ProcessingStatus: String, Codable, Sendable, CaseIterable {
    case pending, done, failed, skipped
}

/// Where a row's on-device text recognition stands (`IndexedScreenshot.textStatus`; nil = never requested).
public enum TextStatus: String, Codable, Sendable, CaseIterable {
    /// Queued: the runner reads it (newest first, `ScreenshotIndex.newestPendingTextRow()`).
    case pending
    /// Read; the text is in `recognizedText`.
    case done
    /// Read, and the image has no text (`recognizedText` nil). Stored as `none`; not named `.none` in Swift, where
    /// `textStatus == .none` would compare against Optional's nil.
    case noText = "none"
    /// The read failed; `textError` says why.
    case failed
}

/// One row of the index.
public struct IndexedScreenshot: Equatable, Sendable {
    /// Assigned by the index; 0 for a row not yet saved.
    public var id: Int64
    /// Current absolute path.
    public var path: String
    public var originalFilename: String
    /// `ContentFingerprint` value.
    public var contentHash: String
    public var capturedAt: Date?
    public var processedAt: Date?
    public var title: String?
    public var titleConfidence: Double?
    public var sourceAppOrSite: String?
    public var contentType: ContentType?
    public var description: String?
    public var tags: [String]
    public var keyText: String?
    public var dateMentioned: String?
    public var producedBy: String?
    public var billedInputTokens: Int?
    public var status: ProcessingStatus
    public var lastError: String?
    /// Human-readable note, e.g. why the name was kept ("title confidence 0.31 < 0.5").
    public var note: String?
    /// The user put this file back to its original name with Undo: never process it again (migration 2).
    public var restoredByUndo: Bool
    /// The screenshot's text, read on the Mac (lines joined with "\n"); nil until read, or when it has none
    /// (migration 3). Never sent anywhere; never put in `textError`, `lastError`, `note` or a log.
    public var recognizedText: String?
    /// nil = never requested (rows indexed before migration 3 stay nil until the user asks).
    public var textStatus: TextStatus?
    /// The recognizer id plus its settings (e.g. `vision-r3-accurate-h1/96-lc0`), so a settings change can find
    /// rows to re-read.
    public var textRecognizedBy: String?
    /// Short reason for `textStatus == .failed` (e.g. "file missing"). Never contains recognized text.
    public var textError: String?

    public init(id: Int64 = 0, path: String, originalFilename: String, contentHash: String, capturedAt: Date? = nil,
                processedAt: Date? = nil, title: String? = nil, titleConfidence: Double? = nil, sourceAppOrSite: String? = nil,
                contentType: ContentType? = nil, description: String? = nil, tags: [String] = [], keyText: String? = nil,
                dateMentioned: String? = nil, producedBy: String? = nil, billedInputTokens: Int? = nil,
                status: ProcessingStatus = .pending, lastError: String? = nil, note: String? = nil,
                restoredByUndo: Bool = false, recognizedText: String? = nil, textStatus: TextStatus? = nil,
                textRecognizedBy: String? = nil, textError: String? = nil) {
        self.id = id
        self.path = path
        self.originalFilename = originalFilename
        self.contentHash = contentHash
        self.capturedAt = capturedAt
        self.processedAt = processedAt
        self.title = title
        self.titleConfidence = titleConfidence
        self.sourceAppOrSite = sourceAppOrSite
        self.contentType = contentType
        self.description = description
        self.tags = tags
        self.keyText = keyText
        self.dateMentioned = dateMentioned
        self.producedBy = producedBy
        self.billedInputTokens = billedInputTokens
        self.status = status
        self.lastError = lastError
        self.note = note
        self.restoredByUndo = restoredByUndo
        self.recognizedText = recognizedText
        self.textStatus = textStatus
        self.textRecognizedBy = textRecognizedBy
        self.textError = textError
    }

    /// Copies the analysis fields in.
    public mutating func apply(_ analysis: ScreenshotAnalysis) {
        title = analysis.title
        titleConfidence = analysis.titleConfidence
        sourceAppOrSite = analysis.sourceAppOrSite
        contentType = analysis.contentType
        description = analysis.description
        tags = analysis.tags
        keyText = analysis.keyText
        dateMentioned = analysis.dateMentioned
        producedBy = analysis.producedBy
        billedInputTokens = analysis.billedInputTokens
    }
}

/// What one text recognition of a row found; written by
/// `ScreenshotIndex.setRecognizedText(_:recognizedBy:id:ifContentHash:)`.
public enum TextRecognitionResult: Equatable, Sendable {
    /// The joined lines → `.done`.
    case text(String)
    /// The image has no text → `.noText`, `recognizedText` nil.
    case noText
    /// The read failed → `.failed`, `reason` in `textError`. A short reason ("file missing", an error code), never
    /// recognized text.
    case failed(reason: String)
}

/// What the search window asks the index for (see `ScreenshotIndex.search(_:limit:)`).
public struct ScreenshotQuery: Equatable, Sendable {
    /// Free text; empty = no text filter (recent first).
    public var text: String
    /// The selected type chip; nil = All.
    public var contentType: ContentType?
    /// Only these paths (a batch from the toast); nil = the whole index.
    public var paths: [String]?
    /// Only screenshots taken on these days (`COALESCE(captured_at, processed_at)`); nil = any time.
    public var date: DateFilter?
    /// Only screenshots from this app or site, in any spelling with the same `SourceKey`; nil = every source.
    public var source: SourceKey?

    public init(text: String = "", contentType: ContentType? = nil, paths: [String]? = nil, date: DateFilter? = nil,
                source: SourceKey? = nil) {
        self.text = text
        self.contentType = contentType
        self.paths = paths
        self.date = date
        self.source = source
    }
}

/// One page of search results plus the counts the footer shows ("6 of 214 screenshots").
public struct ScreenshotSearchResult: Equatable, Sendable {
    /// At most `limit` rows, best match (or newest) first.
    public var rows: [IndexedScreenshot]
    /// All rows matching the query (can exceed `rows.count`).
    public var matchCount: Int
    /// All analyzed (`done`) screenshots in the index.
    public var totalCount: Int

    public init(rows: [IndexedScreenshot], matchCount: Int, totalCount: Int) {
        self.rows = rows
        self.matchCount = matchCount
        self.totalCount = totalCount
    }
}

/// One change to a row of the index, published by `ScreenshotIndex.changes()` after it is committed.
public struct IndexChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `save(_:)` added a row.
        case inserted
        /// `save(_:)` replaced a row's fields, `updatePath(from:to:)` moved it, or `markRestoredByUndo(path:)` flagged it.
        case updated
        /// The row is gone (today only a stale row that `updatePath(from:to:)` replaced).
        case removed
    }

    public var kind: Kind
    /// The row id: stable for the life of the row, also across path changes.
    public var id: Int64
    /// The row's path after the change; for `.removed`, the path it had.
    public var path: String

    public init(_ kind: Kind, id: Int64, path: String) {
        self.kind = kind
        self.id = id
        self.path = path
    }
}

public struct IndexStats: Equatable, Sendable {
    public var count: Int
    public var done: Int
    public var failed: Int
    public var totalBilledInputTokens: Int
}

/// SQLite index of processed screenshots with FTS5 search. Thread-safe (one connection behind a lock).
public final class ScreenshotIndex: @unchecked Sendable {
    private let db: SQLiteDatabase
    private let lock = NSLock()
    /// `changes()` subscribers. Own lock: a stream's `onTermination` may run on any thread, also during a write.
    private let subscribersLock = NSLock()
    private var subscribers: [UUID: AsyncStream<IndexChange>.Continuation] = [:]

    /// Opens (creating if needed) the index at `fileURL` and migrates it. In WAL mode.
    public convenience init(fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(path: fileURL.path)
    }

    /// In-memory index (tests, previews).
    public static func inMemory() throws -> ScreenshotIndex { try ScreenshotIndex(path: ":memory:") }

    init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try db.migrate(Self.migrations)
    }

    deinit {
        for continuation in subscribersLock.withLock({ subscribers.values }) { continuation.finish() }
    }

    public var schemaVersion: Int32 { (try? lock.withLock { try db.userVersion }) ?? 0 }

    /// Every committed row change from now on, in commit order, for as long as the caller iterates (unbounded
    /// buffer, so a slow subscriber misses nothing). Each call is an independent subscription. The stream finishes
    /// when the index is deallocated. A write that throws publishes nothing.
    ///
    /// The buffer has no limit: a stream that is held but not iterated keeps every change in memory. Iterate it, or
    /// drop it (or cancel the task iterating it), which ends the subscription.
    public func changes() -> AsyncStream<IndexChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: IndexChange.self)
        let id = UUID()
        subscribersLock.withLock { subscribers[id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.removeSubscriber(id) }
        return stream
    }

    /// Called with `lock` held, after the write committed, so subscribers see changes in commit order.
    private func publish(_ changes: [IndexChange]) {
        guard !changes.isEmpty else { return }
        for continuation in subscribersLock.withLock({ Array(subscribers.values) }) {
            for change in changes { continuation.yield(change) }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        _ = subscribersLock.withLock { subscribers.removeValue(forKey: id) }
    }

    /// Live `changes()` subscriptions (tests check that a dropped or cancelled stream unsubscribes).
    var subscriberCount: Int { subscribersLock.withLock { subscribers.count } }

    /// Inserts, or updates the row with the same path. Returns the row id.
    /// Publishes `.inserted` or `.updated`; `.updated` also when the saved row equals the stored one (no diffing).
    @discardableResult
    public func save(_ entry: IndexedScreenshot) throws -> Int64 {
        try lock.withLock {
            var existed = false
            try db.query("SELECT 1 FROM screenshots WHERE path = ? LIMIT 1", [.text(entry.path)]) { _ in existed = true }
            var id: Int64 = 0
            try db.query(Self.upsertSQL, Self.columns.map { $0.bind(entry) }) { id = $0.int64(0) }
            publish([IndexChange(existed ? .updated : .inserted, id: id, path: entry.path)])
            return id
        }
    }

    /// After a rename/move/undo. Returns false when no row had `oldPath`.
    /// A row already at `newPath` is stale (its file was deleted or moved away, since our file now lives there) and is
    /// replaced; without that the UNIQUE path would make the update fail after the file was already moved.
    @discardableResult
    public func updatePath(from oldPath: String, to newPath: String) throws -> Bool {
        try lock.withLock {
            var changes: [IndexChange] = []
            let updated = try db.transaction {
                var id: Int64?
                try db.query("SELECT id FROM screenshots WHERE path = ? LIMIT 1", [.text(oldPath)]) { id = $0.int64(0) }
                guard let id else { return false }
                if oldPath == newPath { return true }
                try db.query("DELETE FROM screenshots WHERE path = ? RETURNING id", [.text(newPath)]) {
                    changes.append(IndexChange(.removed, id: $0.int64(0), path: newPath))
                }
                try db.run("UPDATE screenshots SET path = ? WHERE id = ?", [.text(newPath), .int(id)])
                guard db.changes > 0 else { return false }
                changes.append(IndexChange(.updated, id: id, path: newPath))
                return true
            }
            publish(changes)
            return updated
        }
    }

    public func lookup(byPath path: String) throws -> IndexedScreenshot? {
        try select("WHERE path = ? LIMIT 1", [.text(path)]).first
    }

    /// Most recently processed row with this fingerprint.
    public func lookup(byHash hash: String) throws -> IndexedScreenshot? {
        try select("WHERE content_hash = ? ORDER BY COALESCE(processed_at, 0) DESC, id DESC LIMIT 1", [.text(hash)]).first
    }

    public func recent(limit: Int = 50) throws -> [IndexedScreenshot] {
        try select("ORDER BY COALESCE(processed_at, captured_at, 0) DESC, id DESC LIMIT ?", [.int(Int64(limit))])
    }

    /// The newest `done` rows, most recently processed first (the menu's "Recent" list).
    public func recentProcessed(limit: Int = 5) throws -> [IndexedScreenshot] {
        try select("WHERE status = 'done' ORDER BY COALESCE(processed_at, captured_at, 0) DESC, id DESC LIMIT ?",
                   [.int(Int64(limit))])
    }

    /// Flags the row at `path` as restored by Undo. Returns false when no row has that path.
    @discardableResult
    public func markRestoredByUndo(path: String) throws -> Bool {
        try lock.withLock {
            var changes: [IndexChange] = []
            try db.query("UPDATE screenshots SET restored_by_undo = 1 WHERE path = ? RETURNING id", [.text(path)]) {
                changes.append(IndexChange(.updated, id: $0.int64(0), path: path))
            }
            publish(changes)
            return !changes.isEmpty
        }
    }

    /// The conditional text write (spec "Text recognition: when it runs"): sets the text columns of row `id` only if
    /// its `content_hash` still equals `contentHash` (the one read before recognizing) and its `textStatus` is still
    /// `.pending`. Returns whether it applied; publishes `.updated` only then. A stale hash means the file changed
    /// during the read and the processor saved the row again, so the late result is dropped (story 45).
    ///
    /// Sets `textStatus` from `result` (`.done`, `.noText`, `.failed`), `recognizedText` (nil unless `.text`),
    /// `textError` (nil unless `.failed`) and `textRecognizedBy`; nothing else, so the analysis and `status` stay.
    /// Privacy: the recognized text goes only into `recognized_text`. A failure reason must never contain it, and
    /// nothing here logs it.
    @discardableResult
    public func setRecognizedText(_ result: TextRecognitionResult, recognizedBy: String, id: Int64,
                                  ifContentHash contentHash: String) throws -> Bool {
        let (status, text, error): (TextStatus, String?, String?) = switch result {
        case .text(let text): (.done, text, nil)
        case .noText: (.noText, nil, nil)
        case .failed(let reason): (.failed, nil, reason)
        }
        return try lock.withLock {
            var changes: [IndexChange] = []
            try db.query("""
                UPDATE screenshots SET text_status = ?, recognized_text = ?, text_error = ?, text_recognized_by = ?
                WHERE id = ? AND content_hash = ? AND text_status = ? RETURNING path
                """, [.text(status.rawValue), .optional(text), .optional(error), .text(recognizedBy), .int(id),
                      .text(contentHash), .text(TextStatus.pending.rawValue)]) {
                changes.append(IndexChange(.updated, id: id, path: $0.text(0) ?? ""))
            }
            publish(changes)
            return !changes.isEmpty
        }
    }

    /// The text runner's next row: the newest with `textStatus == .pending`, by `COALESCE(captured_at, processed_at)`
    /// (when it was taken, else when it was processed), then newest id. Nil when nothing waits.
    public func newestPendingTextRow() throws -> IndexedScreenshot? {
        try select("WHERE text_status = ? ORDER BY COALESCE(captured_at, processed_at) DESC, id DESC LIMIT 1",
                   [.text(TextStatus.pending.rawValue)]).first
    }

    /// E.g. pending/failed rows to re-enqueue at launch.
    public func entries(withStatus status: ProcessingStatus, limit: Int = 500) throws -> [IndexedScreenshot] {
        try select("WHERE status = ? ORDER BY id LIMIT ?", [.text(status.rawValue), .int(Int64(limit))])
    }

    /// Free-text search. Each term is prefix-matched and all terms must match (AND), each in any FTS column, the
    /// recognized text included. Ranked by bm25 with title > tags > description > source > key text > recognized text
    /// (`ftsColumns`). An empty (or punctuation-only) query returns `recent(limit:)`.
    public func search(_ text: String, limit: Int = 50) throws -> [IndexedScreenshot] {
        guard let match = Self.ftsQuery(text) else { return try recent(limit: limit) }
        return try lock.withLock {
            var rows: [IndexedScreenshot] = []
            try db.query("""
                SELECT \(Self.selectColumns("s")) FROM screenshots_fts
                JOIN screenshots s ON s.id = screenshots_fts.rowid
                WHERE screenshots_fts MATCH ?
                ORDER BY bm25(screenshots_fts, \(Self.bm25Weights)), s.id DESC
                LIMIT ?
                """, [.text(match), .int(Int64(limit))]) { rows.append(Self.row($0)) }
            return rows
        }
    }

    /// The search window's query: free text (same rules as `search(_:limit:)`), an optional content-type chip, an
    /// optional set of paths (a batch from the toast's "View in Search"), an optional date filter and an optional
    /// source, all combined with AND. Only `done` rows (analyzed screenshots) are considered, so `totalCount` matches the menu's
    /// "214 screenshots in the index". The date filter is resolved here, against `now` and `calendar`, so "today" is
    /// today on every call (spec story 5).
    /// The source is resolved to the raw spellings in the index with that key; a key with no rows left finds nothing.
    /// Text → bm25 rank; no text → most recently processed first, or with a date or source filter newest taken first
    /// (the date the rows show, so the list and its labels agree).
    public func search(_ query: ScreenshotQuery, limit: Int = 50, now: Date = Date(),
                       calendar: Calendar = .current) throws -> ScreenshotSearchResult {
        try lock.withLock {
            let spellings = try query.source.map(sourceSpellings) ?? []
            let sql = Self.searchSQL(query, sourceSpellings: spellings, now: now, calendar: calendar)
            var result = ScreenshotSearchResult(rows: [], matchCount: 0, totalCount: 0)
            try db.query(sql.select, sql.bindings + [.int(Int64(max(0, limit)))]) { result.rows.append(Self.row($0)) }
            try db.query(sql.count, sql.bindings) { result.matchCount = Int($0.int64(0)) }
            try db.query("SELECT COUNT(*) FROM screenshots WHERE status = 'done'") { result.totalCount = Int($0.int64(0)) }
            return result
        }
    }

    /// The raw `source_app_or_site` values whose `SourceKey` is `key` (any status, so a row analyzed later still
    /// matches). Reads only the `screenshots_source_app_or_site` index. Call with the lock held.
    private func sourceSpellings(_ key: SourceKey) throws -> [String] {
        var spellings: [String] = []
        try db.query("SELECT DISTINCT source_app_or_site FROM screenshots WHERE source_app_or_site IS NOT NULL") {
            if let raw = $0.text(0), SourceKey(raw) == key { spellings.append(raw) }
        }
        return spellings
    }

    /// The statements `search(_:limit:now:calendar:)` runs: `select` ends in `LIMIT ?` (bind the limit after
    /// `bindings`), `count` takes `bindings` alone. `sourceSpellings` are the raw values `query.source` stands for.
    /// Internal so a test can check their query plan.
    static func searchSQL(_ query: ScreenshotQuery, sourceSpellings: [String] = [], now: Date,
                          calendar: Calendar) -> (select: String, count: String, bindings: [SQLiteValue]) {
        var conditions = ["s.status = 'done'"]
        var bindings: [SQLiteValue] = []
        let match = ftsQuery(query.text)
        if let match {
            conditions.append("screenshots_fts MATCH ?")
            bindings.append(.text(match))
        }
        if let type = query.contentType {
            conditions.append("s.content_type = ?")
            bindings.append(.text(type.rawValue))
        }
        if let paths = query.paths {
            // One JSON-array binding instead of one `?` per path: a batch can hold hundreds of files.
            // json_each: https://www.sqlite.org/json1.html#jeach (built into SQLite since 3.38).
            conditions.append("s.path IN (SELECT value FROM json_each(?))")
            bindings.append(.text(jsonArray(paths)))
        }
        if query.source != nil {
            // The spellings of the chosen source, the same pattern as the batch paths (spec "Filtering by source").
            conditions.append("s.source_app_or_site IN (SELECT value FROM json_each(?))")
            bindings.append(.text(jsonArray(sourceSpellings)))
        }
        if let date = query.date {
            // The date the result row and the preview's "Taken" show (`SearchResultItem.date`). The same expression
            // as the `screenshots_taken_at` index (migration 3), so SQLite can use it.
            let days = date.interval(now: now, calendar: calendar)
            conditions.append("\(takenAt) >= ? AND \(takenAt) < ?")
            bindings += [.optional(days.lowerBound), .optional(days.upperBound)]
        }
        let from = match == nil
            ? "FROM screenshots s"
            : "FROM screenshots_fts JOIN screenshots s ON s.id = screenshots_fts.rowid"
        let whereClause = "WHERE " + conditions.joined(separator: " AND ")
        let order = match != nil ? "ORDER BY bm25(screenshots_fts, \(bm25Weights)), s.id DESC"
            : query.date != nil || query.source != nil ? "ORDER BY \(takenAt) DESC, s.id DESC"
            : "ORDER BY COALESCE(s.processed_at, s.captured_at, 0) DESC, s.id DESC"
        return ("SELECT \(selectColumns("s")) \(from) \(whereClause) \(order) LIMIT ?",
                "SELECT COUNT(*) \(from) \(whereClause)", bindings)
    }

    private static func jsonArray(_ values: [String]) -> String {
        (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// When a screenshot was taken, else when it was processed: what the date filter and the result rows use.
    private static let takenAt = "COALESCE(s.captured_at, s.processed_at)"

    /// The source list for the source filter: one `SourceFacet` per `SourceKey` over all analyzed (`done`) rows,
    /// highest count first, then by name. Rows without a source are left out. Counts cover the whole index, not a query
    /// (wave 1 spec, "Filter model"). Groups by raw value in SQL, then merges the groups by key in Swift.
    public func sources() throws -> [SourceFacet] {
        try lock.withLock {
            var spellings: [(raw: String, count: Int)] = []
            try db.query("""
                SELECT source_app_or_site, COUNT(*) FROM screenshots
                WHERE status = 'done' AND source_app_or_site IS NOT NULL GROUP BY source_app_or_site
                """) { spellings.append(($0.text(0) ?? "", Int($0.int64(1)))) }
            return SourceFacet.merge(spellings)
        }
    }

    public func stats() throws -> IndexStats {
        try lock.withLock {
            var stats = IndexStats(count: 0, done: 0, failed: 0, totalBilledInputTokens: 0)
            try db.query("""
                SELECT COUNT(*), COALESCE(SUM(status = 'done'), 0), COALESCE(SUM(status = 'failed'), 0),
                       COALESCE(SUM(billed_input_tokens), 0) FROM screenshots
                """) {
                stats = IndexStats(count: Int($0.int64(0)), done: Int($0.int64(1)), failed: Int($0.int64(2)),
                                   totalBilledInputTokens: Int($0.int64(3)))
            }
            return stats
        }
    }

    /// Builds a safe FTS5 MATCH expression: every whitespace-separated term becomes a quoted string (quotes doubled)
    /// with a prefix `*`, joined by AND. Terms without any letter or digit are dropped. Nil when nothing is left.
    /// FTS5 syntax: https://www.sqlite.org/fts5.html#full_text_query_syntax (strings, prefix queries, AND).
    public static func ftsQuery(_ text: String) -> String? {
        let terms = text.split(whereSeparator: { $0.isWhitespace }).filter {
            $0.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }.joined(separator: " AND ")
    }

    // MARK: - Schema

    /// The `screenshots_fts` columns in FTS order, each with its bm25 weight: the one list the FTS table, its triggers
    /// (migration 3 on) and `bm25Weights` come from, so they cannot drift apart. Kept apart from `columns` because
    /// FTS order and weights are not column properties.
    ///
    /// 2026-11-28 (wave 1, ticket 01): recognized text joins the match at the lowest weight, so a title hit counts 20x
    /// a hit only in the text (spec "FTS match and ranking"). Changing this list needs a new migration that rebuilds
    /// FTS with it; migration 3 must then get its own frozen copy of today's list (shipped steps never change).
    static let ftsColumns: [(name: String, weight: Double)] = [
        ("title", 10), ("tags", 6), ("description", 3), ("key_text", 1), ("source_app_or_site", 2),
        ("recognized_text", 0.5),
    ]

    /// `bm25()` weights in `ftsColumns` order: "10.0, 6.0, 3.0, 1.0, 2.0, 0.5".
    static let bm25Weights = ftsColumns.map { String($0.weight) }.joined(separator: ", ")

    /// Every column except `id`, in table order. The one place a column is declared: `CREATE TABLE` (migration 1),
    /// `ALTER TABLE ... ADD COLUMN` (later migrations), the upsert, its bindings and the row read all come from here.
    ///
    /// Adding a column (2026-11-28): append one entry with the next `addedIn` version, add
    /// `SQLiteMigration(version: n, statements: addColumns("new_column"))` to `migrations`, and append `(n, ["new_column"])`
    /// to the test's `shippedColumns`. The migration line names its columns, so two PRs that both take version n add
    /// different lines at the same spot and git reports a conflict; keeping both lines fails the versions test, and a
    /// column moved to the wrong migration fails the `addedIn` and `shippedColumns` tests. The second PR to merge
    /// renumbers. Never edit or reorder a shipped entry: existing databases were created from it.
    static let columns: [IndexColumn] = [
        // `path` first: it is the upsert key.
        IndexColumn("path", "TEXT NOT NULL UNIQUE", bind: { .text($0.path) }, read: { $0.path = $1.text ?? "" }),
        IndexColumn("original_filename", "TEXT NOT NULL",
                    bind: { .text($0.originalFilename) }, read: { $0.originalFilename = $1.text ?? "" }),
        IndexColumn("content_hash", "TEXT NOT NULL", bind: { .text($0.contentHash) }, read: { $0.contentHash = $1.text ?? "" }),
        IndexColumn("captured_at", "REAL", bind: { .optional($0.capturedAt) }, read: { $0.capturedAt = $1.date }),
        IndexColumn("processed_at", "REAL", bind: { .optional($0.processedAt) }, read: { $0.processedAt = $1.date }),
        IndexColumn("title", "TEXT", bind: { .optional($0.title) }, read: { $0.title = $1.text }),
        IndexColumn("title_confidence", "REAL",
                    bind: { .optional($0.titleConfidence) }, read: { $0.titleConfidence = $1.double }),
        IndexColumn("source_app_or_site", "TEXT",
                    bind: { .optional($0.sourceAppOrSite) }, read: { $0.sourceAppOrSite = $1.text }),
        IndexColumn("content_type", "TEXT", bind: { .optional($0.contentType?.rawValue) },
                    read: { $0.contentType = $1.text.flatMap(ContentType.init(rawValue:)) }),
        IndexColumn("description", "TEXT", bind: { .optional($0.description) }, read: { $0.description = $1.text }),
        IndexColumn("tags", "TEXT NOT NULL DEFAULT '[]'", bind: { .text(tagsJSON($0.tags)) },
                    read: { $0.tags = $1.text.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? [] }),
        IndexColumn("key_text", "TEXT", bind: { .optional($0.keyText) }, read: { $0.keyText = $1.text }),
        IndexColumn("date_mentioned", "TEXT", bind: { .optional($0.dateMentioned) }, read: { $0.dateMentioned = $1.text }),
        IndexColumn("produced_by", "TEXT", bind: { .optional($0.producedBy) }, read: { $0.producedBy = $1.text }),
        IndexColumn("billed_input_tokens", "INTEGER",
                    bind: { .optional($0.billedInputTokens) }, read: { $0.billedInputTokens = $1.int }),
        IndexColumn("status", "TEXT NOT NULL DEFAULT 'pending'", bind: { .text($0.status.rawValue) },
                    read: { $0.status = $1.text.flatMap(ProcessingStatus.init(rawValue:)) ?? .pending }),
        IndexColumn("last_error", "TEXT", bind: { .optional($0.lastError) }, read: { $0.lastError = $1.text }),
        IndexColumn("note", "TEXT", bind: { .optional($0.note) }, read: { $0.note = $1.text }),
        // 2026-11-21 (UI polish PR 1): a file the user restored with Undo is never processed again, even after a
        // restart or when its content fingerprint changes.
        IndexColumn("restored_by_undo", "INTEGER NOT NULL DEFAULT 0", addedIn: 2,
                    bind: { .int($0.restoredByUndo ? 1 : 0) }, read: { $0.restoredByUndo = ($1.int ?? 0) != 0 }),
        // 2026-11-28 (wave 1, ticket 01): on-device text recognition. Rows from before get NULLs (not requested).
        IndexColumn("recognized_text", "TEXT", addedIn: 3,
                    bind: { .optional($0.recognizedText) }, read: { $0.recognizedText = $1.text }),
        IndexColumn("text_status", "TEXT", addedIn: 3, bind: { .optional($0.textStatus?.rawValue) },
                    read: { $0.textStatus = $1.text.flatMap(TextStatus.init(rawValue:)) }),
        IndexColumn("text_recognized_by", "TEXT", addedIn: 3,
                    bind: { .optional($0.textRecognizedBy) }, read: { $0.textRecognizedBy = $1.text }),
        IndexColumn("text_error", "TEXT", addedIn: 3,
                    bind: { .optional($0.textError) }, read: { $0.textError = $1.text }),
    ]

    /// Applied in order by `SQLiteDatabase.migrate`; `user_version` is the last one applied. Versions are 1, 2, 3, ...
    /// with no gaps (tested). Shipped steps are history: never change what they produce.
    static let migrations: [SQLiteMigration] = [
        SQLiteMigration(version: 1, statements: [
            "CREATE TABLE screenshots (\n    id INTEGER PRIMARY KEY,\n"
                + columns(addedIn: 1).map { "    \($0.name) \($0.definition)" }.joined(separator: ",\n") + "\n)",
            "CREATE INDEX screenshots_content_hash ON screenshots(content_hash)",
            "CREATE INDEX screenshots_processed_at ON screenshots(processed_at)",
            """
            CREATE VIRTUAL TABLE screenshots_fts USING fts5(
                title, tags, description, key_text, source_app_or_site,
                content='screenshots', content_rowid='id', tokenize='unicode61 remove_diacritics 2'
            )
            """,
            """
            CREATE TRIGGER screenshots_ai AFTER INSERT ON screenshots BEGIN
                INSERT INTO screenshots_fts(rowid, title, tags, description, key_text, source_app_or_site)
                VALUES (new.id, new.title, new.tags, new.description, new.key_text, new.source_app_or_site);
            END
            """,
            """
            CREATE TRIGGER screenshots_ad AFTER DELETE ON screenshots BEGIN
                INSERT INTO screenshots_fts(screenshots_fts, rowid, title, tags, description, key_text, source_app_or_site)
                VALUES ('delete', old.id, old.title, old.tags, old.description, old.key_text, old.source_app_or_site);
            END
            """,
            """
            CREATE TRIGGER screenshots_au AFTER UPDATE OF title, tags, description, key_text, source_app_or_site ON screenshots BEGIN
                INSERT INTO screenshots_fts(screenshots_fts, rowid, title, tags, description, key_text, source_app_or_site)
                VALUES ('delete', old.id, old.title, old.tags, old.description, old.key_text, old.source_app_or_site);
                INSERT INTO screenshots_fts(rowid, title, tags, description, key_text, source_app_or_site)
                VALUES (new.id, new.title, new.tags, new.description, new.key_text, new.source_app_or_site);
            END
            """,
        ]),
        SQLiteMigration(version: 2, statements: addColumns("restored_by_undo")),
        SQLiteMigration(version: 3, statements:
            addColumns("recognized_text", "text_status", "text_recognized_by", "text_error")
                + rebuildFTS(ftsColumns.map(\.name)) + [
            // Story 23: the date filter's condition, matched exactly by the expression (SQLite uses an expression index
            // only for the identical expression: https://www.sqlite.org/expridx.html).
            "CREATE INDEX screenshots_taken_at ON screenshots(COALESCE(captured_at, processed_at))",
            "CREATE INDEX screenshots_source_app_or_site ON screenshots(source_app_or_site)",
            // The text runner's queue: only `pending` rows are in it (https://www.sqlite.org/partialindex.html).
            "CREATE INDEX screenshots_text_pending ON screenshots(text_status) WHERE text_status = 'pending'",
        ]),
    ]

    /// Upsert by path; returns the row id.
    private static let upsertSQL = """
        INSERT INTO screenshots (\(columns.map(\.name).joined(separator: ", ")))
        VALUES (\(Array(repeating: "?", count: columns.count).joined(separator: ", ")))
        ON CONFLICT(path) DO UPDATE SET \(columns.dropFirst().map { "\($0.name) = excluded.\($0.name)" }.joined(separator: ", "))
        RETURNING id
        """

    static func columns(addedIn version: Int32) -> [IndexColumn] { columns.filter { $0.addedIn == version } }

    /// `ALTER TABLE` statements adding the named `columns` entries, in that order (SQLite appends them, so the
    /// table order is the order of the migrations). Tests check each name's `addedIn` is the migration it is in.
    static func addColumns(_ names: String...) -> [String] {
        names.map { name in
            guard let column = columns.first(where: { $0.name == name }) else {
                preconditionFailure("addColumns: no column named \(name) in ScreenshotIndex.columns")
            }
            return "ALTER TABLE screenshots ADD COLUMN \(column.name) \(column.definition)"
        }
    }

    /// Replaces `screenshots_fts` and its three triggers with ones over `ftsColumns`, then refills it from
    /// `screenshots`. An FTS5 table cannot gain a column, so it is dropped and created again. The `'rebuild'` command
    /// discards the full-text index and rebuilds it from the external content table (https://www.sqlite.org/fts5.html,
    /// "The 'rebuild' Command"). The triggers follow
    /// "External Content Tables" on the same page (an update deletes the old values, then inserts the new ones).
    static func rebuildFTS(_ ftsColumns: [String]) -> [String] {
        let list = ftsColumns.joined(separator: ", ")
        let old = ftsColumns.map { "old.\($0)" }.joined(separator: ", ")
        let new = ftsColumns.map { "new.\($0)" }.joined(separator: ", ")
        return [
            "DROP TRIGGER screenshots_ai",
            "DROP TRIGGER screenshots_ad",
            "DROP TRIGGER screenshots_au",
            "DROP TABLE screenshots_fts",
            """
            CREATE VIRTUAL TABLE screenshots_fts USING fts5(
                \(list),
                content='screenshots', content_rowid='id', tokenize='unicode61 remove_diacritics 2'
            )
            """,
            """
            CREATE TRIGGER screenshots_ai AFTER INSERT ON screenshots BEGIN
                INSERT INTO screenshots_fts(rowid, \(list)) VALUES (new.id, \(new));
            END
            """,
            """
            CREATE TRIGGER screenshots_ad AFTER DELETE ON screenshots BEGIN
                INSERT INTO screenshots_fts(screenshots_fts, rowid, \(list)) VALUES ('delete', old.id, \(old));
            END
            """,
            """
            CREATE TRIGGER screenshots_au AFTER UPDATE OF \(list) ON screenshots BEGIN
                INSERT INTO screenshots_fts(screenshots_fts, rowid, \(list)) VALUES ('delete', old.id, \(old));
                INSERT INTO screenshots_fts(rowid, \(list)) VALUES (new.id, \(new));
            END
            """,
            "INSERT INTO screenshots_fts(screenshots_fts) VALUES ('rebuild')",
        ]
    }

    private static func tagsJSON(_ tags: [String]) -> String {
        (try? JSONEncoder().encode(tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// `id` then every column, so `row(_:)` finds each value at the position its column has in this list.
    private static func selectColumns(_ alias: String) -> String {
        (["id"] + columns.map(\.name)).map { "\(alias).\($0)" }.joined(separator: ", ")
    }

    private static func row(_ s: SQLiteStatement) -> IndexedScreenshot {
        var entry = IndexedScreenshot(id: s.int64(0), path: "", originalFilename: "", contentHash: "")
        for (offset, column) in columns.enumerated() {
            column.read(&entry, SQLiteColumnValue(statement: s, index: Int32(offset + 1)))
        }
        return entry
    }

    private func select(_ clause: String, _ bindings: [SQLiteValue]) throws -> [IndexedScreenshot] {
        try lock.withLock {
            var rows: [IndexedScreenshot] = []
            try db.query("SELECT \(Self.selectColumns("screenshots")) FROM screenshots \(clause)", bindings) {
                rows.append(Self.row($0))
            }
            return rows
        }
    }
}

/// One column of `screenshots` (not `id`): its SQL, how a row is bound to it and how it is read back.
/// The list is `ScreenshotIndex.columns`.
struct IndexColumn: Sendable {
    let name: String
    /// Type and constraints, as in `CREATE TABLE` / `ADD COLUMN`.
    let definition: String
    /// The migration that adds it (1 = the original `CREATE TABLE`).
    let addedIn: Int32
    let bind: @Sendable (IndexedScreenshot) -> SQLiteValue
    let read: @Sendable (inout IndexedScreenshot, SQLiteColumnValue) -> Void

    init(_ name: String, _ definition: String, addedIn: Int32 = 1,
         bind: @escaping @Sendable (IndexedScreenshot) -> SQLiteValue,
         read: @escaping @Sendable (inout IndexedScreenshot, SQLiteColumnValue) -> Void) {
        self.name = name
        self.definition = definition
        self.addedIn = addedIn
        self.bind = bind
        self.read = read
    }
}
