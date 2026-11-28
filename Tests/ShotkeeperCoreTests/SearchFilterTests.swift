import XCTest
@testable import ShotkeeperCore

/// 2026-11-21 16:24 UTC, a Saturday.
private let now = Date(timeIntervalSince1970: 1_795_278_240)
private let time: TimeLabel = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return TimeLabel(calendar: calendar, locale: Locale(identifier: "en_US"))
}()

private func row(_ name: String) -> IndexedScreenshot {
    .testRow("/Users/parag/Desktop/\(name).png") { $0.title = name; $0.capturedAt = now }
}

private func result(_ names: [String], total: Int = 214) -> ScreenshotSearchResult {
    ScreenshotSearchResult(rows: names.map(row), matchCount: names.count, totalCount: total)
}

private func loaded(_ names: [String] = ["a", "b", "c"]) -> SearchWindowState {
    var state = SearchWindowState(now: now, time: time)
    state.apply(result(names), for: state.query)
    return state
}

private let oct3 = CalendarDay(year: 2026, month: 10, day: 3)
private let oct17 = CalendarDay(year: 2026, month: 10, day: 17)

/// Seam 2: the date filter in `SearchWindowState` (spec "Filter model", stories 13–19).
final class SearchDateFilterStateTests: XCTestCase {
    func testSettingADateFilterChangesTheQueryAndCountsAsAFilter() {
        var state = loaded()
        XCTAssertFalse(state.hasFilter)
        XCTAssertTrue(state.setDateFilter(.last7Days))
        XCTAssertFalse(state.setDateFilter(.last7Days), "same filter: no new search")
        XCTAssertEqual(state.query, ScreenshotQuery(date: .last7Days))
        XCTAssertTrue(state.hasFilter)
        state.apply(ScreenshotSearchResult(rows: [row("a")], matchCount: 6, totalCount: 214), for: state.query)
        XCTAssertEqual(state.footerText, "6 of 214 screenshots")
        state.setText("invoice")
        state.selectChip(.receipt)
        XCTAssertEqual(state.query, ScreenshotQuery(text: "invoice", contentType: .receipt, date: .last7Days))
        XCTAssertTrue(state.setDateFilter(nil))
        XCTAssertEqual(state.query, ScreenshotQuery(text: "invoice", contentType: .receipt))
    }

    func testChangingTheDateLeavesABatchView() {
        var state = loaded()
        state.showBatch(["/a.png"])
        XCTAssertTrue(state.setDateFilter(.today))
        XCTAssertNil(state.batchPaths, "filters always search the whole index (story 19)")
        state.showBatch(["/a.png"])
        XCTAssertNil(state.date, "a batch view starts without a date filter")
        XCTAssertTrue(state.setDateFilter(nil), "clearing an absent date still leaves the batch")
        XCTAssertNil(state.batchPaths)
    }

    func testClearFiltersKeepsTheWords() {
        var state = loaded()
        state.setText("invoice")
        state.selectChip(.receipt)
        state.setDateFilter(.last30Days)
        XCTAssertTrue(state.clearFilters())
        XCTAssertEqual(state.query, ScreenshotQuery(text: "invoice"))
        XCTAssertFalse(state.clearFilters(), "nothing left to clear")
        state.showBatch(["/a.png"])
        XCTAssertTrue(state.clearFilters(), "leaves a batch view")
        XCTAssertNil(state.batchPaths)
    }

    func testEscapeAndClearSearchResetTheDateToo() {
        var state = loaded()
        state.setDateFilter(.today)
        XCTAssertEqual(state.escape(), .clearedSearch, "a date filter is part of the search")
        XCTAssertNil(state.date)
        XCTAssertEqual(state.escape(), .close, "close only when text, chip and date are all empty")

        state.setText("x")
        state.selectChip(.code)
        state.setDateFilter(.yesterday)
        XCTAssertEqual(state.escape(), .clearedSearch)
        XCTAssertEqual(state.query, ScreenshotQuery(), "one press clears everything (story 15)")

        state.setDateFilter(.days(from: oct3, through: oct17))
        XCTAssertTrue(state.clearSearch())
        XCTAssertEqual(state.query, ScreenshotQuery(), "Clear search resets every filter (story 16)")
    }

