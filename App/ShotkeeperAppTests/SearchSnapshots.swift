import AppKit
import ShotkeeperCore
import SwiftUI
import XCTest
@testable import Shotkeeper

/// The search window (PR 2). Each entry is rendered light and dark by `SearchSnapshotsTests`.
/// Add a state with ONE line here (see `UISnapshotCatalog`).
@MainActor
enum SearchSnapshots {
    static var all: [UISnapshot] {
        [
            UISnapshot("search-results") { Fixtures.search(selected: 1) },
            UISnapshot("search-chip-selected") { Fixtures.search(text: "receipt", chip: .receipt) },
            UISnapshot("search-copied") { Fixtures.search(copied: true) },
            UISnapshot("search-file-missing") { Fixtures.search(problem: SearchWindowState.missingFileMessage) },
            UISnapshot("search-batch") { Fixtures.search(batch: true, selected: 2) },
            UISnapshot("search-no-match") { Fixtures.search(text: "zebra crossing", rows: []) },
            UISnapshot("search-empty-index") { Fixtures.search(rows: [], total: 0) },
            UISnapshot("search-index-error") { Fixtures.searchIndexError() },
            UISnapshot("search-date-custom") { Fixtures.search(rows: Array(Fixtures.searchRows.prefix(5)), date: .novemberWeek, datePicker: true) },
            UISnapshot("search-no-match-filters-only") { Fixtures.search(chip: .receipt, rows: [], date: .yesterday) },
            UISnapshot("search-no-match-filters") { Fixtures.search(text: "stripe", chip: .receipt, rows: [], date: .last30Days) },
            UISnapshot("search-filters-on") { Fixtures.search(chip: .receipt, date: .last30Days, source: "Mail") },
            UISnapshot("search-source-picker") { Fixtures.search(sourcePicker: true) },
        ]
    }
}

@MainActor
final class SearchSnapshotsTests: XCTestCase {
    func testRenderSearchInLightAndDark() throws {
        try UISnapshotWriter.write(SearchSnapshots.all)
    }
}

@MainActor
extension Fixtures {
    // MARK: Search window

    private static func shot(_ title: String, folder: String = "/Users/parag/Desktop", source: String?, type: ContentType,
                             minutes: Double, tags: [String], description: String) -> IndexedScreenshot {
        ScreenshotRow.make(title, folder: folder, originalFilename: "Screenshot.png",
                           capturedAt: now.addingTimeInterval(minutes * 60), processedAt: now.addingTimeInterval(minutes * 60 + 4),
                           titleConfidence: 0.9, source: source, type: type, description: description, tags: tags)
    }

    static let searchRows: [IndexedScreenshot] = [
        shot("Tweet semiconductor flashcards", source: "x.com", type: .tweet, minutes: -6,
             tags: ["semiconductor", "flashcards", "chips"],
             description: "A thread of flashcards that explains how chips are made, from wafers to packaging."),
        shot("Invoice from Acme Cloud Services for November", source: "Mail", type: .receipt, minutes: -74,
             tags: ["invoice", "acme", "billing"], description: "November invoice for cloud hosting, total $248.12, due December 5."),
        shot("Swift concurrency error in Xcode", source: "Xcode", type: .code, minutes: -1_440,
             tags: ["swift", "xcode", "concurrency"], description: "Compiler error: sending 'fm' risks causing data races."),
        shot("Slack thread about the launch plan", source: "Slack", type: .chat, minutes: -5 * 1_440,
             tags: ["launch", "planning"], description: "Team discussion of the launch date and who writes the release notes."),
        shot("Figma onboarding mockup", folder: "/Users/parag/Pictures/Screenshots", source: "Figma", type: .design,
             minutes: -7 * 1_440, tags: ["onboarding", "mockup"], description: "Five-step setup flow with indigo step dots."),
        shot("Blue Bottle coffee receipt", source: "Wallet", type: .receipt, minutes: -8 * 1_440,
             tags: ["coffee", "receipt"], description: "Receipt for two lattes and a pastry, total $14.75."),
        shot("How SQLite FTS5 ranks results", source: "sqlite.org", type: .article, minutes: -12 * 1_440,
             tags: ["sqlite", "search"], description: "Documentation page about the bm25 ranking function."),
        shot("Uber receipt from SFO", source: nil, type: .receipt, minutes: -20 * 1_440,
             tags: ["travel", "receipt"], description: "Ride from SFO to downtown San Francisco, total $52.30."),
    ].enumerated().map { offset, row in
        var row = row
        row.id = Int64(offset + 1)  // ids identify list rows
        return row
    }

    /// The source list the panel loads (`ScreenshotIndex.sources()`): many sources, one long name (design §7).
    static let searchSources: [SourceFacet] = [
        ("Slack", 64), ("X", 41), ("GitHub", 27), ("Mail", 18), ("Xcode", 12),
        ("Microsoft Remote Desktop Connection Client for Mac", 9), ("console.cloud.google.com", 4), ("Figma", 3),
        ("Wallet", 2), ("sqlite.org", 1),
    ].map { SourceFacet(key: SourceKey($0.0)!, displayName: $0.0, count: $0.1) }

    static func search(text: String = "", chip: SearchChip = .all, batch: Bool = false, rows: [IndexedScreenshot]? = nil,
                       total: Int = 214, selected: Int = 0, copied: Bool = false, problem: String? = nil,
                       date: DateFilter? = nil, datePicker: Bool = false, source: String? = nil,
                       sourcePicker: Bool = false) -> some View {
        var state = SearchWindowState(now: now, time: time)
        state.setSources(total == 0 ? [] : searchSources)  // an empty index has no source: the pill is disabled
        if batch { state.showBatch(Array(searchRows.prefix(4)).map(\.path)) }
        state.setText(text)
        if chip != .all { state.selectChip(chip) }
        if let date { state.setDateFilter(date) }  // setting nil would leave the batch view
        if let source { state.setSource(searchSources.first { $0.displayName == source }) }
        if datePicker { state.toggleDatePicker() }
        if sourcePicker { state.toggleSourcePicker() }
        var shown = rows ?? (batch ? Array(searchRows.prefix(4)) : searchRows)
        if rows == nil, let type = chip.contentType { shown = shown.filter { $0.contentType == type } }
        if rows == nil, let key = state.source { shown = shown.filter { $0.sourceAppOrSite.flatMap(SourceKey.init) == key } }
        state.apply(ScreenshotSearchResult(rows: shown, matchCount: shown.count, totalCount: total), for: state.query)
        for _ in 0..<selected { state.moveSelection(by: 1) }
        return searchView(state, copied: copied, problem: problem)
    }

    static func searchIndexError() -> some View {
        var state = SearchWindowState()
        let problem = UserFacingProblem(message: "the index file is damaged")  // core maps SQLITE_NOTADB to this
        state.fail(IndexUnavailableError(problem: problem), for: state.query)
        return searchView(state, copied: false, problem: nil)
    }

    private static func searchView(_ state: SearchWindowState, copied: Bool, problem: String?) -> some View {
        let model = SearchViewModel(state: state, now: { now }, time: time) { _, _, _, _ in throw CancellationError() }
        if copied { model.showCopied() }
        if let problem { model.showProblem(problem) }
        return SearchView(model: model, actions: .none, opaqueBackground: true)
    }
}

extension DateFilter {
    /// Nov 14 – 21, 2026: the fixture week ending on `Fixtures.now`, which holds the first five search rows.
    static let novemberWeek = DateFilter.days(from: CalendarDay(year: 2026, month: 11, day: 14),
                                              through: CalendarDay(year: 2026, month: 11, day: 21))
}
