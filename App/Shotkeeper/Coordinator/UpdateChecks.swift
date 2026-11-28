import Foundation
import Observation
import Sparkle

/// "Check for Updates…" (auto-update spec, "The menu item and where update code lives"; ticket 07). The only file
/// that imports Sparkle (`scripts/lint.sh` rule `sparkle-import`). A thin pass-through to Sparkle's standard updater
/// and its standard windows, so it has no unit tests (spec, Testing Decisions); the menu's rows and snapshots cover
/// what the user sees.
///
/// Checks are manual only (Parag, 2026-11-28; docs/wiki/workflow.md): App/project.yml sets `SUEnableAutomaticChecks`,
/// `SUAutomaticallyUpdate` and `SUAllowsAutomaticUpdates` to false, and nothing here starts a background check.
/// Sparkle 2.10.1 refuses to start without `SUPublicEDKey` while `SUVerifyUpdateBeforeExtraction` is true
/// (`SPUUpdater.m` `checkIfConfiguredProperlyAndRequireFeedURL:`); the key arrives with ticket 08.
@MainActor
@Observable
final class UpdateChecks {
    /// Mirrors `SPUUpdater.canCheckForUpdates`, which is KVO compliant (Sparkle "Setting up Sparkle
    /// programmatically", https://sparkle-project.org/documentation/programmatic-setup/ ). False until the updater
    /// has started, and while a check or an install runs; the menu row is disabled then.
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// Creates and starts the one updater. Called from `AppCoordinator.startServices()`. Never in unit tests: they
    /// run hosted in the app and call `startServices()` on test coordinators.
    func start() {
        guard controller == nil, !RuntimeEnvironment.isRunningUnitTests else { return }
        // Created with startingUpdater: false and started after the observer is in place, so no change of
        // canCheckForUpdates is missed (programmatic-setup: "pass false to startingUpdater and call .startUpdater()
        // later"). A start-up failure is logged and shown by Sparkle itself (SPUStandardUpdaterController.h).
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            // Hop to the main actor rather than assume it: KVO calls back on the thread that made the change.
            Task { @MainActor in self?.syncCanCheckForUpdates() }
        }
        controller.startUpdater()
        syncCanCheckForUpdates()
    }

    /// Sparkle's manual check: its standard window shows "up to date", the update, or the error.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private func syncCanCheckForUpdates() {
        canCheckForUpdates = controller?.updater.canCheckForUpdates ?? false
    }
}
