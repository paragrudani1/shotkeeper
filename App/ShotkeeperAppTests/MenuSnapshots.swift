import AppKit
import ShotkeeperCore
import SwiftUI
import XCTest
@testable import Shotkeeper

/// The status item menu (PR 1b) and the menu bar glyph. Each entry is rendered light and dark by `MenuSnapshotsTests`.
/// Add a state with ONE line here (see `UISnapshotCatalog`).
@MainActor
enum MenuSnapshots {
    static var all: [UISnapshot] {
        [
            UISnapshot("menu-idle-recents") { Fixtures.menu(.idle) },
            UISnapshot("menu-idle-recents-highlighted") { Fixtures.menu(.idle, highlighted: .recent(2)) },
            UISnapshot("menu-idle-no-recents") { Fixtures.menu(.idle, recents: false, count: 0) },
            UISnapshot("menu-processing") { Fixtures.menu(.processing(current: URL(fileURLWithPath: "/a"), remaining: 2)) },
            UISnapshot("menu-paused") { Fixtures.menu(.paused(until: Fixtures.now.addingTimeInterval(18 * 60)), canUndo: false) },
            UISnapshot("menu-offline") { Fixtures.menu(.offline) },
            UISnapshot("menu-needs-attention") {
                Fixtures.menu(.error("Cloudflare API token is not set"), message: "Queued 3 screenshots")
            },
            UISnapshot("menu-openrouter-out-of-credits") { Fixtures.menu(.error(OpenRouterBackend.outOfCreditsText)) },
            UISnapshot("menu-error") { Fixtures.menu(.idle, failure: "Could not open the index: disk I/O error.") },
            UISnapshot("menu-downloading") { Fixtures.menu(.idle, recents: false, download: 0.45) },
            UISnapshot("menu-setup-unfinished") { Fixtures.menu(.idle, recents: false, setup: true) },
            // Menu bar glyph (template): normal and pulse frame, at menu bar size and enlarged.
            UISnapshot("menubar-glyph") { Fixtures.glyphs() },
        ]
    }
}

@MainActor
final class MenuSnapshotsTests: XCTestCase {
    func testRenderMenuInLightAndDark() throws {
        try UISnapshotWriter.write(MenuSnapshots.all)
    }
}

@MainActor
extension Fixtures {
    static let recents: [RecentItem] = [
        RecentItem(id: 1, path: "/d/1.png", title: "Tweet semiconductor flashcards", source: "x.com", date: now),
        RecentItem(id: 2, path: "/d/2.png", title: "Invoice from Acme Cloud Services for November", source: "Mail",
                   date: now.addingTimeInterval(-74 * 60)),
        RecentItem(id: 3, path: "/d/3.png", title: "Swift concurrency error in Xcode", source: "Xcode",
                   date: now.addingTimeInterval(-86_400)),
        RecentItem(id: 4, path: "/d/4.png", title: "Slack thread about the launch plan", source: "Slack",
                   date: now.addingTimeInterval(-5 * 86_400)),
        RecentItem(id: 5, path: "/d/5.png", title: "Figma onboarding mockup", source: "Figma",
                   date: now.addingTimeInterval(-7 * 86_400)),
    ]

    static func menu(_ status: QueueStatus, recents: Bool = true, count: Int = 214, failure: String? = nil,
                     message: String? = nil, download: Double? = nil, setup: Bool = false, canUndo: Bool = true,
                     highlighted: MenuRowID? = nil) -> some View {
        let isPaused: Bool = { if case .paused = status { return true } else { return false } }()
        let isError: Bool = { if case .error = status { return true } else { return false } }()
        let state = MenuViewState(
            status: MenuText.status(queue: status, watchedFolderName: "Desktop", indexedCount: count, failure: failure,
                                    notWatchingReason: setup ? BackendGate.statusReason(for: .notConfigured("Cloudflare account ID is not set")) : nil, now: now, time: time),
            message: message,
            showsFixSettings: isError,
            showsFinishSetup: setup,
            download: download.map { .init(text: MenuText.download(fraction: $0, totalGB: 9.1), fraction: $0) },
            recents: recents ? Self.recents : [],
            now: now,
            time: time,
            undoTitle: MenuText.undoItem(for: canUndo ? UndoRecord(timestamp: now, from: "/d/Screenshot.png",
                                                                   to: "/d/Tweet semiconductor flashcards.png") : nil),
            canUndo: canUndo,
            isPaused: isPaused,
            searchShortcut: "⌥⌘S",
            version: "0.1.0")
        let highlight = MenuHighlight()
        highlight.row = highlighted
        return MenuContentView(state: state, actions: .none, highlight: highlight, opaqueBackground: true)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    static func glyphs() -> some View {
        HStack(spacing: 24) {
            ForEach([MenuBarGlyph.Variant.normal, .pulse], id: \.self) { variant in
                VStack(spacing: 10) {
                    Image(nsImage: MenuBarGlyph.image(variant)).renderingMode(.template)
                    Image(nsImage: MenuBarGlyph.image(variant, size: 96)).renderingMode(.template)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
