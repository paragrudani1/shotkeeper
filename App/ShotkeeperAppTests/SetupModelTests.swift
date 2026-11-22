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

    /// Settings-style Clairic configuration (no setup flow, so no grant).
    private func configureClairicInSettings(_ coordinator: AppCoordinator) {
        coordinator.setSecret("tok", for: .cloudflareAPIToken)
        coordinator.updateSettings {
            $0.backend = .clairic
            $0.clairicAccountID = "acct"
        }
    }

    /// Waits for pipeline events, up to 5 s.
    private func waitForEvents(_ events: () -> [ScreenshotEvent], count: Int = 1) async throws {
        for _ in 0..<500 where events().count < count { try await Task.sleep(for: .milliseconds(10)) }
    }

    func testCloudflareIsAllowedOnlyByIAgreeThenClairicContinue() {
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

        XCTAssertEqual(coordinator.settings.uploadGrants, [])
        model.pressPrimary() // I Agree
        XCTAssertTrue(coordinator.settings.hasSeenPrivacyNotice)
        XCTAssertEqual(coordinator.settings.uploadGrants, [], "I Agree alone grants nothing")
        XCTAssertEqual(model.flow.step, .connect)

        model.accountID = "acct"
        model.tokenDraft = "tok"
        let before = Date()
        model.pressPrimary() // Continue with Clairic
        let grant = coordinator.settings.grant(for: .cloudflare)
        XCTAssertNotNil(grant, "I Agree + Clairic's Continue allow Cloudflare")
        XCTAssertGreaterThanOrEqual(grant?.grantedAt ?? .distantPast, before, "from now on, not before")
        XCTAssertNil(coordinator.settings.grant(for: .customEndpoint))
        model.stop()
    }

    func testPickingLocalInSetupGrantsNothing() {
        let coordinator = makeCoordinator()
        coordinator.updateSettings { $0.backend = .localInkling }
        let model = makeModel(coordinator)
        model.pressPrimary()
        model.flow.consentChecked = true
        model.pressPrimary()
        model.choose(.localInkling)
        model.pressPrimary() // Skip (not installed)
        XCTAssertEqual(coordinator.settings.uploadGrants, [], "no silent Cloudflare grant for a Local user")
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
        configureClairicInSettings(coordinator)
        XCTAssertFalse(coordinator.settings.hasSeenPrivacyNotice)
        XCTAssertEqual(coordinator.readiness, .needsConsent)
        XCTAssertFalse(coordinator.isWatching)
        XCTAssertTrue(coordinator.currentAnalyzer is UnconfiguredAnalyzer)
        XCTAssertEqual(coordinator.notWatchingReason, "Not allowed to send screenshots yet")

        coordinator.allowUploads(to: .cloudflare, endpoint: nil) // the Settings confirmation
        XCTAssertTrue(coordinator.isWatching)
        XCTAssertTrue(coordinator.currentAnalyzer is CloudflareClairicAnalyzer)
    }

    /// Review of PR 6: Local first (watching starts), then Clairic before consent. Screenshots taken meanwhile
    /// are skipped, not held, so "I Agree" does not upload them.
    func testScreenshotsTakenBeforeConsentAreNeverUploaded() async throws {
        let coordinator = makeCoordinator()
        // Written before watching starts, so only the explicit enqueue below hands it to the queue.
        let shot = try XCTUnwrap(coordinator.settings.watchedFolderOverride)
            .appendingPathComponent("Screenshot 2026-11-21 at 10.00.00.png")
        try Data("png".utf8).write(to: shot)
        coordinator.startServices()
        defer { coordinator.stopServices() }
        coordinator.chooseLocalBackend(ModelCatalog.inkling2bit)
        XCTAssertTrue(coordinator.isWatching)
        configureClairicInSettings(coordinator)
        XCTAssertEqual(coordinator.readiness, .needsConsent)
        XCTAssertTrue(coordinator.isSkippingForConsent)
        XCTAssertEqual(MenuViewState.make(from: coordinator, searchShortcut: "⌥⌘S").status.detail,
                       MenuText.skippingForConsentText)

        let queue = try XCTUnwrap(coordinator.queue)
        var events: [ScreenshotEvent] = []
        let observer = coordinator.addEventObserver { events.append($0) }
        defer { coordinator.removeEventObserver(observer) }
        await queue.enqueue(shot)
        await queue.waitUntilIdle()
        for _ in 0..<200 where events.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        guard case .processed(let report)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(report.outcome, .skipped(.awaitingConsent))

        coordinator.allowUploads(to: .cloudflare, endpoint: nil)
        XCTAssertEqual(coordinator.readiness, .ready)
        await queue.waitUntilIdle()
        let queued = await queue.queuedCount
        XCTAssertEqual(queued, 0, "nothing was held for after the consent")
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.path), "the file keeps its name")
        XCTAssertNil(coordinator.indexEntry(atPath: shot.standardizedFileURL.path), "never analyzed")
    }

    /// Consent re-review blocker: jobs held by Local ("not installed") were resumed by the Clairic rebuild and
    /// uploaded. The processor's time rule skips them: they were taken before Cloudflare was allowed.
    func testHeldJobsAreNotSentToADestinationAllowedLater() async throws {
        let coordinator = makeCoordinator()
        let shot = try XCTUnwrap(coordinator.settings.watchedFolderOverride)
            .appendingPathComponent("Screenshot 2026-11-21 at 11.00.00.png")
        // A real PNG: the image must reach the analyzer for the local backend to hold it as "not installed".
        try ConnectionTestImage.payload().data.write(to: shot)
        coordinator.startServices()
        defer { coordinator.stopServices() }
        // 1. Setup closed without agreeing. 2. Local in Settings, not installed: the job is held.
        coordinator.updateSettings { $0.backend = .localInkling }
        let queue = try XCTUnwrap(coordinator.queue)
        await queue.enqueue(shot)
        for _ in 0..<500 {
            if case .error = coordinator.queueStatus { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .error = coordinator.queueStatus else { return XCTFail("held as not installed: \(coordinator.queueStatus)") }
        // 3. Setup again: I Agree, still Local, still held.
        coordinator.acceptPrivacyStep()
        var events: [ScreenshotEvent] = []
        let observer = coordinator.addEventObserver { events.append($0) }
        defer { coordinator.removeEventObserver(observer) }
        // 4. Clairic + Continue: the rebuild resumes the queue.
        coordinator.saveClairicSetup(accountID: "acct", token: "tok", agreedThisRun: true)
        XCTAssertEqual(coordinator.readiness, .ready)
        try await waitForEvents({ events })
        await queue.waitUntilIdle()
        guard case .processed(let report)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(report.outcome, .skipped(.awaitingConsent), "taken before Cloudflare was allowed")
        XCTAssertNotEqual(coordinator.indexEntry(atPath: shot.standardizedFileURL.path)?.status, .done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.path))
    }

    /// Consent re-review: a later file event (a Preview save, moving the file back) re-queues a file that was
    /// skipped before consent. Its creation date still predates the grant, so it is skipped again.
    func testALaterFileEventDoesNotSendAFileTakenBeforeConsent() async throws {
        let coordinator = makeCoordinator()
        let shot = try XCTUnwrap(coordinator.settings.watchedFolderOverride)
            .appendingPathComponent("Screenshot 2026-11-21 at 12.00.00.png")
        try Data("png".utf8).write(to: shot)
        try await Task.sleep(for: .milliseconds(20))
        coordinator.acceptPrivacyStep()
        coordinator.saveClairicSetup(accountID: "acct", token: "tok", agreedThisRun: true) // Cloudflare allowed now, after the file
        coordinator.startServices()
        defer { coordinator.stopServices() }
        try Data("edited in Preview".utf8).write(to: shot) // same file, same creation date
        var events: [ScreenshotEvent] = []
        let observer = coordinator.addEventObserver { events.append($0) }
        defer { coordinator.removeEventObserver(observer) }
        let queue = try XCTUnwrap(coordinator.queue)
        await queue.enqueue(shot) // what the watcher does for the event
        try await waitForEvents({ events })
        guard case .processed(let report)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(report.outcome, .skipped(.awaitingConsent))
    }

    /// Waits until `condition` holds, up to 5 s.
    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    /// Consent review 3, B1 path 1: Process Existing on Local (not installed, so every job is held), then setup:
    /// I Agree, Clairic, Continue. The rebuild resumes the queue; the request was for Local, so the old screenshot
    /// is not sent to Cloudflare.
    func testProcessExistingOnLocalIsNotCarriedToClairic() async throws {
        let coordinator = makeCoordinator()
        let shot = try XCTUnwrap(coordinator.settings.watchedFolderOverride)
            .appendingPathComponent("Screenshot 2026-11-21 at 13.00.00.png")
        // A real PNG: the image must reach the analyzer for the local backend to hold it as "not installed".
        try ConnectionTestImage.payload().data.write(to: shot)
        coordinator.startServices()
        defer { coordinator.stopServices() }
        coordinator.chooseLocalBackend(ModelCatalog.inkling2bit)
        XCTAssertEqual(coordinator.readiness, .ready, "Local is ready even when not installed")
        let queued = await coordinator.processExistingScreenshots()
        XCTAssertEqual(queued, 1)
        try await wait {
            if case .error = coordinator.queueStatus { return true }
            return false
        }
        guard case .error = coordinator.queueStatus else { return XCTFail("held as not installed: \(coordinator.queueStatus)") }
        let heldQueue = try XCTUnwrap(coordinator.queue)
        let carriedWhileHeld = await heldQueue.carriedRequestCount
        XCTAssertEqual(carriedWhileHeld, 1, "the held job keeps its request (one job, many attempts)")
        let clicked = coordinator.processExistingRequests.generation

        var events: [ScreenshotEvent] = []
        let observer = coordinator.addEventObserver { events.append($0) }
        defer { coordinator.removeEventObserver(observer) }
        coordinator.acceptPrivacyStep()
        coordinator.saveClairicSetup(accountID: "acct", token: "tok", agreedThisRun: true)
        XCTAssertNotEqual(coordinator.processExistingRequests.generation, clicked, "the switch invalidates the request")
        XCTAssertEqual(coordinator.readiness, .ready)
        try await waitForEvents({ events })
        let queue = try XCTUnwrap(coordinator.queue)
        await queue.waitUntilIdle()
        guard case .processed(let report)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(report.outcome, .skipped(.awaitingConsent), "taken before Cloudflare was allowed; asked for on Local")
        let carriedAfter = await queue.carriedRequestCount
        XCTAssertEqual(carriedAfter, 0, "dropped when the job ended")
        XCTAssertNotEqual(coordinator.indexEntry(atPath: shot.standardizedFileURL.path)?.status, .done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shot.path), "keeps its name")
    }

    /// Consent review 3, B1 path 2: Process Existing on Clairic, still queued (paused) when the user switches to a
    /// custom endpoint and allows it. The requests are cleared with the switch, and the backlog is not sent there.
    func testACloudflareBacklogIsNotSentToACustomEndpointAllowedLater() async throws {
        let coordinator = makeCoordinator()
        let shot = try XCTUnwrap(coordinator.settings.watchedFolderOverride)
            .appendingPathComponent("Screenshot 2026-11-21 at 14.00.00.png")
        try ConnectionTestImage.payload().data.write(to: shot)
        coordinator.acceptPrivacyStep()
        coordinator.saveClairicSetup(accountID: "acct", token: "tok", agreedThisRun: true)
        coordinator.startServices()
        defer { coordinator.stopServices() }
        coordinator.pauseIndefinitely()
        try await wait { coordinator.isPaused }
        let queued = await coordinator.processExistingScreenshots()
        XCTAssertEqual(queued, 1)
        let queue = try XCTUnwrap(coordinator.queue)
        let carried = await queue.carriedRequestCount
        XCTAssertEqual(carried, 1, "held by the pause, not run yet")
        let clicked = coordinator.processExistingRequests.generation

        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:1"))
        coordinator.updateSettings {
            $0.backend = .customEndpoint
            $0.customEndpointURL = endpoint
            $0.customModelName = "m"
        }
        XCTAssertNotEqual(coordinator.processExistingRequests.generation, clicked,
                          "a request is never carried to another destination")
        coordinator.allowUploads(to: .customEndpoint, endpoint: CustomEndpointIdentity(url: endpoint))
        XCTAssertEqual(coordinator.readiness, .ready)

        var events: [ScreenshotEvent] = []
        let observer = coordinator.addEventObserver { events.append($0) }
        defer { coordinator.removeEventObserver(observer) }
        coordinator.resume()
        try await waitForEvents({ events })
        guard case .processed(let report)? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(report.outcome, .skipped(.awaitingConsent), "taken before the endpoint was allowed")
    }

    /// Process Existing requests are invalidated on any destination change, also a grant change (here: Cloudflare
    /// allowed while a Local request waits), and not by unrelated settings.
    func testProcessExistingRequestsAreInvalidatedWhenTheDestinationChanges() async throws {
        let coordinator = makeCoordinator()
        let watched = try XCTUnwrap(coordinator.settings.watchedFolderOverride)
        try ConnectionTestImage.payload().data.write(to: watched.appendingPathComponent("Screenshot 2026-11-21 at 15.00.00.png"))
        coordinator.chooseLocalBackend(ModelCatalog.inkling2bit)
        coordinator.pauseIndefinitely()
        try await wait { coordinator.isPaused }
        let clicked = coordinator.processExistingRequests.generation
        _ = await coordinator.processExistingScreenshots()
        let queue = try XCTUnwrap(coordinator.queue)
        let carried = await queue.carriedRequestCount
        XCTAssertEqual(carried, 1)
        let request = try XCTUnwrap(coordinator.processExistingRequests.request(for: .thisMac, madeIn: clicked))
        coordinator.updateSettings { $0.renameEnabled = false }
        XCTAssertNotNil(coordinator.processExistingRequests.authorization(for: request), "an unrelated setting keeps it")
        coordinator.allowUploads(to: .cloudflare, endpoint: nil)
        XCTAssertNil(coordinator.processExistingRequests.authorization(for: request), "a grant change invalidates it")
    }

    /// Review 4 nit: a destination change during the folder scan queues nothing and says so.
    func testProcessExistingSaysSoWhenTheDestinationChangedDuringTheScan() async throws {
        let coordinator = makeCoordinator()
        let watched = try XCTUnwrap(coordinator.settings.watchedFolderOverride)
        try ConnectionTestImage.payload().data.write(to: watched.appendingPathComponent("Screenshot 2026-11-21 at 16.00.00.png"))
        coordinator.chooseLocalBackend(ModelCatalog.inkling2bit)
        coordinator.pauseIndefinitely()
        try await wait { coordinator.isPaused }
        coordinator.afterProcessExistingScan = { coordinator.updateSettings { $0.backend = .clairic } }
        let queued = await coordinator.processExistingScreenshots()
        XCTAssertEqual(queued, 0)
        XCTAssertEqual(coordinator.lastMessage, "The destination changed. Run Process Existing again.")
        let queue = try XCTUnwrap(coordinator.queue)
        let count = await queue.queuedCount
        XCTAssertEqual(count, 0, "nothing queued")
    }

    /// Review N3: only this run's "I Agree" allows Cloudflare, not a flag saved by an earlier run.
    func testSaveClairicSetupGrantsOnlyWithThisRunsAgreement() {
        let coordinator = makeCoordinator()
        coordinator.acceptPrivacyStep() // an earlier run
        coordinator.saveClairicSetup(accountID: "acct", token: "tok", agreedThisRun: false)
        XCTAssertNil(coordinator.settings.grant(for: .cloudflare))
        XCTAssertEqual(coordinator.readiness, .needsConsent)
        coordinator.saveClairicSetup(accountID: "acct", token: "", agreedThisRun: true)
        XCTAssertNotNil(coordinator.settings.grant(for: .cloudflare))
        XCTAssertEqual(coordinator.readiness, .ready)
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
        XCTAssertNotNil(model.flow.tryItOpenedAt)
        XCTAssertEqual(result.newName, "Tweet semiconductor flashcards.png")
        XCTAssertEqual(result.hashtags, ["#semiconductor", "#flashcards"])
        XCTAssertEqual(model.current.primary.title, "Continue")

        model.stop()
        model.flow.tryIt = .waiting(note: nil)
        coordinator.handle(event)
        XCTAssertEqual(model.flow.tryIt, .waiting(note: nil), "no events after the window closed")
    }

    func testABacklogFileFinishingInStepFourIsNotShown() throws {
        let coordinator = makeCoordinator()
        let model = makeModel(coordinator)
        coordinator.updateSettings { $0.backend = .localInkling }
        model.pressPrimary()
        model.flow.consentChecked = true
        model.pressPrimary()
        model.pressPrimary()
        XCTAssertEqual(model.flow.step, .tryIt)
        let final = URL(fileURLWithPath: "/d/Old receipt.png")
        _ = try XCTUnwrap(coordinator.index).save(IndexedScreenshot(
            path: final.path, originalFilename: "Screenshot 2026-11-01 at 09.00.00.png", contentHash: "old",
            capturedAt: Date().addingTimeInterval(-3_600), tags: ["receipt"], status: .done))
        coordinator.handle(.processed(ProcessingReport(
            originalURL: URL(fileURLWithPath: "/d/Screenshot 2026-11-01 at 09.00.00.png"),
            outcome: .processed(finalURL: final, renamed: true, moved: false))))
        XCTAssertEqual(model.current.tryIt, .waiting(note: nil), "taken an hour before step 4 opened")
        model.stop()
    }

    func testAStaleTestResultIsDropped() async throws {
        var services = Fixtures.setupServices()
        services.testClairic = { _, _ in
            try? await Task.sleep(for: .milliseconds(100))
            return .success("")
        }
        let model = SetupModel(services: services)
        model.accountID = "acct"
        model.tokenDraft = "first"
        model.runTest()
        model.tokenDraft = "second" // edited while the test runs
        XCTAssertEqual(model.test, .idle)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(model.test, .idle, "the result for the old token is not shown")

        model.runTest()
        for _ in 0..<100 where model.test == .running { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.test, .succeeded)
    }

    func testTheKeychainIsReadOncePerCredentialsChange() {
        var reads = 0
        var revision = 0
        var services = Fixtures.setupServices()
        services.hasSavedToken = { reads += 1; return true }
        services.credentialsRevision = { revision }
        let model = SetupModel(services: services)
        for _ in 0..<5 { _ = model.current }
        XCTAssertEqual(reads, 1)
        revision = 1
        XCTAssertTrue(model.current.inputs.hasSavedToken)
        XCTAssertEqual(reads, 2)
    }

    func testCustomEndpointRerunKeepsTheBackend() {
        let coordinator = makeCoordinator()
        coordinator.updateSettings {
            $0.backend = .customEndpoint
            $0.customEndpointURL = URL(string: "http://gpu-box.lan:8080")
            $0.customModelName = "m"
            $0.hasSeenPrivacyNotice = true
        }
        coordinator.setSecret("tok", for: .cloudflareAPIToken)
        coordinator.updateSettings { $0.clairicAccountID = "acct" }
        let model = makeModel(coordinator)
        XCTAssertEqual(model.flow.choice, .customEndpoint)
        XCTAssertFalse(model.flow.consentChecked, "ticked only when Cloudflare was allowed before")
        model.pressPrimary()
        model.flow.consentChecked = true
        model.pressPrimary()
        XCTAssertEqual(model.current.primary.title, "Continue")
        model.pressPrimary() // Return on step 3
        XCTAssertEqual(coordinator.settings.backend, .customEndpoint, "not silently switched to Clairic")
        XCTAssertNil(coordinator.settings.grant(for: .cloudflare), "a re-run that keeps Custom grants Cloudflare nothing")
        model.stop()
    }

    func testCustomEndpointNeedsItsOwnConsentForItsEndpoint() {
        let coordinator = makeCoordinator()
        coordinator.allowUploads(to: .cloudflare, endpoint: nil)
        coordinator.updateSettings {
            $0.backend = .customEndpoint
            $0.customEndpointURL = URL(string: "http://gpu-box.lan:8080")
            $0.customModelName = "m"
        }
        XCTAssertEqual(coordinator.readiness, .needsConsent)
        let request = BackendGate.consentRequest(for: coordinator.settings)
        XCTAssertEqual(request?.prompt, "Screenshots will be sent to http://gpu-box.lan:8080")
        // The URL changed while the dialog was open: "Allow" grants nothing.
        coordinator.updateSettings { $0.customEndpointURL = URL(string: "http://gpu-box.lan:9090") }
        coordinator.allowUploads(to: .customEndpoint, endpoint: request?.endpoint)
        XCTAssertEqual(coordinator.readiness, .needsConsent)
        coordinator.updateSettings { $0.customEndpointURL = URL(string: "http://gpu-box.lan:8080") }
        coordinator.allowUploads(to: .customEndpoint, endpoint: request?.endpoint)
        XCTAssertEqual(coordinator.readiness, .ready)
        coordinator.updateSettings { $0.customEndpointURL = URL(string: "http://gpu-box.lan:9090") }
        XCTAssertEqual(coordinator.readiness, .needsConsent, "another port is another endpoint: asked again")
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
