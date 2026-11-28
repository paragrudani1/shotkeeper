import ShotkeeperCore
import XCTest
@testable import Shotkeeper

final class SettingsStoreTests: TempDirectoryTestCase {
    func testMissingFileGivesDefaults() {
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        XCTAssertEqual(store.current, AppSettings())
    }

    func testSaveThenReloadRoundTrips() throws {
        let url = directory.appendingPathComponent("nested/settings.json")
        var settings = AppSettings()
        settings.backend = .customEndpoint
        settings.customEndpointURL = URL(string: "http://127.0.0.1:8080")
        settings.customModelName = "inkling"
        settings.requestsPerMinute = 12
        settings.excludeRules.rules = [.init(.filenameContains, "bank")]
        settings.hasSeenPrivacyNotice = true
        try SettingsStore(fileURL: url).save(settings)

        XCTAssertEqual(SettingsStore(fileURL: url).current, settings)
    }

    func testUpdatePersists() throws {
        let url = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: url)
        let updated = try store.update { $0.moveEnabled = true; $0.minTitleConfidence = 0.7 }
        XCTAssertTrue(updated.moveEnabled)
        XCTAssertEqual(SettingsStore(fileURL: url).current.minTitleConfidence, 0.7)
    }

    func testUnreadableFileGivesDefaultsAndKeepsABackup() throws {
        let url = directory.appendingPathComponent("settings.json")
        try Data("{not json".utf8).write(to: url)
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.current, AppSettings())
        let backup = url.appendingPathExtension("unreadable")
        XCTAssertEqual(try Data(contentsOf: backup), Data("{not json".utf8))
    }

    func testSettingsFileIsPrettyJSONWithoutSecrets() throws {
        let url = directory.appendingPathComponent("settings.json")
        var settings = AppSettings()
        settings.clairicAccountID = "acct"
        try SettingsStore(fileURL: url).save(settings)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"clairicAccountID\""))
        XCTAssertFalse(text.lowercased().contains("token"), "the API token lives in the Keychain only")
    }
}

/// Records calls; optionally fails `beginRequest`.
final class FakeLocalRuntime: LocalModelServing, @unchecked Sendable {
    let url: URL
    let failure: AnalyzerError?
    private let lock = NSLock()
    private var _begins: [String] = []
    private var _ends = 0

    init(url: URL = URL(string: "http://127.0.0.1:1")!, failure: AnalyzerError? = nil) {
        self.url = url
        self.failure = failure
    }

    var begins: [String] { lock.withLock { _begins } }
    var ends: Int { lock.withLock { _ends } }

    func beginRequest(for variant: ModelVariant) async throws -> URL {
        lock.withLock { _begins.append(variant.id) }
        if let failure { throw failure }
        return url
    }

    func endRequest() async { lock.withLock { _ends += 1 } }

    func modelArgument(for variant: ModelVariant) -> String { "/models/\(variant.id)" }
}

final class AnalyzerFactoryTests: XCTestCase {
    private let gb16: UInt64 = 16 * 1_073_741_824
    private let gb32: UInt64 = 32 * 1_073_741_824

    private func expectNotConfigured(_ analyzer: any ScreenshotAnalyzer, contains text: String,
                                     file: StaticString = #filePath, line: UInt = #line) async throws {
        let unconfigured = try XCTUnwrap(analyzer as? UnconfiguredAnalyzer, file: file, line: line)
        XCTAssertTrue(unconfigured.reason.contains(text), unconfigured.reason, file: file, line: line)
        do {
            _ = try await analyzer.analyze(try ConnectionTestImage.payload(), context: ConnectionTestImage.context)
            XCTFail("expected notConfigured", file: file, line: line)
        } catch let error as AnalyzerError {
            XCTAssertEqual(error, .notConfigured(unconfigured.reason), file: file, line: line)
        }
    }

