# 07: Sparkle 2.10.1 and the "Check for Updates…" menu row

**What to build:** the Shotkeeper menu has a **Check for Updates…** row between "About Shotkeeper" and "Quit
Shotkeeper". Choosing it closes the panel, brings Sparkle's standard window to the front (Dock-less app) and runs a
manual check. The row is disabled while a check or install runs and skipped by ↑/↓. The app never checks on its own
and never asks "Check for updates automatically?". Sparkle is pinned with `exactVersion: 2.10.1`, linked by the app
target only, and imported in one file only.

**Blocked by:** PR #10 merged (it creates `Coordinator/` with its part-per-file convention, the per-screen
`MenuSnapshots`, and `scripts/lint.sh`); 06 (so Sparkle's helpers are signed inside-out from the first build that
contains them, never with `--deep`).

**Status:** ready-for-agent

**Sources:** spec "Dependency", "The menu item and where update code lives", "Info.plist keys", stories 4–8, 15–16,
33, 35–36; Testing Decisions, seams 2 and 3; PR #10's `docs/wiki/prefactor-app.md` ("Update checks (feature 8)").

**Test seams:** seam 2, `MenuViewState.rows` and the menu snapshot catalog (prior art `ToastAndMenuTests` row order,
`MenuSnapshots`); seam 3, the CI plist check. `UpdateChecks` is deliberately not unit-tested (thin pass-through to
Sparkle).

- [ ] `App/project.yml`: Sparkle package `exactVersion: 2.10.1`, app target only. The root `Package.swift` is
      unchanged (Linux build unaffected).
- [ ] `UpdateChecks` in its own file under `Coordinator/`: one `SPUStandardUpdaterController` with
      `startingUpdater: false`, started from `AppCoordinator.startServices()`, not started under
      `RuntimeEnvironment.isRunningUnitTests`; observable `canCheckForUpdates` mirrored from KVO; `checkForUpdates()`.
      Owned as `coordinator.updates`.
- [ ] `MenuRowID.checkForUpdates`; row after the divider, between About and Quit; no shortcut; disabled when
      `canCheckForUpdates` is false; shown before setup. `AppDelegate.perform(.checkForUpdates)` closes the panel,
      `NSApp.activate()` as `.about` does, then checks.
- [ ] Info.plist keys (all in `project.yml`): `SUFeedURL`
      (`https://github.com/paragrudani1/shotkeeper/releases/latest/download/appcast.xml`),
      `SUEnableAutomaticChecks` false, `SUAutomaticallyUpdate` false, `SUAllowsAutomaticUpdates` false (confirm the
      key and its effect in Sparkle's docs [S3] and cite them; the research doesn't cover it),
      `SUVerifyUpdateBeforeExtraction` true. **`SUPublicEDKey` is added in 08**, when Parag's key exists.
- [ ] Before merging, read Sparkle 2.10.1's updater start-up checks and cite them: does the updater start without
      `SUPublicEDKey` (unsigned-by-Team-ID app)? If it refuses to start or shows an error at launch, **stop and
      report**: then 07 waits for 03 and merges together with 08, instead of shipping a broken row.
- [ ] Plist check script (shared with 09's build step 4): the built app's `SUEnableAutomaticChecks` is false and
      `SUFeedURL` is present and non-empty, and optionally the expected `CFBundleVersion` /
      `CFBundleShortVersionString`. `macos-app` runs it after signing (expects 0.1.0 / 1). 08 turns on the
      `SUPublicEDKey` check.
- [ ] `scripts/lint.sh` rule `sparkle-import`: `import Sparkle` only in the `UpdateChecks` file, with a self-test case.
- [ ] Tests: row order (About, Check for Updates…, Quit); disabled row is not in the ↑/↓ order. New snapshots,
      light and dark: the menu with the row enabled and disabled.
- [ ] Docs: dated line in `docs/wiki/architecture.md` beside "No third-party dependencies" (Sparkle 2.10.1, pinned,
      app target only, approved by Parag 2026-11-28, the only exception); matching AGENTS.md layout line; wiki
      `auto-update.md` lines. Upgrading Sparkle is its own PR with the real-Mac checks.
- [ ] Linux tests and `scripts/lint.sh` green.
- [ ] **Done only when `macos-app` CI is green** on the PR, with the signing script signing Sparkle's items
      (visible in the log) and the plist check passing.

**Real-Mac checks** (on the CI artifact; spec real-Mac checks 2–5, 8): the update window comes to the front over other
apps; the row is disabled during a check and enabled afterwards; across several launches no update window appears
unprompted and `defaults read dev.shotkeeper.Shotkeeper SULastCheckTime` has no value until the first manual check;
offline, the check shows an error and screenshots still process. Before the first release exists the feed URL 404s,
so an error is the expected result online too; checks 1 and 6 wait for ticket 13.
