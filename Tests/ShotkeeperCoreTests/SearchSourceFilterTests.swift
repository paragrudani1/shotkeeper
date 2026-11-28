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

private func facet(_ name: String, _ count: Int) -> SourceFacet {
    SourceFacet(key: SourceKey(name)!, displayName: name, count: count)
}

private let slack = facet("Slack", 64)
private let x = facet("X", 41)
private let stripe = facet("Stripe", 12)

private func loaded(_ names: [String] = ["a", "b", "c"], sources: [SourceFacet] = [slack, x, stripe]) -> SearchWindowState {
    var state = SearchWindowState(now: now, time: time)
    state.setSources(sources)
    state.apply(result(names), for: state.query)
    return state
}

/// Seam 2: the source filter in `SearchWindowState` (spec "Filter model"; stories 11, 14–19).
final class SearchSourceFilterStateTests: XCTestCase {
    func testSettingASourceChangesTheQueryAndCountsAsAFilter() {
        var state = loaded()
        XCTAssertNil(state.source)
        XCTAssertTrue(state.setSource(slack))
        XCTAssertFalse(state.setSource(facet("slack", 3)), "the same source: no new search")
        XCTAssertEqual(state.query, ScreenshotQuery(source: SourceKey("Slack")))
        XCTAssertTrue(state.hasFilter)
        state.apply(ScreenshotSearchResult(rows: [row("a")], matchCount: 6, totalCount: 214), for: state.query)
        XCTAssertEqual(state.footerText, "6 of 214 screenshots")
        state.setText("invoice")
        state.selectChip(.receipt)
        state.setDateFilter(.last30Days)
        XCTAssertEqual(state.query, ScreenshotQuery(text: "invoice", contentType: .receipt, date: .last30Days,
                                                    source: SourceKey("slack")))
        XCTAssertTrue(state.setSource(nil))
        XCTAssertNil(state.query.source)
    }

    func testChangingTheSourceLeavesABatchView() {
        var state = loaded()
        state.showBatch(["/a.png"])
        XCTAssertTrue(state.setSource(x))
        XCTAssertNil(state.batchPaths, "filters always search the whole index (story 19)")
        state.showBatch(["/a.png"])
        XCTAssertNil(state.source, "a batch view starts without a source")
        XCTAssertTrue(state.setSource(nil), "clearing an absent source still leaves the batch")
        XCTAssertNil(state.batchPaths)
    }

    func testEscClearSearchClearFiltersAndATagClickResetTheSource() {
        var state = loaded()
        state.setSource(slack)
        XCTAssertEqual(state.escape(), .clearedSearch, "a source is part of the search")
        XCTAssertNil(state.source)
        XCTAssertEqual(state.escape(), .close)

        state.setText("plan")
        state.setSource(slack)
        XCTAssertTrue(state.clearFilters())
        XCTAssertEqual(state.query, ScreenshotQuery(text: "plan"), "Clear filters keeps the words")
        XCTAssertFalse(state.clearFilters())

        state.setSource(slack)
        XCTAssertTrue(state.clearSearch())
        XCTAssertEqual(state.query, ScreenshotQuery(), "story 16")

        state.setSource(slack)
        XCTAssertTrue(state.clickTag("#launch"))
        XCTAssertEqual(state.query, ScreenshotQuery(text: "launch"), "story 20")
        state.setSource(slack)
        XCTAssertTrue(state.clickTag("launch"), "same words, but the source was reset")
    }

    func testHidingTheWindowKeepsTheSource() {
        var state = loaded()
        state.setSource(stripe)
        XCTAssertFalse(state.windowHidden())
        XCTAssertEqual(state.query, ScreenshotQuery(source: SourceKey("stripe")), "story 18")
        XCTAssertEqual(state.sourcePillTitle, "Stripe")
    }

    func testTheStateHoldsTheLoadedList() {
        var state = SearchWindowState(now: now, time: time)
        XCTAssertNil(state.sources, "not loaded yet")
        state.setSources([slack, x])
        XCTAssertEqual(state.sources, [slack, x])
        state.setSource(x)
        state.setSources([facet("x.com", 50), slack])
        XCTAssertEqual(state.sourcePillTitle, "x.com", "the reloaded list names the chosen source")
        XCTAssertEqual(state.query.source, SourceKey("X"))
    }
}

