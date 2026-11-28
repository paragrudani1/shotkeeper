# App prefactor: coordinator parts, search keys in core, CI lint (2026-11-28)

Prefactors 4, 5, 8 (app half), 9 and 7 from the roadmap survey ("Conflict hotspots" and "Prefactors" in the survey
of the eight features Parag approved on 2026-11-28). The aim was to let the feature PRs run in parallel without
editing the same lines. Refactor only: no user-visible behaviour changed. Branch `t3/prefactor-app`. The core index and
settings prefactors (1 and 2, and the core row builder) are a separate PR on `t3/prefactor-index`.

## Commits
- `2dda65c` Core: `SearchKeyMap` (the search window's key → action table) and `SearchKeyMapTests`.
- `e164967` App: `CaptureSources`, `FileActions`, Test Connection moved to `ConnectionTest.swift`;
  `SearchResultActions` and `WorkspaceActions` out of `SearchPanel.swift`; the shared test harness.
- `89a06df` App tests: snapshots split per screen.
- `3e34e7f` CI: `scripts/lint.sh` and the `lint-allow` markers; CODING_STANDARDS names the script.

## Coordinator boundaries (2026-11-28, `e164967`)
`AppCoordinator` (841 → ~710 lines) stays the wiring point and the one object views observe. The parts that features
will grow are now their own types. Each type has a small `@MainActor` host protocol, and the coordinator implements
it, so a part never reaches into coordinator internals.
- `FolderCapture` (`coordinator.capture`, `@Observable`; named `CaptureSources` until the review fixes below): the
  watched folder and Process Existing. Watcher, detector, `watchedFolder`, `isWatching`, the re-queue of `pending`
  rows. The coordinator still decides *when* watching starts (`startWatchingIfReady`: services started and
  `BackendGate` ready).
- `FileActions` (`coordinator.fileActions`): `undoLast()`, `undo(ids:)`, `rename(_:to:)`. All three go through
  `ScreenshotProcessor`. Features 4 (re-sort into subfolders), 6 (move to the Bin) and 5 (re-analyse from the search
  window) add their action as an extension in `FileActions+<Feature>.swift`, so the three PRs do not edit one file.
  Re-analyse also needs the queue and a consent change (survey prefactor 6). That PR gives `FileActions` the queue,
  since nothing uses it today.
- Search panel: `SearchResultActions` (open / copy / reveal on the selected result, the missing-file and copy-failed
  pills) is the search-panel action set for features 2, 5 and 6. `WorkspaceActions` (was `SearchActions`) holds the
  `NSWorkspace` and pasteboard calls that the menu's Recent rows use too. `SearchPanelController` keeps the window,
  Quick Look and key dispatch.
- Update checks (feature 8): no code exists yet, so no type was made for it. Add `UpdateChecks` as its own file under
  `Coordinator/`, started from `startServices()`.
- Not moved, because no planned feature changes them: settings and secret drafts, the local model runtime, and
  pipeline events/toasts. The Spotlight sync (feature 3) should follow the index change feed (survey prefactor 3), not
  `handle(_:)`.

## Search keys in core (2026-11-28, `2dda65c`)
- `SearchKeyMap.bindings` is the table: plain keys by virtual key code, ⌘ keys by lower-case ASCII character. The app
  keeps only the `NSEvent` → (key code, modifiers, characters) translation (`extension SearchKeyMap` in
  `SearchPanel.swift`) and `SearchPanelController.handle`.
- Rules the tests enforce (`SearchKeyMapTests`). No trigger maps to two actions. Every ⌘ character has exactly one
  ANSI physical key, so it works on Russian or Greek layouts (docs/wiki/appkit-gotchas.md). ⌘A/V/X/Z (the field's
  editing keys) and ⌘H/M/Q stay free. Each chip keeps ⌘1–⌘7 and its tooltip says so.
- The physical key now comes from core's `KeyCode` table, not from a ten-entry list in the app. Results for every
  bound key are the same. The old app tests moved to core unchanged, and the app keeps a translation test
  (`.function`/`.numericPad` flags ignored, Caps Lock).

## Test helpers (2026-11-28, `e164967`)
- `App/ShotkeeperAppTests/TestHarness.swift`: `TempDirectoryTestCase`, `AppCoordinator.forTesting(in:credentials:memoryGB:)`
  (it replaces nine copies of the init call; the snapshot fixtures use it too), `waitUntil(timeout:_:)`, and
  `ScreenshotRow.make(_:…)`, an `IndexedScreenshot` builder for app tests and snapshots. The core tests get their own
  builder in the index PR; this one is not in core.

## Snapshot split (2026-11-28, `89a06df`)
- One file per screen, with its catalog, fixtures and test (see [macos-ci](macos-ci.md), "UI snapshots"). All 77 names
  and their order are unchanged. `UISnapshotCatalogTests.testSnapshotNamesAreUnique` guards the artifact against two
  screens writing the same PNG.

## CI lint (2026-11-28, `3e34e7f`)
- `scripts/lint.sh` runs first in `linux-core` (`--self-test`, then the check) and runs locally. It is written for
  bash 3.2 and BSD grep (no `\b`, no empty-array expansion) but was only run on Linux. Rules:
  - `core-imports`: an allowlist (Foundation, FoundationNetworking, Dispatch, Darwin, Glibc, SQLite3, CSQLite), not
    a denylist of AppKit/SwiftUI/ImageIO/Security/CoreServices. CoreGraphics or UniformTypeIdentifiers would break the
    Linux build just as surely.
  - `file-op`: `removeItem`/`trashItem`/`moveItem`/`replaceItem(At)` and POSIX `unlink`/`rename*` only in
    `FileOrganizer`, `NoReplaceRename` (its primitive) and `UndoLog`. `UndoLog` has no such call today; it is allowed
    because undo is its job.
  - `analyze`: `.analyze(` only in `ScreenshotProcessor`.
- Exceptions on main at `295df83` are marked on their line with `// lint-allow: <rule> (<why>)`:
  - `file-op`: the app's own files. Log rotation in `ManagedProcess`, `ServerPIDFile`, the settings backup in
    `SettingsStore`, and the downloaded model in `LocalModelRuntime`.
  - `analyze`: the developer CLI, `ManagedLocalAnalyzer` (it forwards its own `analyze`), and Test Connection (a
    generated image).
  - Per-line markers rather than per-file: a new delete in the same file still fails.
- Tests are not linted (they delete their temp folders).

## Feature 7 dropped (2026-11-28)
- Parag dropped feature 7 (clipboard images and screen recordings as capture sources) on 2026-11-28. The capture type
  stays, as it keeps the watcher and Process Existing out of `AppCoordinator`, but it was renamed `FolderCapture`, and
  its doc comment, this page and the PR body no longer promise a home for new sources.

## Review fixes (2026-11-28)
Review of PR 10 at `06d1aea` (no blockers). Branch `t3/prefactor-app-fix`, merged `origin/main` (PR 9) first, no conflicts.
- `scripts/lint.sh`:
  - `core-imports` sees Swift 6 access-level imports (`public`/`package`/`internal`/`fileprivate`/`private import`)
    and every `;`-separated import on a line.
  - `file-op` also matches `recycle(` (`NSWorkspace`), `unlinkat(`, `rmdir(`, `Darwin.`/`Glibc.`/`Foundation.remove(`
    (not `Array.remove(at:)`) and whitespace before `(`. Feature 6 (move to the Bin) will hit it with `recycle` or
    `trashItem` and must live in, or go through, `FileOrganizer`.
  - Allow markers count only as the line's trailing `// lint-allow: <rule> (<why>)` with a non-empty reason. A marker
    in a string literal, in a `/* */` mid-line, or without a reason fails (self-test cases for each). All existing
    markers already had that form.
  - The header lists the blind spots: a line starting with a comment is skipped (code after `*/` too), method
    references without a call, and a call split across lines.
  - ~~`macos-app` runs `/bin/bash scripts/lint.sh --self-test && /bin/bash scripts/lint.sh`, so it is proven on bash 3.2
    and BSD grep/sed.~~ Correction 2026-11-28 (PR #19 review): that step was added to `linux-core` (Ubuntu), so it
    ran Linux bash and GNU grep, and the script had never run on macOS. True from 2026-11-28 (branch
    `t3/ci-lint-on-macos`): the step "Lint on macOS (bash 3.2, BSD grep/sed)" is the first step after checkout in
    `macos-app` and logs `/bin/bash --version`; `linux-core` keeps "Lint on Linux (bash 5, GNU grep/sed)". Busybox
    grep has no `--include`, so the script does not run there (noted in its header).
- `testTheCoordinatorWiresItsParts` replaced by `testStartWatchingRequeuesPendingRowsOnce` (`FolderCapture` with a
  fake host: only `pending` rows are queued, and a second `startWatching()` queues nothing).
- `GlobalHotKey.modifiers(from:)` is `nonisolated` and the search keys use it (the copy in `SearchPanel.swift` is gone).
  `SearchKeyMap.keypadEnter` moved to `KeyCode.keypadEnter` (checked against `kVK_ANSI_KeypadEnter` in the app tests).
  `SearchResultActions.hidePanel`/`announce` are `@MainActor` closures. `FileActions.processor` stays a `var` with a
  comment: the coordinator sets it once in `openStorage()`, which cannot run before `fileActions` is initialized.
- PR 9 follow-up: `shippedColumns` (core `ScreenshotIndexTests`) is an ordered `(version, columns)` list, and the test
  asserts versions are unique and run 1, 2, 3…. A "keep both" merge used to crash the run on a duplicate dictionary key.

## Verification (2026-11-28)
- Linux: `SCRATCH=.build/linux-pfb scripts/test-linux.sh`, 410 tests, 0 failures. `scripts/lint.sh` and `--self-test` pass.
- CI runs 46127111976 (`3e34e7f`) and 46127989839 (`0f02d9f`): `linux-core` and `macos-app` green.
- Snapshots: 170 PNGs, same names as main's run 45052894155. Run 46127989839 is byte-identical to main for all 170.
  Run 46127111976 differed only in `search-results-light.png` (scroller gutter), a timing flake (see [macos-ci](macos-ci.md)).

## Open
- 2026-11-28: the push used `gh-shotkeeper auth git-credential`. The clone's own credential helper and the token file
  that `gh-shotkeeper` reads both point at a missing secrets file. `gh-shotkeeper` printed the `cat` error and still
  worked, which suggests it fell back to the default `gh` login. Reported in the PR handoff.
