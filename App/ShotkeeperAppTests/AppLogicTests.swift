import AppKit
import ImageIO
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

final class StatusTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func line(_ status: QueueStatus) -> String {
        StatusText.line(for: status, now: now, calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
    }

    func testLines() {
        XCTAssertEqual(line(.idle), "Idle: watching for screenshots")
        XCTAssertEqual(line(.processing(current: URL(fileURLWithPath: "/a.png"), remaining: 2)), "Processing: 3 left")
        XCTAssertEqual(line(.paused(until: nil)), "Paused")
        XCTAssertTrue(line(.paused(until: now.addingTimeInterval(600))).hasPrefix("Paused until "))
        XCTAssertEqual(line(.paused(until: now.addingTimeInterval(-1))), "Resuming…")
        XCTAssertEqual(line(.offline), "Offline: waiting for the model backend")
        XCTAssertEqual(line(.error("Cloudflare API token is not set")), "Needs attention: Cloudflare API token is not set")
    }

    func testEveryStatusHasASymbol() {
        let statuses: [QueueStatus] = [.idle, .processing(current: URL(fileURLWithPath: "/a"), remaining: 0),
                                       .paused(until: nil), .offline, .error("x")]
        for status in statuses { XCTAssertNotNil(NSImage(systemSymbolName: StatusText.symbol(for: status),
                                                         accessibilityDescription: nil), "\(status)") }
    }

    func testDescribeUnauthorizedMentionsPermissions() {
        XCTAssertTrue(StatusText.describe(AnalyzerError.unauthorized("bad token")).contains("Workers AI Read + Edit"))
        XCTAssertEqual(StatusText.describe(AnalyzerError.notConfigured("No token")), "No token")
    }
}

final class BackendCopyTests: XCTestCase {
    func testSixteenGigabyteMacRecommendsClairicWithExplicitLocalFallback() throws {
        let recommendation = BackendRecommender.recommend(physicalMemoryBytes: 16 * 1_073_741_824)
        XCTAssertEqual(recommendation.recommended.backend, .clairic)
        let local = try XCTUnwrap(recommendation.alternatives.first { $0.backend == .localInkling })
        XCTAssertEqual(BackendCopy.title(for: local), "Use local anyway (2-bit, lower quality, high memory use)")
        XCTAssertNotNil(local.warning)
        XCTAssertEqual(BackendCopy.title(for: recommendation.recommended), recommendation.recommended.title)
    }

    func testPrivacyCopyPerBackend() {
        XCTAssertTrue(BackendCopy.privacy(for: .clairic).contains("your own Cloudflare account"))
        XCTAssertEqual(BackendCopy.privacy(for: .localInkling), "100% on-device, nothing leaves your Mac.")
        XCTAssertTrue(BackendCopy.privacy(for: .customEndpoint).contains("endpoint you enter"))
    }

    func testRuntimePhaseText() {
        XCTAssertEqual(BackendCopy.describe(.downloading(0.426)), "Downloading… 43%")
        XCTAssertEqual(BackendCopy.describe(.running(port: 50123)), "Running on 127.0.0.1:50123")
    }
}