    func testATagClickResetsTheDate() {
        var state = loaded()
        state.setDateFilter(.last7Days)
        XCTAssertTrue(state.clickTag("#coffee"))
        XCTAssertEqual(state.query, ScreenshotQuery(text: "coffee"))
        state.setDateFilter(.today)
        XCTAssertTrue(state.clickTag("coffee"), "same words, but the date was reset")
        XCTAssertNil(state.date)
    }

    func testHidingTheWindowKeepsTheDate() {
        var state = loaded()
        state.setText("receipt")
        state.setDateFilter(.today)
        XCTAssertFalse(state.windowHidden(), "nothing changed: no new search")
        XCTAssertEqual(state.query, ScreenshotQuery(text: "receipt", date: .today), "story 18")
    }
}

/// No-match states with a date filter (design §5, "No-match states"; story 17).
final class SearchFilterNoMatchTests: XCTestCase {
    private func noMatch(text: String = "", chip: SearchChip = .all, date: DateFilter?) -> SearchWindowState {
        var state = loaded()
        state.setText(text)
        state.selectChip(chip)
        state.setDateFilter(date)
        state.apply(result([]), for: state.query)
        return state
    }

    private let clearFilters = "Clear filters to see every screenshot."

    func testDateWithoutTextNamesTheFilterAndOffersClearFilters() {
        let state = noMatch(date: .last7Days)
        XCTAssertEqual(state.phase, .noMatch(SearchMessage(title: "No screenshots taken in the last 7 days", message: clearFilters)))
        XCTAssertEqual(state.noMatchButtons, [.clearFilters], "nothing typed, so nothing else to clear")
        XCTAssertEqual(state.help(for: .clearFilters), "Show every screenshot")
        XCTAssertEqual(noMatch(date: .today).phase,
                       .noMatch(SearchMessage(title: "No screenshots taken today", message: clearFilters)))
        XCTAssertEqual(noMatch(date: .days(from: oct17, through: oct3)).phase,
                       .noMatch(SearchMessage(title: "No screenshots taken between Oct 3 and Oct 17", message: clearFilters)))
    }

    func testDateAndChipWithoutText() {
        let state = noMatch(chip: .receipt, date: .days(from: oct3, through: oct3))
        XCTAssertEqual(state.phase, .noMatch(SearchMessage(title: "No Receipt screenshots taken on Oct 3", message: clearFilters)))
        XCTAssertEqual(state.noMatchButtons, [.clearFilters])
    }

    func testTextAndDateSayWhatTheFiltersLimit() {
        let state = noMatch(text: " invoice ", date: .today)
        XCTAssertEqual(state.phase, .noMatch(SearchMessage(
            title: "No screenshots match “invoice”",
            message: "Your filters limit this search to screenshots taken today.")))
        XCTAssertEqual(state.noMatchButtons, [.clearFilters, .clearSearch], "Clear filters first: it keeps the words")
        XCTAssertEqual(state.help(for: .clearFilters), "Show every screenshot that matches the words")
        XCTAssertEqual(state.help(for: .clearSearch), "Clear the words and every filter")

        XCTAssertEqual(noMatch(text: "invoice", chip: .receipt, date: .last30Days).phase, .noMatch(SearchMessage(
            title: "No screenshots match “invoice”",
            message: "Your filters limit this search to Receipt screenshots taken in the last 30 days.")))
    }