    func testClairicNeedsAccountAndToken() async throws {
        var settings = AppSettings()
        let credentials = InMemoryCredentialStore()
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "account ID")
        settings.clairicAccountID = "  acct  "
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "token")
        try credentials.setSecret("   ", for: .cloudflareAPIToken)
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "token")
        try credentials.setSecret("secret-token", for: .cloudflareAPIToken)
        // Configured in Settings but setup's privacy notice not accepted: nothing may be sent yet.
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "Finish setup")
        settings.uploadGrants = [.init(destination: .cloudflare, grantedAt: .distantPast)]
        let analyzer = AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil)
        XCTAssertTrue(analyzer is CloudflareClairicAnalyzer)
        XCTAssertEqual(analyzer.backendID, "clairic")
    }

    func testClairicRequestUsesTrimmedAccountAndKeychainToken() throws {
        var settings = AppSettings()
        settings.clairicAccountID = " acct123 "
        settings.uploadGrants = [.init(destination: .cloudflare, grantedAt: .distantPast)]
        let credentials = InMemoryCredentialStore([.cloudflareAPIToken: "tok"])
        let analyzer = try XCTUnwrap(AnalyzerFactory.make(settings: settings, credentials: credentials,
                                                          localRuntime: nil) as? CloudflareClairicAnalyzer)
        let request = try analyzer.makeRequest(image: try ConnectionTestImage.payload(), context: ConnectionTestImage.context)
        XCTAssertTrue(request.url?.absoluteString.contains("/accounts/acct123/ai/run/") == true, "\(request.url!)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testCustomEndpoint() async throws {
        var settings = AppSettings()
        settings.backend = .customEndpoint
        let credentials = InMemoryCredentialStore()
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "URL")
        settings.customEndpointURL = URL(string: "ftp://example.com")
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "URL")
        settings.customEndpointURL = URL(string: "http://192.168.1.5:8080")
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "model")
        settings.customModelName = "inkling-2-mini"
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "Finish setup")
        settings = BackendGate.granting(.customEndpoint, expectedEndpoint: CustomEndpointIdentity(url: settings.customEndpointURL),
                                        in: settings)
        let plain = try XCTUnwrap(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil)
            as? OpenAICompatibleAnalyzer)
        XCTAssertEqual(plain.configuration.baseURL, URL(string: "http://192.168.1.5:8080"))
        XCTAssertEqual(plain.configuration.model, "inkling-2-mini")
        XCTAssertNil(plain.configuration.apiKey)

        try credentials.setSecret("key", for: .customEndpointAPIKey)
        let withKey = try XCTUnwrap(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil)
            as? OpenAICompatibleAnalyzer)
        XCTAssertEqual(withKey.configuration.apiKey, "key")
    }

    func testOpenRouterNeedsAKeyAndItsOwnGrant() async throws {
        var settings = AppSettings()
        settings.backend = .openRouter
        settings.uploadGrants = [.init(destination: .cloudflare, grantedAt: .distantPast)]
        let credentials = InMemoryCredentialStore()
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "OpenRouter API key")
        try credentials.setSecret("  ", for: .openRouterAPIKey)
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "OpenRouter API key")
        try credentials.setSecret("sk-or-v1-key", for: .openRouterAPIKey)
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "Finish setup")  // Cloudflare's grant does not cover OpenRouter
        settings = BackendGate.granting(.openRouter, expectedOpenRouterModel: OpenRouterBackend.defaultModel, in: settings)
        let analyzer = try XCTUnwrap(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil)
            as? OpenAICompatibleAnalyzer)
        XCTAssertEqual(analyzer.backendID, "openrouter")
        XCTAssertEqual(analyzer.configuration.profile, OpenRouterBackend.profile(model: OpenRouterBackend.defaultModel))
        XCTAssertEqual(analyzer.configuration.model, OpenRouterBackend.defaultModel)
        XCTAssertEqual(analyzer.configuration.apiKey, "sk-or-v1-key")
        settings.openRouterModel = "thinkingmachines/inkling-2-mini-20261120"
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil),
                                      contains: "Finish setup")  // another model needs its own grant (S1)
        settings = BackendGate.granting(.openRouter, expectedOpenRouterModel: "thinkingmachines/inkling-2-mini-20261120",
                                        in: settings)
        let custom = try XCTUnwrap(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil)
            as? OpenAICompatibleAnalyzer)
        let body = try AnalysisJSON.parse(XCTUnwrap(custom.makeRequest(messages: [], includeExtras: true).httpBody))
        XCTAssertNil(body["provider"]?["only"],
                     "another model is not pinned to the default model's providers")
        XCTAssertEqual(custom.configuration.model, "thinkingmachines/inkling-2-mini-20261120")
    }

    func testLocalVariantFollowsSettingsThenMemory() {
        var settings = AppSettings()
        settings.backend = .localInkling
        XCTAssertEqual(AnalyzerFactory.localVariant(for: settings, physicalMemoryBytes: gb16), ModelCatalog.inkling2bit)
        XCTAssertEqual(AnalyzerFactory.localVariant(for: settings, physicalMemoryBytes: gb32), ModelCatalog.inkling4bit)
        settings.localModelVariantID = ModelCatalog.inkling3bit.id
        XCTAssertEqual(AnalyzerFactory.localVariant(for: settings, physicalMemoryBytes: gb16), ModelCatalog.inkling3bit)
        settings.localModelVariantID = "unknown/model"
        XCTAssertEqual(AnalyzerFactory.localVariant(for: settings, physicalMemoryBytes: gb16), ModelCatalog.inkling2bit)
    }

    func testLocalInklingUsesTheRuntime() async throws {
        var settings = AppSettings()
        settings.backend = .localInkling
        try await expectNotConfigured(AnalyzerFactory.make(settings: settings, credentials: InMemoryCredentialStore(),
                                                           localRuntime: nil), contains: "runtime")
        let runtime = FakeLocalRuntime(failure: .notConfigured("not installed"))
        let analyzer = AnalyzerFactory.make(settings: settings, credentials: InMemoryCredentialStore(),
                                            localRuntime: runtime, physicalMemoryBytes: gb16)
        let managed = try XCTUnwrap(analyzer as? ManagedLocalAnalyzer)
        XCTAssertEqual(managed.variant, ModelCatalog.inkling2bit)
        do {
            _ = try await analyzer.analyze(try ConnectionTestImage.payload(), context: ConnectionTestImage.context)
            XCTFail("expected an error")
        } catch let error as AnalyzerError {
            XCTAssertEqual(error, .notConfigured("not installed"))
        }
        XCTAssertEqual(runtime.begins, [ModelCatalog.inkling2bit.id])
        XCTAssertEqual(runtime.ends, 0, "a failed begin is not paired with an end")
    }

    func testManagedLocalAnalyzerEndsTheRequestWhenTheServerFails() async throws {
        // Port 1 on loopback refuses connections: the request fails fast without leaving this machine.
        let runtime = FakeLocalRuntime(url: URL(string: "http://127.0.0.1:1")!)
        let analyzer = ManagedLocalAnalyzer(variant: ModelCatalog.inkling2bit, runtime: runtime)
        do {
            _ = try await analyzer.analyze(try ConnectionTestImage.payload(), context: ConnectionTestImage.context)
            XCTFail("expected an error")
        } catch let error as AnalyzerError {
            XCTAssertTrue(error.isRetryable, "\(error)")
        }
        XCTAssertEqual(runtime.begins.count, 1)
        XCTAssertEqual(runtime.ends, 1)
    }
}