final class ConnectionTestImageTests: XCTestCase {
    func testGeneratesADecodablePNG() throws {
        let payload = try ConnectionTestImage.payload()
        XCTAssertEqual(payload.mimeType, "image/png")
        XCTAssertEqual(payload.pixelWidth, 640)
        XCTAssertEqual(payload.pixelHeight, 400)
        XCTAssertLessThan(payload.data.count, CloudflareClairicAnalyzer.maxImageBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(payload.data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 640)
    }

    func testSummary() {
        let analysis = ScreenshotAnalysis(title: "Coffee receipt", titleConfidence: 0.9, sourceAppOrSite: nil,
                                          contentType: .receipt, description: nil, tags: ["coffee"], keyText: nil,
                                          dateMentioned: nil, producedBy: "x", billedInputTokens: 1234)
        XCTAssertEqual(ConnectionTestImage.summary(analysis), "OK: “Coffee receipt” (receipt, 1 tag), 1234 input tokens")
    }
}

final class DownloadProgressTests: XCTestCase {
    func testParsesTheFetchingBarOnly() {
        let output = "Fetching 12 files:   0%|          | 0/12 [00:00<?, ?it/s]\r"
            + "model-00001.safetensors:  87%|████████▋ | 3.4G/3.9G\r"
            + "Fetching 12 files:  42%|████▏     | 5/12 [00:10<00:14, 2.1s/it]\r"
            + "model-00002.safetensors:   3%|▎         | 0.1G/3.9G"
        XCTAssertEqual(DownloadProgress.fetchingFraction(in: output) ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertNil(DownloadProgress.fetchingFraction(in: "model.safetensors:  87%|"))
        XCTAssertNil(DownloadProgress.fetchingFraction(in: "no progress here"))
    }

    func testEstimateTakesTheLargerSourceAndCapsBelowOne() {
        XCTAssertEqual(DownloadProgress.estimate(parsed: nil, bytesOnDisk: 5_000_000_000, expectedGB: 10), 0.5, accuracy: 1e-9)
        XCTAssertEqual(DownloadProgress.estimate(parsed: 0.7, bytesOnDisk: 5_000_000_000, expectedGB: 10), 0.7, accuracy: 1e-9)
        XCTAssertEqual(DownloadProgress.estimate(parsed: 1.0, bytesOnDisk: 20_000_000_000, expectedGB: 10), 0.99, accuracy: 1e-9)
    }

    func testBytesOnDiskCountsNestedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(".cache/huggingface"),
                                                withIntermediateDirectories: true)
        try Data(count: 1000).write(to: directory.appendingPathComponent("a.safetensors"))
        try Data(count: 500).write(to: directory.appendingPathComponent(".cache/huggingface/b.incomplete"))
        XCTAssertEqual(DownloadProgress.bytesOnDisk(in: directory), 1500)
    }
}

final class ServerPIDFileTests: XCTestCase {
    private var file: ServerPIDFile!

    override func setUp() {
        file = ServerPIDFile(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("pid-\(UUID().uuidString)/server.pid"))
    }

    private func spawnSleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
    }

    func testKillsTheRecordedLeftoverProcess() throws {
        let process = try spawnSleeper()
        defer { if process.isRunning { process.terminate() } }
        let started = try XCTUnwrap(ProcessInfoReader.startTime(of: process.processIdentifier))
        try file.write(.init(pid: process.processIdentifier, startTime: started, port: 1234))
        XCTAssertEqual(file.read()?.port, 1234)

        XCTAssertTrue(file.killLeftover(gracePeriod: 2))
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
        XCTAssertNil(file.read(), "the record is removed")
    }

    func testLeavesAProcessWhoseStartTimeDiffers() throws {
        let process = try spawnSleeper()
        defer { process.terminate() }
        let started = try XCTUnwrap(ProcessInfoReader.startTime(of: process.processIdentifier))
        try file.write(.init(pid: process.processIdentifier, startTime: started + 1, port: 1))
        XCTAssertFalse(file.killLeftover(gracePeriod: 0.2), "pid reused by another process: never kill it")
        XCTAssertTrue(process.isRunning)
        XCTAssertNil(file.read())
    }

    func testNoFileOrDeadProcessIsANoOp() throws {
        XCTAssertFalse(file.killLeftover())
        try file.write(.init(pid: 999_999, startTime: 1, port: 1))
        XCTAssertFalse(file.killLeftover())
    }
}

