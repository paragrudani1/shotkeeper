import XCTest
@testable import ShotkeeperCore

private func shot(_ name: String, source: String?, status: ProcessingStatus = .done) -> IndexedScreenshot {
    .testRow("/Users/parag/Desktop/\(name).png") {
        $0.title = name
        $0.sourceAppOrSite = source
        $0.status = status
    }
}

private func index(_ sources: [String?]) throws -> ScreenshotIndex {
    let index = try ScreenshotIndex.inMemory()
    for (offset, source) in sources.enumerated() { try index.save(shot("shot \(offset)", source: source)) }
    return index
}

/// Seam 1: the source list, `ScreenshotIndex.sources()` (spec "Filter model", Sources; stories 6–9).
final class SourceListTests: XCTestCase {
    private func names(_ sources: [String?]) throws -> [String: Int] {
        Dictionary(uniqueKeysWithValues: try index(sources).sources().map { ($0.displayName, $0.count) })
    }

    func testASiteAndItsAppAreOneSource() throws {
        XCTAssertEqual(try names(["X", "x.com", "GitHub", "github.com", "www.github.com"]), ["GitHub": 3, "X": 2])
    }

    func testCaseDiacriticsAndSpacesAreFolded() throws {
        XCTAssertEqual(try names(["Café", " cafe ", "CAFÉ", "cafe"]).values.sorted(), [4])
        XCTAssertEqual(try names(["WWW.NYTimes.COM", "nytimes"]).values.sorted(), [2])
    }

    func testOnlyALoneTopLevelDomainIsDropped() throws {
        XCTAssertEqual(try names(["bbc.co.uk", "bbc", "docs.google.com", "google", "google.com"]),
                       ["bbc.co.uk": 1, "bbc": 1, "docs.google.com": 1, "google": 2])
    }

    func testTheListIsOrderedByCountThenNameAndNamedByTheMostCommonSpelling() throws {
        let index = try index(["x.com", "X", "x.com", "Slack", "slack", "Mail", "figma", "Figma", "Slack", nil, "  ", ""])
        try index.save(shot("pending", source: "Pending app", status: .pending))
        try index.save(shot("failed", source: "Slack", status: .failed))
        XCTAssertEqual(try index.sources().map { "\($0.displayName) \($0.count)" },
                       ["Slack 3", "x.com 3", "Figma 2", "Mail 1"],
                       "only analyzed rows count; rows without a source are left out; ties sorted by name")
        XCTAssertEqual(try index.sources().first?.key, SourceKey("SLACK"))
        XCTAssertEqual(try ScreenshotIndex.inMemory().sources(), [])
    }

    func testThereIsNoAliasTable() throws {
        XCTAssertEqual(try names(["Twitter", "X"]), ["Twitter": 1, "X": 1], "Twitter is not mapped to X")
    }
}

