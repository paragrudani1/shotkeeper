import Foundation
import ShotkeeperCore

/// What `FileActions` reports back to the coordinator (the menu message, recents, the toast).
@MainActor
protocol FileActionsHost: AnyObject {
    /// The menu's last message (an error that the menu shows for 30 s).
    var lastMessage: String? { get set }
    /// An action worked: a stale error in the menu goes away.
    func clearMessageAfterSuccess()
    /// Re-reads the menu's recents, the "Undo: <title>" target and the index count.
    func refreshHistory()
    /// Shows a toast, or the menu message when rename toasts are off.
    func showToast(_ content: ToastContent)
}

/// Changes to a user's file after it was processed: undo (menu and toast) and the toast's "Edit name". Every change
/// goes through `ScreenshotProcessor`, which uses `FileOrganizer` and writes the undo record (CODING_STANDARDS #1).
///
/// Features that act on processed files (re-sort into subfolders, move to the Bin, re-analyse) add their action
/// here, in a `FileActions+<Feature>.swift` extension, instead of in `AppCoordinator`.
@MainActor
final class FileActions {
    /// Set by the coordinator once the index opened; nil when it did not (every action then reports that).
    /// Assigned exactly once, in `AppCoordinator.openStorage()`: it cannot go through `init` because the coordinator
    /// must initialize this stored `let` before it may call its own methods, and the processor comes from one of them.
    /// Nothing reassigns it afterwards.
    var processor: ScreenshotProcessor?
    weak var host: (any FileActionsHost)?

    static let indexNotOpen = UserFacingProblem(message: "the index is not open")

    /// The menu's "Undo: <title>" (⌘Z): the most recent rename. Shows the "restored" toast.
    func undoLast() {
        guard let processor else { return }
        do {
            let record = try processor.undoLast()
            host?.clearMessageAfterSuccess()
            host?.refreshHistory()
            host?.showToast(.restored(RestoredToast(restoredPaths: [record.from])))
        } catch {
            host?.lastMessage = StatusText.describe(error)
        }
    }

    /// The toast's Undo / Undo All. Returns the toast to show next.
    func undo(ids: [UUID]) -> ToastContent {
        guard let processor else { return .error(ErrorToast(.undo, Self.indexNotOpen)) }
        defer { host?.refreshHistory() }
        if ids.count == 1 {
            do {
                let record = try processor.undo(id: ids[0])
                host?.clearMessageAfterSuccess()
                return .restored(RestoredToast(restoredPaths: [record.from]))
            } catch {
                return .error(ErrorToast(.undo, UserFacingError.problem(for: error)))
            }
        }
        let result = processor.undo(ids: ids)
        if result.restored.isEmpty {
            return .error(ErrorToast(.undo, UserFacingProblem(message: "the files were moved or renamed since")))
        }
        host?.clearMessageAfterSuccess()
        return .restored(RestoredToast(restoredPaths: result.restored.map(\.from), failedCount: result.failed.count))
    }

    /// The toast's "Edit name": rename through the pipeline's rules, update the index, write an undo record.
    func rename(_ toast: RenamedToast, to name: String) -> Result<RenamedToast, UserFacingProblem> {
        guard let processor else { return .failure(Self.indexNotOpen) }
        do {
            let result = try processor.rename(toast.currentURL, to: name)
            host?.clearMessageAfterSuccess()
            host?.refreshHistory()
            return .success(toast.edited(to: result.finalURL, undoRecordID: result.undoRecordID))
        } catch {
            return .failure(UserFacingError.problem(for: error))
        }
    }
}
