import XCTest
@testable import ShotkeeperCore

/// Formatters may use U+202F (narrow no-break space) before AM/PM depending on the ICU/CLDR version.
private func plain(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-11-21 16:24:00 UTC, a Saturday.
private let now = Date(timeIntervalSince1970: 1_795_278_240)
private let us = TimeLabel(calendar: utc, locale: Locale(identifier: "en_US"))

private func row(_ name: String, type: ContentType? = .other, title: String? = nil, tags: [String] = [],
                 description: String? = nil, source: String? = nil, minutes: Double = 0,
                 status: ProcessingStatus = .done, folder: String = "/Users/parag/Desktop") -> IndexedScreenshot {
    IndexedScreenshot(path: "\(folder)/\(name).png", originalFilename: "Screenshot.png", contentHash: "h-\(name)",
                      capturedAt: now.addingTimeInterval(minutes * 60), processedAt: now.addingTimeInterval(minutes * 60 + 5),
                      title: title ?? name, titleConfidence: 0.9, sourceAppOrSite: source, contentType: type,
                      description: description, tags: tags, status: status)
}

final class ScreenshotQueryIndexTests: XCTestCase {
    private func makeIndex() throws -> ScreenshotIndex {
        let index = try ScreenshotIndex.inMemory()
        try index.save(row("Tweet about chips", type: .tweet, tags: ["semiconductor"], source: "x.com", minutes: -1))
        try index.save(row("Coffee receipt", type: .receipt, tags: ["coffee"], description: "Blue Bottle receipt", minutes: -2))
        try index.save(row("Chip design review", type: .design, tags: ["semiconductor"], minutes: -3))
        try index.save(row("Article on chips", type: .article, minutes: -4))
        try index.save(row("Pending chips", type: nil, minutes: 0, status: .pending))
        try index.save(row("Failed chips", type: nil, minutes: 0, status: .failed))
        return index
    }

    func testEmptyQueryIsRecentDoneRowsWithCounts() throws {
        let result = try makeIndex().search(ScreenshotQuery(), limit: 2)
        XCTAssertEqual(result.rows.map(\.title), ["Tweet about chips", "Coffee receipt"])
        XCTAssertEqual(result.matchCount, 4, "pending and failed rows are not results")
        XCTAssertEqual(result.totalCount, 4)
    }

    func testChipFiltersByContentTypeAndCombinesWithText() throws {
        let index = try makeIndex()
        XCTAssertEqual(try index.search(ScreenshotQuery(contentType: .receipt)).rows.map(\.title), ["Coffee receipt"])
        let chips = try index.search(ScreenshotQuery(text: "chip"))
        XCTAssertEqual(Set(chips.rows.map(\.title)), ["Tweet about chips", "Chip design review", "Article on chips"])
        XCTAssertEqual(chips.matchCount, 3)
        let designChips = try index.search(ScreenshotQuery(text: "chip", contentType: .design))
        XCTAssertEqual(designChips.rows.map(\.title), ["Chip design review"])
        XCTAssertEqual(designChips.matchCount, 1)
        XCTAssertEqual(designChips.totalCount, 4)
        XCTAssertEqual(try index.search(ScreenshotQuery(text: "coffee", contentType: .tweet)).rows, [])
    }

    func testMatchCountIsNotCappedByTheLimit() throws {
        let result = try makeIndex().search(ScreenshotQuery(text: "semiconductor"), limit: 1)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.matchCount, 2)
    }

    func testBatchPathsLimitTheResultsAndKeepRecentOrder() throws {
        let index = try makeIndex()
        let paths = ["/Users/parag/Desktop/Article on chips.png", "/Users/parag/Desktop/Tweet about chips.png",
                     "/Users/parag/Desktop/Moved away.png", "/Users/parag/Desktop/Pending chips.png"]
        let batch = try index.search(ScreenshotQuery(paths: paths))
        XCTAssertEqual(batch.rows.map(\.title), ["Tweet about chips", "Article on chips"])
        XCTAssertEqual(batch.matchCount, 2)
        XCTAssertEqual(try index.search(ScreenshotQuery(text: "article", paths: paths)).rows.map(\.title), ["Article on chips"])
        XCTAssertEqual(try index.search(ScreenshotQuery(paths: [])).rows, [])
        // Paths with quotes and non-ASCII survive the JSON binding.
        try index.save(row("Café \"menu\"", minutes: -9))
        XCTAssertEqual(try index.search(ScreenshotQuery(paths: ["/Users/parag/Desktop/Café \"menu\".png"])).rows.count, 1)
    }

    func testHostileTextWithAChipAndBatchPathsNeverThrows() throws {
        let index = try makeIndex()
        let paths = ["/Users/parag/Desktop/Tweet about chips.png", "/Users/parag/Desktop/Chip design review.png"]
        let hostile = ["\"", "\"\"", "near(x", "chips OR coffee", "*", "-chips", "title:chips", ")", "'", "\\",
                       "chips\"*", "^chips", "NOT", "AND OR", "{title}: x", "[", "chips' --"]
        for text in hostile {
            XCTAssertNoThrow(try index.search(ScreenshotQuery(text: text, contentType: .tweet, paths: paths)), text)
            XCTAssertNoThrow(try index.search(ScreenshotQuery(text: text, contentType: .design)), text)
        }
        // Operators are searched as plain words: "chips OR coffee" needs all three words.
        XCTAssertEqual(try index.search(ScreenshotQuery(text: "chips OR coffee")).rows, [])
        XCTAssertEqual(try index.search(ScreenshotQuery(text: "-chips", contentType: .tweet, paths: paths)).rows.map(\.title),
                       ["Tweet about chips"])
        // "title:chips" is the phrase "title chips", not a column filter (which would match "Chip design review").
        XCTAssertEqual(try index.search(ScreenshotQuery(text: "title:chips", contentType: .design, paths: paths)).rows, [])
    }

    func testEmptyIndex() throws {
        let result = try ScreenshotIndex.inMemory().search(ScreenshotQuery(text: "anything"))
        XCTAssertEqual(result, ScreenshotSearchResult(rows: [], matchCount: 0, totalCount: 0))
    }
}

