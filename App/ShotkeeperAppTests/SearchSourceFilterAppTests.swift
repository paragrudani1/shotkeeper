import AppKit
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

/// The source filter in the panel: the list loaded on each open, key routing while the picker is open, the beep and
/// the announcements. The rules are core's (`SearchSourcePickerTests`); this checks the app performs them.
@MainActor
final class SearchSourceFilterAppTests: XCTestCase {
    private static let slack = SourceFacet(key: SourceKey("Slack")!, displayName: "Slack", count: 64)
    private static let x = SourceFacet(key: SourceKey("X")!, displayName: "X", count: 41)

    private func makeController(sources: [SourceFacet] = [slack, x])
        -> (SearchPanelController, LockedValue<[ScreenshotQuery]>, LockedValue<Int>) {
        let queries = LockedValue<[ScreenshotQuery]>([])
        let loads = LockedValue(0)
        let model = SearchViewModel(debounce: .zero, search: { query, _, _, _ in
            queries.withValue { $0.append(query) }
            return ScreenshotSearchResult(rows: [], matchCount: 0, totalCount: 5)
        }, sources: {
            loads.withValue { $0 += 1 }
            return sources
        })
        return (SearchPanelController(model: model), queries, loads)
    }

    func testTheListLoadsEachTimeThePanelOpens() async {
        let (controller, _, loads) = makeController()
        controller.show()
        await controller.model.waitForSourceLoad()
        XCTAssertEqual(controller.model.state.sources, [Self.slack, Self.x])
        controller.hide()
        controller.show()
        await controller.model.waitForSourceLoad()
        XCTAssertEqual(loads.value, 2)
        controller.hide()
    }

    func testCommandSTypeAndReturnChooseASource() async {
        let (controller, queries, _) = makeController()
        controller.show()
        await controller.model.waitForSourceLoad()
        XCTAssertTrue(controller.handle(.sourceFilter))
        XCTAssertNotNil(controller.model.state.sourcePicker)
        controller.model.setSourceNarrowText("sl")
        XCTAssertFalse(controller.handle(.space), "a space is typed into the narrow field")
        XCTAssertFalse(controller.handle(.deleteBackward), "⌫ deletes the typed letter")
        XCTAssertTrue(controller.handle(.open))
        await controller.model.waitForPendingSearch()
        XCTAssertNil(controller.model.state.sourcePicker)
        XCTAssertEqual(queries.value.last, ScreenshotQuery(source: SourceKey("slack")))
        controller.hide()
    }

    func testArrowsEscAndOtherKeysWhileThePickerIsOpen() async {
        let (controller, _, _) = makeController()
        controller.show()
        await controller.model.waitForSourceLoad()
        _ = controller.handle(.sourceFilter)
        XCTAssertTrue(controller.handle(.down))
        XCTAssertEqual(controller.model.state.sourcePicker?.highlighted, .source(Self.slack))
        XCTAssertTrue(controller.handle(.chip(.receipt)), "consumed, so the field doesn't see it")
        XCTAssertEqual(controller.model.state.chip, .all)
        XCTAssertFalse(controller.handle(.copyImage), "⌘C never copies the image behind the picker")
        XCTAssertTrue(controller.handle(.dateFilter), "⌘D switches to the date picker")
        XCTAssertNil(controller.model.state.sourcePicker)
        XCTAssertNotNil(controller.model.state.datePicker)
        XCTAssertTrue(controller.handle(.sourceFilter), "⌘S switches back")
        XCTAssertNotNil(controller.model.state.sourcePicker)
        XCTAssertTrue(controller.handle(.close), "Esc closes the picker first")
        XCTAssertNil(controller.model.state.sourcePicker)
        XCTAssertTrue(controller.isVisible)
        controller.hide()
    }

    func testCommandSDeleteClearsTheSourceAndAnnounces() async {
        let (controller, queries, _) = makeController()
        var said: [String] = []
        controller.model.announce = { said.append($0) }
        controller.show()
        await controller.model.waitForSourceLoad()
        controller.model.chooseSourceForTest(Self.x)
        _ = controller.handle(.sourceFilter)
        XCTAssertTrue(controller.handle(.deleteBackward), "⌘S ⌫ with an empty narrow field")
        await controller.model.waitForPendingSearch()
        XCTAssertNil(controller.model.state.source)
        XCTAssertNil(controller.model.state.sourcePicker)
        XCTAssertEqual(queries.value.last, ScreenshotQuery())
        controller.model.chooseSourceForTest(Self.x)
        controller.model.clearSource()
        XCTAssertEqual(said, ["Source cleared", "Source cleared"])
        controller.hide()
    }

    func testCommandSBeepsWhenThePillIsDisabled() async {
        let (controller, _, _) = makeController(sources: [])
        var beeps = 0
        controller.beep = { beeps += 1 }
        controller.show()
        await controller.model.waitForSourceLoad()
        XCTAssertTrue(controller.model.state.sourcePillIsDisabled)
        XCTAssertTrue(controller.handle(.sourceFilter), "consumed: ⌘S never reaches the menu")
        XCTAssertEqual(beeps, 1)
        XCTAssertNil(controller.model.state.sourcePicker)
        controller.hide()
    }

    func testHidingThePanelClosesThePickerAndKeepsTheSource() async {
        let (controller, _, _) = makeController()
        controller.show()
        await controller.model.waitForSourceLoad()
        controller.model.chooseSourceForTest(Self.slack)
        _ = controller.handle(.sourceFilter)
        controller.hide()
        XCTAssertNil(controller.model.state.sourcePicker)
        XCTAssertEqual(controller.model.state.source, SourceKey("slack"))
    }
}

extension SearchViewModel {
    /// Sets a source through the picker, as a click would.
    func chooseSourceForTest(_ facet: SourceFacet) {
        if state.sourcePicker == nil { _ = toggleSourcePicker() }
        chooseSource(.source(facet))
    }
}