final class SearchKeyTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(SearchKey.from(keyCode: 126, modifiers: [], characters: nil), .up)
        XCTAssertEqual(SearchKey.from(keyCode: 125, modifiers: [], characters: nil), .down)
        XCTAssertEqual(SearchKey.from(keyCode: 36, modifiers: [], characters: "\r"), .open)
        XCTAssertEqual(SearchKey.from(keyCode: 76, modifiers: [], characters: nil), .open)
        XCTAssertEqual(SearchKey.from(keyCode: 53, modifiers: [], characters: nil), .close)
        XCTAssertEqual(SearchKey.from(keyCode: 49, modifiers: [], characters: " "), .space)
        XCTAssertEqual(SearchKey.from(keyCode: 8, modifiers: [.command], characters: "c"), .copyImage)
        XCTAssertEqual(SearchKey.from(keyCode: 15, modifiers: [.command], characters: "r"), .reveal)
        XCTAssertEqual(SearchKey.from(keyCode: 16, modifiers: [.command], characters: "y"), .quickLook)
        // Arrow keys carry .function/.numericPad flags on real events; those must not block the match.
        XCTAssertEqual(SearchKey.from(keyCode: 126, modifiers: [.function, .numericPad], characters: nil), .up)
        XCTAssertNil(SearchKey.from(keyCode: 8, modifiers: [], characters: "c"), "plain c is typing")
        XCTAssertNil(SearchKey.from(keyCode: 8, modifiers: [.command, .shift], characters: "c"))
        XCTAssertNil(SearchKey.from(keyCode: 126, modifiers: [.shift], characters: nil), "⇧↑ extends the text selection")
        XCTAssertNil(SearchKey.from(keyCode: 49, modifiers: [.shift], characters: " "), "⇧Space is typing")
    }
}

@MainActor
final class SearchViewModelTests: XCTestCase {
    nonisolated private static func row(_ name: String, type: ContentType = .other) -> IndexedScreenshot {
        IndexedScreenshot(path: "/tmp/\(name).png", originalFilename: name, contentHash: name, processedAt: Date(),
                          title: name, contentType: type, status: .done)
    }

    nonisolated private static func page(_ names: [String], total: Int? = nil) -> ScreenshotSearchResult {
        ScreenshotSearchResult(rows: names.map { row($0) }, matchCount: names.count, totalCount: total ?? names.count)
    }

    func testEmptyQueryShowsRecentAndSelectsTheFirstRow() async {
        let queries = LockedValue<[ScreenshotQuery]>([])
        let model = SearchViewModel(debounce: .milliseconds(10)) { query, _ in
            queries.withValue { $0.append(query) }
            return Self.page(["a", "b"], total: 214)
        }
        model.refresh()
        await model.waitForPendingSearch()
        XCTAssertEqual(queries.value, [ScreenshotQuery()])
        XCTAssertEqual(model.state.items.map(\.path), ["/tmp/a.png", "/tmp/b.png"])
        XCTAssertEqual(model.state.selectedIndex, 0)
        XCTAssertEqual(model.state.footerText, "Recent · 214 screenshots")
    }

    func testTypingIsDebouncedToTheLastQuery() async {
        let queries = LockedValue<[String]>([])
        let model = SearchViewModel(debounce: .milliseconds(200)) { query, _ in
            queries.withValue { $0.append(query.text) }
            return Self.page([])
        }
        model.setText("r")
        model.setText("re")
        model.setText("rec")
        await model.waitForPendingSearch()
        XCTAssertEqual(queries.value, ["rec"])
        XCTAssertEqual(model.searchesRun, 1)
    }

    func testChipTagEscapeAndBatchRunTheRightQueries() async {
        let queries = LockedValue<[ScreenshotQuery]>([])
        let limits = LockedValue<[Int]>([])
        let model = SearchViewModel(debounce: .zero) { query, limit in
            queries.withValue { $0.append(query) }
            limits.withValue { $0.append(limit) }
            return Self.page(["a"], total: 5)
        }
        model.setText("coffee")
        await model.waitForPendingSearch()
        model.selectChip(.receipt)
        await model.waitForPendingSearch()
        XCTAssertEqual(queries.value.last, ScreenshotQuery(text: "coffee", contentType: .receipt))
        model.clickTag("#beans")
        await model.waitForPendingSearch()
        XCTAssertEqual(queries.value.last, ScreenshotQuery(text: "beans"))
        XCTAssertFalse(model.escape(), "the first esc clears the search")
        await model.waitForPendingSearch()
        XCTAssertEqual(queries.value.last, ScreenshotQuery())
        XCTAssertTrue(model.escape(), "the second esc closes")
        model.showBatch(["/tmp/a.png"])
        await model.waitForPendingSearch()
        XCTAssertEqual(queries.value.last, ScreenshotQuery(paths: ["/tmp/a.png"]))
        XCTAssertEqual(model.state.footerText, "This batch · 1 screenshot")
        XCTAssertEqual(limits.value.last, SearchWindowState.pageSize)
        model.windowHidden()
        XCTAssertNil(model.state.batchPaths, "the next open shows recent screenshots")
    }