final class SearchResultItemTests: XCTestCase {
    func testRowWordingAndVoiceOverName() {
        let item = SearchResultItem(row("Tweet semiconductor flashcards", type: .tweet, tags: ["chips", " "],
                                        source: " x.com ", minutes: -5))
        XCTAssertEqual(item.title, "Tweet semiconductor flashcards")
        XCTAssertEqual(item.subtitle(now: now, time: us), "x.com · 5 min ago")
        XCTAssertEqual(plain(item.accessibilityLabel(now: now, time: us)), "Tweet semiconductor flashcards, x.com, today 4:19 PM")
        XCTAssertEqual(item.hashtags, ["#chips"])
    }

    func testTitleIsTheCurrentFileNameNotTheModelTitle() {
        let item = SearchResultItem(row("Screenshot 2026-11-21 at 16.24.11", title: "Coffee receipt"))
        XCTAssertEqual(item.title, "Screenshot 2026-11-21 at 16.24.11")
    }

    func testSourceFallsBackToTheTypeAndThenToNothing() {
        XCTAssertEqual(SearchResultItem(row("a", type: .receipt, minutes: -90)).subtitle(now: now, time: us), "Receipt · 1 h ago")
        XCTAssertEqual(SearchResultItem(row("b", type: .other, minutes: -2 * 1440)).subtitle(now: now, time: us), "Thu")
        XCTAssertEqual(plain(SearchResultItem(row("c", type: nil)).accessibilityLabel(now: now, time: us)), "c, today 4:24 PM")
    }

    func testMetadataGrid() {
        let item = SearchResultItem(row("Tweet", type: .tweet, source: "x.com"))
        let rows = item.metadata(time: us)
        XCTAssertEqual(rows.map(\.label), ["Source", "Type", "Taken", "Folder"])
        XCTAssertEqual(rows[0].value, "x.com")
        XCTAssertEqual(rows[1].value, "Tweet")
        XCTAssertEqual(plain(rows[2].value), "Nov 21, 2026 at 4:24 PM")
        XCTAssertEqual(rows[3].value, "Desktop")
        let unknown = SearchResultItem(IndexedScreenshot(path: "/x.png", originalFilename: "x.png", contentHash: "h"))
        XCTAssertEqual(unknown.metadata(time: us).map(\.value), ["Unknown", "Unknown", "Unknown", "/"])
    }

