# macOS CI

Workflow: `.github/workflows/ci.yml` (added on branch `app/phase1`, 2026-11-21). Read runs with
`/root/local-dev/shotkeeper-llm/bin/gh-shotkeeper run list|view --log-failed` (plain `gh` cannot see the repo).

## Jobs
- `linux-core`: container `swift:6.4.3-noble` + `libsqlite3-dev`; `swift build`, then `swift test`.
  2026-11-28 (`3e34e7f`): first step "Lint (scripts/lint.sh)": `--self-test`, then the rules (see
  [prefactor-app](prefactor-app.md)).
- `macos-app` (`macos-latest`): newest non-beta `/Applications/Xcode_*.app` via `xcode-select`; package tests;
  `brew install xcodegen`; `xcodegen generate --spec App/project.yml`; `xcodebuild build` (Release) and
  `xcodebuild test` (Debug), both `CODE_SIGNING_ALLOWED=NO`; ad-hoc `codesign --sign -` of the Release app;
  `ditto -c -k --keepParent` → artifact `Shotkeeper-unsigned`.
- Caches: SwiftPM `.build` only (keyed by Xcode version and source hashes). DerivedData is not cached.

## UI snapshots (added 2026-11-21, UI polish PR 1)
No agent has a Mac, so CI renders SwiftUI views to PNGs and uploads them as the artifact `Shotkeeper-ui-snapshots`.
- Where: `App/ShotkeeperAppTests/UISnapshotTests.swift`. `UISnapshotCatalog.all` lists the views; **adding a view is one
  line**: `UISnapshot("search-empty") { SearchView(...) },`. Each entry is rendered in light and dark mode
  (`<name>-light.png`, `<name>-dark.png`) at 2×, on a neutral backdrop with a soft shadow.
  2026-11-28 (`89a06df`): one file per screen: `ToastSnapshots.swift`, `MenuSnapshots.swift`, `SearchSnapshots.swift`,
  `SetupSnapshots.swift`, `SettingsSnapshots.swift`, each with its catalog (`<Screen>Snapshots.all`), its fixtures
  (`extension Fixtures`) and one test (`<Screen>SnapshotsTests`). Add a state with one line in that screen's `all`; a new
  screen gets a file and one term in `UISnapshotCatalog.all`. Shared code (renderer, `UISnapshotWriter`, `Fixtures.now`)
  stays in `UISnapshotTests.swift`; `UISnapshotCatalogTests` fails on a repeated name. PNG names are unchanged.
- How: `NSHostingView` in an offscreen borderless `NSWindow` with the appearance set, then
  `cacheDisplay(in:to:)` into a 2× `NSBitmapImageRep` (`SnapshotRenderer`). This draws AppKit-backed controls
  (TextField, ProgressView, buttons) too, which `ImageRenderer` does not. Behind-window materials cannot be captured
  offscreen, so views take an `opaqueBackground` flag that draws `windowBackgroundColor` instead of the panel's blur.
- Fake data only: `Fixtures` (fixed date 2026-11-21 16:24 UTC, en_US) and `FakeThumbnails` (generated images injected via
  the `thumbnailSource` environment value; `cached` returns them synchronously so the first render shows them).
- Output dir: env `SHOTKEEPER_SNAPSHOT_DIR`, which the workflow sets as `TEST_RUNNER_SHOTKEEPER_SNAPSHOT_DIR` (xcodebuild
  strips the prefix for the test process); fallback `/tmp/shotkeeper-ui-snapshots`, which the "Collect UI snapshots"
  step copies if the env did not arrive. The test fails if an image looks blank (fewer than 9 colors on a sample grid).
- Look at them: `mkdir -p /tmp/sk-snap-<run> && gh-shotkeeper run download <run-id> -n Shotkeeper-ui-snapshots -D
  /tmp/sk-snap-<run>`, open the PNGs with the Read tool, then delete the folder.