@MainActor
final class AppCoordinatorTests: TempDirectoryTestCase {
    private func makeCoordinator(credentials: InMemoryCredentialStore = InMemoryCredentialStore(),
                                 memoryGB: UInt64 = 16) -> AppCoordinator {
        .forTesting(in: directory, credentials: credentials, memoryGB: memoryGB)
    }

    func testOpensIndexAndDefaultsToUnconfiguredClairic() {
        let coordinator = makeCoordinator()
        XCTAssertNil(coordinator.startupError)
        XCTAssertNotNil(coordinator.index)
        XCTAssertNotNil(coordinator.queue)
        XCTAssertEqual(coordinator.settings.backend, .clairic)
        XCTAssertTrue(coordinator.currentAnalyzer is UnconfiguredAnalyzer)
        XCTAssertEqual(coordinator.recommendation.recommended.backend, .clairic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("support/index.sqlite").path))
    }

    func testAnalyzerIsRebuiltWhenSettingsOrSecretsChange() {
        let coordinator = makeCoordinator()
        coordinator.updateSettings { $0.clairicAccountID = "acct" }
        XCTAssertTrue(coordinator.currentAnalyzer is UnconfiguredAnalyzer)
        coordinator.setSecret("tok", for: .cloudflareAPIToken)
        XCTAssertTrue(coordinator.hasSecret(.cloudflareAPIToken))
        // Credentials alone are not enough: nothing leaves the Mac before the privacy notice is accepted.
        XCTAssertTrue(coordinator.currentAnalyzer is UnconfiguredAnalyzer)
        coordinator.allowUploads(to: .cloudflare, endpoint: nil)
        XCTAssertTrue(coordinator.currentAnalyzer is CloudflareClairicAnalyzer)

        coordinator.updateSettings {
            $0.backend = .customEndpoint
            $0.customEndpointURL = URL(string: "http://127.0.0.1:9")
            $0.customModelName = "m"
        }
        XCTAssertTrue(coordinator.currentAnalyzer is UnconfiguredAnalyzer, "Cloudflare consent does not cover a custom endpoint")
        coordinator.allowUploads(to: .customEndpoint,
                                 endpoint: CustomEndpointIdentity(url: coordinator.settings.customEndpointURL))
        XCTAssertTrue(coordinator.currentAnalyzer is OpenAICompatibleAnalyzer)

        coordinator.updateSettings { $0.backend = .localInkling }
        XCTAssertTrue(coordinator.currentAnalyzer is ManagedLocalAnalyzer)

        coordinator.updateSettings { $0.backend = .clairic }
        coordinator.setSecret("", for: .cloudflareAPIToken)
        XCTAssertFalse(coordinator.hasSecret(.cloudflareAPIToken))
        XCTAssertTrue(coordinator.currentAnalyzer is UnconfiguredAnalyzer)
    }

    func testSettingsArePersistedAndReloaded() {
        let coordinator = makeCoordinator()
        coordinator.updateSettings {
            $0.renameEnabled = false
            $0.requestsPerMinute = 7
            $0.hasSeenPrivacyNotice = true
        }
        let reloaded = makeCoordinator()
        XCTAssertFalse(reloaded.settings.renameEnabled)
        XCTAssertEqual(reloaded.settings.requestsPerMinute, 7)
        XCTAssertTrue(reloaded.settings.hasSeenPrivacyNotice)
    }

    /// The rate changes in place: a paused queue keeps its jobs held (a rebuilt queue used to resume the old one,
    /// which ran its queued screenshots during the pause).
    func testRequestsPerMinuteChangeKeepsTheQueueAndItsPause() async throws {
        let coordinator = makeCoordinator()
        let queue = try XCTUnwrap(coordinator.queue)
        coordinator.pauseIndefinitely()
        await waitUntil { coordinator.isPaused }
        let screenshot = directory.appendingPathComponent("Screenshot 2026-11-21 at 10.00.00.png")
        await queue.enqueue(screenshot)
        coordinator.updateSettings { $0.requestsPerMinute = 5 }
        XCTAssertTrue(coordinator.queue === queue)
        var rate = await queue.configuration.requestsPerMinute
        for _ in 0..<200 where rate != 5 {
            await Task.yield()
            rate = await queue.configuration.requestsPerMinute
        }
        XCTAssertEqual(rate, 5)
        let status = await queue.status
        XCTAssertEqual(status, .paused(until: nil))
        let queued = await queue.queuedCount
        XCTAssertEqual(queued, 1, "the held screenshot is still waiting, not processed")
    }

    func testTestConnectionSendsOnlyTheGeneratedImageAndSavesNoConsent() async {
        let coordinator = makeCoordinator()
        var candidate = AppSettings()
        candidate.backend = .customEndpoint
        candidate.customEndpointURL = URL(string: "http://127.0.0.1:1")
        candidate.customModelName = "m"
        XCTAssertFalse(candidate.hasSeenPrivacyNotice)
        let result = await coordinator.testConnection(settings: candidate, secrets: [:])
        guard case .failure(let failure) = result else { return XCTFail("port 1 cannot answer") }
        XCTAssertFalse(failure.message.contains("Finish setup"), failure.message)
        XCTAssertEqual(coordinator.settings.uploadGrants, [], "the test's own grants are never saved")
    }

    func testPauseSetsTheSkipWindowAndResumeClearsIt() {
        let coordinator = makeCoordinator()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.pause(minutes: 10, now: now)
        XCTAssertEqual(coordinator.settings.excludeRules.pausedFrom, now)
        XCTAssertEqual(coordinator.settings.excludeRules.pausedUntil, now.addingTimeInterval(600))
        coordinator.resume()
        XCTAssertNil(coordinator.settings.excludeRules.pausedUntil)
    }

    func testUndoWithNothingToUndoReportsInsteadOfThrowing() {
        let coordinator = makeCoordinator()
        coordinator.fileActions.undoLast()
        XCTAssertNotNil(coordinator.lastMessage)
    }

    func testTestConnectionUsesUnsavedSecretsWithoutStoringThem() async throws {
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(credentials: credentials)
        var candidate = AppSettings()
        candidate.backend = .customEndpoint
        candidate.customEndpointURL = URL(string: "http://127.0.0.1:1")
        candidate.customModelName = "m"
        let result = await coordinator.testConnection(settings: candidate, secrets: [.customEndpointAPIKey: "unsaved"])
        guard case .failure(let failure) = result else { return XCTFail("port 1 cannot answer") }
        XCTAssertFalse(failure.message.contains("unsaved"))
        XCTAssertNil(try credentials.secret(for: .customEndpointAPIKey), "testing must not save the key")

        candidate.backend = .clairic
        let missing = await coordinator.testConnection(settings: candidate, secrets: [:])
        XCTAssertEqual(missing, .failure(AnalyzerFailure(message: "Cloudflare account ID is not set.")))
    }
}