    func testRelativeTimeLabels() {
        XCTAssertEqual(us.relative(now, now: now), "Just now")
        XCTAssertEqual(us.relative(now.addingTimeInterval(30), now: now), "Just now", "future (clock skew)")
        XCTAssertEqual(us.relative(now.addingTimeInterval(-59), now: now), "Just now")
        XCTAssertEqual(us.relative(now.addingTimeInterval(-60), now: now), "1 min ago")
        XCTAssertEqual(us.relative(now.addingTimeInterval(-59 * 60), now: now), "59 min ago")
        XCTAssertEqual(us.relative(now.addingTimeInterval(-3 * 3600), now: now), "3 h ago")
        XCTAssertEqual(us.relative(now.addingTimeInterval(-17 * 3600), now: now), "Yesterday", "23:24 the day before")
        XCTAssertEqual(us.relative(now.addingTimeInterval(-7 * 86_400), now: now), "Nov 14")
    }

    func testChipShortcutsAndTooltips() {
        XCTAssertEqual(SearchChip.allCases.map(\.shortcutNumber), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(SearchChip.forShortcut(1), .all)
        XCTAssertEqual(SearchChip.forShortcut(7), .design)
        XCTAssertNil(SearchChip.forShortcut(0))
        XCTAssertNil(SearchChip.forShortcut(8))
        XCTAssertEqual(SearchChip.tweet.help, "Show only tweet screenshots (⌘2)")
        XCTAssertEqual(SearchChip.all.help, "Show every type (⌘1)")
    }

    func testChipsAndTypeNames() {
        XCTAssertEqual(SearchChip.allCases.map(\.title), ["All", "Tweet", "Article", "Code", "Chat", "Receipt", "Design"])
        XCTAssertNil(SearchChip.all.contentType)
        XCTAssertEqual(SearchChip.receipt.contentType, .receipt)
        XCTAssertEqual(ContentType.other.displayName, "Other")
    }
}

final class SearchWindowStateTests: XCTestCase {
    private func result(_ names: [String], match: Int? = nil, total: Int = 214) -> ScreenshotSearchResult {
        ScreenshotSearchResult(rows: names.map { row($0) }, matchCount: match ?? names.count, totalCount: total)
    }

    private func loaded(_ names: [String] = ["a", "b", "c"], total: Int = 214) -> SearchWindowState {
        var state = SearchWindowState()
        state.apply(result(names, total: total), for: state.query)
        return state
    }

    func testStartsLoadingThenShowsRecent() {
        var state = SearchWindowState()
        XCTAssertEqual(state.phase, .loading)
        XCTAssertEqual(state.footerText, "")
        XCTAssertEqual(state.query, ScreenshotQuery())
        XCTAssertTrue(state.apply(result(["a", "b"]), for: state.query))
        XCTAssertEqual(state.phase, .results)
        XCTAssertEqual(state.selected?.title, "a")
        XCTAssertEqual(state.footerText, "Recent · 214 screenshots")
    }

    func testFooterCountsMatchesOfTheTotal() {
        var state = loaded()
        state.setText("receipt")
        state.apply(result(["r1", "r2"], match: 6), for: state.query)
        XCTAssertEqual(state.footerText, "6 of 214 screenshots")
        state.setText("   ")
        state.apply(result(["a"], total: 1), for: state.query)
        XCTAssertEqual(state.footerText, "Recent · 1 screenshot", "whitespace is not a filter")
        state.selectChip(.code)
        state.apply(result(["c"], total: 1), for: state.query)
        XCTAssertEqual(state.footerText, "1 of 1 screenshot")
    }

    func testChipCombinesWithTextInTheQuery() {
        var state = loaded()
        XCTAssertTrue(state.setText("chips"))
        XCTAssertFalse(state.setText("chips"), "same text: no new search")
        XCTAssertTrue(state.selectChip(.design))
        XCTAssertFalse(state.selectChip(.design))
        XCTAssertEqual(state.query, ScreenshotQuery(text: "chips", contentType: .design))
        XCTAssertTrue(state.hasFilter)
        state.selectChip(.all)
        XCTAssertEqual(state.query, ScreenshotQuery(text: "chips"))
    }

