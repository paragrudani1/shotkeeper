import AppKit
import ShotkeeperCore
import SwiftUI
import XCTest
@testable import Shotkeeper

/// Settings (PR 4) and the shortcut recorder. Each entry is rendered light and dark by `SettingsSnapshotsTests`.
/// Add a state with ONE line here (see `UISnapshotCatalog`).
@MainActor
enum SettingsSnapshots {
    static var all: [UISnapshot] {
        [
            // Settings (PR 4): each tab under a drawn stand-in for the scene's toolbar (snapshots cannot draw the
            // real window toolbar). General is drawn taller than the window so the whole form shows.
            UISnapshot("settings-general") { Fixtures.settings(.general) },
            UISnapshot("settings-general-kebab-date") { Fixtures.settings(.general, kebabWithDate: true) },
            UISnapshot("settings-model-clairic") { Fixtures.settings(.model) },
            UISnapshot("settings-model-custom-consent") { Fixtures.settings(.model, backend: .customEndpoint) },
            UISnapshot("settings-model-openrouter-consent") { Fixtures.settings(.model, backend: .openRouter) },
            UISnapshot("settings-model-openrouter-other-model-consent") {
                Fixtures.settings(.model, backend: .openRouter, openRouterAllowed: true, openRouterAdvanced: true,
                                  openRouterModel: "vendor/other-model")
            },
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
}

@MainActor
final class SettingsSnapshotsTests: XCTestCase {
    func testRenderSettingsInLightAndDark() throws {
        try UISnapshotWriter.write(SettingsSnapshots.all)
    }
}

@MainActor
extension Fixtures {
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
        let coordinator = AppCoordinator.forTesting(in: folder, credentials: credentials)
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
                         openRouterAdvanced: Bool = false, openRouterModel: String? = nil) -> some View {
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
            settings.openRouterModel = openRouterModel
            if openRouterAllowed {
                settings.uploadGrants = [.init(destination: .openRouter, grantedAt: now,
                                               openRouterModel: OpenRouterBackend.defaultModel)]
            }
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