final class ExistingScreenshotScannerTests: TempDirectoryTestCase {
    func testFindsUnindexedScreenshotsOldestFirst() throws {
        let fm = FileManager.default
        let names = ["Screenshot 2026-11-21 at 10.00.00.png", "Screenshot 2026-11-20 at 09.00.00.png",
                     "Screenshot 2026-11-19 at 08.00.00.png", "holiday.png", ".Screenshot 2026-11-21 temp.png"]
        for (offset, name) in names.enumerated() {
            let url = directory.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try fm.setAttributes([.creationDate: Date(timeIntervalSince1970: TimeInterval(1_000_000 - offset * 1000))],
                                 ofItemAtPath: url.path)
        }
        try fm.createDirectory(at: directory.appendingPathComponent("Screenshot 2026 folder.png"),
                               withIntermediateDirectories: true)
        let indexed = directory.appendingPathComponent(names[1]).standardizedFileURL.path

        let found = ExistingScreenshotScanner.candidates(in: directory, detector: ScreenshotDetector()) {
            $0.standardizedFileURL.path == indexed
        }
        XCTAssertEqual(found.map(\.lastPathComponent), [names[2], names[0]])
    }

    func testSkipsFilesWhoseDataIsNotOnThisMac() throws {
        let local = directory.appendingPathComponent("Screenshot 2026-11-20 at 09.00.00.png")
        let evicted = directory.appendingPathComponent("Screenshot 2026-11-21 at 10.00.00.png")
        try Data("x".utf8).write(to: local)
        try Data("x".utf8).write(to: evicted)
        XCTAssertTrue(ExistingScreenshotScanner.isStoredLocally(local), "an ordinary file is local")
        let found = ExistingScreenshotScanner.candidates(in: directory, detector: ScreenshotDetector(),
                                                         isIndexed: { _ in false },
                                                         isStoredLocally: { $0.lastPathComponent != evicted.lastPathComponent })
        XCTAssertEqual(found.map(\.lastPathComponent), [local.lastPathComponent])
    }

