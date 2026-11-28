import AppKit
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
    /// Copy Text on a row that was never read. Ticket 07 reads it on demand; until then this beeps.
    var beep: @MainActor () -> Void = { NSSound.beep() }
    /// Where Copy Image and Copy Text write (tests use a private one).
    var pasteboard: NSPasteboard = .general

    init(model: SearchViewModel) {
        self.model = model
        model.resultsApplied = { [weak self] in self?.resolveWaitingTextCopy() }
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
        guard WorkspaceActions.copyImage(url, to: pasteboard) else {
            report(SearchWindowState.copyFailedMessage)
            return
        }
        model.showCopied()
        announce("Copied")
    }

    /// ⇧⌘C or the Copy Text badge, by the selection's text status (core `CopyTextOutcome`). A row still being read
    /// copies when its text arrives, unless the clipboard changed or the panel moved on (`resolveWaitingTextCopy`).
    /// Returns false when nothing is selected.
    @discardableResult
    func copyText() -> Bool {
        let outcome = model.requestCopyText(pasteboardChangeCount: pasteboard.changeCount)
        guard outcome != .notAvailable else { return false }
        perform(outcome)
        return true
    }

    /// After each refresh: a waiting Copy Text whose row has been read is performed or dropped (late-copy rule).
    func resolveWaitingTextCopy() {
        guard case .perform(let outcome)? = model.resolveWaitingTextCopy(pasteboardChangeCount: pasteboard.changeCount)
        else { return }  // still reading, nothing waiting, or dropped: nothing is written, the badge shows the row
        perform(outcome)
    }

    private func perform(_ outcome: CopyTextOutcome) {
        switch outcome {
        case .copy(let text):
            // The text goes to the pasteboard only; never into a log or a message.
            guard WorkspaceActions.copyText(text, to: pasteboard) else { return report(SearchWindowState.textFailedMessage) }
            model.showTextCopied()
            announce(SearchWindowState.Announcement.textCopied)
        case .noText:
            model.showNoText()
            announce(SearchWindowState.noTextMessage)
        case .failed:
            // Ticket 07 makes the badge re-read the row; ⇧⌘C keeps showing why it has no text.
            report(outcome.message ?? SearchWindowState.textFailedMessage)
        case .wait:
            break  // the badge shows "Reading text…"; the copy happens after the row's `.updated` refresh
        case .readFirst:
            beep()  // interim until ticket 07: a never-read row has no badge and ⇧⌘C beeps
        case .notAvailable:
            break
        }
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
