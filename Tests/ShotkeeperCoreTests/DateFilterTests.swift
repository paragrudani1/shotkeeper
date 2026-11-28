import XCTest
@testable import ShotkeeperCore

private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func at(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

private func days(_ start: String, _ end: String) -> Range<Date> {
    at(start)..<at(end)
}

/// `DateFilter` resolves to whole local days, `[start, end)`, for a given clock and calendar (spec "Filter model").
final class DateFilterTests: XCTestCase {
    private let utc = calendar("UTC")
    /// 2026-11-21 16:24 UTC, a Saturday.
    private let now = at("2026-11-21T16:24:00Z")

    func testPresetsAreWholeDaysEndingTonight() {
        XCTAssertEqual(DateFilter.today.interval(now: now, calendar: utc),
                       days("2026-11-21T00:00:00Z", "2026-11-22T00:00:00Z"))
        XCTAssertEqual(DateFilter.yesterday.interval(now: now, calendar: utc),
                       days("2026-11-20T00:00:00Z", "2026-11-21T00:00:00Z"))
        XCTAssertEqual(DateFilter.last7Days.interval(now: now, calendar: utc),
                       days("2026-11-15T00:00:00Z", "2026-11-22T00:00:00Z"), "today plus the 6 days before it")
        XCTAssertEqual(DateFilter.last30Days.interval(now: now, calendar: utc),
                       days("2026-10-23T00:00:00Z", "2026-11-22T00:00:00Z"), "today plus the 29 days before it")
    }

    func testDayEdges() {
        let today = DateFilter.today.interval(now: now, calendar: utc)
        XCTAssertTrue(today.contains(at("2026-11-21T00:00:00Z")), "midnight belongs to the new day")
        XCTAssertTrue(today.contains(at("2026-11-21T23:59:59Z")))
        XCTAssertFalse(today.contains(at("2026-11-22T00:00:00Z")), "the end is open")
        XCTAssertFalse(today.contains(at("2026-11-20T23:59:59Z")))
    }

    func testMidnightRollsTodayOver() {
        let before = DateFilter.today.interval(now: at("2026-11-21T23:59:59Z"), calendar: utc)
        let after = DateFilter.today.interval(now: at("2026-11-22T00:00:00Z"), calendar: utc)
        XCTAssertEqual(before, days("2026-11-21T00:00:00Z", "2026-11-22T00:00:00Z"))
        XCTAssertEqual(after, days("2026-11-22T00:00:00Z", "2026-11-23T00:00:00Z"))
        XCTAssertEqual(DateFilter.yesterday.interval(now: at("2026-11-22T00:00:00Z"), calendar: utc), before)
    }

    func testDaysAreLocalDaysInTheCalendarsTimeZone() {
        // 06:00 UTC is still Friday evening (22:00) in Los Angeles.
        let losAngeles = calendar("America/Los_Angeles")
        XCTAssertEqual(DateFilter.today.interval(now: at("2026-11-21T06:00:00Z"), calendar: losAngeles),
                       days("2026-11-20T08:00:00Z", "2026-11-21T08:00:00Z"))
        // Kolkata is UTC+5:30: its day starts at 18:30 UTC the evening before.
        XCTAssertEqual(DateFilter.today.interval(now: now, calendar: calendar("Asia/Kolkata")),
                       days("2026-11-20T18:30:00Z", "2026-11-21T18:30:00Z"))
    }

    func testADaylightSavingDayIsOneWholeLocalDay() {
        let newYork = calendar("America/New_York")
        // Clocks go forward on 2026-03-08: that day has 23 hours.
        let springForward = DateFilter.today.interval(now: at("2026-03-08T18:00:00Z"), calendar: newYork)
        XCTAssertEqual(springForward, days("2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z"))
        // Clocks go back on 2026-11-01 (25 hours); the last 7 days span the change.
        XCTAssertEqual(DateFilter.last7Days.interval(now: at("2026-11-03T15:00:00Z"), calendar: newYork),
                       days("2026-10-28T04:00:00Z", "2026-11-04T05:00:00Z"))
        XCTAssertEqual(DateFilter.days(from: CalendarDay(year: 2026, month: 11, day: 1),
                                       through: CalendarDay(year: 2026, month: 11, day: 1))
                           .interval(now: now, calendar: newYork),
                       days("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z"))
    }

    func testCustomRangeCoversBothDaysAndIsSwappedWhenReversed() {
        let oct3 = CalendarDay(year: 2026, month: 10, day: 3)
        let oct17 = CalendarDay(year: 2026, month: 10, day: 17)
        let expected = days("2026-10-03T00:00:00Z", "2026-10-18T00:00:00Z")
        XCTAssertEqual(DateFilter.days(from: oct3, through: oct17).interval(now: now, calendar: utc), expected)
        XCTAssertEqual(DateFilter.days(from: oct17, through: oct3).interval(now: now, calendar: utc), expected)
    }

    func testAOneDayRange() {
        let oct3 = CalendarDay(year: 2026, month: 10, day: 3)
        XCTAssertEqual(DateFilter.days(from: oct3, through: oct3).interval(now: now, calendar: utc),
                       days("2026-10-03T00:00:00Z", "2026-10-04T00:00:00Z"))
    }

    func testACustomRangeDoesNotDependOnTheClock() {
        let range = DateFilter.days(from: CalendarDay(year: 2025, month: 12, day: 28),
                                    through: CalendarDay(year: 2026, month: 1, day: 4))
        XCTAssertEqual(range.interval(now: now, calendar: utc), range.interval(now: at("2030-01-01T00:00:00Z"), calendar: utc))
        XCTAssertEqual(range.interval(now: now, calendar: utc), days("2025-12-28T00:00:00Z", "2026-01-05T00:00:00Z"))
    }

    func testCalendarDayOfADateUsesTheCalendarsTimeZone() {
        XCTAssertEqual(CalendarDay(at("2026-11-21T06:00:00Z"), calendar: calendar("America/Los_Angeles")),
                       CalendarDay(year: 2026, month: 11, day: 20))
        XCTAssertEqual(CalendarDay(at("2026-11-21T06:00:00Z"), calendar: utc), CalendarDay(year: 2026, month: 11, day: 21))
        XCTAssertLessThan(CalendarDay(year: 2025, month: 12, day: 31), CalendarDay(year: 2026, month: 1, day: 1))
    }
}

/// Seam 1: `ScreenshotIndex.search(_:limit:now:calendar:)` with the date filter, on an in-memory index.
final class DateFilterIndexTests: XCTestCase {
    private let utc = calendar("UTC")
    /// 2026-11-21 16:24 UTC.
    private let now = at("2026-11-21T16:24:00Z")

    private func shot(_ title: String, taken: String?, processed: String?, type: ContentType = .other,
                      tags: [String] = [], status: ProcessingStatus = .done) -> IndexedScreenshot {
        .testRow("/Users/parag/Desktop/\(title).png") {
            $0.title = title
            $0.capturedAt = taken.map(at)
            $0.processedAt = processed.map(at)
            $0.contentType = type
            $0.tags = tags
            $0.status = status
        }
    }

    private func makeIndex() throws -> ScreenshotIndex {
        let index = try ScreenshotIndex.inMemory()
        try index.save(shot("Receipt this morning", taken: "2026-11-21T09:00:00Z", processed: "2026-11-21T09:00:05Z",
                            type: .receipt, tags: ["invoice"]))
        try index.save(shot("Chat just after midnight", taken: "2026-11-21T00:00:00Z", processed: "2026-11-21T00:00:04Z",
                            type: .chat, tags: ["invoice"]))
        try index.save(shot("Code late yesterday", taken: "2026-11-20T23:59:59Z", processed: "2026-11-21T00:01:00Z",
                            type: .code))
        // Taken last week but processed today (Process Existing): the date taken counts.
        try index.save(shot("Old receipt processed today", taken: "2026-11-14T12:00:00Z", processed: "2026-11-21T10:00:00Z",
                            type: .receipt, tags: ["invoice"]))
        // No capture date: the processing date counts, like the row's time label.
        try index.save(shot("Clipboard image from today", taken: nil, processed: "2026-11-21T08:00:00Z"))
        try index.save(shot("Pending from today", taken: "2026-11-21T11:00:00Z", processed: nil, status: .pending))
        return index
    }

    private func titles(_ query: ScreenshotQuery, in index: ScreenshotIndex) throws -> [String] {
        try index.search(query, now: now, calendar: utc).rows.map(\.title!)
    }

    func testTodayUsesTheDateTakenElseTheDateProcessedNewestFirst() throws {
        let index = try makeIndex()
        XCTAssertEqual(try titles(ScreenshotQuery(date: .today), in: index),
                       ["Receipt this morning", "Clipboard image from today", "Chat just after midnight"],
                       "no text: newest first; a pending row is not a result")
        XCTAssertEqual(try titles(ScreenshotQuery(date: .yesterday), in: index), ["Code late yesterday"])
        XCTAssertEqual(try titles(ScreenshotQuery(date: .days(from: CalendarDay(year: 2026, month: 11, day: 14),
                                                              through: CalendarDay(year: 2026, month: 11, day: 14))),
                                  in: index),
                       ["Old receipt processed today"])
    }

    func testDateCombinesWithTextTypeAndBatchAndCounts() throws {
        let index = try makeIndex()
        let invoicesToday = try index.search(ScreenshotQuery(text: "invoice", date: .today), now: now, calendar: utc)
        XCTAssertEqual(Set(invoicesToday.rows.map(\.title!)), ["Receipt this morning", "Chat just after midnight"])
        XCTAssertEqual(invoicesToday.matchCount, 2)
        XCTAssertEqual(invoicesToday.totalCount, 5, "the total is the whole index, not the filtered rows")

        XCTAssertEqual(try titles(ScreenshotQuery(text: "invoice", contentType: .receipt, date: .today), in: index),
                       ["Receipt this morning"])
        XCTAssertEqual(try titles(ScreenshotQuery(contentType: .receipt, date: .last30Days), in: index),
                       ["Receipt this morning", "Old receipt processed today"],
                       "type and date; newest by the date taken, the date the rows show, not by when it was processed")
        let batch = ["/Users/parag/Desktop/Code late yesterday.png", "/Users/parag/Desktop/Receipt this morning.png"]
        XCTAssertEqual(try titles(ScreenshotQuery(paths: batch, date: .today), in: index), ["Receipt this morning"])
        let none = try index.search(ScreenshotQuery(text: "invoice", contentType: .code, date: .today), now: now, calendar: utc)
        XCTAssertEqual(none.rows, [])
        XCTAssertEqual(none.matchCount, 0)
        XCTAssertEqual(none.totalCount, 5)
    }

    func testTodayIsResolvedOnEachSearch() throws {
        let index = try makeIndex()
        let query = ScreenshotQuery(date: .today)
        XCTAssertEqual(try index.search(query, now: at("2026-11-22T00:00:00Z"), calendar: utc).rows, [],
                       "after midnight the same query shows the new day")
        XCTAssertEqual(try index.search(query, now: at("2026-11-20T20:00:00Z"), calendar: utc).rows.map(\.title!),
                       ["Code late yesterday"])
    }

    func testTheCalendarsTimeZoneDecidesTheDay() throws {
        let index = try makeIndex()
        // In Los Angeles (UTC-8) it is 08:24 on Nov 21; "today" runs from 08:00 UTC, so midnight UTC is yesterday there.
        XCTAssertEqual(try index.search(ScreenshotQuery(date: .today), now: now, calendar: calendar("America/Los_Angeles"))
                           .rows.map(\.title!),
                       ["Receipt this morning", "Clipboard image from today"])
    }
}

/// The date filter's SQL uses migration 3's `screenshots_taken_at` expression index (ticket 01), read from
/// `EXPLAIN QUERY PLAN` (https://www.sqlite.org/eqp.html) on the statements `search` runs.
final class DateFilterQueryPlanTests: XCTestCase {
    private let utc = calendar("UTC")

    private func plan(_ query: ScreenshotQuery) throws -> (select: [String], count: [String]) {
        let dir = try TempDir()
        let file = dir.url.appendingPathComponent("index.sqlite")
        let index = try ScreenshotIndex(fileURL: file) // migrates the file to version 3
        for day in 1...30 {
            try index.save(.testRow("/shot-\(day).png") {
                $0.title = "Invoice \(day)"
                $0.capturedAt = at("2026-11-\(String(format: "%02d", day))T09:00:00Z")
                $0.processedAt = at("2026-11-21T10:00:00Z")
            })
        }
        let sql = ScreenshotIndex.searchSQL(query, now: at("2026-11-21T16:24:00Z"), calendar: utc)
        let db = try SQLiteDatabase(path: file.path)
        func explain(_ statement: String, _ bindings: [SQLiteValue]) throws -> [String] {
            var details: [String] = []
            // Columns: id, parent, notused, detail.
            try db.query("EXPLAIN QUERY PLAN " + statement, bindings) { details.append($0.text(3) ?? "") }
            return details
        }
        return (try explain(sql.select, sql.bindings + [.int(50)]), try explain(sql.count, sql.bindings))
    }

    func testDateFilteredSearchUsesTheTakenAtIndex() throws {
        let dateOnly = try plan(ScreenshotQuery(date: .last7Days))
        for details in [dateOnly.select, dateOnly.count] {
            XCTAssertTrue(details.contains { $0.contains("USING INDEX screenshots_taken_at") }, "\(details)")
            XCTAssertFalse(details.contains { $0.hasPrefix("SCAN s") && !$0.contains("INDEX") }, "\(details)")
        }
        XCTAssertFalse(dateOnly.select.contains { $0.contains("TEMP B-TREE") },
                       "newest taken first is read from the index, not sorted: \(dateOnly.select)")
        let withType = try plan(ScreenshotQuery(contentType: .receipt, date: .today))
        XCTAssertTrue(withType.select.contains { $0.contains("USING INDEX screenshots_taken_at") }, "\(withType.select)")
    }
}

/// Wording of the date filter (design §5, "Filter pills" and "No-match states").
final class DateFilterLabelTests: XCTestCase {
    private let time = TimeLabel(calendar: calendar("UTC"), locale: Locale(identifier: "en_US"))
    /// 2026-11-21 16:24 UTC.
    private let now = at("2026-11-21T16:24:00Z")

    /// ICU puts thin or narrow no-break spaces around the range dash, depending on its version.
    private func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2009}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func range(_ from: (Int, Int, Int), _ through: (Int, Int, Int)) -> DateFilter {
        .days(from: CalendarDay(year: from.0, month: from.1, day: from.2),
              through: CalendarDay(year: through.0, month: through.1, day: through.2))
    }

    func testPillLabels() {
        XCTAssertEqual(DateFilter.today.label(now: now, time: time), "Today")
        XCTAssertEqual(DateFilter.yesterday.label(now: now, time: time), "Yesterday")
        XCTAssertEqual(DateFilter.last7Days.label(now: now, time: time), "Last 7 days")
        XCTAssertEqual(DateFilter.last30Days.label(now: now, time: time), "Last 30 days")
    }

    func testCustomRangeLabelsDropTheYearInTheCurrentYear() {
        XCTAssertEqual(plain(range((2026, 10, 3), (2026, 10, 17)).label(now: now, time: time)), "Oct 3 – 17")
        XCTAssertEqual(plain(range((2026, 10, 17), (2026, 10, 3)).label(now: now, time: time)), "Oct 3 – 17", "swapped")
        XCTAssertEqual(plain(range((2026, 10, 28), (2026, 11, 3)).label(now: now, time: time)), "Oct 28 – Nov 3")
        XCTAssertEqual(plain(range((2025, 12, 28), (2026, 1, 4)).label(now: now, time: time)), "Dec 28, 2025 – Jan 4, 2026")
        XCTAssertEqual(plain(range((2025, 3, 1), (2025, 3, 9)).label(now: now, time: time)), "Mar 1 – 9, 2025")
        XCTAssertEqual(range((2026, 10, 3), (2026, 10, 3)).label(now: now, time: time), "Oct 3", "one day")
        XCTAssertEqual(range((2025, 10, 3), (2025, 10, 3)).label(now: now, time: time), "Oct 3, 2025")
    }

    func testVoiceOverValues() {
        XCTAssertEqual(DateFilter.today.spokenValue(now: now, time: time), "today")
        XCTAssertEqual(DateFilter.yesterday.spokenValue(now: now, time: time), "yesterday")
        XCTAssertEqual(DateFilter.last7Days.spokenValue(now: now, time: time), "last 7 days")
        XCTAssertEqual(DateFilter.last30Days.spokenValue(now: now, time: time), "last 30 days")
        XCTAssertEqual(range((2026, 10, 3), (2026, 10, 17)).spokenValue(now: now, time: time), "October 3 to October 17")
        XCTAssertEqual(range((2026, 10, 3), (2026, 10, 3)).spokenValue(now: now, time: time), "October 3")
    }

    func testTakenPhrases() {
        XCTAssertEqual(DateFilter.today.takenPhrase(now: now, time: time), "taken today")
        XCTAssertEqual(DateFilter.yesterday.takenPhrase(now: now, time: time), "taken yesterday")
        XCTAssertEqual(DateFilter.last7Days.takenPhrase(now: now, time: time), "taken in the last 7 days")
        XCTAssertEqual(DateFilter.last30Days.takenPhrase(now: now, time: time), "taken in the last 30 days")
        XCTAssertEqual(range((2026, 10, 3), (2026, 10, 3)).takenPhrase(now: now, time: time), "taken on Oct 3")
        XCTAssertEqual(range((2026, 10, 17), (2026, 10, 3)).takenPhrase(now: now, time: time), "taken between Oct 3 and Oct 17")
        XCTAssertEqual(range((2025, 12, 28), (2026, 1, 4)).takenPhrase(now: now, time: time),
                       "taken between Dec 28, 2025 and Jan 4, 2026")
    }
}
