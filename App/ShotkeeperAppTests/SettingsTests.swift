import AppKit
import Security
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

/// Settings (UI polish PR 4): the search shortcut, the local model's disk check and download stats, and the small
/// rules behind the tabs.
@MainActor
final class SettingsBehaviourTests: TempDirectoryTestCase {
    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(supportDirectory: directory.appendingPathComponent("support"), credentials: InMemoryCredentialStore(),
                       physicalMemoryBytes: 16 * 1_073_741_824,
                       applicationSupport: directory, logDirectory: directory.appendingPathComponent("logs"))
    }

    private let taken = HotKeyShortcut(keyCode: KeyCode.k, modifiers: [.control, .option])
    private let free = HotKeyShortcut(keyCode: KeyCode.j, modifiers: [.control, .option])

    func testChangingTheShortcutSavesOnlyWhatRegistered() {
        let coordinator = makeCoordinator()
        var attempts: [HotKeyShortcut] = []
        coordinator.registerSearchShortcut = { shortcut in
            attempts.append(shortcut)
            return shortcut == self.taken ? .registrationFailed(inUseByAnotherApp: true) : nil
        }
        coordinator.startSearchShortcut()
        XCTAssertEqual(coordinator.activeSearchShortcut, .defaultSearch)

        XCTAssertEqual(coordinator.changeSearchShortcut(to: taken), .registrationFailed(inUseByAnotherApp: true))
        XCTAssertEqual(coordinator.settings.searchShortcut, .defaultSearch, "not saved")
        XCTAssertEqual(coordinator.activeSearchShortcut, .defaultSearch, "the old one is still the active one")

        let spotlight = HotKeyShortcut(keyCode: KeyCode.space, modifiers: [.command])
        XCTAssertEqual(coordinator.changeSearchShortcut(to: spotlight), .system(name: "Spotlight"))
        XCTAssertFalse(attempts.contains(spotlight), "known system shortcuts are refused before registering")

        XCTAssertNil(coordinator.changeSearchShortcut(to: free))
        XCTAssertEqual(coordinator.settings.searchShortcut, free)
        XCTAssertEqual(coordinator.activeSearchShortcut, free)
        XCTAssertEqual(MenuViewState.make(from: coordinator).searchShortcut, "⌃⌥J", "the menu shows the new shortcut")
        XCTAssertEqual(SettingsStore(fileURL: AppPaths.settingsFile(in: directory.appendingPathComponent("support")))
            .current.searchShortcut, free, "saved to the settings file")
    }

    func testAShortcutRefusedAtLaunchIsReportedAndNotShown() {
        let coordinator = makeCoordinator()
        coordinator.registerSearchShortcut = { _ in .registrationFailed(inUseByAnotherApp: true) }
        coordinator.startSearchShortcut()
        XCTAssertNil(coordinator.activeSearchShortcut)
        XCTAssertEqual(coordinator.searchShortcutProblem, "Another app already uses ⌥⌘S. Choose another shortcut.")
        XCTAssertNil(MenuViewState.make(from: coordinator).searchShortcut, "no shortcut shown that does not work")
        coordinator.registerSearchShortcut = { _ in nil }
        XCTAssertNil(coordinator.changeSearchShortcut(to: free))
        XCTAssertNil(coordinator.searchShortcutProblem)
    }

    func testRecorderKeepsRecordingAfterAProblemAndStopsOnSuccess() {
        var answers: [HotKeyProblem?] = [.registrationFailed(inUseByAnotherApp: true), nil]
        let model = ShortcutRecorderModel { _ in answers.removeFirst() }
        model.start()
        XCTAssertEqual(model.phase, .recording)
        XCTAssertTrue(GlobalHotKey.isSuspended, "the current shortcut does not open Search while recording")
        model.receive(taken)
        XCTAssertEqual(model.phase, .recording)
        XCTAssertEqual(model.problem, "Another app already uses ⌃⌥K. Choose another shortcut.")
        model.receive(free)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.problem)
        XCTAssertFalse(GlobalHotKey.isSuspended)
    }

    func testChangeShortcutRequestIsTakenOnce() {
        let navigation = SettingsNavigation()
        XCTAssertFalse(navigation.takeRecordShortcutRequest())
        navigation.recordShortcutRequest += 1
        XCTAssertTrue(navigation.takeRecordShortcutRequest())
        XCTAssertFalse(navigation.takeRecordShortcutRequest(), "reopening General later does not record again")
    }

    func testInstallRefusesWhenTheDiskIsTooFull() async {
        let coordinator = makeCoordinator()
        coordinator.availableDiskBytes = { _ in 3_000_000_000 }
        await coordinator.installLocalModel(ModelCatalog.inkling2bit)
        let problem = try? XCTUnwrap(coordinator.localInstallProblem)
        XCTAssertTrue(problem?.hasPrefix("Not enough disk space: the download needs about 13.4 GB free") == true, problem ?? "")
        XCTAssertEqual(coordinator.runtimePhase, .notInstalled, "nothing was started")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Shotkeeper/runtime/models").path))
    }

    func testDownloadStatsFollowTheDownloadPhase() {
        let coordinator = makeCoordinator()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.recordDownloadBytes(1, at: start)
        XCTAssertNil(coordinator.downloadStats, "only while downloading")
        coordinator.applyRuntimePhase(.downloading(0.1))
        coordinator.recordDownloadBytes(1_000_000_000, at: start)
        coordinator.recordDownloadBytes(1_100_000_000, at: start.addingTimeInterval(10))
        XCTAssertEqual(coordinator.downloadStats?.speedText, "10.0 MB/s")
        XCTAssertEqual(coordinator.downloadStats?.totalBytes, 10_400_000_000, "the selected 2-bit build on 16 GB")
        coordinator.applyRuntimePhase(.ready)
        XCTAssertNil(coordinator.downloadStats)
    }

    func testFilenameExampleAndAboutLinks() {
        XCTAssertEqual(FilenameStyleExample.text(for: FilenameStyle()), "Tweet semiconductor flashcards.png")
        XCTAssertEqual(FilenameStyleExample.text(for: FilenameStyle(casing: .kebab, datePrefix: true)),
                       "2026-11-21-tweet-semiconductor-flashcards.png")
        XCTAssertEqual(AboutLinks.readme.absoluteString, "https://github.com/paragrudani1/shotkeeper#readme")
        XCTAssertEqual(AboutLinks.privacy.fragment, "privacy", "the README heading is \"## Privacy\"")
        XCTAssertEqual(BackendCopy.shortName(for: .localInkling), "Local")
        XCTAssertEqual(ExclusionsSettingsTab.emptyText,
                       "No rules yet. Screenshots that match a rule are never sent, renamed or indexed.")
    }

    /// B1 (review of `9552c66`): the pause while typing a token writes it to the Keychain but must not use it: no
    /// analyzer rebuild, no readiness change (which would start the watcher and resume a held queue). Commit uses it.
    func testAHalfTypedTokenIsSavedButNotUsedUntilCommitted() throws {
        let credentials = InMemoryCredentialStore()
        let coordinator = AppCoordinator(supportDirectory: directory.appendingPathComponent("support"),
                                         credentials: credentials, physicalMemoryBytes: 16 * 1_073_741_824,
                                         applicationSupport: directory, logDirectory: directory.appendingPathComponent("logs"))
        coordinator.updateSettings {
            $0.backend = .clairic
            $0.clairicAccountID = "acct"
            $0.uploadGrants = [.init(destination: .cloudflare, grantedAt: Date())]
        }
        XCTAssertEqual(coordinator.readiness, .notConfigured("Cloudflare API token is not set"))
        let rebuilds = coordinator.analyzerRebuilds

        coordinator.updateSecretDraft("par", for: .cloudflareAPIToken)
        try coordinator.persistSecretDraft(for: .cloudflareAPIToken)
        XCTAssertEqual(try credentials.secret(for: .cloudflareAPIToken), "par", "saved so it is not lost")
        XCTAssertEqual(coordinator.analyzerRebuilds, rebuilds, "no rebuild, so no queue resume")
        XCTAssertTrue(coordinator.currentAnalyzer is UnconfiguredAnalyzer)
        XCTAssertEqual(coordinator.readiness, .notConfigured("Cloudflare API token is not set"), "not ready: no watcher, no resume")

        // Another change that rebuilds still uses the committed (empty) token, not the draft.
        coordinator.updateSettings { $0.clairicAccountID = "acct2" }
        XCTAssertEqual(coordinator.readiness, .notConfigured("Cloudflare API token is not set"))

        coordinator.updateSecretDraft("partial-token-full", for: .cloudflareAPIToken)
        try coordinator.commitSecretDraft(for: .cloudflareAPIToken)
        XCTAssertEqual(try credentials.secret(for: .cloudflareAPIToken), "partial-token-full")
        XCTAssertEqual(coordinator.readiness, .ready, "commit uses it")
        XCTAssertTrue(coordinator.currentAnalyzer is CloudflareClairicAnalyzer)

        // A draft left in the field when the app quits is written and used.
        coordinator.updateSecretDraft("newer", for: .cloudflareAPIToken)
        coordinator.commitAllSecretDrafts()
        XCTAssertEqual(try credentials.secret(for: .cloudflareAPIToken), "newer")
    }

    func testAFailedKeychainWriteIsReported() {
        let coordinator = AppCoordinator(supportDirectory: directory.appendingPathComponent("support"),
                                         credentials: FailingCredentialStore(), physicalMemoryBytes: 16 * 1_073_741_824,
                                         applicationSupport: directory, logDirectory: directory.appendingPathComponent("logs"))
        coordinator.updateSecretDraft("token", for: .cloudflareAPIToken)
        XCTAssertThrowsError(try coordinator.persistSecretDraft(for: .cloudflareAPIToken)) { error in
            XCTAssertEqual(StatusText.describe(error), "The Keychain is locked. Unlock the Mac and try again.")
        }
    }

    func testInstallingComesFromTheRuntimePhase() {
        XCTAssertTrue(LocalInstallState.isInstalling(.downloading(0.3)))
        XCTAssertTrue(LocalInstallState.isInstalling(.installing("step")))
        XCTAssertFalse(LocalInstallState.isInstalling(.starting))
        XCTAssertFalse(LocalInstallState.isInstalling(.ready))
    }
}

private final class FailingCredentialStore: CredentialStore, @unchecked Sendable {
    func secret(for key: CredentialKey) throws -> String? { nil }
    func setSecret(_ value: String, for key: CredentialKey) throws {
        throw KeychainError.status(operation: "SecItemAdd", errSecInteractionNotAllowed)
    }
    func removeSecret(for key: CredentialKey) throws {}
}
