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
            // Search window (PR 2)
            UISnapshot("search-results") { Fixtures.search(selected: 1) },
            UISnapshot("search-chip-selected") { Fixtures.search(text: "receipt", chip: .receipt) },
            UISnapshot("search-copied") { Fixtures.search(copied: true) },
            UISnapshot("search-file-missing") { Fixtures.search(problem: SearchWindowState.missingFileMessage) },
            UISnapshot("search-batch") { Fixtures.search(batch: true, selected: 2) },
            UISnapshot("search-no-match") { Fixtures.search(text: "zebra crossing", rows: []) },
            UISnapshot("search-empty-index") { Fixtures.search(rows: [], total: 0) },
            UISnapshot("search-index-error") { Fixtures.searchIndexError() },
            // First-run setup (PR 3) and the app icon it shows
            UISnapshot("app-icon") { Fixtures.appIcons() },
            // PR 4: the compiled AppIcon asset (the bundle's icon, as the Dock and Finder get it) at 16…256 pt.
            UISnapshot("app-icon-asset") { Fixtures.bundleIcons() },
            UISnapshot("setup-1-welcome") { Fixtures.setup(.welcome) },
            UISnapshot("setup-2-privacy") { Fixtures.setup(.privacy) },
            UISnapshot("setup-2-privacy-agreed") { Fixtures.setup(.privacy, consent: true) },
            UISnapshot("setup-3-clairic-empty") { Fixtures.setup(.connect) },
            UISnapshot("setup-3-clairic-testing") { Fixtures.setup(.connect, account: Fixtures.account, token: "fake", test: .running) },
            UISnapshot("setup-3-clairic-connected") {
                Fixtures.setup(.connect, account: Fixtures.account, token: "fake", test: .succeeded)
            },
            UISnapshot("setup-3-clairic-error") {
                Fixtures.setup(.connect, account: Fixtures.account, token: "fake", test: .failed(
                    ConnectionTestText.failure(AnalyzerError.unauthorized("HTTP 401"), backend: .clairic)))
            },
            UISnapshot("setup-3-local") { Fixtures.setup(.connect, choice: .localInkling) },
            UISnapshot("setup-3-local-downloading") { Fixtures.setup(.connect, choice: .localInkling, phase: .downloading(0.42)) },
            UISnapshot("setup-3-local-32gb") { Fixtures.setup(.connect, choice: .localInkling, memoryGB: 32) },
            UISnapshot("setup-3-8gb") { Fixtures.setup(.connect, memoryGB: 8) },
            UISnapshot("setup-3-custom-rerun") { Fixtures.setup(.connect, choice: .customEndpoint, backend: .customEndpoint) },
            // OpenRouter (Inkling 2 Mini through OpenRouter): empty, and ready to continue after a test.
            UISnapshot("setup-3-openrouter") { Fixtures.setup(.connect, choice: .openRouter) },
            UISnapshot("setup-3-openrouter-ready") {
                Fixtures.setup(.connect, choice: .openRouter, test: .succeeded, openRouterKey: "fake", acknowledged: true)
            },
            UISnapshot("setup-3-openrouter-out-of-credits") {
                Fixtures.setup(.connect, choice: .openRouter, test: .failed(
                    ConnectionTestText.failure(AnalyzerError.badRequest(status: 402, message: "x"), backend: .openRouter)),
                               openRouterKey: "fake", acknowledged: true)
            },
            UISnapshot("setup-3-openrouter-8gb") { Fixtures.setup(.connect, choice: .openRouter, memoryGB: 8) },
            UISnapshot("setup-4-waiting") { Fixtures.setup(.tryIt) },
            UISnapshot("setup-4-waiting-download") {
                Fixtures.setup(.tryIt, phase: .downloading(0.42), backend: .localInkling)
            },
            UISnapshot("setup-4-problem") {
                Fixtures.setup(.tryIt, tryIt: .problem("Could not name that screenshot: the model backend rejected the token. "
                                                       + "Take another one to try again."))
            },
            UISnapshot("setup-4-result") { Fixtures.setup(.tryIt, tryIt: .result(Fixtures.tryItResult)) },
            UISnapshot("setup-4-not-connected") { Fixtures.setup(.tryIt, tryIt: .notConnected(TryIt.notConnectedText)) },
            UISnapshot("setup-5-done") { Fixtures.setup(.done) },
            UISnapshot("setup-5-done-custom-shortcut") { Fixtures.setup(.done, shortcut: Fixtures.customShortcut) },
            // Settings (PR 4): each tab under a drawn stand-in for the scene's toolbar (snapshots cannot draw the
            // real window toolbar). General is drawn taller than the window so the whole form shows.
            UISnapshot("settings-general") { Fixtures.settings(.general) },
            UISnapshot("settings-general-kebab-date") { Fixtures.settings(.general, kebabWithDate: true) },
            UISnapshot("settings-model-clairic") { Fixtures.settings(.model) },
            UISnapshot("settings-model-custom-consent") { Fixtures.settings(.model, backend: .customEndpoint) },
            UISnapshot("settings-model-openrouter-consent") { Fixtures.settings(.model, backend: .openRouter) },
            UISnapshot("settings-model-openrouter") {
                Fixtures.settings(.model, backend: .openRouter, openRouterAllowed: true, openRouterAdvanced: true)
            },
            UISnapshot("settings-model-local-not-installed") {
                Fixtures.settings(.model, backend: .localInkling, install: Fixtures.install(.notInstalled))
            },
            UISnapshot("settings-model-local-downloading") {
                Fixtures.settings(.model, backend: .localInkling, install: Fixtures.install(.downloading(0.45)))
            },
            UISnapshot("settings-model-local-no-disk-space") {
                Fixtures.settings(.model, backend: .localInkling, install: Fixtures.install(.notInstalled, problem:
                    DiskSpaceCheck.evaluate(availableBytes: 6_200_000_000, downloadBytes: 10_400_000_000,
                                            alreadyOnDisk: 0, needsRuntime: true).message))
            },
            UISnapshot("settings-model-local-partial-download") {
                Fixtures.settings(.model, backend: .localInkling, install: Fixtures.install(.notInstalled, partial: 3_400_000_000))
            },
            UISnapshot("settings-model-local-beyond-estimate") {
                Fixtures.settings(.model, backend: .localInkling, install: Fixtures.install(.downloading(0.99), beyondEstimate: true))
            },
            UISnapshot("settings-model-local-installed") {
                Fixtures.settings(.model, backend: .localInkling, install: Fixtures.install(.running(port: 50123)))
            },
            UISnapshot("settings-exclusions-empty") { Fixtures.settings(.exclusions) },
            UISnapshot("settings-exclusions-rules") { Fixtures.settings(.exclusions, rules: true) },
            UISnapshot("settings-about") { Fixtures.settings(.about) },
            // Shortcut recorder states
            UISnapshot("shortcut-recorder-idle") { Fixtures.recorder(.idle) },
            UISnapshot("shortcut-recorder-idle-custom") { Fixtures.recorder(.idle, current: Fixtures.customShortcut) },
            UISnapshot("shortcut-recorder-recording") { Fixtures.recorder(.recording) },
            UISnapshot("shortcut-recorder-conflict") { Fixtures.recorder(.conflict) },
            UISnapshot("shortcut-recorder-system-shortcut") { Fixtures.recorder(.systemShortcut) },
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

    /// Square for thumbnails; landscape (16:10) for large previews (side > 100), like a real screenshot.
    @MainActor
    static func image(for path: String, side: CGFloat) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let hues: [CGFloat] = [0.58, 0.08, 0.36, 0.75, 0.95]
        let hue = hues[path.unicodeScalars.reduce(0) { $0 + Int($1.value) } % hues.count]  // stable across runs
        let size = side > 100 ? NSSize(width: 320, height: 200) : NSSize(width: 120, height: 120)
        return NSImage(size: size, flipped: true) { rect in
            let unit = rect.height / 120
            NSColor.white.setFill()
            rect.fill()
            NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: rect.width, height: 26 * unit).fill()
            NSColor(white: 0.75, alpha: 1).setFill()
            for (row, width) in [0.8, 0.6, 0.9, 0.5, 0.7].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 10 * unit, y: (38 + CGFloat(row) * 15) * unit,
                                                 width: (rect.width - 20 * unit) * width, height: 7 * unit),
                             xRadius: 3 * unit, yRadius: 3 * unit).fill()
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

    // MARK: Search window

    private static func shot(_ title: String, folder: String = "/Users/parag/Desktop", source: String?, type: ContentType,
                             minutes: Double, tags: [String], description: String) -> IndexedScreenshot {
        IndexedScreenshot(path: "\(folder)/\(title).png",
                          originalFilename: "Screenshot.png", contentHash: title,
                          capturedAt: now.addingTimeInterval(minutes * 60), processedAt: now.addingTimeInterval(minutes * 60 + 4),
                          title: title, titleConfidence: 0.9, sourceAppOrSite: source, contentType: type,
                          description: description, tags: tags, status: .done)
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

    static func search(text: String = "", chip: SearchChip = .all, batch: Bool = false, rows: [IndexedScreenshot]? = nil,
                       total: Int = 214, selected: Int = 0, copied: Bool = false, problem: String? = nil) -> some View {
        var state = SearchWindowState()
        if batch { state.showBatch(Array(searchRows.prefix(4)).map(\.path)) }
        state.setText(text)
        if chip != .all { state.selectChip(chip) }
        var shown = rows ?? (batch ? Array(searchRows.prefix(4)) : searchRows)
        if rows == nil, let type = chip.contentType { shown = shown.filter { $0.contentType == type } }
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
        let model = SearchViewModel(state: state, now: { now }, time: time) { _, _ in throw CancellationError() }
        if copied { model.showCopied() }
        if let problem { model.showProblem(problem) }
        return SearchView(model: model, actions: .none, opaqueBackground: true)
    }

    // MARK: Setup

    static let account = "0123456789abcdef0123456789abcdef"
    static let tryItResult = TryItResult(path: "/Users/parag/Desktop/Tweet semiconductor flashcards.png",
                                         oldName: "Screenshot 2026-11-21 at 16.24.11.png",
                                         newName: "Tweet semiconductor flashcards.png",
                                         hashtags: ["#semiconductor", "#flashcards", "#chips", "#x.com"])

    /// Fixed answers and no-op actions: nothing reaches a coordinator, the Keychain or the network.
    static func setupServices(memoryGB: UInt64 = 16, phase: RuntimePhase = .notInstalled,
                              backend: AppSettings.Backend = .clairic) -> SetupServices {
        let settings: AppSettings = {
            var settings = AppSettings()
            settings.backend = backend
            if backend == .customEndpoint { settings.customEndpointURL = URL(string: "http://gpu-box.lan:8080") }
            return settings
        }()
        return SetupServices(
            physicalMemoryBytes: memoryGB * 1_073_741_824,
            settings: { settings }, hasSavedToken: { false }, credentialsRevision: { 0 }, loginItemEnabled: { nil },
            runtimePhase: { phase }, readiness: { .ready },
            isPaused: { false }, acceptConsent: {}, saveClairic: { _, _, _ in }, chooseLocal: { _ in },
            refreshLocal: { _ in }, installLocal: { _ in }, cancelInstall: {},
            testClairic: { _, _ in .success("") }, addEventObserver: { _ in nil }, removeEventObserver: { _ in },
            indexEntry: { _ in nil }, openShortcutSettings: {}, finish: { _ in })
    }

    static func setup(_ step: SetupStep, choice: AppSettings.Backend = .clairic, consent: Bool = false,
                      account: String = "", token: String = "", test: ConnectionTestState = .idle,
                      tryIt: TryItState? = nil, phase: RuntimePhase = .notInstalled, memoryGB: UInt64 = 16,
                      backend: AppSettings.Backend = .clairic, shortcut: HotKeyShortcut = .defaultSearch,
                      openRouterKey: String = "", acknowledged: Bool = false) -> some View {
        var services = setupServices(memoryGB: memoryGB, phase: phase, backend: backend)
        services.searchShortcut = { shortcut }
        let model = SetupModel(services: services)
        var flow = model.flow
        for _ in 1..<step.rawValue { flow.advance() }
        flow.consentChecked = consent || step.rawValue > SetupStep.privacy.rawValue
        flow.choose(choice)
        if let tryIt { flow.tryIt = tryIt }
        model.flow = flow
        model.accountID = account
        model.tokenDraft = token
        model.openRouterKeyDraft = openRouterKey
        model.openRouterAcknowledged = acknowledged
        model.test = test
        return SetupView(model: model)
    }

    // MARK: Settings

    /// ⌃⌥K
    static let customShortcut = HotKeyShortcut(keyCode: KeyCode.k, modifiers: [.control, .option])

    /// A coordinator in a fresh temp folder with in-memory credentials: nothing touches the user's files or Keychain.
    static func settingsCoordinator(_ configure: (inout AppSettings) -> Void, token: Bool,
                                    openRouterKey: Bool = false) -> AppCoordinator {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotkeeperSnapshot-\(UUID().uuidString)", isDirectory: true)
        let credentials = InMemoryCredentialStore()
        if token { try? credentials.setSecret("fake-token", for: .cloudflareAPIToken) }
        if openRouterKey { try? credentials.setSecret("fake-key", for: .openRouterAPIKey) }
        let coordinator = AppCoordinator(supportDirectory: folder, credentials: credentials,
                                         physicalMemoryBytes: 16 * 1_073_741_824,
                                         applicationSupport: folder, logDirectory: folder)
        var settings = coordinator.settings
        configure(&settings)
        coordinator.updateSettings(settings)
        return coordinator
    }

    static func install(_ phase: RuntimePhase, problem: String? = nil, partial: Int64 = 0,
                        beyondEstimate: Bool = false) -> LocalInstallState {
        var stats: DownloadStats?
        if case .downloading = phase {
            var measured = DownloadStats(totalBytes: 10_400_000_000)
            let start: Int64 = beyondEstimate ? 10_500_000_000 : 4_560_000_000
            measured.record(bytes: start, at: now)
            measured.record(bytes: start + 123_000_000, at: now.addingTimeInterval(10))  // 12.3 MB/s
            stats = measured
        }
        let installing: Bool = { if case .downloading = phase { return true } else { return false } }()
        return LocalInstallState(phase: phase, stats: stats, installing: installing, problem: problem,
                                 variantName: ModelCatalog.inkling2bit.displayName, downloadGB: 10,
                                 partialDownloadBytes: partial)
    }

    static func settings(_ tab: SettingsTab, backend: AppSettings.Backend = .clairic, install: LocalInstallState? = nil,
                         rules: Bool = false, kebabWithDate: Bool = false, openRouterAllowed: Bool = false,
                         openRouterAdvanced: Bool = false) -> some View {
        let coordinator = settingsCoordinator({ settings in
            settings.backend = backend
            settings.clairicAccountID = account
            settings.organizedFolder = URL(fileURLWithPath: "/Users/parag/Pictures/Screenshots", isDirectory: true)
            settings.localModelVariantID = ModelCatalog.inkling2bit.id
            if backend == .customEndpoint {
                settings.customEndpointURL = URL(string: "http://gpu-box.lan:8080")
                settings.customModelName = "inkling-2-mini"
            }
            if backend == .clairic { settings.uploadGrants = [.init(destination: .cloudflare, grantedAt: now)] }
            if openRouterAllowed { settings.uploadGrants = [.init(destination: .openRouter, grantedAt: now)] }
            if rules {
                settings.excludeRules.rules = [.init(.filenameContains, "bank"), .init(.folder, "~/Desktop/Private"),
                                               .init(.filenameGlob, "*invoice*")]
            }
            if kebabWithDate { settings.filenameStyle = FilenameStyle(casing: .kebab, datePrefix: true) }
        }, token: backend == .clairic, openRouterKey: backend == .openRouter)
        let content: AnyView
        var height = SettingsView.size.height
        switch tab {
        case .general:
            content = AnyView(GeneralSettingsTab(coordinator: coordinator, navigation: SettingsNavigation(), showSetup: {}))
            height = 1_000
        case .model:
            content = AnyView(ModelSettingsTab(coordinator: coordinator, installStateOverride: install,
                                               showsOpenRouterAdvanced: openRouterAdvanced))
            if backend == .localInkling { height = 640 }
            if backend == .openRouter { height = 760 }
        case .exclusions:
            content = AnyView(ExclusionsSettingsTab(coordinator: coordinator))
        case .about:
            content = AnyView(AboutSettingsTab(version: "Version 0.1.0 (1)"))
        }
        return SettingsSnapshotFrame(selected: tab) {
            content.frame(width: SettingsView.size.width, height: height)
        }
    }

    enum RecorderState { case idle, recording, conflict, systemShortcut }

    static func recorder(_ state: RecorderState, current: HotKeyShortcut = .defaultSearch) -> some View {
        let model = ShortcutRecorderModel { _ in nil }
        switch state {
        case .idle: break
        case .recording:
            model.phase = .recording
            model.heldModifiers = [.control, .option]
        case .conflict:
            model.phase = .recording
            model.problem = HotKeyRules.registrationProblem(status: HotKeyRules.eventHotKeyExistsErr).message(for: customShortcut)
        case .systemShortcut:
            model.phase = .recording
            let spotlight = HotKeyShortcut(keyCode: KeyCode.space, modifiers: [.command])
            model.problem = HotKeyRules.problem(with: spotlight)?.message(for: spotlight)
        }
        return Form {
            Section("Search shortcut") {
                ShortcutRecorderView(model: model, current: current)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.size.width, height: 150)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    static func appIcons() -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            AppIconView(size: 32)
            AppIconView(size: 72)
            AppIconView(size: 160)
            VStack(spacing: 10) {
                MenuBarGlyphView(size: 18)
                MenuBarGlyphView(size: 72)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The hosting app's own icon (`NSApp.applicationIconImage`, from `AppIcon.icns`/`Assets.car`): a generic app
    /// icon here means the asset catalog did not make it into the bundle.
    static func bundleIcons() -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            ForEach([16, 32, 64, 128, 256], id: \.self) { side in
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: CGFloat(side), height: CGFloat(side))
                    Text("\(side) pt").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
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

/// A drawn stand-in for the Settings window's toolbar tabs (General · Model · Exclusions · About), so a snapshot
/// shows which tab it is. The real window draws its own toolbar; snapshots cannot capture it.
private struct SettingsSnapshotFrame<Content: View>: View {
    let selected: SettingsTab
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                item(.general, "General", "gearshape")
                item(.model, "Model", "cpu")
                item(.exclusions, "Exclusions", "eye.slash")
                item(.about, "About", "info.circle")
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            content()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func item(_ tab: SettingsTab, _ title: String, _ symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 18))
            Text(title).font(.system(size: 11))
        }
        .foregroundStyle(tab == selected ? Color.accentColor : Color.primary.opacity(0.7))
        .frame(width: 76, height: 44)
        .background(RoundedRectangle(cornerRadius: 6).fill(tab == selected ? Color.primary.opacity(0.08) : .clear))
    }
}
