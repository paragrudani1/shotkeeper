import ShotkeeperCore
import XCTest
@testable import Shotkeeper

/// The setup window against a real coordinator (temp folder, in-memory credentials): when consent and the token are
/// stored, when watching starts, and step 4 reacting to pipeline events. CODING_STANDARDS #2.
@MainActor
final class SetupModelTests: TempDirectoryTestCase {
    private var credentials: InMemoryCredentialStore!
    private var closed = 0
    private var shortcutSettingsOpened = 0

    private func makeCoordinator(memoryGB: UInt64 = 16) -> AppCoordinator {
        credentials = InMemoryCredentialStore()
        let coordinator = AppCoordinator(supportDirectory: directory.appendingPathComponent("support"),
                                         credentials: credentials, physicalMemoryBytes: memoryGB * 1_073_741_824,
                                         applicationSupport: directory, logDirectory: directory.appendingPathComponent("logs"))
        // Watch a temp folder, never the user's screenshot location.
        let watched = directory.appendingPathComponent("watched", isDirectory: true)
        try? FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        coordinator.updateSettings { $0.watchedFolderOverride = watched }
        return coordinator
    }

    private func makeModel(_ coordinator: AppCoordinator) -> SetupModel {
        let model = SetupModel(services: .live(coordinator: coordinator,
                                               openShortcutSettings: { [weak self] in self?.shortcutSettingsOpened += 1 },
                                               close: { [weak self] in self?.closed += 1 }))
        model.start()
        return model
    }

    func testConsentIsStoredOnlyByIAgree() {
        let coordinator = makeCoordinator()
        let model = makeModel(coordinator)
        model.pressPrimary() // Get Started
        XCTAssertEqual(model.flow.step, .privacy)
        XCTAssertFalse(coordinator.settings.hasSeenPrivacyNotice)

        model.pressPrimary() // I Agree, but the box is not ticked
        XCTAssertEqual(model.flow.step, .privacy)
        model.flow.consentChecked = true
        XCTAssertFalse(coordinator.settings.hasSeenPrivacyNotice, "ticking the box alone stores nothing")
        model.goBack()
        model.pressPrimary()
        XCTAssertFalse(coordinator.settings.hasSeenPrivacyNotice, "Back and Get Started store nothing")

        model.pressPrimary() // I Agree
        XCTAssertTrue(coordinator.settings.hasSeenPrivacyNotice)
        XCTAssertEqual(model.flow.step, .connect)
        model.stop()
    }

    func testTokenReachesTheKeychainOnlyOnContinueAndWatchingStartsThen() throws {
        let coordinator = makeCoordinator()
        coordinator.startServices()
        defer { coordinator.stopServices() }
        let model = makeModel(coordinator)
        XCTAssertFalse(coordinator.isWatching, "nothing is watched before setup")
        model.pressPrimary()
        model.flow.consentChecked = true
        model.pressPrimary()
        XCTAssertFalse(coordinator.isWatching, "consent alone: no backend yet")
        XCTAssertEqual(coordinator.notWatchingReason, "Cloudflare account ID is not set")

        model.accountID = " acct "
        model.tokenDraft = "secret-token"
        XCTAssertNil(try credentials.secret(for: .cloudflareAPIToken), "typing stores nothing")
        XCTAssertEqual(model.current.primary.title, "Continue")
        XCTAssertNil(coordinator.settings.clairicAccountID)

        model.pressPrimary() // Continue
        XCTAssertEqual(try credentials.secret(for: .cloudflareAPIToken), "secret-token")
        XCTAssertEqual(coordinator.settings.clairicAccountID, "acct")
        XCTAssertEqual(coordinator.settings.backend, .clairic)
        XCTAssertEqual(model.tokenDraft, "", "the typed token is not kept in the window")
        XCTAssertTrue(coordinator.isWatching)
        XCTAssertTrue(coordinator.currentAnalyzer is CloudflareClairicAnalyzer)
        XCTAssertEqual(model.flow.step, .tryIt)
        XCTAssertEqual(model.current.tryIt, .waiting(note: nil))

        let json = String(decoding: try Data(contentsOf: AppPaths.settingsFile(in: directory.appendingPathComponent("support"))),
                          as: UTF8.self)
        XCTAssertFalse(json.contains("secret-token"), "the token never goes to settings.json")
        model.stop()
    }

    func testCloudCredentialsWithoutConsentNeverUploadOrWatch() {
        let coordinator = makeCoordinator()
        coordinator.startServices()
        defer { coordinator.stopServices() }
        // E.g. entered in Settings after closing setup at step 1.
        coordinator.saveClairicSetup(accountID: "acct", token: "tok")
        XCTAssertFalse(coordinator.settings.hasSeenPrivacyNotice)
        XCTAssertEqual(coordinator.readiness, .needsConsent)
        XCTAssertFalse(coordinator.isWatching)
        XCTAssertTrue(coordinator.currentAnalyzer is UnconfiguredAnalyzer)
        XCTAssertEqual(coordinator.notWatchingReason, "Setup is not finished")

        coordinator.acceptUploadConsent()
        XCTAssertTrue(coordinator.isWatching)
        XCTAssertTrue(coordinator.currentAnalyzer is CloudflareClairicAnalyzer)
    }

    func testLocalNeedsNoUploadConsent() {
        let coordinator = makeCoordinator()
        coordinator.startServices()
        defer { coordinator.stopServices() }
        coordinator.chooseLocalBackend(ModelCatalog.inkling2bit)
        XCTAssertFalse(coordinator.settings.hasSeenPrivacyNotice)
        XCTAssertEqual(coordinator.readiness, .ready)
        XCTAssertTrue(coordinator.isWatching)
        XCTAssertTrue(coordinator.currentAnalyzer is ManagedLocalAnalyzer)
        XCTAssertEqual(coordinator.settings.localModelVariantID, ModelCatalog.inkling2bit.id)
    }