/// The Source pill (design §4 "Row 2", §5 "Filter pills").
final class SearchSourcePillTests: XCTestCase {
    func testOffOnAndDisabled() {
        var state = loaded()
        XCTAssertEqual(state.sourcePillTitle, "Source")
        XCTAssertEqual(state.sourcePillValue, "any source")
        XCTAssertEqual(state.sourcePillHelp, "Filter by app or site (⌘S)")
        XCTAssertFalse(state.sourcePillIsDisabled)
        state.setSource(facet("Microsoft Remote Desktop Connection", 9))
        XCTAssertEqual(state.sourcePillTitle, "Microsoft Remote Desktop Connection", "the view truncates; core keeps it whole")
        XCTAssertEqual(state.sourcePillValue, "Microsoft Remote Desktop Connection")
        XCTAssertEqual(state.sourcePillHelp, "Microsoft Remote Desktop Connection. Change the source (⌘S)")

        let empty = loaded([], sources: [])
        XCTAssertTrue(empty.sourcePillIsDisabled, "empty index, or no row has a source")
        XCTAssertEqual(empty.sourcePillHelp, "No screenshot has an app or site yet.")
        XCTAssertEqual(empty.sourcePillValue, "No screenshot has an app or site yet.")
        XCTAssertFalse(SearchWindowState().sourcePillIsDisabled, "not disabled before the list has loaded")

        var gone = loaded(sources: [slack])
        gone.setSource(slack)
        gone.setSources([])
        XCTAssertFalse(gone.sourcePillIsDisabled, "a chosen source can always be changed or cleared")
    }

    func testAnnouncement() {
        XCTAssertEqual(SearchWindowState.Announcement.sourceCleared, "Source cleared")
    }
}

/// No-match states with a source (design §5 "No-match states"; story 17).
final class SearchSourceNoMatchTests: XCTestCase {
    private func noMatch(text: String = "", chip: SearchChip = .all, date: DateFilter? = nil,
                         source: SourceFacet?, sources: [SourceFacet] = [slack, x, stripe]) -> SearchWindowState {
        var state = loaded(sources: sources)
        state.setText(text)
        state.selectChip(chip)
        state.setDateFilter(date)
        state.setSource(source)
        state.apply(result([]), for: state.query)
        return state
    }

    private let clearFilters = "Clear filters to see every screenshot."

    func testSourceWithoutTextNamesTheFilters() {
        XCTAssertEqual(noMatch(source: slack).phase,
                       .noMatch(SearchMessage(title: "No screenshots from Slack", message: clearFilters)))
        XCTAssertEqual(noMatch(date: .last7Days, source: slack).phase,
                       .noMatch(SearchMessage(title: "No screenshots from Slack taken in the last 7 days", message: clearFilters)))
        let all = noMatch(chip: .receipt, date: .last30Days, source: stripe)
        XCTAssertEqual(all.phase, .noMatch(SearchMessage(
            title: "No Receipt screenshots from Stripe taken in the last 30 days", message: clearFilters)))
        XCTAssertEqual(all.noMatchButtons, [.clearFilters])
    }

    func testTextAndASourceSayWhatTheFiltersLimit() {
        let state = noMatch(text: "invoice", chip: .receipt, date: .last30Days, source: stripe)
        XCTAssertEqual(state.phase, .noMatch(SearchMessage(
            title: "No screenshots match “invoice”",
            message: "Your filters limit this search to Receipt screenshots from Stripe taken in the last 30 days.")))
        XCTAssertEqual(state.noMatchButtons, [.clearFilters, .clearSearch])
        XCTAssertEqual(noMatch(text: "invoice", source: x).phase, .noMatch(SearchMessage(
            title: "No screenshots match “invoice”", message: "Your filters limit this search to screenshots from X.")))
    }