    func testIndexedCheckUsesFinalStatusOnly() throws {
        let index = try ScreenshotIndex.inMemory()
        let done = directory.appendingPathComponent("Screenshot a.png")
        let failed = directory.appendingPathComponent("Screenshot b.png")
        try index.save(IndexedScreenshot(path: done.path, originalFilename: "a", contentHash: "h1", status: .done))
        try index.save(IndexedScreenshot(path: failed.path, originalFilename: "b", contentHash: "h2", status: .failed))
        let check = ExistingScreenshotScanner.indexedCheck(index)
        XCTAssertTrue(check(done))
        XCTAssertFalse(check(failed), "failed rows are retried")
        XCTAssertFalse(check(directory.appendingPathComponent("Screenshot c.png")))
    }

    func testMissingFolderGivesNothing() {
        XCTAssertEqual(ExistingScreenshotScanner.candidates(in: directory.appendingPathComponent("nope"),
                                                            detector: ScreenshotDetector()) { _ in false }, [])
    }
}

/// The coordinator's parts work against their small host protocols (2026-11-28 prefactor).
@MainActor
final class CoordinatorPartsTests: TempDirectoryTestCase {
    private final class FakeHost: FileActionsHost {
        var lastMessage: String?
        var cleared = 0, refreshed = 0
        var toasts: [ToastContent] = []
        func clearMessageAfterSuccess() { cleared += 1 }
        func refreshHistory() { refreshed += 1 }
        func showToast(_ content: ToastContent) { toasts.append(content) }
    }