    func testWithoutADateTheApprovedStatesAreUnchanged() {
        let text = noMatch(text: "zebra", date: nil)
        XCTAssertEqual(text.phase, .noMatch(SearchMessage(
            title: "No screenshots match “zebra”",
            message: "Try other words from the title, from the text in the image, or a tag.")))
        XCTAssertEqual(text.noMatchButtons, [.clearSearch])
        XCTAssertEqual(noMatch(text: "zebra", chip: .receipt, date: nil).noMatchButtons, [.clearSearch])
        let chip = noMatch(chip: .tweet, date: nil)
        XCTAssertEqual(chip.phase, .noMatch(SearchMessage(title: "No Tweet screenshots", message: "Choose All to see every screenshot.")))
        XCTAssertEqual(chip.noMatchButtons, [.clearSearch])
    }

    func testClearFiltersFromTheNoMatchStateKeepsTheWords() {
        var state = noMatch(text: "invoice", chip: .receipt, date: .today)
        XCTAssertTrue(state.clearFilters())
        XCTAssertEqual(state.query, ScreenshotQuery(text: "invoice"))
    }
}

/// The Date pill's text, tooltip and VoiceOver value (design §5, "Filter pills").
final class SearchDatePillTests: XCTestCase {
    func testOffAndOn() {
        var state = loaded()
        XCTAssertEqual(state.datePillTitle, "Date")
        XCTAssertEqual(state.datePillValue, "any time")
        XCTAssertEqual(state.datePillHelp, "Filter by the day it was taken (⌘D)")
        state.setDateFilter(.last7Days)
        XCTAssertEqual(state.datePillTitle, "Last 7 days")
        XCTAssertEqual(state.datePillValue, "last 7 days")
        XCTAssertEqual(state.datePillHelp, "Change the date (⌘D)")
        state.setDateFilter(.days(from: oct3, through: oct3))
        XCTAssertEqual(state.datePillTitle, "Oct 3")
        XCTAssertEqual(state.datePillValue, "October 3")
    }

    func testAnnouncements() {
        XCTAssertEqual(SearchWindowState.Announcement.dateCleared, "Date cleared")
        XCTAssertEqual(SearchWindowState.Announcement.filtersCleared, "Filters cleared")
        XCTAssertEqual(SearchWindowState.Announcement.searchCleared, "Search cleared")
    }
}

/// The in-panel date picker (design §4 "Date picker", §6 keys and Esc order). The app draws it; core decides.
final class SearchDatePickerTests: XCTestCase {
    func testDCommandOpensThePickerOnTheCurrentValueAndClosesIt() throws {
        var state = loaded()
        XCTAssertNil(state.datePicker)
        state.toggleDatePicker()
        let picker = try XCTUnwrap(state.datePicker)
        XCTAssertEqual(DatePickerOption.allCases.map(\.title),
                       ["Any time", "Today", "Yesterday", "Last 7 days", "Last 30 days", "Custom range…"])
        XCTAssertEqual(picker.highlighted, .anyTime)
        XCTAssertFalse(picker.showsCustomRange)
        XCTAssertEqual(state.currentDateOption, .anyTime, "the check mark")
        state.toggleDatePicker()
        XCTAssertNil(state.datePicker, "⌘D again closes it")

        state.setDateFilter(.last7Days)
        state.toggleDatePicker()
        XCTAssertEqual(state.datePicker?.highlighted, .last7Days)
        XCTAssertEqual(state.currentDateOption, .last7Days)
    }

    func testArrowsMoveTheHighlightAndReturnChooses() {
        var state = loaded()
        state.toggleDatePicker()
        state.moveDateHighlight(by: 1)
        state.moveDateHighlight(by: 1)
        state.moveDateHighlight(by: 1)
        XCTAssertEqual(state.datePicker?.highlighted, .last7Days, "⌘D ↓↓↓ ↩ is Last 7 days")
        XCTAssertTrue(state.chooseHighlightedDate())
        XCTAssertEqual(state.date, .last7Days)
        XCTAssertNil(state.datePicker, "a choice closes the picker")

        state.toggleDatePicker()
        state.moveDateHighlight(by: -9)
        XCTAssertEqual(state.datePicker?.highlighted, .anyTime, "clamped at the top")
        state.moveDateHighlight(by: 9)
        XCTAssertEqual(state.datePicker?.highlighted, .customRange, "clamped at the bottom")
        state.moveDateHighlight(by: -6)
        XCTAssertTrue(state.chooseHighlightedDate(), "Any time clears the date")
        XCTAssertNil(state.date)

        state.toggleDatePicker()
        XCTAssertFalse(state.chooseHighlightedDate(), "Any time when already any time: no new search")
        XCTAssertNil(state.datePicker)
    }

