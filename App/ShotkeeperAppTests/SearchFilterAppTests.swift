import AppKit
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

/// The date filter in the panel: key routing while the picker is open and the VoiceOver announcements. The rules are
/// core's (`SearchDatePickerTests`); this checks the app performs them.
@MainActor
final class SearchDateFilterAppTests: XCTestCase {
    private func makeController() -> (SearchPanelController, LockedValue<[ScreenshotQuery]>) {
        let queries = LockedValue<[ScreenshotQuery]>([])
        let controller = SearchPanelController(model: SearchViewModel(debounce: .zero) { query, _, _, _ in
            queries.withValue { $0.append(query) }
            return ScreenshotSearchResult(rows: [], matchCount: 0, totalCount: 5)
        })
        return (controller, queries)
    }

    func testCommandDArrowsAndReturnChooseADate() async {
        let (controller, queries) = makeController()
        XCTAssertTrue(controller.handle(.dateFilter))
        XCTAssertNotNil(controller.model.state.datePicker)
        for _ in 0..<3 { XCTAssertTrue(controller.handle(.down)) }
        XCTAssertTrue(controller.handle(.open))
        await controller.model.waitForPendingSearch()
        XCTAssertNil(controller.model.state.datePicker)
        XCTAssertEqual(queries.value.last, ScreenshotQuery(date: .last7Days))
    }

    func testOtherKeysAreIgnoredWhileThePickerIsOpen() {
        let (controller, _) = makeController()
        _ = controller.handle(.dateFilter)
        XCTAssertTrue(controller.handle(.chip(.receipt)), "consumed, so the field doesn't see it")
        XCTAssertEqual(controller.model.state.chip, .all)
        XCTAssertFalse(controller.handle(.copyImage), "⌘C never copies the image behind the picker")
        XCTAssertTrue(controller.handle(.dateFilter), "⌘D again closes it")
        XCTAssertNil(controller.model.state.datePicker)
        XCTAssertFalse(controller.handle(.deleteBackward), "with the picker closed ⌫ deletes in the field")
    }

    func testCustomRangeLeavesArrowsAndDeleteToTheDateFields() async {
        let (controller, queries) = makeController()
        _ = controller.handle(.dateFilter)
        controller.model.chooseDate(.customRange)
        XCTAssertFalse(controller.handle(.down), "↑/↓ change the focused date field")
        XCTAssertFalse(controller.handle(.deleteBackward), "⌫ edits the date field")
        controller.model.setCustomRange(from: CalendarDay(year: 2026, month: 10, day: 3),
                                        through: CalendarDay(year: 2026, month: 10, day: 17))
        XCTAssertTrue(controller.handle(.open), "↩ is Apply")
        await controller.model.waitForPendingSearch()
        XCTAssertEqual(queries.value.last?.date, .days(from: CalendarDay(year: 2026, month: 10, day: 3),
                                                       through: CalendarDay(year: 2026, month: 10, day: 17)))
    }

    func testEscClosesThePickerThenClearsThenClosesThePanel() {
        let (controller, _) = makeController()
        controller.show()
        controller.model.chooseDateForTest(.today)
        _ = controller.handle(.dateFilter)
        XCTAssertTrue(controller.handle(.close))
        XCTAssertNil(controller.model.state.datePicker)
        XCTAssertEqual(controller.model.state.date, .today, "closing the picker changes nothing")
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(controller.handle(.close))
        XCTAssertNil(controller.model.state.date)
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(controller.handle(.close))
        XCTAssertFalse(controller.isVisible)
    }

    func testHidingThePanelClosesThePickerAndKeepsTheDate() {
        let (controller, _) = makeController()
        controller.show()
        controller.model.chooseDateForTest(.yesterday)
        _ = controller.handle(.dateFilter)
        controller.hide()
        XCTAssertNil(controller.model.state.datePicker)
        XCTAssertEqual(controller.model.state.date, .yesterday)
    }

    func testClearingAnnounces() {
        let (controller, _) = makeController()
        var said: [String] = []
        controller.model.announce = { said.append($0) }
        controller.model.chooseDateForTest(.today)
        controller.model.clearDate()
        controller.model.chooseDateForTest(.today)
        _ = controller.handle(.dateFilter)
        _ = controller.handle(.deleteBackward)
        controller.model.chooseDateForTest(.today)
        controller.model.clearFilters()
        controller.model.setText("receipt")
        _ = controller.handle(.close)
        controller.model.setText("receipt")
        controller.model.clearSearch()
        XCTAssertEqual(said, ["Date cleared", "Date cleared", "Filters cleared", "Search cleared", "Search cleared"])
    }
}

extension SearchViewModel {
    /// Sets a date through the picker, as a click would.
    func chooseDateForTest(_ option: DatePickerOption) {
        if state.datePicker == nil { toggleDatePicker() }
        chooseDate(option)
    }
}