    func testIndexUnavailableShowsTheErrorStateNotTheEmptyState() async {
        let model = SearchViewModel(debounce: .zero) { _, _ in
            throw IndexUnavailableError(problem: UserFacingProblem(message: "the index file is damaged"))
        }
        model.refresh()
        await model.waitForPendingSearch()
        guard case .error(let message) = model.state.phase else { return XCTFail("got \(model.state.phase)") }
        XCTAssertEqual(message.title, "The screenshot index could not be opened")
        XCTAssertTrue(message.message.hasPrefix("The index file is damaged."))
        XCTAssertNil(model.selectedURL)
    }

    func testCopiedPillHidesAgain() async throws {
        let model = SearchViewModel(debounce: .zero) { _, _ in Self.page([]) }
        model.showCopied()
        XCTAssertTrue(model.showsCopiedPill)
        try await Task.sleep(for: .seconds(SearchWindowState.copiedPillDuration + 0.4))
        XCTAssertFalse(model.showsCopiedPill)
        model.showCopied()
        model.windowHidden()
        XCTAssertFalse(model.showsCopiedPill)
    }

    func testSearchesTheRealIndex() async throws {
        let index = try ScreenshotIndex.inMemory()
        var receipt = Self.row("receipt", type: .receipt)
        receipt.title = "Coffee receipt"
        receipt.keyText = "Total 8.25"
        try index.save(receipt)
        try index.save(Self.row("diagram", type: .design))
        let model = SearchViewModel(debounce: .zero) { try index.search($0, limit: $1) }
        model.setText("coffee")
        await model.waitForPendingSearch()
        XCTAssertEqual(model.state.items.map(\.path), ["/tmp/receipt.png"])
        XCTAssertEqual(model.state.footerText, "1 of 2 screenshots")
        model.setText("")
        model.selectChip(.design)
        await model.waitForPendingSearch()
        XCTAssertEqual(model.state.items.map(\.path), ["/tmp/diagram.png"])
    }
}

final class PlatformConformanceTests: XCTestCase {
    func testPlatformTypesConformToCoreProtocols() {
        let preparer: any ImagePreparer = ImageIODownscaler()
        let writer: any FileMetadataWriter = XattrMetadataWriter()
        let store: any CredentialStore = KeychainCredentialStore()
        XCTAssertNotNil(preparer)
        XCTAssertNotNil(writer)
        XCTAssertNotNil(store)
    }

    func testCoreFinderMetadataMergesTagsThroughTheXattrWriter() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fm-\(UUID().uuidString).png")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let writer = XattrMetadataWriter()
        try writer.setTags(["Work\n6"], for: file)
        try FinderMetadata.apply(tags: ["receipt", "work"], comment: "A receipt", to: file, using: writer)
        XCTAssertEqual(try writer.tags(of: file), ["Work\n6", "receipt"])
        XCTAssertEqual(try writer.finderComment(of: file), "A receipt")
    }

    func testSettingsDrivenPreparerReadsTheLongSidePerCall() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.png")
        try ConnectionTestImage.payload().data.write(to: url)
        let side = LockedValue(320)
        let preparer = SettingsDrivenImagePreparer(settings: {
            var settings = AppSettings()
            settings.maxImageLongSide = side.value
            return settings
        })
        XCTAssertEqual(try preparer.prepare(url).pixelWidth, 320)
        side.value = 512
        XCTAssertEqual(try preparer.prepare(url).pixelWidth, 512)
    }
}
