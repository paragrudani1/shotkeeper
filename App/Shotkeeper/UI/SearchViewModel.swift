import Foundation
import Observation
import ShotkeeperCore

/// Drives the search window. The rules (chips, footer, states, esc, selection, tag click, batch view) live in core's
/// `SearchWindowState`; this class runs the searches it asks for, debounced and off the main actor, and owns the
/// short-lived UI bits (the "✓ Copied" pill, focus requests).
@MainActor
@Observable
final class SearchViewModel {
    typealias SearchFunction = @Sendable (ScreenshotQuery, Int) throws -> ScreenshotSearchResult

    private(set) var state: SearchWindowState
    /// A short message on the preview image: "✓ Copied" after ⌘C / Copy Image, or a problem (file gone).
    private(set) var pill: SearchPill?
    /// Bumped when the panel is shown; the view focuses the search field.
    private(set) var focusRequest = 0
    /// Number of searches whose answer was applied (debounce check in tests).
    private(set) var searchesRun = 0

    @ObservationIgnored let debounce: Duration
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let time: TimeLabel
    @ObservationIgnored private var searchFunction: SearchFunction
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var pillTask: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(150), state: SearchWindowState = SearchWindowState(),
         now: @escaping () -> Date = Date.init, time: TimeLabel = TimeLabel(), search: @escaping SearchFunction) {
        self.debounce = debounce
        self.state = state
        self.now = now
        self.time = time
        self.searchFunction = search
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
    }

    /// Esc. Returns true when the window should close (nothing was left to clear).
    func escape() -> Bool {
        switch state.escape() {
        case .clearedSearch:
            schedule(after: .zero)
            return false
        case .close:
            return true
        }
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

    // MARK: Feedback

    func showCopied() {
        showPill(.copied, for: SearchWindowState.copiedPillDuration)
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
        let query = state.query
        let limit = state.resultLimit
        let search = searchFunction
        pending = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let outcome = await Task.detached { () -> SearchOutcome in
                do { return .found(try search(query, limit)) } catch { return .failed(error) }
            }.value
            guard !Task.isCancelled, let self else { return }
            let applied: Bool
            switch outcome {
            case .found(let result): applied = self.state.apply(result, for: query)
            case .failed(let error): applied = self.state.fail(error, for: query)
            }
            if applied { self.searchesRun += 1 }
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
    case problem(String)
}