    func testASourceThatIsGoneIsStillNamed() {
        var state = noMatch(source: slack)
        state.setSources([x, stripe])
        XCTAssertEqual(state.phase,
                       .noMatch(SearchMessage(title: "No screenshots from Slack", message: clearFilters)))
        XCTAssertEqual(state.sourcePillTitle, "Slack", "the pill keeps the name")
    }
}

/// The in-panel source picker (design §4 "Source picker", §6 keys and Esc order). The app draws it; core decides.
final class SearchSourcePickerTests: XCTestCase {
    private let many = [slack, x, facet("GitHub", 27), facet("Mail", 18), facet("Xcode", 12),
                        facet("Microsoft Remote Desktop", 9), facet("console.cloud.google.com", 4), facet("Figma", 3),
                        facet("Café Déjà Vu", 2)]

    private func titles(_ state: SearchWindowState) -> [String] {
        state.sourcePicker?.rows.map { [$0.title, $0.count.map(String.init)].compactMap { $0 }.joined(separator: " ") } ?? []
    }

    func testCommandSOpensTheListWithAnySourceFirstAndCounts() throws {
        var state = loaded(sources: many)
        XCTAssertTrue(state.toggleSourcePicker())
        XCTAssertEqual(titles(state), ["Any source", "Slack 64", "X 41", "GitHub 27", "Mail 18", "Xcode 12",
                                       "Microsoft Remote Desktop 9", "console.cloud.google.com 4", "Figma 3",
                                       "Café Déjà Vu 2"])
        XCTAssertEqual(state.sourcePicker?.highlighted, .anySource)
        XCTAssertTrue(state.isCurrentSource(.anySource), "the check mark")
        XCTAssertEqual(state.sourcePicker?.rows[1].accessibilityLabel, "Slack, 64 screenshots")
        XCTAssertEqual(SourcePickerRow.source(facet("Figma", 1)).accessibilityLabel, "Figma, 1 screenshot")
        XCTAssertTrue(state.toggleSourcePicker())
        XCTAssertNil(state.sourcePicker, "⌘S again closes it")

        state.setSource(x)
        state.toggleSourcePicker()
        XCTAssertEqual(state.sourcePicker?.highlighted, .source(x), "opens on the current source")
        XCTAssertTrue(state.isCurrentSource(.source(x)))
    }

    func testTypingNarrowsByAFoldedSubstringAndHighlightsTheFirstMatch() {
        var state = loaded(sources: many)
        state.toggleSourcePicker()
        state.setSourceNarrowText("x")
        XCTAssertEqual(titles(state), ["X 41", "Xcode 12"], "no Any source while narrowing")
        XCTAssertEqual(state.sourcePicker?.highlighted, .source(x))
        state.setSourceNarrowText("sl")
        XCTAssertTrue(state.chooseHighlightedSource(), "⌘S, sl, ↩ picks Slack")
        XCTAssertEqual(state.source, SourceKey("slack"))
        XCTAssertNil(state.sourcePicker, "a choice closes the picker")

        state.toggleSourcePicker()
        state.setSourceNarrowText(" DEJA ")
        XCTAssertEqual(titles(state), ["Café Déjà Vu 2"], "case and diacritics are folded")
        state.setSourceNarrowText("GOOGLE")
        XCTAssertEqual(titles(state), ["console.cloud.google.com 4"])
    }

    func testNothingMatches() {
        var state = loaded(sources: many)
        state.toggleSourcePicker()
        XCTAssertNil(state.sourcePicker?.noMatchMessage)
        state.setSourceNarrowText("zz ")
        XCTAssertEqual(state.sourcePicker?.rows, [])
        XCTAssertEqual(state.sourcePicker?.noMatchMessage, "No source matches “zz”")
        XCTAssertNil(state.sourcePicker?.highlighted)
        state.moveSourceHighlight(by: 1)
        XCTAssertFalse(state.chooseHighlightedSource(), "↩ with no match does nothing")
        XCTAssertNotNil(state.sourcePicker, "and the picker stays open")
    }

