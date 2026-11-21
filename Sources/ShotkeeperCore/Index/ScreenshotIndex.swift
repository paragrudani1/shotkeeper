import Foundation

public enum ProcessingStatus: String, Codable, Sendable, CaseIterable {
    case pending, done, failed, skipped
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

    public init(id: Int64 = 0, path: String, originalFilename: String, contentHash: String, capturedAt: Date? = nil,
                processedAt: Date? = nil, title: String? = nil, titleConfidence: Double? = nil, sourceAppOrSite: String? = nil,
                contentType: ContentType? = nil, description: String? = nil, tags: [String] = [], keyText: String? = nil,
                dateMentioned: String? = nil, producedBy: String? = nil, billedInputTokens: Int? = nil,
                status: ProcessingStatus = .pending, lastError: String? = nil, note: String? = nil,
                restoredByUndo: Bool = false) {
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

/// What the search window asks the index for (see `ScreenshotIndex.search(_:limit:)`).
public struct ScreenshotQuery: Equatable, Sendable {
    /// Free text; empty = no text filter (recent first).
    public var text: String
    /// The selected type chip; nil = All.
    public var contentType: ContentType?
    /// Only these paths (a batch from the toast); nil = the whole index.
    public var paths: [String]?

    public init(text: String = "", contentType: ContentType? = nil, paths: [String]? = nil) {
        self.text = text
        self.contentType = contentType
        self.paths = paths
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

    public var schemaVersion: Int32 { (try? lock.withLock { try db.userVersion }) ?? 0 }

    /// Inserts, or updates the row with the same path. Returns the row id.
    @discardableResult
    public func save(_ entry: IndexedScreenshot) throws -> Int64 {
        try lock.withLock {
            var id: Int64 = 0
            try db.query("""
                INSERT INTO screenshots (\(Self.writableColumns.joined(separator: ", ")))
                VALUES (\(Array(repeating: "?", count: Self.writableColumns.count).joined(separator: ", ")))
                ON CONFLICT(path) DO UPDATE SET \(Self.writableColumns.dropFirst().map { "\($0) = excluded.\($0)" }.joined(separator: ", "))
                RETURNING id
                """, Self.bindings(entry)) { id = $0.int64(0) }
            return id
        }
    }

    /// After a rename/move/undo. Returns false when no row had `oldPath`.
    /// A row already at `newPath` is stale (its file was deleted or moved away, since our file now lives there) and is
    /// replaced; without that the UNIQUE path would make the update fail after the file was already moved.
    @discardableResult
    public func updatePath(from oldPath: String, to newPath: String) throws -> Bool {
        try lock.withLock {
            try db.transaction {
                var exists = false
                try db.query("SELECT 1 FROM screenshots WHERE path = ? LIMIT 1", [.text(oldPath)]) { _ in exists = true }
                guard exists else { return false }
                if oldPath == newPath { return true }
                try db.run("DELETE FROM screenshots WHERE path = ?", [.text(newPath)])
                try db.run("UPDATE screenshots SET path = ? WHERE path = ?", [.text(newPath), .text(oldPath)])
                return db.changes > 0
            }
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
            try db.run("UPDATE screenshots SET restored_by_undo = 1 WHERE path = ?", [.text(path)])
            return db.changes > 0
        }
    }

    /// E.g. pending/failed rows to re-enqueue at launch.
    public func entries(withStatus status: ProcessingStatus, limit: Int = 500) throws -> [IndexedScreenshot] {
        try select("WHERE status = ? ORDER BY id LIMIT ?", [.text(status.rawValue), .int(Int64(limit))])
    }

    /// Free-text search. Each term is prefix-matched and all terms must match (AND). Ranked by bm25 with
    /// title > tags > description > source > key text. An empty (or punctuation-only) query returns `recent(limit:)`.
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

    /// The search window's query: free text (same rules as `search(_:limit:)`), an optional content-type chip and an
    /// optional set of paths (a batch from the toast's "View in Search"), all combined with AND. Only `done` rows
    /// (analyzed screenshots) are considered, so `totalCount` matches the menu's "214 screenshots in the index".
    /// Text → bm25 rank; no text → most recently processed first.
    public func search(_ query: ScreenshotQuery, limit: Int = 50) throws -> ScreenshotSearchResult {
        var conditions = ["s.status = 'done'"]
        var bindings: [SQLiteValue] = []
        let match = Self.ftsQuery(query.text)
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
            let json = (try? JSONEncoder().encode(paths)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            conditions.append("s.path IN (SELECT value FROM json_each(?))")
            bindings.append(.text(json))
        }
        let from = match == nil
            ? "FROM screenshots s"
            : "FROM screenshots_fts JOIN screenshots s ON s.id = screenshots_fts.rowid"
        let whereClause = "WHERE " + conditions.joined(separator: " AND ")
        let order = match == nil
            ? "ORDER BY COALESCE(s.processed_at, s.captured_at, 0) DESC, s.id DESC"
            : "ORDER BY bm25(screenshots_fts, \(Self.bm25Weights)), s.id DESC"
        return try lock.withLock {
            var result = ScreenshotSearchResult(rows: [], matchCount: 0, totalCount: 0)
            try db.query("SELECT \(Self.selectColumns("s")) \(from) \(whereClause) \(order) LIMIT ?",
                         bindings + [.int(Int64(max(0, limit)))]) { result.rows.append(Self.row($0)) }
            try db.query("SELECT COUNT(*) \(from) \(whereClause)", bindings) { result.matchCount = Int($0.int64(0)) }
            try db.query("SELECT COUNT(*) FROM screenshots WHERE status = 'done'") { result.totalCount = Int($0.int64(0)) }
            return result
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

    /// FTS column order: title, tags, description, key_text, source_app_or_site.
    static let bm25Weights = "10.0, 6.0, 3.0, 1.0, 2.0"

    static let migrations: [SQLiteMigration] = [
        SQLiteMigration(version: 1, statements: [
            """
            CREATE TABLE screenshots (
                id INTEGER PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                original_filename TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                captured_at REAL,
                processed_at REAL,
                title TEXT,
                title_confidence REAL,
                source_app_or_site TEXT,
                content_type TEXT,
                description TEXT,
                tags TEXT NOT NULL DEFAULT '[]',
                key_text TEXT,
                date_mentioned TEXT,
                produced_by TEXT,
                billed_input_tokens INTEGER,
                status TEXT NOT NULL DEFAULT 'pending',
                last_error TEXT,
                note TEXT
            )
            """,
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
        // 2026-11-21 (UI polish PR 1): a file the user restored with Undo is never processed again, even after a
        // restart or when its content fingerprint changes.
        SQLiteMigration(version: 2, statements: [
            "ALTER TABLE screenshots ADD COLUMN restored_by_undo INTEGER NOT NULL DEFAULT 0",
        ]),
    ]

    /// Every column except id, in insert order. `path` first: it is the upsert key.
    private static let writableColumns = [
        "path", "original_filename", "content_hash", "captured_at", "processed_at", "title", "title_confidence",
        "source_app_or_site", "content_type", "description", "tags", "key_text", "date_mentioned", "produced_by",
        "billed_input_tokens", "status", "last_error", "note", "restored_by_undo",
    ]

    private static func selectColumns(_ alias: String) -> String {
        (["id"] + writableColumns).map { "\(alias).\($0)" }.joined(separator: ", ")
    }

    private static func bindings(_ e: IndexedScreenshot) -> [SQLiteValue] {
        let tagsJSON = (try? JSONEncoder().encode(e.tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return [
            .text(e.path), .text(e.originalFilename), .text(e.contentHash), .optional(e.capturedAt), .optional(e.processedAt),
            .optional(e.title), .optional(e.titleConfidence), .optional(e.sourceAppOrSite), .optional(e.contentType?.rawValue),
            .optional(e.description), .text(tagsJSON), .optional(e.keyText), .optional(e.dateMentioned),
            .optional(e.producedBy), .optional(e.billedInputTokens), .text(e.status.rawValue), .optional(e.lastError),
            .optional(e.note), .int(e.restoredByUndo ? 1 : 0),
        ]
    }

    private static func row(_ s: SQLiteStatement) -> IndexedScreenshot {
        let tags = s.text(11).flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
        return IndexedScreenshot(
            id: s.int64(0), path: s.text(1) ?? "", originalFilename: s.text(2) ?? "", contentHash: s.text(3) ?? "",
            capturedAt: s.optionalDate(4), processedAt: s.optionalDate(5), title: s.text(6), titleConfidence: s.optionalDouble(7),
            sourceAppOrSite: s.text(8), contentType: s.text(9).flatMap(ContentType.init(rawValue:)), description: s.text(10),
            tags: tags, keyText: s.text(12), dateMentioned: s.text(13), producedBy: s.text(14),
            billedInputTokens: s.optionalInt(15), status: s.text(16).flatMap(ProcessingStatus.init(rawValue:)) ?? .pending,
            lastError: s.text(17), note: s.text(18), restoredByUndo: s.int64(19) != 0)
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
