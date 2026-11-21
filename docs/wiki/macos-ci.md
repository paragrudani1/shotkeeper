# macOS CI

Workflow: `.github/workflows/ci.yml` (added on branch `app/phase1`, 2026-11-21). Read runs with
`/root/local-dev/shotkeeper-llm/bin/gh-shotkeeper run list|view --log-failed` (plain `gh` cannot see the repo).

## Jobs
- `linux-core`: container `swift:6.4.3-noble` + `libsqlite3-dev`; `swift build`, then `scripts/ci-swift-test.sh`.
- `macos-app` (`macos-latest`): newest non-beta `/Applications/Xcode_*.app` via `xcode-select`; package tests;
  `brew install xcodegen`; `xcodegen generate --spec App/project.yml`; `xcodebuild build` (Release) and
  `xcodebuild test` (Debug), both `CODE_SIGNING_ALLOWED=NO`; ad-hoc `codesign --sign -` of the Release app;
  `ditto -c -k --keepParent` → artifact `Shotkeeper-unsigned`.
- Caches: SwiftPM `.build` only (keyed by Xcode version and source hashes). DerivedData is not cached.

## Lessons
- 2026-11-21: `swift test` fails with "no tests found" while `Tests/ShotkeeperCoreTests` holds no Swift files (true on
  main then). `scripts/ci-swift-test.sh` falls back to `swift build --build-tests` with a `::warning::` in that case only.
- 2026-11-21: the artifact is ad-hoc signed, not notarized. On a Mac: unzip, `xattr -dr com.apple.quarantine Shotkeeper.app`,
  then open. `SMAppService.mainApp.register()` needs the app in /Applications (else status `notFound`).
- 2026-11-21: unit tests run hosted in the app (`TEST_HOST`); `AppDelegate` skips hotkey/watch setup when XCTest is loaded.
