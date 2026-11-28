import AppKit
import ShotkeeperCore
import SwiftUI
import XCTest
@testable import Shotkeeper

/// The rename toast (UI polish PR 1a). Each entry is rendered light and dark by `ToastSnapshotsTests`.
/// Add a state with ONE line here (see `UISnapshotCatalog`).
@MainActor
enum ToastSnapshots {
    static var all: [UISnapshot] {
        [
            UISnapshot("toast-renamed") { Fixtures.toast(.renamed(Fixtures.renamed)) },
            UISnapshot("toast-renamed-long-name") { Fixtures.toast(.renamed(Fixtures.renamedLong)) },
            UISnapshot("toast-sorted") { Fixtures.toast(.renamed(Fixtures.sorted)) },
            UISnapshot("toast-editing") { Fixtures.toast(.renamed(Fixtures.renamed), editing: true) },
            UISnapshot("toast-editing-error") {
                Fixtures.toast(.renamed(Fixtures.renamed), editing: true,
                               problem: "That name cannot be used as a file name.", text: "...")
            },
            UISnapshot("toast-restored") { Fixtures.toast(.restored(RestoredToast(restoredPaths: [Fixtures.originalPath]))) },
            UISnapshot("toast-restored-all") {
                Fixtures.toast(.restored(RestoredToast(restoredPaths: Fixtures.batchPaths, failedCount: 2)))
            },
            UISnapshot("toast-batch") { Fixtures.toast(.batch(Fixtures.batch(excluded: 2))) },
            UISnapshot("toast-batch-no-skipped") { Fixtures.toast(.batch(Fixtures.batch(excluded: 0))) },
            UISnapshot("toast-error") {
                Fixtures.toast(.error(ErrorToast(.rename, UserFacingProblem(message: "Cloudflare API token is not set",
                                                                             needsSettings: true))))
            },
            UISnapshot("toast-error-openrouter-out-of-credits") {
                Fixtures.toast(.error(ErrorToast(.rename, UserFacingError.problem(
                    for: AnalyzerError.accountState(OpenRouterBackend.outOfCreditsText)))))
            },
            UISnapshot("toast-error-no-fix") {
                Fixtures.toast(.error(ErrorToast(.undo, UserFacingProblem(message: "another file now has the original name"))))
            },
        ]
    }
}

@MainActor
final class ToastSnapshotsTests: XCTestCase {
    func testRenderToastInLightAndDark() throws {
        try UISnapshotWriter.write(ToastSnapshots.all)
    }
}

@MainActor
extension Fixtures {
    static let originalPath = "/Users/parag/Desktop/Screenshot 2026-11-21 at 16.24.11.png"
    static let renamed = RenamedToast(originalURL: URL(fileURLWithPath: originalPath),
                                      currentURL: URL(fileURLWithPath: "/Users/parag/Desktop/Tweet semiconductor flashcards.png"),
                                      undoRecordIDs: [UUID()])
    static let renamedLong = RenamedToast(
        originalURL: URL(fileURLWithPath: originalPath),
        currentURL: URL(fileURLWithPath: "/Users/parag/Desktop/Invoice from Acme Cloud Services for November with VAT breakdown and payment link.png"),
        undoRecordIDs: [UUID()])
    /// Design §7: "Sorted into Receipts", a long name on two lines.
    static let sorted = RenamedToast(
        originalURL: URL(fileURLWithPath: "/Users/parag/Desktop/Screenshot 2026-11-28 at 09.12.44.png"),
        currentURL: URL(fileURLWithPath: "/Users/parag/Pictures/Screenshots/Receipts/Invoice from Acme Cloud Services for November.png"),
        undoRecordIDs: [UUID()], sortedInto: ["Receipts"])
    static let batchPaths = (1...3).map { "/Users/parag/Desktop/Batch item \($0).png" }

    static func batch(excluded: Int) -> BatchToast {
        BatchToast(renamedCount: 37, excludedCount: excluded, renamedPaths: batchPaths,
                   undoRecordIDs: (0..<37).map { _ in UUID() })
    }

    static func toast(_ content: ToastContent, editing: Bool = false, problem: String? = nil,
                      text: String? = nil) -> some View {
        var countdown = ToastCountdown(startingAt: Date().addingTimeInterval(-1.5))
        countdown.pause(at: Date())  // a frozen bar at ~62% so the PNG is stable
        let model = ToastModel(content: content, countdown: countdown)
        if editing, case .renamed(let toast) = content {
            model.isEditing = true
            model.editText = text ?? toast.name
            model.editProblem = problem
        }
        return ToastView(model: model, actions: .none, opaqueBackground: true)
    }
}
