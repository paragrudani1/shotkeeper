import Foundation
import Observation
import ShotkeeperCore

/// Drives the search window. The rules (chips, footer, states, esc, selection, tag click, batch view) live in core's
/// `SearchWindowState`; this class runs the searches it asks for, debounced and off the main actor, and owns the
/// short-lived UI bits (the "✓ Copied" pill, focus requests).
@MainActor
@Observable
final class SearchViewModel {
    /// Query, limit, and the clock and calendar the index resolves the date filter against (the model's `now()` and
    /// `time.calendar`, so the rows and the date wording agree on what "today" is).
    typealias SearchFunction = @Sendable (ScreenshotQuery, Int, Date, Calendar) throws -> ScreenshotSearchResult
    /// The source list for the Source pill and picker (`ScreenshotIndex.sources()`), loaded each time the panel opens.
    typealias SourcesFunction = @Sendable () throws -> [SourceFacet]

    private(set) var state: SearchWindowState
    /// A short message on the preview image: "✓ Copied" after ⌘C / Copy Image, "✓ Text copied" after ⇧⌘C, or a
    /// problem (file gone, no text, text not read).
    private(set) var pill: SearchPill?
    /// Bumped when the panel is shown; the view focuses the search field.
    private(set) var focusRequest = 0
    /// Number of searches whose answer was applied (debounce check in tests).
    private(set) var searchesRun = 0