    func testNoMatchEmptyIndexAndClearSearch() {
        var state = loaded()
        state.setText("zebra")
        state.selectChip(.receipt)
        state.apply(result([]), for: state.query)
        XCTAssertEqual(state.phase, .noMatch(SearchMessage(
            title: "No screenshots match “zebra”",
            message: "Try other words from the title, from the text in the image, or a tag.")))
        XCTAssertEqual(state.footerText, "0 of 214 screenshots")
        XCTAssertNil(state.selected)

        XCTAssertTrue(state.clearSearch())
        XCTAssertEqual(state.query, ScreenshotQuery(), "Clear search resets the text and the chip")
        XCTAssertFalse(state.clearSearch())

        state.selectChip(.chat)
        state.apply(result([]), for: state.query)
        XCTAssertEqual(state.phase, .noMatch(SearchMessage(title: "No Chat screenshots",
                                                           message: "Choose All to see every screenshot.")))

        var empty = loaded([], total: 0)
        XCTAssertEqual(empty.phase, .emptyIndex)
        XCTAssertEqual(empty.footerText, "Recent · 0 screenshots")
        empty.setText("anything")
        empty.apply(result([], total: 0), for: empty.query)
        XCTAssertEqual(empty.phase, .emptyIndex, "an empty index is not a 'no match'")
    }

    func testIndexErrorIsARealErrorStateNotTheEmptyState() {
        var state = SearchWindowState()
        let problem = UserFacingError.problem(for: SQLiteError(code: 26, message: "file is not a database /Users/x"))
        state.fail(IndexUnavailableError(problem: problem), for: state.query)
        guard case .error(let message) = state.phase else { return XCTFail("expected the error state, got \(state.phase)") }
        XCTAssertEqual(message.title, "The screenshot index could not be opened")
        XCTAssertEqual(message.message,
                       "The index file is damaged. Your screenshots are not affected. Quit and reopen Shotkeeper to try again.")
        XCTAssertEqual(state.footerText, "")

        state.setText("x")
        state.fail(SQLiteError(code: 5, message: "database is locked"), for: state.query)
        XCTAssertEqual(state.phase, .error(SearchMessage(
            title: "Search failed",
            message: "The index is busy, try again in a moment. Try again, or quit and reopen Shotkeeper.")))
        // A later success clears the error.
        state.apply(result(["a"]), for: state.query)
        XCTAssertEqual(state.phase, .results)
    }

    func testStaleResultsAreIgnored() {
        var state = loaded()
        let old = state.query
        state.setText("new")
        XCTAssertFalse(state.apply(result(["stale"]), for: old))
        XCTAssertFalse(state.fail(SQLiteError(code: 1, message: ""), for: old))
        XCTAssertEqual(state.items.map(\.title), ["a", "b", "c"])
    }

    func testEscapeClearsTheSearchFirstThenCloses() {
        var state = loaded()
        state.setText("receipt")
        XCTAssertEqual(state.escape(), .clearedSearch)
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.escape(), .close)
        state.selectChip(.tweet)
        XCTAssertEqual(state.escape(), .clearedSearch, "a chip is part of the search")
        XCTAssertEqual(state.chip, .all)
        XCTAssertEqual(state.escape(), .close)
        state.showBatch(["/a.png"])
        XCTAssertEqual(state.escape(), .close, "a batch view has nothing typed to clear")
    }

    func testSelectionMovesAndClamps() {
        var state = loaded()
        XCTAssertEqual(state.selectedIndex, 0)
        state.moveSelection(by: 1)
        state.moveSelection(by: 1)
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selectedIndex, 2)
        state.moveSelection(by: -5)
        XCTAssertEqual(state.selectedIndex, 0)
        state.select(7)
        XCTAssertEqual(state.selectedIndex, 0, "out of range is ignored")
        state.select(1)
        XCTAssertEqual(state.selected?.title, "b")

