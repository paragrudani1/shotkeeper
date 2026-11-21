import AppKit
import ShotkeeperCore
import SwiftUI
import XCTest
@testable import Shotkeeper

/// Renders UI states to PNGs (light and dark) so agents without a Mac can look at them. CI uploads the folder as
/// the `Shotkeeper-ui-snapshots` artifact. See docs/wiki/macos-ci.md ("UI snapshots").
///
/// To add a view: add ONE line to `UISnapshotCatalog.all`, e.g.
///     UISnapshot("search-empty") { SearchView(...) },
@MainActor
enum UISnapshotCatalog {
    static var all: [UISnapshot] {
        [
            // Toast (PR 1a)
            UISnapshot("toast-renamed") { Fixtures.toast(.renamed(Fixtures.renamed)) },
            UISnapshot("toast-renamed-long-name") { Fixtures.toast(.renamed(Fixtures.renamedLong)) },
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
            UISnapshot("toast-error-no-fix") {
                Fixtures.toast(.error(ErrorToast(.undo, UserFacingProblem(message: "another file now has the original name"))))
            },
            // Menu (PR 1b)
            UISnapshot("menu-idle-recents") { Fixtures.menu(.idle) },
            UISnapshot("menu-idle-recents-highlighted") { Fixtures.menu(.idle, highlighted: .recent(2)) },
            UISnapshot("menu-idle-no-recents") { Fixtures.menu(.idle, recents: false, count: 0) },
            UISnapshot("menu-processing") { Fixtures.menu(.processing(current: URL(fileURLWithPath: "/a"), remaining: 2)) },
            UISnapshot("menu-paused") { Fixtures.menu(.paused(until: Fixtures.now.addingTimeInterval(18 * 60)), canUndo: false) },
            UISnapshot("menu-offline") { Fixtures.menu(.offline) },
            UISnapshot("menu-needs-attention") {
                Fixtures.menu(.error("Cloudflare API token is not set"), message: "Queued 3 screenshots")
            },
            UISnapshot("menu-error") { Fixtures.menu(.idle, failure: "Could not open the index: disk I/O error.") },
            UISnapshot("menu-downloading") { Fixtures.menu(.idle, recents: false, download: 0.45) },
            UISnapshot("menu-setup-unfinished") { Fixtures.menu(.idle, recents: false, setup: true) },
            // Menu bar glyph (template): normal and pulse frame, at menu bar size and enlarged.
            UISnapshot("menubar-glyph") { Fixtures.glyphs() },
        ]
    }

    /// `SHOTKEEPER_SNAPSHOT_DIR` (CI passes it as `TEST_RUNNER_SHOTKEEPER_SNAPSHOT_DIR`), else /tmp.
    static var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["SHOTKEEPER_SNAPSHOT_DIR"] ?? "/tmp/shotkeeper-ui-snapshots"
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

struct UISnapshot {
    let name: String
    let make: @MainActor () -> AnyView

    init<V: View>(_ name: String, @ViewBuilder _ make: @escaping @MainActor () -> V) {
        self.name = name
        self.make = { AnyView(make()) }
    }
}

@MainActor
final class UISnapshotTests: XCTestCase {
    func testRenderEverySnapshotInLightAndDark() throws {
        let directory = UISnapshotCatalog.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [String] = []
        for snapshot in UISnapshotCatalog.all {
            let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
            for (suffix, appearance) in appearances {
                let rep = try SnapshotRenderer.render(snapshot.make(), appearance: appearance)
                XCTAssertGreaterThan(SnapshotRenderer.distinctColors(in: rep), 8, "\(snapshot.name)-\(suffix) looks blank")
                let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                let url = directory.appendingPathComponent("\(snapshot.name)-\(suffix).png")
                try data.write(to: url)
                written.append(url.lastPathComponent)
            }
        }
        print("UI snapshots: wrote \(written.count) PNGs to \(directory.path)")
    }
}

@MainActor
enum SnapshotRenderer {
    /// Hosts `view` in an offscreen window with `appearance`, on a neutral desktop-like backdrop, and draws it at 2×.
    static func render(_ view: AnyView, appearance: NSAppearance.Name, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        let isDark = appearance == .darkAqua
        let framed = view
            .shadow(color: .black.opacity(isDark ? 0.5 : 0.22), radius: 14, y: 6)
            .padding(28)
            .background(LinearGradient(colors: isDark ? [Color(white: 0.16), Color(white: 0.24)]
                                                      : [Color(red: 0.80, green: 0.84, blue: 0.90),
                                                         Color(red: 0.90, green: 0.88, blue: 0.92)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, isDark ? .dark : .light)
            .environment(\.thumbnailSource, FakeThumbnails.source)
        let hosting = NSHostingView(rootView: framed)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))  // let SwiftUI finish its first update
        hosting.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "SnapshotRenderer", code: 1)
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.close()
        return rep
    }

    /// Rough "is anything drawn" check on a sample grid.
    static func distinctColors(in rep: NSBitmapImageRep) -> Int {
        var colors = Set<UInt32>()
        let step = max(1, min(rep.pixelsWide, rep.pixelsHigh) / 40)
        for x in stride(from: 0, to: rep.pixelsWide, by: step) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
                var pixel = [Int](repeating: 0, count: 4)
                rep.getPixel(&pixel, atX: x, y: y)
                colors.insert(UInt32(pixel[0]) << 24 | UInt32(pixel[1]) << 16 | UInt32(pixel[2]) << 8 | UInt32(pixel[3]))
            }
        }
        return colors.count
    }
}

/// Generated "screenshot" thumbnails: a colored app header and text lines, color picked from the path.
enum FakeThumbnails {
    static let source = ThumbnailSource(cached: { path, side in image(for: path, side: side) },
                                        load: { path, side, _ in image(for: path, side: side) })

    @MainActor
    static func image(for path: String, side: CGFloat) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let hues: [CGFloat] = [0.58, 0.08, 0.36, 0.75, 0.95]
        let hue = hues[path.unicodeScalars.reduce(0) { $0 + Int($1.value) } % hues.count]  // stable across runs
        let size = NSSize(width: 120, height: 120)
        return NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: rect.width, height: 26).fill()
            NSColor(white: 0.75, alpha: 1).setFill()
            for (row, width) in [0.8, 0.6, 0.9, 0.5, 0.7].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 10, y: 38 + CGFloat(row) * 15, width: (rect.width - 20) * width,
                                                 height: 7), xRadius: 3, yRadius: 3).fill()
            }
            return true
        }
    }
}

@MainActor
enum Fixtures {
    /// 2026-11-21 16:24 UTC.
    static let now = Date(timeIntervalSince1970: 1_795_278_240)
    static let time: TimeLabel = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return TimeLabel(calendar: calendar, locale: Locale(identifier: "en_US"))
    }()
    static let originalPath = "/Users/parag/Desktop/Screenshot 2026-11-21 at 16.24.11.png"
    static let renamed = RenamedToast(originalURL: URL(fileURLWithPath: originalPath),
                                      currentURL: URL(fileURLWithPath: "/Users/parag/Desktop/Tweet semiconductor flashcards.png"),
                                      undoRecordIDs: [UUID()])
    static let renamedLong = RenamedToast(
        originalURL: URL(fileURLWithPath: originalPath),
        currentURL: URL(fileURLWithPath: "/Users/parag/Desktop/Invoice from Acme Cloud Services for November with VAT breakdown and payment link.png"),
        undoRecordIDs: [UUID()])
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
                                    now: now, time: time),
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