    func testAClickChoosesAnOption() {
        var state = loaded()
        state.showBatch(["/a.png"])
        state.toggleDatePicker()
        XCTAssertTrue(state.chooseDate(.today))
        XCTAssertEqual(state.query, ScreenshotQuery(date: .today), "and leaves the batch")
        XCTAssertNil(state.datePicker)
    }

    func testCustomRangeExpandsInPlaceStartingAtTheLast7DaysAndApplies() throws {
        var state = loaded()
        state.toggleDatePicker()
        XCTAssertFalse(state.chooseDate(.customRange), "expanding is not a search")
        let picker = try XCTUnwrap(state.datePicker, "still open")
        XCTAssertTrue(picker.showsCustomRange)
        XCTAssertEqual(picker.customTitle, "Custom range")
        XCTAssertEqual(picker.from, CalendarDay(year: 2026, month: 11, day: 15), "6 days ago")
        XCTAssertEqual(picker.through, CalendarDay(year: 2026, month: 11, day: 21), "today")
        XCTAssertFalse(picker.takesArrowKeys, "↑↓ change the focused date field")

        state.setCustomRange(from: oct17, through: oct3)
        XCTAssertTrue(state.chooseHighlightedDate(), "↩ is Apply while the range is shown")
        XCTAssertEqual(state.date, .days(from: oct17, through: oct3), "core swaps it when resolving")
        XCTAssertNil(state.datePicker)

        state.toggleDatePicker()
        XCTAssertEqual(state.datePicker?.showsCustomRange, true, "reopens on the current range")
        XCTAssertEqual(state.datePicker?.highlighted, .customRange)
        XCTAssertEqual(state.datePicker?.from, oct17)
        XCTAssertEqual(state.datePicker?.through, oct3)
        XCTAssertEqual(state.currentDateOption, .customRange)
        XCTAssertFalse(state.applyCustomRange(), "the same range again: no new search")
        XCTAssertNil(state.datePicker)
        XCTAssertEqual(DatePickerState(today: oct3, current: nil, calendar: time.calendar).customTitle, "Custom range…")
    }

    func testDeleteInTheDateListClearsTheDateAndCloses() {
        var state = loaded()
        state.setDateFilter(.yesterday)
        state.toggleDatePicker()
        XCTAssertTrue(state.clearDateFromPicker())
        XCTAssertNil(state.date)
        XCTAssertNil(state.datePicker)
        state.toggleDatePicker()
        XCTAssertFalse(state.clearDateFromPicker(), "nothing to clear")
        XCTAssertNil(state.datePicker)
    }

    func testEscClosesThePickerThenClearsEverythingThenCloses() {
        var state = loaded()
        state.setText("invoice")
        state.setDateFilter(.today)
        state.toggleDatePicker()
        XCTAssertEqual(state.escape(), .closedPicker)
        XCTAssertNil(state.datePicker)
        XCTAssertEqual(state.query, ScreenshotQuery(text: "invoice", date: .today), "closing the picker changes nothing")
        XCTAssertEqual(state.escape(), .clearedSearch)
        XCTAssertEqual(state.escape(), .close)
    }

    func testHidingTheWindowClosesThePicker() {
        var state = loaded()
        state.setDateFilter(.today)
        state.toggleDatePicker()
        state.windowHidden()
        XCTAssertNil(state.datePicker, "a stale picker never stays open")
        XCTAssertEqual(state.date, .today)
    }
}