        var empty = loaded([])
        empty.moveSelection(by: 1)
        XCTAssertNil(empty.selectedIndex)
    }

    func testANewQuerySelectsTheBestMatchAndARefreshKeepsTheSelection() {
        var state = loaded()
        state.moveSelection(by: 2)
        XCTAssertTrue(state.apply(result(["x", "c"]), for: state.query), "same query again (window reopened)")
        XCTAssertEqual(state.selected?.title, "c")
        state.apply(result(["x", "y"]), for: state.query)
        XCTAssertEqual(state.selectedIndex, 0, "the selected file is gone")
        state.moveSelection(by: 1)
        state.setText("y")
        state.apply(result(["x", "y"]), for: state.query)
        XCTAssertEqual(state.selectedIndex, 0, "a new query selects the best match")
    }

    func testTagClickPutsTheTagInTheFieldAndResetsTheChip() {
        var state = loaded()
        state.setText("old words")
        state.selectChip(.receipt)
        XCTAssertTrue(state.clickTag("#coffee"))
        XCTAssertEqual(state.text, "coffee")
        XCTAssertEqual(state.chip, .all)
        XCTAssertFalse(state.clickTag("coffee"), "already showing it")
        state.showBatch(["/a.png"])
        XCTAssertTrue(state.clickTag("coffee"), "leaves the batch")
        XCTAssertNil(state.batchPaths)
    }

    func testBatchViewAndLeavingIt() {
        var state = loaded()
        state.setText("old")
        state.selectChip(.code)
        state.showBatch(["/a.png", "/b.png"])
        XCTAssertEqual(state.query, ScreenshotQuery(paths: ["/a.png", "/b.png"]))
        state.apply(result(["a", "b"]), for: state.query)
        XCTAssertEqual(state.footerText, "This batch · 2 screenshots")
        XCTAssertEqual(state.resultLimit, SearchWindowState.pageSize)
        state.showBatch((0..<300).map { "/\($0).png" })
        XCTAssertEqual(state.resultLimit, 300, "a batch asks for all its files")
        state.apply(result([]), for: state.query)
        XCTAssertEqual(state.phase, .noMatch(SearchMessage(
            title: "These screenshots are no longer in the index",
            message: "They were moved, renamed or restored since. Clear the search to see recent screenshots.")))

        state.showBatch((0..<1500).map { "/\($0).png" })
        XCTAssertEqual(state.resultLimit, SearchWindowState.maxResults, "capped at 1000")
        XCTAssertTrue(state.setText("a"))
        XCTAssertNil(state.batchPaths, "typing searches the whole index")
        state.showBatch(["/a.png"])
        XCTAssertTrue(state.selectChip(.all), "choosing a chip (even All) leaves the batch")
        XCTAssertNil(state.batchPaths)
        state.showBatch(["/a.png"])
        XCTAssertTrue(state.windowHidden())
        XCTAssertNil(state.batchPaths, "the next open shows recent screenshots")
        XCTAssertFalse(state.windowHidden())
    }

    func testSpaceOpensQuickLookOnlyWhenNotTypingAQuery() {
        var state = loaded()
        XCTAssertTrue(state.spaceOpensQuickLook, "empty field + a selection")
        state.setText("coffee")
        state.apply(result(["a", "b"]), for: state.query)
        XCTAssertFalse(state.spaceOpensQuickLook, "typing: Space is a space")
        state.moveSelection(by: 1)
        XCTAssertTrue(state.spaceOpensQuickLook, "after ↑/↓ the user is browsing")
        state.setText("coffee ")
        XCTAssertFalse(state.spaceOpensQuickLook)
        state.apply(result(["a"]), for: state.query)
        state.select(0)
        XCTAssertTrue(state.spaceOpensQuickLook, "a click on a row is browsing too")
        var empty = loaded([])
        XCTAssertFalse(empty.spaceOpensQuickLook, "nothing selected")
        empty.moveSelection(by: 1)
        XCTAssertFalse(empty.spaceOpensQuickLook)
    }

    func testClearButtonOnlyWithText() {
        var state = loaded()
        XCTAssertFalse(state.showsClearButton)
        state.setText(" ")
        XCTAssertTrue(state.showsClearButton)
    }
}

final class IndexErrorTextTests: XCTestCase {
    func testSQLiteErrorsGetShortTextWithoutSQLiteMessages() {
        func text(_ code: Int32) -> String {
            UserFacingError.problem(for: SQLiteError(code: code, message: "near SELECT: /Users/parag/secret.sqlite")).message
        }
        XCTAssertEqual(text(11), "the index file is damaged")
        XCTAssertEqual(text(26), "the index file is damaged")
        XCTAssertEqual(text(14), "the index file could not be opened")
        XCTAssertEqual(text(13), "the disk is full")
        XCTAssertEqual(text(8), "the index file is read-only")
        XCTAssertEqual(text(5), "the index is busy, try again in a moment")
        XCTAssertEqual(text(266), "the index file could not be read from disk", "SQLITE_IOERR_READ is an extended IOERR")
        XCTAssertEqual(text(3), "Shotkeeper is not allowed to open the index file")
        XCTAssertEqual(text(1), "the index could not be read (SQLite error 1)")
        XCTAssertFalse(text(1).contains("/Users"))
    }

    func testAProblemPassesThrough() {
        let problem = UserFacingProblem(message: "the index is not open")
        XCTAssertEqual(UserFacingError.problem(for: problem), problem)
    }
}
