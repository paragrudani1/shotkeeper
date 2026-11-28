import Foundation
import ShotkeeperCore

/// The search panel's action set: what the buttons and keys do to the selected result. `SearchPanelController` maps
/// keys (core `SearchKeyMap`) to these; `SearchView` calls them through `SearchViewActions`. A new result action
/// (copy text, rename, re-analyse, move to Bin) goes here, so it does not touch the panel's window and Quick Look code.
@MainActor
final class SearchResultActions {
    let model: SearchViewModel
    /// Hides the search panel (after Open and Reveal).
    var hidePanel: @MainActor () -> Void = {}
    /// Posts a VoiceOver announcement from the panel.
    var announce: @MainActor (String) -> Void = { _ in }

    init(model: SearchViewModel) {
        self.model = model
    }

    func open(_ url: URL) {
        guard fileStillExists(url) else { return }
        WorkspaceActions.open(url)
        hidePanel()
    }

    func reveal(_ url: URL) {
        guard fileStillExists(url) else { return }
        WorkspaceActions.reveal(url)
        hidePanel()
    }

    func copy(_ url: URL) {
        guard fileStillExists(url) else { return }
        guard WorkspaceActions.copyImage(url) else {
            report(SearchWindowState.copyFailedMessage)
            return
        }
        model.showCopied()
        announce("Copied")
    }

    /// A file moved or deleted after it was indexed: say so instead of failing silently; the panel stays open.
    private func fileStillExists(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            report(SearchWindowState.missingFileMessage)
            return false
        }
        return true
    }

    private func report(_ message: String) {
        model.showProblem(message)
        announce(message)
    }
}