    func testLocalChoiceIsSavedOnContinueOnceTheInstallStarted() {
        let coordinator = makeCoordinator()
        let model = makeModel(coordinator)
        model.pressPrimary()
        model.flow.consentChecked = true
        model.pressPrimary()
        model.choose(.localInkling)
        XCTAssertEqual(model.current.primary.title, "Skip", "the model is not installed")
        XCTAssertEqual(SetupModel.localModelState(.downloading(0.3)), .installing)
        XCTAssertEqual(SetupModel.localModelState(.installing("Installing mlx-lm…")), .installing)
        XCTAssertEqual(SetupModel.localModelState(.ready), .installed)
        XCTAssertEqual(SetupModel.localModelState(.running(port: 5)), .installed)
        XCTAssertEqual(SetupModel.localModelState(.failed("x")), .failed)

        model.pressPrimary() // Skip
        XCTAssertEqual(coordinator.settings.backend, .clairic, "Skip changes nothing")
        XCTAssertEqual(model.current.tryIt, .notConnected(TryIt.notConnectedText))
        XCTAssertEqual(model.current.primary.title, "Continue")
        model.stop()
    }

    func testTestConnectionSendsTheDraftsWithoutStoringThem() async throws {
        let coordinator = makeCoordinator()
        let model = makeModel(coordinator)
        model.accountID = ""
        model.tokenDraft = "unsaved"
        model.runTest()
        XCTAssertEqual(model.test, .running)
        for _ in 0..<500 where model.test == .running { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.test, .failed("Cloudflare account ID is not set."))
        XCTAssertNil(try credentials.secret(for: .cloudflareAPIToken))
        model.tokenDraft = "changed"
        XCTAssertEqual(model.test, .idle, "editing clears an old result")
        model.stop()
    }

    func testStepFourShowsTheNextRealScreenshot() throws {
        let coordinator = makeCoordinator()
        let model = makeModel(coordinator)
        let original = URL(fileURLWithPath: "/d/Screenshot 2026-11-21 at 16.24.11.png")
        let final = URL(fileURLWithPath: "/d/Tweet semiconductor flashcards.png")
        let event = ScreenshotEvent.processed(ProcessingReport(
            originalURL: original, outcome: .processed(finalURL: final, renamed: true, moved: false)))
        coordinator.handle(event) // before step 4: ignored
        XCTAssertEqual(model.flow.tryIt, .waiting(note: nil))

        coordinator.updateSettings { $0.backend = .localInkling } // usable without consent
        model.pressPrimary()
        model.flow.consentChecked = true
        model.pressPrimary()
        model.pressPrimary() // Skip: the local backend chosen above stays
        XCTAssertEqual(model.flow.step, .tryIt)
        XCTAssertEqual(model.current.tryIt, .waiting(note: nil))
        XCTAssertEqual(model.current.primary.title, "Skip")

        _ = try XCTUnwrap(coordinator.index).save(IndexedScreenshot(path: final.path, originalFilename: original.lastPathComponent,
                                                                contentHash: "h", tags: ["semiconductor", "flashcards"],
                                                                status: .done))
        coordinator.handle(event)
        guard case .result(let result) = model.current.tryIt else { return XCTFail("\(model.current.tryIt)") }
        XCTAssertEqual(result.newName, "Tweet semiconductor flashcards.png")
        XCTAssertEqual(result.hashtags, ["#semiconductor", "#flashcards"])
        XCTAssertEqual(model.current.primary.title, "Continue")

        model.stop()
        model.flow.tryIt = .waiting(note: nil)
        coordinator.handle(event)
        XCTAssertEqual(model.flow.tryIt, .waiting(note: nil), "no events after the window closed")
    }

    func testFinishAppliesLoginItemAndCloses() {
        let coordinator = makeCoordinator()
        let model = makeModel(coordinator)
        for _ in 0..<4 { model.flow.advance() }
        XCTAssertEqual(model.flow.step, .done)
        XCTAssertTrue(model.flow.openAtLogin, "on by default")
        model.services.openShortcutSettings()
        XCTAssertEqual(shortcutSettingsOpened, 1)
        model.pressPrimary()
        XCTAssertTrue(coordinator.settings.launchAtLogin)
        XCTAssertEqual(closed, 1)
    }

    func testProcessExistingWaitsForSetup() async throws {
        let coordinator = makeCoordinator()
        let watched = try XCTUnwrap(coordinator.settings.watchedFolderOverride)
        try Data("png".utf8).write(to: watched.appendingPathComponent("Screenshot 2026-11-21 at 10.00.00.png"))
        let queued = await coordinator.processExistingScreenshots()
        XCTAssertEqual(queued, 0, "nothing is queued for a later upload before setup")
        XCTAssertEqual(coordinator.lastMessage, "Finish setup first: Cloudflare account ID is not set")
    }

    func testEventObserversCanBeRemoved() {
        let coordinator = makeCoordinator()
        var seen = 0
        let id = coordinator.addEventObserver { _ in seen += 1 }
        let event = ScreenshotEvent.failed(originalURL: URL(fileURLWithPath: "/d/x.png"),
                                           problem: UserFacingProblem(message: "x"))
        coordinator.handle(event)
        coordinator.removeEventObserver(id)
        coordinator.handle(event)
        XCTAssertEqual(seen, 1)
    }
}
