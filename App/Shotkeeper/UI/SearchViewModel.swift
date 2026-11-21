import Foundation
import Observation
import ShotkeeperCore

/// Search-as-you-type over `ScreenshotIndex.search` (FTS5). Debounced; an empty query shows recent screenshots
/// (core's `search("")` returns `recent`). Selection is an index into `results` and is moved with ↑/↓.
@MainActor
@Observable
final class SearchViewModel {
    typealias SearchFunction = @Sendable (String) throws -> [IndexedScreenshot]

    private(set) var query = ""
    private(set) var results: [IndexedScreenshot] = []
    private(set) var selectedIndex: Int?
    private(set) var errorMessage: String?
    /// Number of searches that actually ran (debounce check in tests).
    private(set) var searchesRun = 0

    @ObservationIgnored let debounce: Duration
    @ObservationIgnored let limit: Int
    @ObservationIgnored private var searchFunction: SearchFunction
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(150), limit: Int = 50, search: @escaping SearchFunction) {
        self.debounce = debounce
        self.limit = limit
        self.searchFunction = search
    }

    /// Swap the data source (the coordinator opens the index after the panel may already exist).
    func setSearchFunction(_ search: @escaping SearchFunction) {
        searchFunction = search
    }

    var selected: IndexedScreenshot? {
        guard let selectedIndex, results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    var selectedURL: URL? { selected.map { URL(fileURLWithPath: $0.path) } }

    func setQuery(_ text: String) {
        guard text != query else { return }
        query = text
        schedule(after: debounce)
    }

    /// Runs the current query now (panel shown).
    func refresh() {
        schedule(after: .zero)
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { selectedIndex = nil; return }
        let current = selectedIndex ?? (delta > 0 ? -1 : results.count)
        selectedIndex = min(max(current + delta, 0), results.count - 1)
    }

    func select(_ index: Int) {
        selectedIndex = results.indices.contains(index) ? index : nil
    }

    /// Awaits the in-flight debounced search (tests).
    func waitForPendingSearch() async {
        await pending?.value
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        let text = query
        let search = searchFunction
        let limit = self.limit
        pending = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let outcome = await Task.detached { () -> SearchOutcome in
                do { return .found(Array(try search(text).prefix(limit))) } catch { return .failed(StatusText.describe(error)) }
            }.value
            guard !Task.isCancelled, let self else { return }
            self.apply(outcome, for: text)
        }
    }

    private func apply(_ outcome: SearchOutcome, for text: String) {
        guard text == query else { return }
        searchesRun += 1
        switch outcome {
        case .found(let rows):
            let previousPath = selected?.path
            results = rows
            errorMessage = nil
            selectedIndex = rows.firstIndex { $0.path == previousPath } ?? (rows.isEmpty ? nil : 0)
        case .failed(let message):
            results = []
            selectedIndex = nil
            errorMessage = message
        }
    }

    private enum SearchOutcome: Sendable {
        case found([IndexedScreenshot])
        case failed(String)
    }
}
