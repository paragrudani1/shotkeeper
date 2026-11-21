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
