import XCTest
@testable import ShotkeeperCore

final class ScreenshotIndexTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ path: String, title: String? = nil, tags: [String] = [], description: String? = nil,
                       keyText: String? = nil, source: String? = nil, hash: String? = nil, minutes: Double = 0,
                       tokens: Int? = nil, status: ProcessingStatus = .done) -> IndexedScreenshot {
        IndexedScreenshot(path: path, originalFilename: "Screenshot.png", contentHash: hash ?? "h-\(path)",
                          capturedAt: t0, processedAt: t0.addingTimeInterval(minutes * 60), title: title,
                          titleConfidence: 0.9, sourceAppOrSite: source, contentType: .other, description: description,
                          tags: tags, keyText: keyText, billedInputTokens: tokens, status: status)
    }

    func testSaveLookupAndUpsertByPath() throws {
        let index = try ScreenshotIndex.inMemory()
        var row = entry("/a.png", title: "Alpha", tags: ["x", "y"], hash: "H1", tokens: 100)
        let id = try index.save(row)
        XCTAssertGreaterThan(id, 0)
        var stored = try XCTUnwrap(index.lookup(byPath: "/a.png"))
        XCTAssertEqual(stored.id, id)
        row.id = id
        XCTAssertEqual(stored, row)
        XCTAssertEqual(try index.lookup(byHash: "H1")?.id, id)
        XCTAssertNil(try index.lookup(byPath: "/missing.png"))

        row.title = "Alpha 2"
        row.status = .failed
        row.lastError = "boom"
        XCTAssertEqual(try index.save(row), id, "same path updates the row")
        stored = try XCTUnwrap(index.lookup(byPath: "/a.png"))
        XCTAssertEqual(stored.title, "Alpha 2")
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.lastError, "boom")
        XCTAssertEqual(try index.entries(withStatus: .failed).map(\.id), [id])
    }

    func testUpdatePath() throws {
        let index = try ScreenshotIndex.inMemory()
        try index.save(entry("/a.png", title: "Alpha"))
        XCTAssertTrue(try index.updatePath(from: "/a.png", to: "/b.png"))
        XCTAssertFalse(try index.updatePath(from: "/a.png", to: "/c.png"))
        XCTAssertNil(try index.lookup(byPath: "/a.png"))
        XCTAssertEqual(try index.lookup(byPath: "/b.png")?.title, "Alpha")
        XCTAssertEqual(try index.search("alpha").map(\.path), ["/b.png"])
    }

    func testUpdatePathOntoStaleRowReplacesIt() throws {
        // A row whose file is gone still holds "/b.png"; a new file now lives there. The UNIQUE path must not
        // make the update fail, and the stale row must leave the FTS index too.
        let index = try ScreenshotIndex.inMemory()
        try index.save(entry("/b.png", title: "Stale"))
        try index.save(entry("/a.png", title: "Fresh"))
        XCTAssertTrue(try index.updatePath(from: "/a.png", to: "/b.png"))
        XCTAssertEqual(try index.lookup(byPath: "/b.png")?.title, "Fresh")
        XCTAssertEqual(try index.stats().count, 1)
        XCTAssertEqual(try index.search("stale"), [])
        XCTAssertEqual(try index.search("fresh").map(\.path), ["/b.png"])
        // Same path or a missing source leaves the target alone.
        XCTAssertTrue(try index.updatePath(from: "/b.png", to: "/b.png"))
        XCTAssertFalse(try index.updatePath(from: "/missing.png", to: "/b.png"))
        XCTAssertEqual(try index.lookup(byPath: "/b.png")?.title, "Fresh")
    }

    func testRecentAndStats() throws {
        let index = try ScreenshotIndex.inMemory()
        try index.save(entry("/old.png", minutes: 0, tokens: 100))
        try index.save(entry("/new.png", minutes: 5, tokens: 250))
        try index.save(entry("/failed.png", minutes: 1, status: .failed))
        XCTAssertEqual(try index.recent(limit: 2).map(\.path), ["/new.png", "/failed.png"])
        XCTAssertEqual(try index.stats(), IndexStats(count: 3, done: 2, failed: 1, totalBilledInputTokens: 350))
        XCTAssertEqual(try index.search("", limit: 10).map(\.path), ["/new.png", "/failed.png", "/old.png"])
        XCTAssertEqual(try index.search("  \"*  ", limit: 1).map(\.path), ["/new.png"], "punctuation-only = recent")
    }

    func testSearchRankingTitleOverTagsOverDescriptionOverKeyText() throws {
        let index = try ScreenshotIndex.inMemory()
        try index.save(entry("/keytext.png", title: "Alpha one", tags: ["misc"], description: "A plain picture", keyText: "invoice"))
        try index.save(entry("/description.png", title: "Alpha two", tags: ["misc"], description: "An invoice picture", keyText: "none"))
        try index.save(entry("/tags.png", title: "Alpha three", tags: ["invoice"], description: "A plain picture", keyText: "none"))
        try index.save(entry("/title.png", title: "Invoice four", tags: ["misc"], description: "A plain picture", keyText: "none"))
        try index.save(entry("/other.png", title: "Unrelated", tags: ["misc"], description: "Nothing", keyText: "none"))
        XCTAssertEqual(try index.search("invoice").map(\.path), ["/title.png", "/tags.png", "/description.png", "/keytext.png"])
    }

    func testPrefixAndAndAndDiacritics() throws {
        let index = try ScreenshotIndex.inMemory()
        try index.save(entry("/1.png", title: "Invoice from Acme", source: "Mail"))
        try index.save(entry("/2.png", title: "Invoice from Globex"))
        try index.save(entry("/3.png", title: "Menu at Café Luna"))
        XCTAssertEqual(Set(try index.search("inv").map(\.path)), ["/1.png", "/2.png"])
        XCTAssertEqual(try index.search("invoice acm").map(\.path), ["/1.png"])
        XCTAssertEqual(try index.search("INVOICE mail").map(\.path), ["/1.png"])
        XCTAssertEqual(try index.search("cafe").map(\.path), ["/3.png"])
        XCTAssertEqual(try index.search("invoice luna"), [])
    }

    func testHostileQueriesDoNotThrow() throws {
        let index = try ScreenshotIndex.inMemory()
        try index.save(entry("/1.png", title: #"He said "hi" (loudly)"#, keyText: "a*b NEAR(x y) title:z"))
        let queries = [#"""#, #""hi"#, "*", "a*b", "NEAR(", "AND", "OR NOT", "title:z", "(", ")", "-x", "^hi", "'", "\\",
                       "😀", "{}", "col:", "\u{0}", #"" OR 1=1 --"#, "hi\"", "x\" OR \"y"]
        for query in queries {
            XCTAssertNoThrow(try index.search(query), query)
        }
        XCTAssertEqual(try index.search(#""hi"#).map(\.path), ["/1.png"])
        XCTAssertEqual(try index.search("near(x").map(\.path), ["/1.png"])
    }

    // MARK: - Recognized text (wave 1, ticket 01)

    func testRecognizedTextIsPartOfTheAndMatch() throws {
        let index = try ScreenshotIndex.inMemory()
        try index.save(.testRow("/both.png") { $0.title = "Invoice from Acme"; $0.recognizedText = "Total due\nPayable to Globex" })
        try index.save(.testRow("/title-only.png") { $0.title = "Invoice from Initech" })
        try index.save(.testRow("/text-only.png") { $0.title = "Lunch menu"; $0.recognizedText = "Globex cafeteria" })
        XCTAssertEqual(try index.search("invoice globex").map(\.path), ["/both.png"], "one term in the title, one only in the text")
        XCTAssertEqual(Set(try index.search("globex").map(\.path)), ["/both.png", "/text-only.png"])
        XCTAssertEqual(try index.search(ScreenshotQuery(text: "invoice payable")).rows.map(\.path), ["/both.png"])
        XCTAssertEqual(try index.search("invoice nowhere"), [], "every term must match somewhere")
    }

    /// Spec story 27: a hit only in the recognized text ranks below a title, tags or description hit. Pins the order,
    /// not the weights. The text-only row has the shortest text, which bm25 favours most.
    func testRecognizedTextHitRanksBelowTitleTagsAndDescription() throws {
        let index = try ScreenshotIndex.inMemory()
        try index.save(.testRow("/text.png") {
            $0.title = "Alpha one"; $0.tags = ["misc"]; $0.description = "A plain picture"; $0.recognizedText = "invoice"
        })
        try index.save(.testRow("/description.png") {
            $0.title = "Alpha two"; $0.tags = ["misc"]; $0.description = "An invoice picture"; $0.recognizedText = "plain words here"
        })
        try index.save(.testRow("/tags.png") {
            $0.title = "Alpha three"; $0.tags = ["invoice"]; $0.description = "A plain picture"; $0.recognizedText = "plain words here"
        })
        try index.save(.testRow("/title.png") {
            $0.title = "Invoice four"; $0.tags = ["misc"]; $0.description = "A plain picture"; $0.recognizedText = "plain words here"
        })
        let expected = ["/title.png", "/tags.png", "/description.png", "/text.png"]
        XCTAssertEqual(try index.search("invoice").map(\.path), expected)
        XCTAssertEqual(try index.search(ScreenshotQuery(text: "invoice")).rows.map(\.path), expected)
    }

    func testFTSQueryBuilder() {
        XCTAssertEqual(ScreenshotIndex.ftsQuery("foo bar"), #""foo"* AND "bar"*"#)
        XCTAssertEqual(ScreenshotIndex.ftsQuery(#"say "hi""#), #""say"* AND """hi"""*"#)
        XCTAssertNil(ScreenshotIndex.ftsQuery(" - * \" "))
    }

    func testFTSFollowsUpdates() throws {
        let index = try ScreenshotIndex.inMemory()
        var row = entry("/1.png", title: "Old title")
        row.id = try index.save(row)
        row.title = "Fresh title"
        try index.save(row)
        XCTAssertEqual(try index.search("old"), [])
        XCTAssertEqual(try index.search("fresh").map(\.path), ["/1.png"])
    }

    func testFileIndexMigratesOnceUsesWALAndPersists() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("db/index.sqlite")
        do {
            let index = try ScreenshotIndex(fileURL: url)
            XCTAssertEqual(index.schemaVersion, Int32(ScreenshotIndex.migrations.count))
            try index.save(entry("/1.png", title: "Kept"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + "-wal"), "WAL mode")
        }
        let reopened = try ScreenshotIndex(fileURL: url)
        XCTAssertEqual(reopened.schemaVersion, Int32(ScreenshotIndex.migrations.count))
        XCTAssertEqual(try reopened.search("kept").map(\.path), ["/1.png"])
    }

    func testRecentProcessedAndRestoredFlag() throws {
        let index = try ScreenshotIndex.inMemory()
        try index.save(entry("/old.png", minutes: 1))
        try index.save(entry("/new.png", minutes: 5))
        try index.save(entry("/failed.png", minutes: 9, status: .failed))
        XCTAssertEqual(try index.recentProcessed(limit: 5).map(\.path), ["/new.png", "/old.png"])
        XCTAssertEqual(try index.recentProcessed(limit: 1).map(\.path), ["/new.png"])

        XCTAssertEqual(try index.lookup(byPath: "/old.png")?.restoredByUndo, false)
        XCTAssertTrue(try index.markRestoredByUndo(path: "/old.png"))
        XCTAssertFalse(try index.markRestoredByUndo(path: "/missing.png"))
        XCTAssertEqual(try index.lookup(byPath: "/old.png")?.restoredByUndo, true)
        XCTAssertTrue(try index.updatePath(from: "/old.png", to: "/moved.png"))
        XCTAssertEqual(try index.lookup(byPath: "/moved.png")?.restoredByUndo, true, "the flag follows the row")
    }

    func testVersionOneDatabaseMigratesWithRowsKept() throws {
        let dir = try TempDir()
        let path = dir.url.appendingPathComponent("index.sqlite").path
        do {
            let db = try SQLiteDatabase(path: path)
            try db.migrate([ScreenshotIndex.migrations[0]])
            try db.run("INSERT INTO screenshots (path, original_filename, content_hash, status) VALUES (?, ?, ?, 'done')",
                       [.text("/v1.png"), .text("Screenshot.png"), .text("h")])
        }
        let index = try ScreenshotIndex(fileURL: URL(fileURLWithPath: path))
        XCTAssertEqual(index.schemaVersion, ScreenshotIndex.migrations.last?.version)
        let row = try XCTUnwrap(index.lookup(byPath: "/v1.png"))
        XCTAssertFalse(row.restoredByUndo)
    }

    /// Migration 3 replaces the FTS table: rows saved before it are still found (the 'rebuild' refilled it), keep their
    /// values, and get no text status (not requested).
    func testVersionTwoDatabaseMigratesWithRowsStillFoundAndNoTextStatus() throws {
        let dir = try TempDir()
        let path = dir.url.appendingPathComponent("index.sqlite").path
        do {
            let db = try SQLiteDatabase(path: path)
            try db.migrate(Array(ScreenshotIndex.migrations.prefix(2)))
            XCTAssertEqual(try db.userVersion, 2)
            try db.run("""
                INSERT INTO screenshots (path, original_filename, content_hash, title, tags, key_text, source_app_or_site,
                    status) VALUES ('/a.png', 'a.png', 'ha', 'Invoice from Acme', '["billing"]', 'Total 42', 'Mail', 'done')
                """)
            try db.run("""
                INSERT INTO screenshots (path, original_filename, content_hash, description, status)
                VALUES ('/b.png', 'b.png', 'hb', 'Globex dashboard', 'done')
                """)
        }
        let index = try ScreenshotIndex(fileURL: URL(fileURLWithPath: path))
        XCTAssertEqual(index.schemaVersion, ScreenshotIndex.migrations.last?.version)
        for (query, expected) in [("acme", "/a.png"), ("billing", "/a.png"), ("total", "/a.png"), ("mail", "/a.png"),
                                  ("globex", "/b.png")] {
            XCTAssertEqual(try index.search(query).map(\.path), [expected], query)
            XCTAssertEqual(try index.search(ScreenshotQuery(text: query)).rows.map(\.path), [expected], query)
        }
        for path in ["/a.png", "/b.png"] {
            let row = try XCTUnwrap(index.lookup(byPath: path))
            XCTAssertNil(row.textStatus, path)
            XCTAssertNil(row.recognizedText, path)
            XCTAssertNil(row.textRecognizedBy, path)
            XCTAssertNil(row.textError, path)
        }
        // The new triggers keep FTS in step after the migration too.
        try index.save(.testRow("/a.png") { $0.title = "Renamed"; $0.recognizedText = "Quarterly figures" })
        XCTAssertEqual(try index.search("acme"), [])
        XCTAssertEqual(try index.search("renamed quarterly").map(\.path), ["/a.png"])
    }

    /// Migration 4 (wave 2, spec "Index schema"): a name the user typed in the toast before this feature is marked as
    /// theirs, found by the note `rename(_:to:)` has written since `02e6420`; every other row keeps NULL (= the model's).
    func testVersionThreeDatabaseBackfillsTitleSourceFromTheRenamedByTheUserNote() throws {
        let dir = try TempDir()
        let path = dir.url.appendingPathComponent("index.sqlite").path
        do {
            let db = try SQLiteDatabase(path: path)
            try db.migrate(Array(ScreenshotIndex.migrations.prefix(3)))
            XCTAssertEqual(try db.userVersion, 3)
            try db.run("""
                INSERT INTO screenshots (path, original_filename, content_hash, title, note, status, text_status)
                VALUES ('/typed.png', 'Screenshot.png', 'h1', 'Acme - March invoice',
                        'kept name: title confidence 0.31 < 0.50; renamed by the user', 'done', 'done')
                """)
            try db.run("""
                INSERT INTO screenshots (path, original_filename, content_hash, title, note, status)
                VALUES ('/model.png', 'Screenshot 2.png', 'h2', 'Invoice From Acme', 'Finder metadata not written', 'done')
                """)
            try db.run("INSERT INTO screenshots (path, original_filename, content_hash) VALUES ('/bare.png', 'b.png', 'h3')")
        }
        let index = try ScreenshotIndex(fileURL: URL(fileURLWithPath: path))
        XCTAssertEqual(index.schemaVersion, ScreenshotIndex.migrations.last?.version)
        let typed = try XCTUnwrap(index.lookup(byPath: "/typed.png"))
        XCTAssertEqual(typed.titleSource, .user)
        XCTAssertEqual(typed.title, "Acme - March invoice")
        XCTAssertEqual(typed.note, "kept name: title confidence 0.31 < 0.50; renamed by the user")
        XCTAssertEqual(typed.textStatus, .done, "the other values stay")
        XCTAssertNil(try index.lookup(byPath: "/model.png")?.titleSource)
        XCTAssertNil(try index.lookup(byPath: "/bare.png")?.titleSource)
        XCTAssertEqual(try index.stats().count, 3)
        XCTAssertEqual(try index.search("march").map(\.path), ["/typed.png"])
    }

    /// Story 23: date and source filters and the text runner's queue have indexes (checked by name, not SQL text).
    func testFilterAndPendingTextIndexesExist() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.migrate(ScreenshotIndex.migrations)
        var names: Set<String> = []
        try db.query("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'screenshots'") {
            names.insert($0.text(0) ?? "")
        }
        for name in ["screenshots_taken_at", "screenshots_source_app_or_site", "screenshots_text_pending"] {
            XCTAssertTrue(names.contains(name), "missing index \(name); have \(names.sorted())")
        }
        // The FTS table has exactly the columns the weights are given for.
        var ftsColumns: [String] = []
        try db.query("PRAGMA table_info(screenshots_fts)") { ftsColumns.append($0.text(1) ?? "") }
        XCTAssertEqual(ftsColumns, ["title", "tags", "description", "key_text", "source_app_or_site", "recognized_text"])
        XCTAssertEqual(ScreenshotIndex.ftsColumns.map(\.name), ftsColumns)
    }

    func testMigrationVersionsAreUniqueAndContiguous() {
        let versions = ScreenshotIndex.migrations.map(\.version)
        XCTAssertEqual(versions, Array(1...Int32(versions.count)), "1, 2, 3, ... in order, no duplicates or gaps")
        for migration in ScreenshotIndex.migrations {
            XCTAssertFalse(migration.statements.isEmpty, "migration \(migration.version) does nothing")
        }
        let names = ScreenshotIndex.columns.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "duplicate column")
        XCTAssertEqual(names.first, "path", "the upsert key comes first")
        for column in ScreenshotIndex.columns {
            XCTAssertTrue(versions.contains(column.addedIn), "\(column.name): no migration \(column.addedIn)")
        }
        // ADD COLUMN appends, so the table order is the order columns were added in.
        XCTAssertEqual(ScreenshotIndex.columns.map(\.addedIn), ScreenshotIndex.columns.map(\.addedIn).sorted())
    }

    /// Each migration adds exactly the columns whose `addedIn` names it, and exactly the columns it shipped with.
    /// A column moved into a version that is already out (and so never reruns on a user's database) fails here.
    func testEachMigrationAddsItsShippedColumns() {
        let versions = Self.shippedColumns.map(\.version)
        XCTAssertEqual(versions, Array(1...Int32(versions.count)),
                       "shippedColumns versions must be unique and run 1, 2, 3… in order; two entries with one "
                       + "version usually mean a merge kept both sides: renumber the newer one")
        XCTAssertEqual(versions, ScreenshotIndex.migrations.map(\.version),
                       "add `(n, [columns])` to shippedColumns with each new migration")
        for migration in ScreenshotIndex.migrations {
            let declared = ScreenshotIndex.columns(addedIn: migration.version).map(\.name)
            let shipped = Self.shippedColumns.first { $0.version == migration.version }?.columns ?? []
            XCTAssertEqual(declared, shipped,
                           "columns with addedIn: \(migration.version) differ from what that version shipped")
            guard migration.version > 1 else { continue }
            let prefix = "ALTER TABLE screenshots ADD COLUMN "
            let added = migration.statements.filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count).prefix { $0 != " " }) }
            XCTAssertEqual(added, declared, "migration \(migration.version) adds other columns than their addedIn says")
        }
    }

    /// The columns each migration adds, as shipped. Append `(n, [...])` with each new migration; never edit a line:
    /// a database already at that version will not run it again. An ordered list, not a dictionary literal: a merge
    /// that keeps two entries for one version then fails the test above instead of crashing the run on duplicate keys.
    private static let shippedColumns: [(version: Int32, columns: [String])] = [
        (1, ["path", "original_filename", "content_hash", "captured_at", "processed_at", "title", "title_confidence",
             "source_app_or_site", "content_type", "description", "tags", "key_text", "date_mentioned", "produced_by",
             "billed_input_tokens", "status", "last_error", "note"]),
        (2, ["restored_by_undo"]),
        (3, ["recognized_text", "text_status", "text_recognized_by", "text_error"]),
        (4, ["title_source"]),
    ]

    /// The migrated table has exactly the declared columns, in order: a column without its migration (or the other
    /// way round) fails here, not at the first save on a user's Mac.
    func testMigratedTableMatchesColumnTable() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.migrate(ScreenshotIndex.migrations)
        XCTAssertEqual(try tableColumns(db).map(\.name), ["id"] + ScreenshotIndex.columns.map(\.name))
    }

    /// Every column survives save → read by its own name (a mixed-up read would swap two values).
    func testEveryColumnRoundTrips() throws {
        let index = try ScreenshotIndex.inMemory()
        let row = IndexedScreenshot.testRow("/full.png") {
            $0.originalFilename = "Screenshot 2026-11-28 at 10.00.00.png"
            $0.contentHash = "v1:1:2:3"
            $0.capturedAt = t0
            $0.processedAt = t0.addingTimeInterval(1)
            $0.title = "Title"
            $0.titleConfidence = 0.75
            $0.sourceAppOrSite = "x.com"
            $0.contentType = .tweet
            $0.description = "Description"
            $0.tags = ["a", "b"]
            $0.keyText = "Key text"
            $0.dateMentioned = "2026-01-13"
            $0.producedBy = "model"
            $0.billedInputTokens = 640
            $0.status = .failed
            $0.lastError = "boom"
            $0.note = "note"
            $0.restoredByUndo = true
            $0.recognizedText = "Line one\nLine two"
            $0.textStatus = .failed
            $0.textRecognizedBy = "vision-r3-accurate-h1/96-lc0"
            $0.textError = "file missing"
            $0.titleSource = .user
        }
        var expected = row
        expected.id = try index.save(row)
        XCTAssertEqual(try index.lookup(byPath: "/full.png"), expected)
        // Every stored property is non-default above, so a new column without a value here fails this check.
        let blank = IndexedScreenshot(path: "", originalFilename: "", contentHash: "")
        for (label, value) in Mirror(reflecting: row).children where label != "id" {
            let blankValue = Mirror(reflecting: blank).children.first { $0.label == label }?.value
            XCTAssertNotEqual(String(describing: value), String(describing: blankValue ?? ""), "set \(label ?? "") above")
        }
    }

    /// A database created by the build at `295df83` (schema version 2) opens, runs only the migrations after 2, keeps
    /// every row and every value, and has exactly the schema a new database gets.
    func testDatabaseFrom295df83OpensWithEveryValueKept() throws {
        let dir = try TempDir()
        let legacyPath = dir.url.appendingPathComponent("legacy.sqlite").path
        do {
            let db = try SQLiteDatabase(path: legacyPath)
            try db.migrate(Self.schemaAt295df83)
            try db.run("""
                INSERT INTO screenshots (path, original_filename, content_hash, captured_at, processed_at, title,
                    title_confidence, source_app_or_site, content_type, description, tags, key_text, date_mentioned,
                    produced_by, billed_input_tokens, status, last_error, note, restored_by_undo)
                VALUES ('/old.png', 'Screenshot.png', 'v1:1:2:3', 1800000000, 1800000060, 'Invoice from Acme', 0.8,
                    'Mail', 'receipt', 'An invoice', '["invoice","acme"]', 'Total 42', '2026-01-13', 'clairic', 640,
                    'done', NULL, 'kept', 1)
                """)
            try db.run("INSERT INTO screenshots (path, original_filename, content_hash) VALUES ('/pending.png', 'p.png', 'h')")
            XCTAssertEqual(try db.userVersion, 2, "the frozen schema")
        }
        let index = try ScreenshotIndex(fileURL: URL(fileURLWithPath: legacyPath))
        XCTAssertEqual(index.schemaVersion, ScreenshotIndex.migrations.last?.version)
        let old = try XCTUnwrap(index.lookup(byPath: "/old.png"))
        XCTAssertEqual(old, IndexedScreenshot(
            id: old.id, path: "/old.png", originalFilename: "Screenshot.png", contentHash: "v1:1:2:3",
            capturedAt: t0, processedAt: t0.addingTimeInterval(60), title: "Invoice from Acme", titleConfidence: 0.8,
            sourceAppOrSite: "Mail", contentType: .receipt, description: "An invoice", tags: ["invoice", "acme"],
            keyText: "Total 42", dateMentioned: "2026-01-13", producedBy: "clairic", billedInputTokens: 640,
            status: .done, note: "kept", restoredByUndo: true))
        let pending = try XCTUnwrap(index.lookup(byPath: "/pending.png"))
        XCTAssertEqual(pending.status, .pending)
        XCTAssertEqual(pending.tags, [])
        XCTAssertFalse(pending.restoredByUndo)
        XCTAssertEqual(try index.search("acme").map(\.path), ["/old.png"])
        try index.save(entry("/new.png", title: "Fresh"))
        XCTAssertEqual(try index.search("fresh").map(\.path), ["/new.png"])

        let freshPath = dir.url.appendingPathComponent("fresh.sqlite").path
        _ = try ScreenshotIndex(fileURL: URL(fileURLWithPath: freshPath))
        XCTAssertEqual(try schema(SQLiteDatabase(path: freshPath)), try schema(SQLiteDatabase(path: legacyPath)),
                       "a new database is built exactly like one from 295df83")
    }

    /// The schema SQL as shipped at `295df83`, copied verbatim. Frozen: never update it.
    private static let schemaAt295df83: [SQLiteMigration] = [
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
        SQLiteMigration(version: 2, statements: [
            "ALTER TABLE screenshots ADD COLUMN restored_by_undo INTEGER NOT NULL DEFAULT 0",
        ]),
    ]

    private struct TableColumn: Equatable {
        var name: String, type: String, notNull: Bool, defaultValue: String?, primaryKey: Bool
    }

    private func tableColumns(_ db: SQLiteDatabase) throws -> [TableColumn] {
        var columns: [TableColumn] = []
        try db.query("PRAGMA table_info(screenshots)") {
            columns.append(TableColumn(name: $0.text(1) ?? "", type: $0.text(2) ?? "", notNull: $0.int64(3) != 0,
                                       defaultValue: $0.text(4), primaryKey: $0.int64(5) != 0))
        }
        return columns
    }

    /// Every schema object's SQL text plus the version.
    private func schema(_ db: SQLiteDatabase) throws -> [String] {
        var objects = ["user_version \(try db.userVersion)"]
        try db.query("SELECT type, name, sql FROM sqlite_master ORDER BY type, name") {
            objects.append("\($0.text(0) ?? "") \($0.text(1) ?? ""): \($0.text(2) ?? "")")
        }
        return objects
    }

    // MARK: - Change feed

    /// Awaits `operation`. After `seconds` it fails the test with a message naming `what`, and returns nil instead of
    /// hanging (the operation need not react to cancellation).
    private func awaitResult<T: Sendable>(_ what: String, seconds: Double = 10, file: StaticString = #filePath,
                                          line: UInt = #line, _ operation: @escaping @Sendable () async -> T) async -> T? {
        let work = Task { await operation() }
        let timer = Locked<Task<Void, Never>?>(nil)
        let result: T? = await withCheckedContinuation { continuation in
            let resumed = Locked(false)
            let finish: @Sendable (T?) -> Void = { value in
                if resumed.mutate({ done in defer { done = true }; return !done }) { continuation.resume(returning: value) }
            }
            Task { finish(await work.value) }
            timer.set(Task { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); finish(nil) })
        }
        timer.get?.cancel()
        work.cancel()
        if result == nil { XCTFail("timed out after \(seconds) s waiting for \(what)", file: file, line: line) }
        return result
    }

    /// Everything `stream` yields until it finishes. Free the index first: that is what finishes it.
    private func collect(_ stream: AsyncStream<IndexChange>, file: StaticString = #filePath,
                         line: UInt = #line) async -> [IndexChange] {
        await awaitResult("the change stream to finish (it ends when the index is freed)", file: file, line: line) {
            var changes: [IndexChange] = []
            for await change in stream { changes.append(change) }
            return changes
        } ?? []
    }

    func testChangesReportInsertUpdateAndRemoveInCommitOrder() async throws {
        var index: ScreenshotIndex! = try ScreenshotIndex.inMemory()
        let stale = try index.save(.testRow("/b.png"))
        let changes = index.changes()

        let a = try index.save(.testRow("/a.png") { $0.title = "Alpha" })
        try index.save(.testRow("/a.png") { $0.title = "Alpha 2" })
        try index.markRestoredByUndo(path: "/a.png")
        try index.updatePath(from: "/a.png", to: "/b.png")
        // No row changes: nothing is published.
        try index.markRestoredByUndo(path: "/missing.png")
        try index.updatePath(from: "/missing.png", to: "/c.png")
        try index.updatePath(from: "/b.png", to: "/b.png")
        try index.updatePath(from: "/b.png", to: "/c.png")
        // An identical row is still reported (save does not diff).
        let current = try XCTUnwrap(index.lookup(byPath: "/c.png"))
        try index.save(current)
        index = nil

        let received = await collect(changes)
        XCTAssertEqual(received, [
            IndexChange(.inserted, id: a, path: "/a.png"),
            IndexChange(.updated, id: a, path: "/a.png"),
            IndexChange(.updated, id: a, path: "/a.png"),
            IndexChange(.removed, id: stale, path: "/b.png"),
            IndexChange(.updated, id: a, path: "/b.png"),
            IndexChange(.updated, id: a, path: "/c.png"),
            IndexChange(.updated, id: a, path: "/c.png"),
        ])
    }

    func testEverySubscriberGetsEveryChangeAndStreamsEndWithTheIndex() async throws {
        var index: ScreenshotIndex! = try ScreenshotIndex.inMemory()
        let first = index.changes()
        let second = index.changes()
        let id = try index.save(.testRow("/a.png"))
        index = nil
        let expected = [IndexChange(.inserted, id: id, path: "/a.png")]
        let firstReceived = await collect(first)
        let secondReceived = await collect(second)
        XCTAssertEqual(firstReceived, expected)
        XCTAssertEqual(secondReceived, expected)
    }

    func testAFailedWritePublishesNothing() async throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("index.sqlite")
        var index: ScreenshotIndex! = try ScreenshotIndex(fileURL: url)
        try index.save(.testRow("/a.png"))
        let changes = index.changes()
        let b = try index.save(.testRow("/b.png"))
        // Makes the UPDATE fail after the stale row's DELETE, so the transaction rolls back.
        try SQLiteDatabase(path: url.path).execute("""
            CREATE TRIGGER fail_update BEFORE UPDATE OF path ON screenshots BEGIN SELECT RAISE(ABORT, 'no'); END
            """)
        XCTAssertThrowsError(try index.updatePath(from: "/a.png", to: "/b.png"))
        XCTAssertNotNil(try index.lookup(byPath: "/b.png"), "rolled back")
        let c = try index.save(.testRow("/c.png"))
        index = nil
        let received = await collect(changes)
        XCTAssertEqual(received, [IndexChange(.inserted, id: b, path: "/b.png"), IndexChange(.inserted, id: c, path: "/c.png")],
                       "nothing from the failed updatePath")
    }

    func testADroppedStreamUnsubscribes() throws {
        let index = try ScreenshotIndex.inMemory()
        let kept = index.changes()
        _ = index.changes()
        XCTAssertEqual(index.subscriberCount, 1, "the dropped stream unsubscribed, the kept one did not")
        withExtendedLifetime(kept) {}
    }

    func testCancellingTheIteratingTaskUnsubscribes() async throws {
        let index = try ScreenshotIndex.inMemory()
        let changes = index.changes()
        let received = Locked(0)
        let iterating = Task { for await _ in changes { received.mutate { $0 += 1 } } }
        try index.save(.testRow("/a.png"))
        for _ in 0..<2_000 where received.get == 0 { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(received.get, 1, "the task is iterating")
        XCTAssertEqual(index.subscriberCount, 1)

        iterating.cancel()
        _ = await awaitResult("the cancelled iteration to end") { await iterating.value }
        XCTAssertEqual(index.subscriberCount, 0, "cancelling the iteration unsubscribed (the stream itself is still held)")
        try index.save(.testRow("/b.png"))
        XCTAssertEqual(received.get, 1)
        withExtendedLifetime(changes) {}
    }

    // MARK: - Conditional text write

    private func pendingTextRow(_ path: String) -> IndexedScreenshot {
        .testRow(path) { $0.title = "Receipt"; $0.contentHash = "hash-\(path)"; $0.textStatus = .pending }
    }

    func testSettingTextAppliesToAPendingRowWithItsHashAndIsSearchable() async throws {
        var index: ScreenshotIndex! = try ScreenshotIndex.inMemory()
        let id = try index.save(pendingTextRow("/a.png"))
        let changes = index.changes()

        XCTAssertTrue(try index.setRecognizedText(.text("Order 7781\nShipped to Globex"), recognizedBy: "vision-test",
                                                  id: id, ifContentHash: "hash-/a.png"))
        let row = try XCTUnwrap(index.lookup(byPath: "/a.png"))
        XCTAssertEqual(row.recognizedText, "Order 7781\nShipped to Globex")
        XCTAssertEqual(row.textStatus, .done)
        XCTAssertEqual(row.textRecognizedBy, "vision-test")
        XCTAssertNil(row.textError)
        XCTAssertEqual(row.title, "Receipt", "the analysis is untouched")
        XCTAssertEqual(row.status, .done)
        // The write is an UPDATE of the text columns only: the FTS trigger must fire for recognized_text.
        XCTAssertEqual(try index.search("globex receipt").map(\.path), ["/a.png"])
        XCTAssertEqual(try index.search("7781").map(\.path), ["/a.png"])
        index = nil
        let received = await collect(changes)
        XCTAssertEqual(received, [IndexChange(.updated, id: id, path: "/a.png")])
    }

    func testSettingNoTextAndFailureRecordTheirStatus() throws {
        let index = try ScreenshotIndex.inMemory()
        let none = try index.save(pendingTextRow("/none.png"))
        let failed = try index.save(pendingTextRow("/failed.png"))
        XCTAssertTrue(try index.setRecognizedText(.noText, recognizedBy: "vision-test", id: none, ifContentHash: "hash-/none.png"))
        XCTAssertTrue(try index.setRecognizedText(.failed(reason: "file missing"), recognizedBy: "vision-test",
                                                  id: failed, ifContentHash: "hash-/failed.png"))

        let noneRow = try XCTUnwrap(index.lookup(byPath: "/none.png"))
        XCTAssertEqual(noneRow.textStatus, .noText)
        XCTAssertNil(noneRow.recognizedText)
        XCTAssertNil(noneRow.textError)
        XCTAssertEqual(noneRow.textRecognizedBy, "vision-test")
        let failedRow = try XCTUnwrap(index.lookup(byPath: "/failed.png"))
        XCTAssertEqual(failedRow.textStatus, .failed)
        XCTAssertNil(failedRow.recognizedText)
        XCTAssertEqual(failedRow.textError, "file missing")
        XCTAssertEqual(failedRow.status, .done, "a failed read never touches the analysis status")
    }

    /// Spec story 45: the file changed during the read (the processor saved the row again with a new hash), or the
    /// row is no longer pending: the late result is dropped, the row is unchanged and nothing is published.
    func testSettingTextIsRefusedForAStaleHashANonPendingStatusOrAMissingRow() async throws {
        var index: ScreenshotIndex! = try ScreenshotIndex.inMemory()
        let pending = try index.save(pendingTextRow("/pending.png"))
        let notRequested = try index.save(.testRow("/old.png") { $0.contentHash = "hash-old" })
        let done = try index.save(.testRow("/done.png") {
            $0.contentHash = "hash-done"; $0.textStatus = .done; $0.recognizedText = "Kept text"; $0.textRecognizedBy = "v1"
        })
        let failed = try index.save(.testRow("/failed.png") {
            $0.contentHash = "hash-failed"; $0.textStatus = .failed; $0.textError = "file missing"
        })
        let before = try ["/pending.png", "/old.png", "/done.png", "/failed.png"].map { try index.lookup(byPath: $0) }
        let changes = index.changes()

        XCTAssertFalse(try index.setRecognizedText(.text("Late"), recognizedBy: "v2", id: pending, ifContentHash: "stale"))
        XCTAssertFalse(try index.setRecognizedText(.text("Late"), recognizedBy: "v2", id: notRequested, ifContentHash: "hash-old"))
        XCTAssertFalse(try index.setRecognizedText(.noText, recognizedBy: "v2", id: done, ifContentHash: "hash-done"))
        XCTAssertFalse(try index.setRecognizedText(.text("Late"), recognizedBy: "v2", id: failed, ifContentHash: "hash-failed"))
        XCTAssertFalse(try index.setRecognizedText(.text("Late"), recognizedBy: "v2", id: 9_999, ifContentHash: "hash-/pending.png"))

        let after = try ["/pending.png", "/old.png", "/done.png", "/failed.png"].map { try index.lookup(byPath: $0) }
        XCTAssertEqual(after, before)
        XCTAssertEqual(try index.search("late"), [])
        index = nil
        let received = await collect(changes)
        XCTAssertEqual(received, [], "a refused write publishes nothing")
    }

    /// The text runner reads the newest `pending` row first, by when it was taken (processed time when unknown).
    func testNewestPendingTextRowIsByTakenTimeThenProcessedTime() throws {
        let index = try ScreenshotIndex.inMemory()
        XCTAssertNil(try index.newestPendingTextRow())
        func row(_ path: String, captured: Double?, processed: Double, text: TextStatus?) -> IndexedScreenshot {
            .testRow(path) {
                $0.capturedAt = captured.map { t0.addingTimeInterval($0 * 60) }
                $0.processedAt = t0.addingTimeInterval(processed * 60)
                $0.textStatus = text
            }
        }
        try index.save(row("/old.png", captured: 1, processed: 50, text: .pending))
        try index.save(row("/no-capture-time.png", captured: nil, processed: 5, text: .pending))
        try index.save(row("/newest-done.png", captured: 40, processed: 40, text: .done))
        try index.save(row("/newest-unrequested.png", captured: 30, processed: 30, text: nil))
        try index.save(row("/newest-failed.png", captured: 20, processed: 20, text: .failed))
        XCTAssertEqual(try index.newestPendingTextRow()?.path, "/no-capture-time.png", "taken at 5 beats taken at 1")

        try index.save(row("/new.png", captured: 10, processed: 11, text: .pending))
        XCTAssertEqual(try index.newestPendingTextRow()?.path, "/new.png")
        let new = try XCTUnwrap(index.lookup(byPath: "/new.png"))
        XCTAssertTrue(try index.setRecognizedText(.noText, recognizedBy: "v", id: new.id, ifContentHash: new.contentHash))
        XCTAssertEqual(try index.newestPendingTextRow()?.path, "/no-capture-time.png", "a read row leaves the queue")
    }

    func testGenericMigrationsApplyOnlyNewSteps() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        XCTAssertEqual(try db.userVersion, 0)
        let v1 = SQLiteMigration(version: 1, statements: ["CREATE TABLE t (a INTEGER)"])
        try db.migrate([v1])
        try db.run("INSERT INTO t (a) VALUES (?)", [.int(7)])
        try db.migrate([v1, SQLiteMigration(version: 2, statements: ["ALTER TABLE t ADD COLUMN b TEXT"])])
        XCTAssertEqual(try db.userVersion, 2)
        var rows: [(Int64, String?)] = []
        try db.query("SELECT a, b FROM t") { rows.append(($0.int64(0), $0.text(1))) }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.0, 7)
        // A failing step rolls back and leaves the version unchanged.
        XCTAssertThrowsError(try db.migrate([SQLiteMigration(version: 3, statements: ["CREATE TABLE u (x)", "NOT SQL"])]))
        XCTAssertEqual(try db.userVersion, 2)
        XCTAssertThrowsError(try db.run("SELECT * FROM u"))
    }

    func testFingerprint() throws {
        let dir = try TempDir()
        let a = try dir.file("a.png", contents: "same bytes")
        let fp = try ContentFingerprint.compute(for: a)
        XCTAssertTrue(fp.hasPrefix("v1:10:"))
        XCTAssertEqual(try ContentFingerprint.compute(for: a), fp, "stable")
        let moved = dir.url.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: a, to: moved)
        XCTAssertEqual(try ContentFingerprint.compute(for: moved), fp, "rename keeps the fingerprint")
        XCTAssertNotEqual(ContentFingerprint.make(size: 10, modificationTime: 1, prefix: Data("a".utf8)),
                          ContentFingerprint.make(size: 10, modificationTime: 1, prefix: Data("b".utf8)))
        XCTAssertEqual(ContentFingerprint.fnv1a64(Data()), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(ContentFingerprint.fnv1a64(Data("a".utf8)), 0xaf63_dc4c_8601_ec8c)
    }
}
