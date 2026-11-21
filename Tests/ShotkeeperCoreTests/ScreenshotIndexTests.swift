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
        XCTAssertEqual(reopened.schemaVersion, 1)
        XCTAssertEqual(try reopened.search("kept").map(\.path), ["/1.png"])
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
