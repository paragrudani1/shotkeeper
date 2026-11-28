# Architecture

- 2026-11-21 (contract commit, see `git log`): SwiftPM package `Shotkeeper`, tools 6.0, macOS 14.
  - `ShotkeeperCore`: Foundation-only, builds on Linux. Clairic + local analyzers, filename sanitizer, file organizer, undo log,
    SQLite FTS5 index, processing queue, pipeline, settings model, model-runtime planning logic (quant picker, command lines).
  - `CSQLite`: system module for Linux only; Apple platforms `import SQLite3`. No third-party dependencies (decided to cut CI risk).
  - `shotkeeper-cli`: Linux-capable CLI used to run live analyzer calls from this box.
  - macOS app (XcodeGen `project.yml`): AppKit/SwiftUI, FSEvents watcher, ImageIO downscale, xattrs, Keychain, SMAppService,
    hotkey, process management for `mlx_lm.server`. Depends on the local package.
- Seams in core (protocols the app implements): `ScreenshotAnalyzer`, image preparation, file-metadata writing (xattrs), credentials,
  clock/sleep for queue tests, HTTP transport for analyzer tests.
- 2026-11-21 (app phase 1, branch `app/phase1`): the app target `Shotkeeper` builds in **Swift 6 language mode**
  (`SWIFT_VERSION: "6.0"` in `App/project.yml`). C callbacks (FSEvents, Carbon hotkey) are file-level nonisolated
  functions; Carbon hops to the main actor with `Task { @MainActor in … }`. Lock-protected classes
  (`ManagedProcess`, `RotatingLogFile`, `FolderWatcher`'s queue confinement) use `@unchecked Sendable`.
- 2026-11-21: platform services live in `App/Shotkeeper/Platform/`. `ImageIODownscaler`, `XattrMetadataWriter` and
  `KeychainCredentialStore` match the core protocols `ImagePreparer`, `FileMetadataWriter`, `CredentialStore`
  (unmerged on that date) but do not declare conformance; phase 2 adds it. Keychain keys are `String` until then
  (phase 2 passes `CredentialKey.rawValue`).
- 2026-11-21 (app phase 2, PR #1): the platform types now declare conformance (`ImageIODownscaler: ImagePreparer`,
  `XattrMetadataWriter: FileMetadataWriter` using core's `FinderMetadata` payloads, `KeychainCredentialStore:
  CredentialStore` keyed by `CredentialKey`). App wiring: [app-implementation](app-implementation.md).
- 2026-11-21: first complete version on `main` at `c53afa2` (PRs #1 app, #2 app review fixes). CI run 44908642660 green:
  `linux-core` (170 core tests) and `macos-app` (package tests + app tests, artifact `Shotkeeper-unsigned`).
  Not yet verified: a live Clairic call (no credentials), any run on a real Mac, the local MLX runtime.
- 2026-11-28: **Minimum raised to macOS 15** (Parag, wave 3 decision D1, against the recommendation to keep 14).
  Source: the 2026-11-28 "Wave 3 decisions" line in [workflow](workflow.md), on branch `t3/roadmap-2026-11` until it
  merges. Changed: `Package.swift` `.macOS(.v15)`, `App/project.yml` deployment target 15.0, the CI actool
  `--minimum-deployment-target`, README and the AGENTS.md availability example. No `#available`/`@available(macOS …)`
  checks existed, so none were removed. Supersedes story 50 of the wave 1 spec ("as a user on macOS 14") and the
  "Vision runs on macOS 14" check in wave 1 ticket 04: there are no macOS 14 users now. Research notes that say
  "targets 14.0" are dated snapshots and stay as written.
