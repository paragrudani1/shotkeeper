import AppKit
import ShotkeeperCore
import SwiftUI
import XCTest
@testable import Shotkeeper

/// First-run setup (PR 3) and the app icon it shows. Each entry is rendered light and dark by `SetupSnapshotsTests`.
/// Add a state with ONE line here (see `UISnapshotCatalog`).
@MainActor
enum SetupSnapshots {
    static var all: [UISnapshot] {
        [
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
                Fixtures.setup(.connect, choice: .openRouter, test: .succeeded, openRouterKey: "fake")
            },
            UISnapshot("setup-3-openrouter-out-of-credits") {
                Fixtures.setup(.connect, choice: .openRouter, test: .failed(
                    ConnectionTestText.failure(AnalyzerError.accountState(OpenRouterBackend.outOfCreditsText),
                                               backend: .openRouter)),
                               openRouterKey: "fake")
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
        ]
    }
}

@MainActor
final class SetupSnapshotsTests: XCTestCase {
    func testRenderSetupInLightAndDark() throws {
        try UISnapshotWriter.write(SetupSnapshots.all)
    }
}

@MainActor
extension Fixtures {
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
                      openRouterKey: String = "") -> some View {
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
        model.test = test
        return SetupView(model: model)
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
}