- 2026-11-22 (UI polish PR 4, `0145a1e`): the step "Check the app icon in the bundle" (after "Collect UI snapshots")
  fails if the Release app lacks `AppIcon.icns`/`Assets.car`, and adds the icns PNGs to the snapshot artifact as
  `bundle-icon_*.png`. Snapshot `app-icon-asset` is the hosting app's own icon.
- 2026-11-22 (`0bcdb15`): the step "Compile the Icon Composer icon (actool)" runs `xcrun actool` on
  `AppIcon.icon` + `Assets.xcassets` (the target's inputs) and fails on any warning/error; it also logs two
  informational variants and `assetutil --info`, and adds `actool-<variant>-icon_*.png` to the snapshot artifact.

## Lessons
- 2026-11-21: `swift test` fails with "no tests found" while `Tests/ShotkeeperCoreTests` holds no Swift files (true on
  main then). `scripts/ci-swift-test.sh` fell back to `swift build --build-tests` in that case only.
  Superseded 2026-11-21: core tests landed on main (169 tests at `6f1f98c`); the script was removed and CI runs plain `swift test`.
- 2026-11-21: the artifact is ad-hoc signed, not notarized. On a Mac: unzip, `xattr -dr com.apple.quarantine Shotkeeper.app`,
  then open. `SMAppService.mainApp.register()` needs the app in /Applications (else status `notFound`).
- 2026-11-21: unit tests run hosted in the app (`TEST_HOST`); `AppDelegate` skips hotkey/watch setup when XCTest is loaded.
- 2026-11-21 (PR #1, first compile of `App/`): the Release app built on the first try; only the test target failed.
  `bind(...)` inside an `XCTestCase` resolves to NSObject's KVO `bind(_:to:withKeyPath:options:)`; call `Darwin.bind`.
- 2026-11-21: `SearchPanel()` compiled but silently called NSWindow's inherited `init()` instead of the convenience
  `init(size: = default)`, so the panel was neither floating nor non-activating. An exact `init()` match beats a
  defaulted-argument init: give AppKit-subclass convenience inits a required label (`init(contentSize:)`).
- 2026-11-21: Swift 6 region isolation: inside an actor, `let fm = FileManager.default; a(fm) && b(fm)` fails with
  "sending 'fm' risks causing data races" (the `&&` autoclosure captures a non-Sendable value). Call
  `FileManager.default` per use. Region errors are SIL diagnostics: they appear only after type errors are fixed.
- 2026-11-21: the core test `testConcurrencyRunsJobsInParallel` was timing-based (`settle(50)` yields) and failed on the
  2-core Linux runner (run 44904349330); it now uses a rendezvous with a 5 s fallback (commit `64a0c85`).
- 2026-11-21: a full green `macos-app` run takes ~1.5–3 min (SwiftPM cache hit); app tests run hosted with a temp
  support folder and `InMemoryCredentialStore` (`AppDelegate.init` checks `RuntimeEnvironment.isRunningUnitTests`).
  The Keychain tests ran (not skipped) on `macos-latest`.
- 2026-11-21: `gh run view` lists ARTIFACTS a few seconds after the run completes; check the job log
  ("Artifact Shotkeeper-unsigned has been successfully uploaded") before concluding the upload failed.

- 2026-11-28 (prefactor-app runs 46127111976 and 46127989839, same app code): `search-results-light.png` drew the results
  list with a legacy-scroller gutter in one run and without it in the other; the other 169 PNGs were byte-identical to
  main (run 45052894155). The gutter is render timing, not a code change: when comparing snapshot runs, a width
  change of the list rows in `search-results-*` alone is this flake.

## Outages
- 2026-11-21 ~20:07 UTC: from run 44944596470 on, every job of every run failed in about 2 s with no runner and
  zero steps, including re-runs (PR #6, heads `80113d7` and `b9a7009`). The PAT gets 403 on billing and check
  annotations, so the cause could not be read; an exhausted Actions minutes/spending limit is suspected (private
  repo, macOS minutes count 10×). Reported to Parag; no workaround per AGENTS.md. Diagnose with the job's
  `runner_name` empty and `steps` length 0 in `gh-shotkeeper api repos/paragrudani1/shotkeeper/actions/runs/<id>/jobs`.