    /// Posts a VoiceOver announcement from the panel ("Date cleared", "Search cleared"). Set by the controller.
    @ObservationIgnored var announce: @MainActor (String) -> Void = { _ in }
    /// Called after a search's answer was applied (a refresh after a row's `.updated` change resolves a waiting
    /// Copy Text there). Set by `SearchResultActions`.
    @ObservationIgnored var resultsApplied: @MainActor () -> Void = {}
    @ObservationIgnored let debounce: Duration
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let time: TimeLabel
    @ObservationIgnored private var searchFunction: SearchFunction
    @ObservationIgnored private let sourcesFunction: SourcesFunction
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var sourceLoad: Task<Void, Never>?
    @ObservationIgnored private var pillTask: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(150), state: SearchWindowState = SearchWindowState(),
         now: @escaping () -> Date = Date.init, time: TimeLabel = TimeLabel(calendar: .autoupdatingCurrent),
         search: @escaping SearchFunction, sources: @escaping SourcesFunction = { [] }) {
        self.debounce = debounce
        var state = state
        state.now = now()  // date wording (the Date pill, no-match sentences) uses the same clock and calendar
        state.time = time
        self.state = state
        self.now = now
        self.time = time
        self.searchFunction = search
        self.sourcesFunction = sources
    }

    var selected: SearchResultItem? { state.selected }
    var selectedURL: URL? { state.selected.map { URL(fileURLWithPath: $0.path) } }

    // MARK: Input

    func setText(_ text: String) {
        if state.setText(text) { schedule(after: debounce) }
    }

    func selectChip(_ chip: SearchChip) {
        if state.selectChip(chip) { schedule(after: .zero) }
    }

    func clickTag(_ tag: String) {
        if state.clickTag(tag) { schedule(after: .zero) }
    }

    func clearSearch() {
        if state.clearSearch() { schedule(after: .zero) }
        announce(SearchWindowState.Announcement.searchCleared)
    }

    /// "Clear filters" in the no-match state: resets the chip, the date and the source, keeps the words.
    func clearFilters() {
        if state.clearFilters() { schedule(after: .zero) }
        announce(SearchWindowState.Announcement.filtersCleared)
    }

    /// Esc: closes an open picker, else clears the search, else asks to close. Returns true when the window should
    /// close (nothing was left to clear).
    func escape() -> Bool {
        switch state.escape() {
        case .closedPicker:
            return false
        case .clearedSearch:
            schedule(after: .zero)
            announce(SearchWindowState.Announcement.searchCleared)
            return false
        case .close:
            return true
        }
    }

    // MARK: Date filter (the Date pill and its in-panel picker)

    /// The Date pill's ✕.
    func clearDate() {
        if state.setDateFilter(nil) { schedule(after: .zero) }
        announce(SearchWindowState.Announcement.dateCleared)
    }

    /// ⌘D or a click on the Date pill.
    func toggleDatePicker() {
        state.now = now()  // the custom range starts at the last 7 days of today
        state.toggleDatePicker()
    }

    func moveDateHighlight(by delta: Int) {
        state.moveDateHighlight(by: delta)
    }

    func chooseDate(_ option: DatePickerOption) {
        if state.chooseDate(option) { schedule(after: .zero) }
    }

    /// ↩ in the picker: the highlighted row, or Apply while the custom range is shown.
    func chooseHighlightedDate() {
        if state.chooseHighlightedDate() { schedule(after: .zero) }
    }

    func setCustomRange(from: CalendarDay, through: CalendarDay) {
        state.setCustomRange(from: from, through: through)
    }

    func applyCustomRange() {
        if state.applyCustomRange() { schedule(after: .zero) }
    }

    /// ⌫ in the date list.
    func clearDateFromPicker() {
        let hadDate = state.date != nil
        if state.clearDateFromPicker() { schedule(after: .zero) }
        if hadDate { announce(SearchWindowState.Announcement.dateCleared) }
    }

    // MARK: Source filter (the Source pill and its in-panel picker)

    /// Loads the source list off the main actor (the panel opened). A newer load cancels the previous one, so an older,
    /// slower load never overwrites a newer list. A failure keeps the previous list: the search shows the index error
    /// itself.
    func reloadSources() {
        let load = sourcesFunction
        sourceLoad?.cancel()
        sourceLoad = Task { [weak self] in
            let list = await Task.detached { try? load() }.value
            guard !Task.isCancelled, let self, let list else { return }
            self.state.setSources(list)
        }
    }

    /// Awaits the in-flight source list load (tests).
    func waitForSourceLoad() async {
        await sourceLoad?.value
    }

    /// ⌘S or a click on the Source pill. Returns false when the pill is disabled (the panel beeps).
    func toggleSourcePicker() -> Bool {
        state.toggleSourcePicker()
    }

    /// A click outside an open picker, or the panel hiding.
    func closePickers() {
        state.closePickers()
    }

    func setSourceNarrowText(_ text: String) {
        state.setSourceNarrowText(text)
    }

    func moveSourceHighlight(by delta: Int) {
        state.moveSourceHighlight(by: delta)
    }

    func chooseSource(_ row: SourcePickerRow) {
        if state.chooseSource(row) { schedule(after: .zero) }
    }

    /// ↩ in the source picker.
    func chooseHighlightedSource() {
        if state.chooseHighlightedSource() { schedule(after: .zero) }
    }

    /// The Source pill's ✕.
    func clearSource() {
        if state.setSource(nil) { schedule(after: .zero) }
        announce(SearchWindowState.Announcement.sourceCleared)
    }

    /// ⌫ in the source picker with an empty narrow field.
    func clearSourceFromPicker() {
        let hadSource = state.source != nil
        if state.clearSourceFromPicker() { schedule(after: .zero) }
        if hadSource { announce(SearchWindowState.Announcement.sourceCleared) }
    }

    /// "View in Search" on a batch toast.
    func showBatch(_ paths: [String]) {
        state.showBatch(paths)
        schedule(after: .zero)
    }

    /// Runs the current query now (panel shown).
    func refresh() {
        schedule(after: .zero)
    }

    func windowHidden() {
        // Leaving a batch view: search again now, so its rows are not what the next open shows first.
        if state.windowHidden() { schedule(after: .zero) }
        pillTask?.cancel()
        pill = nil
    }

    func requestFocus() {
        focusRequest += 1
    }

    // MARK: Selection

    func moveSelection(by delta: Int) {
        state.moveSelection(by: delta)
    }

    func select(_ index: Int) {
        state.select(index)
    }

    // MARK: Copy Text (core decides; `SearchResultActions` performs)

    func requestCopyText(pasteboardChangeCount: Int) -> CopyTextOutcome {
        state.requestCopyText(pasteboardChangeCount: pasteboardChangeCount)
    }

    func resolveWaitingTextCopy(pasteboardChangeCount: Int) -> LateTextCopy? {
        state.resolveWaitingTextCopy(pasteboardChangeCount: pasteboardChangeCount)
    }

    // MARK: Feedback

    func showCopied() {
        showPill(.copied, for: SearchWindowState.copiedPillDuration)
    }

    /// "✓ Text copied", with the "✓ Copied" timing.
    func showTextCopied() {
        showPill(.textCopied, for: SearchWindowState.copiedPillDuration)
    }

    /// "No text found in this screenshot.": not a failure, so it has its own symbol.
    func showNoText() {
        showPill(.noText, for: SearchWindowState.problemPillDuration)
    }

    func showProblem(_ message: String) {
        showPill(.problem(message), for: SearchWindowState.problemPillDuration)
    }

    private func showPill(_ newPill: SearchPill, for seconds: TimeInterval) {
        pillTask?.cancel()
        pill = newPill
        pillTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.pill = nil
        }
    }

    /// Awaits the in-flight debounced search (tests).
    func waitForPendingSearch() async {
        await pending?.value
    }

    // MARK: Private

    private func schedule(after delay: Duration) {
        pending?.cancel()
        state.now = now()  // the index resolves "today" when the search runs; the wording follows the same day
        let query = state.query
        let limit = state.resultLimit
        let (searchNow, calendar) = (state.now, time.calendar)
        let search = searchFunction
        pending = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let outcome = await Task.detached { () -> SearchOutcome in
                do { return .found(try search(query, limit, searchNow, calendar)) } catch { return .failed(error) }
            }.value
            guard !Task.isCancelled, let self else { return }
            let applied: Bool
            switch outcome {
            case .found(let result): applied = self.state.apply(result, for: query)
            case .failed(let error): applied = self.state.fail(error, for: query)
            }
            if applied {
                self.searchesRun += 1
                self.resultsApplied()
            }
        }
    }

    private enum SearchOutcome: Sendable {
        case found(ScreenshotSearchResult)
        case failed(any Error)  // Error is Sendable
    }
}

/// The message shown on the preview image.
enum SearchPill: Equatable {
    case copied
    /// "✓ Text copied" (Copy Text).
    case textCopied
    /// "No text found in this screenshot." (`text.viewfinder`, not the warning symbol: nothing went wrong).
    case noText
    case problem(String)
}