    func testArrowsMoveAndClamp() {
        var state = loaded()
        state.toggleSourcePicker()
        state.moveSourceHighlight(by: 1)
        XCTAssertEqual(state.sourcePicker?.highlighted, .source(slack))
        state.moveSourceHighlight(by: 9)
        XCTAssertEqual(state.sourcePicker?.highlighted, .source(stripe), "clamped at the bottom")
        state.moveSourceHighlight(by: -9)
        XCTAssertEqual(state.sourcePicker?.highlighted, .anySource, "clamped at the top")
        state.moveSourceHighlight(by: 2)
        XCTAssertTrue(state.chooseHighlightedSource())
        XCTAssertEqual(state.query, ScreenshotQuery(source: SourceKey("x")))

        state.toggleSourcePicker()
        XCTAssertTrue(state.chooseSource(.anySource), "Any source clears it")
        XCTAssertNil(state.source)
        state.toggleSourcePicker()
        XCTAssertFalse(state.chooseSource(.anySource), "already any source: no new search")
    }

    func testAChosenSourceThatIsGoneStaysPinnedWithCountZero() {
        var state = loaded()
        state.setSource(facet("Linear", 5))
        state.setSources([slack, x])  // the panel reopened; Linear's rows were renamed away
        state.toggleSourcePicker()
        XCTAssertEqual(titles(state), ["Any source", "Linear 0", "Slack 64", "X 41"])
        XCTAssertEqual(state.sourcePicker?.highlighted, .source(facet("Linear", 0)))
        XCTAssertTrue(state.isCurrentSource(.source(facet("Linear", 0))), "checked")
        state.setSourceNarrowText("lin")
        XCTAssertEqual(titles(state), ["Linear 0"])
    }

    func testDeleteClearsOnlyWithAnEmptyNarrowField() {
        var state = loaded()
        state.setSource(slack)
        state.toggleSourcePicker()
        XCTAssertEqual(state.sourcePicker?.deleteClearsSource, true)
        state.setSourceNarrowText("s")
        XCTAssertEqual(state.sourcePicker?.deleteClearsSource, false, "⌫ deletes the typed letter")
        state.setSourceNarrowText("")
        XCTAssertTrue(state.clearSourceFromPicker(), "⌘S ⌫ clears the source")
        XCTAssertNil(state.source)
        XCTAssertNil(state.sourcePicker)
    }

    func testDisabledPillDoesNotOpen() {
        var state = loaded([], sources: [])
        XCTAssertFalse(state.toggleSourcePicker(), "the app beeps")
        XCTAssertNil(state.sourcePicker)
    }

    func testOnePickerAtATimeEscOrderAndHiding() {
        var state = loaded()
        state.setText("plan")
        state.setSource(slack)
        state.toggleDatePicker()
        state.toggleSourcePicker()
        XCTAssertNil(state.datePicker, "⌘S switches from the date picker")
        XCTAssertTrue(state.isPickerOpen)
        state.toggleDatePicker()
        XCTAssertNil(state.sourcePicker, "⌘D switches back")
        state.toggleSourcePicker()
        XCTAssertEqual(state.escape(), .closedPicker)
        XCTAssertEqual(state.query, ScreenshotQuery(text: "plan", source: SourceKey("slack")), "closing changes nothing")
        XCTAssertEqual(state.escape(), .clearedSearch)
        XCTAssertEqual(state.escape(), .close)

        state.setSource(x)
        state.toggleSourcePicker()
        state.setSourceNarrowText("sl")
        state.windowHidden()
        XCTAssertNil(state.sourcePicker, "a stale picker never stays open")
        XCTAssertEqual(state.source, SourceKey("x"))
        state.toggleSourcePicker()
        XCTAssertEqual(state.sourcePicker?.narrowText, "", "the narrow field starts empty each time")
    }

    func testTheListReloadingWhileOpenKeepsTheHighlight() {
        var state = loaded()
        state.toggleSourcePicker()
        state.moveSourceHighlight(by: 2)
        state.setSources([facet("Figma", 99), slack, x, stripe])
        XCTAssertEqual(state.sourcePicker?.highlighted, .source(x))
        XCTAssertEqual(state.sourcePicker?.rows.count, 5)
    }
}