/// Seam 1: `ScreenshotIndex.search` with a source (spec "Filtering by source"; stories 8, 11).
final class SourceFilterIndexTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-21 16:24 UTC.
    private let now = Date(timeIntervalSince1970: 1_795_278_240)

    private func makeIndex() throws -> ScreenshotIndex {
        let index = try ScreenshotIndex.inMemory()
        func save(_ title: String, _ source: String?, _ type: ContentType, daysAgo: Double, tags: [String] = [],
                  status: ProcessingStatus = .done) throws {
            try index.save(.testRow("/Users/parag/Desktop/\(title).png") {
                $0.title = title
                $0.sourceAppOrSite = source
                $0.contentType = type
                $0.tags = tags
                $0.capturedAt = now.addingTimeInterval(-daysAgo * 86_400)
                $0.processedAt = now.addingTimeInterval(-daysAgo * 86_400 + 5)
                $0.status = status
            })
        }
        try save("Tweet about chips", "x.com", .tweet, daysAgo: 0, tags: ["chips"])
        try save("Tweet about invoices", "X", .tweet, daysAgo: 3, tags: ["invoice"])
        try save("Old X thread", "www.x.com", .tweet, daysAgo: 40)
        try save("Stripe invoice", "Stripe", .receipt, daysAgo: 2, tags: ["invoice"])
        try save("Stripe payout", "stripe.com", .receipt, daysAgo: 20, tags: ["payout"])
        try save("Stripe dashboard", "Stripe", .design, daysAgo: 1)
        try save("Pending Stripe", "Stripe", .receipt, daysAgo: 0, tags: ["invoice"], status: .pending)
        try save("No source", nil, .receipt, daysAgo: 0, tags: ["invoice"])
        return index
    }

    private func titles(_ query: ScreenshotQuery, in index: ScreenshotIndex) throws -> [String] {
        try index.search(query, now: now, calendar: utc).rows.map(\.title!)
    }

    func testASourceFindsEverySpellingNewestTakenFirst() throws {
        let index = try makeIndex()
        XCTAssertEqual(try titles(ScreenshotQuery(source: SourceKey("X")), in: index),
                       ["Tweet about chips", "Tweet about invoices", "Old X thread"])
        let result = try index.search(ScreenshotQuery(source: SourceKey("stripe.com")), now: now, calendar: utc)
        XCTAssertEqual(result.rows.map(\.title), ["Stripe dashboard", "Stripe invoice", "Stripe payout"],
                       "only analyzed rows")
        XCTAssertEqual(result.matchCount, 3)
        XCTAssertEqual(result.totalCount, 7)
    }

    func testSourceCombinesWithTextTypeDateAndBatch() throws {
        let index = try makeIndex()
        let stripe = SourceKey("Stripe")
        XCTAssertEqual(try titles(ScreenshotQuery(text: "invoice", source: stripe), in: index), ["Stripe invoice"])
        XCTAssertEqual(try titles(ScreenshotQuery(contentType: .receipt, source: stripe), in: index),
                       ["Stripe invoice", "Stripe payout"])
        XCTAssertEqual(try titles(ScreenshotQuery(date: .last7Days, source: stripe), in: index),
                       ["Stripe dashboard", "Stripe invoice"])
        XCTAssertEqual(try titles(ScreenshotQuery(text: "invoice", contentType: .receipt, date: .last30Days,
                                                  source: stripe), in: index), ["Stripe invoice"], "story 11")
        let batch = ["/Users/parag/Desktop/Stripe payout.png", "/Users/parag/Desktop/Tweet about chips.png"]
        XCTAssertEqual(try titles(ScreenshotQuery(paths: batch, source: stripe), in: index), ["Stripe payout"])
        let counted = try index.search(ScreenshotQuery(text: "invoice", source: SourceKey("x")), now: now, calendar: utc)
        XCTAssertEqual(counted.matchCount, 1)
        XCTAssertEqual(counted.totalCount, 7)
    }

    func testASourceWithNoRowsLeftFindsNothing() throws {
        let index = try makeIndex()
        let gone = try index.search(ScreenshotQuery(source: SourceKey("Slack")), now: now, calendar: utc)
        XCTAssertEqual(gone.rows, [])
        XCTAssertEqual(gone.matchCount, 0)
        XCTAssertEqual(gone.totalCount, 7)
        XCTAssertEqual(try titles(ScreenshotQuery(text: "\"; DROP TABLE screenshots; --", source: SourceKey("x'); --")),
                                  in: index), [], "hostile input is bound, never spliced")
    }
}

/// The source filter's SQL reads migration 3's `screenshots_source_app_or_site` index (ticket 01; story 23), from
/// `EXPLAIN QUERY PLAN` (https://www.sqlite.org/eqp.html) on the statements `search` runs.
final class SourceFilterQueryPlanTests: XCTestCase {
    func testSourceFilteredSearchUsesTheSourceIndex() throws {
        let dir = try TempDir()
        let file = dir.url.appendingPathComponent("index.sqlite")
        let index = try ScreenshotIndex(fileURL: file)  // migrates the file to version 3
        for n in 1...60 {
            try index.save(.testRow("/shot-\(n).png") {
                $0.title = "Shot \(n)"
                $0.sourceAppOrSite = ["Slack", "x.com", "Mail", "GitHub", "Figma", "Xcode"][n % 6]
                $0.capturedAt = Date(timeIntervalSince1970: 1_795_000_000 + Double(n) * 3_600)
            })
        }
        let sql = ScreenshotIndex.searchSQL(ScreenshotQuery(source: SourceKey("slack")), sourceSpellings: ["Slack"],
                                            now: Date(timeIntervalSince1970: 1_795_278_240), calendar: .current)
        let db = try SQLiteDatabase(path: file.path)
        for (statement, bindings) in [(sql.select, sql.bindings + [.int(50)]), (sql.count, sql.bindings)] {
            var details: [String] = []
            try db.query("EXPLAIN QUERY PLAN " + statement, bindings) { details.append($0.text(3) ?? "") }
            XCTAssertTrue(details.contains { $0.contains("USING INDEX screenshots_source_app_or_site") }, "\(details)")
            XCTAssertFalse(details.contains { $0.hasPrefix("SCAN s") && !$0.contains("INDEX") }, "\(details)")
        }
    }
}