    func testFileActionsWithoutAnIndexSayWhy() {
        let host = FakeHost()
        let actions = FileActions()
        actions.host = host
        guard case .error(let error) = actions.undo(ids: [UUID()]) else { return XCTFail() }
        XCTAssertEqual(error.problem, FileActions.indexNotOpen)
        let toast = RenamedToast(originalURL: URL(fileURLWithPath: "/d/a.png"), currentURL: URL(fileURLWithPath: "/d/b.png"),
                                 undoRecordIDs: [UUID()])
        XCTAssertEqual(actions.rename(toast, to: "c"), .failure(FileActions.indexNotOpen))
        actions.undoLast()
        XCTAssertEqual(host.cleared, 0)
        XCTAssertEqual(host.toasts, [])
    }

    private final class CaptureHost: FolderCaptureHost {
        var settings = AppSettings()
        var readiness = BackendReadiness.ready
        var index: ScreenshotIndex?
        var queue: ProcessingQueue?
        let userUploadRequests = UserUploadRequests()
        var lastMessage: String?
        func beginProcessExistingRun(_ files: [URL]) {}
    }

    /// Work interrupted by a quit (`pending` rows) is queued again when watching starts, once; finished and failed
    /// rows are not.
    func testStartWatchingRequeuesPendingRowsOnce() async throws {
        let index = try ScreenshotIndex.inMemory()
        let pending = directory.appendingPathComponent("Screenshot pending.png").standardizedFileURL
        try index.save(IndexedScreenshot(path: pending.path, originalFilename: "p", contentHash: "h1", status: .pending))
        try index.save(IndexedScreenshot(path: directory.appendingPathComponent("Screenshot done.png").path,
                                         originalFilename: "d", contentHash: "h2", status: .done))
        try index.save(IndexedScreenshot(path: directory.appendingPathComponent("Screenshot failed.png").path,
                                         originalFilename: "f", contentHash: "h3", status: .failed))
        let handled = LockedValue<[URL]>([])
        let queue = ProcessingQueue(jobHandler: { url, _ in handled.withValue { $0.append(url) } })
        let host = CaptureHost()
        host.settings.watchedFolderOverride = directory
        host.index = index
        host.queue = queue
        let capture = FolderCapture()
        capture.host = host
        defer { capture.stop() }

        capture.startWatching()
        XCTAssertTrue(capture.isWatching)
        let requeued = await waitUntil { handled.value == [pending] }
        XCTAssertTrue(requeued, "handled: \(handled.value)")
        capture.startWatching()  // already watching: nothing is queued twice
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(handled.value, [pending])
    }
}
