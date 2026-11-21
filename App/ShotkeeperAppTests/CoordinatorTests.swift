import ShotkeeperCore
import XCTest
@testable import Shotkeeper

/// Temp folder per test.
class TempDirectoryTestCase: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(type(of: self))-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }
}

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
        let analyzer = AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil)
        XCTAssertTrue(analyzer is CloudflareClairicAnalyzer)
        XCTAssertEqual(analyzer.backendID, "clairic")
    }

    func testClairicRequestUsesTrimmedAccountAndKeychainToken() throws {
        var settings = AppSettings()
        settings.clairicAccountID = " acct123 "
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
        let plain = try XCTUnwrap(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil)
            as? LocalOpenAICompatibleAnalyzer)
        XCTAssertEqual(plain.configuration.baseURL, URL(string: "http://192.168.1.5:8080"))
        XCTAssertEqual(plain.configuration.model, "inkling-2-mini")
        XCTAssertNil(plain.configuration.apiKey)

        try credentials.setSecret("key", for: .customEndpointAPIKey)
        let withKey = try XCTUnwrap(AnalyzerFactory.make(settings: settings, credentials: credentials, localRuntime: nil)
            as? LocalOpenAICompatibleAnalyzer)
        XCTAssertEqual(withKey.configuration.apiKey, "key")
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
        AppCoordinator(supportDirectory: directory.appendingPathComponent("support"), credentials: credentials,
                       physicalMemoryBytes: memoryGB * 1_073_741_824,
                       applicationSupport: directory, logDirectory: directory.appendingPathComponent("logs"))
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
        XCTAssertTrue(coordinator.currentAnalyzer is CloudflareClairicAnalyzer)

        coordinator.updateSettings {
            $0.backend = .customEndpoint
            $0.customEndpointURL = URL(string: "http://127.0.0.1:9")
            $0.customModelName = "m"
        }
        XCTAssertTrue(coordinator.currentAnalyzer is LocalOpenAICompatibleAnalyzer)

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

    func testRequestsPerMinuteChangeRebuildsTheQueue() async {
        let coordinator = makeCoordinator()
        let before = coordinator.queue
        coordinator.updateSettings { $0.requestsPerMinute = 5 }
        let after = coordinator.queue
        XCTAssertFalse(before === after)
        let rate = await after?.configuration.requestsPerMinute
        XCTAssertEqual(rate, 5)
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
        coordinator.undoLastRename()
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
        XCTAssertEqual(missing, .failure(AnalyzerFailure(message: "Cloudflare account ID is not set")))
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
