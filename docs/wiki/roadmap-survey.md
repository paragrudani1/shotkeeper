# Roadmap survey (2026-11-28)

Survey for the eight features Parag approved on 2026-11-28. Every code claim is about `295df83` (origin/main). No tests were run (14 GB free, below the 15 GB floor in [environment](environment.md)).

## Shared facts (2026-11-28, 295df83)
- **Index:** `ScreenshotIndex.swift` runs `user_version` migrations, and the schema is at version 2. Migration tests exist. A new column changes four places: `migrations`, `writableColumns`, `bindings` and `row()`, which reads columns by position.
- **Settings:** `AppSettings` has a hand-written `CodingKeys` and `init(from:)`, so a new setting changes three places in one file.
- **Pipeline:** `ScreenshotProcessor.process` skips a file as `.alreadyIndexed` (same fingerprint) or `.restoredByUndo` (permanently). Consent is decided only in `UploadConsent.decide`.
- **Search keys:** `SearchKey` lives in `SearchPanel.swift`. ⌘C copies the image and its URL, ⌘R reveals, ⌘Y opens Quick Look, and ⌘1–⌘7 pick the chips.
- CI runs no lint step.

## Per feature

### 1. Search filters
- (a) `ScreenshotQuery` holds `text`, `contentType` and `paths`, and `search(_:limit:)` ANDs them together. There are 7 `SearchChip`s; `.other` has no chip. The `captured_at REAL` and `source_app_or_site TEXT` columns exist.
- (b) Missing: date and source fields in the query, a "distinct sources with counts" query, and SQL indexes on `captured_at` and the source column. Sources are free model text ("X" vs "x.com"): normalize them.
- (c) Mostly core. Test seam: the `SearchWindowState` mutations produce `query`, and that query goes to `ScreenshotIndex.search`.
- (d) Read-only.

### 2. Copy text
- (a) `key_text` is the model's "verbatim" main text, capped at 500 characters (`AnalysisFields.keyTextMaxLength`), and it is full-text indexed. `SearchResultItem` doesn't carry it. ⌘C is already taken by the image, or by the search field's own text when that text is selected.
- (b) Missing: the text in the result item, a key for copying it, and a "truncated" hint. It is model output, not OCR. Full text would need Apple Vision OCR (app-only) behind a new core protocol.
- (c) Core: `SearchResultItem`. App: pasteboard and key (CODING_STANDARDS #7).
- (d) No file or consent impact (OCR is on-device).

### 3. Shortcuts and Spotlight
- (a) Only the Finder tags and comment xattrs, which Spotlight indexes (`FinderMetadata`). There is no App Intents or CoreSpotlight code.
- (b) Missing: an App Intent, and syncing `CSSearchableIndex` on every save, path update, undo and missing file. `ScreenshotIndex` has no change feed for that sync to follow.
- (c) App only. Core seams: `search(ScreenshotQuery)`, plus a pure row→item mapping that would be new.
- (d) The description and `key_text` would go into the system index. Undo must update the entry. Nobody has checked whether intents work in an ad-hoc-signed `LSUIElement` app, which ties this feature to #8.

### 4. Subfolders
- (a) There is one `organizedFolder` plus `moveEnabled`. `FileOrganizer.organize(_:stem:into:)` creates the folder if needed. The processor writes an undo record after each move. `FolderWatcher` emits only direct children.
- (b) Missing: a type/source → folder-name rule with name cleaning, setting and UI, re-sorting processed files.
- (c) Core: a pure folder router whose result feeds `into:`. Seam: `ScreenshotProcessorTests` with `StubAnalyzer` and `TempDir`.
- (d) Every move goes through `FileOrganizer`, so undo already works. Undo leaves empty folders behind; keep them. Re-sorting is a bulk move with one undo record per file (`undo(ids:)` exists).

### 5. Fix or re-run a title
- (a) `ScreenshotProcessor.rename(_:to:)` handles the toast's "Edit name": it writes an undo record, updates the index title and notes "renamed by the user". There is no re-analyse path.
- (b) Missing: rename in the search window, and a `reanalyze` that gets past `.alreadyIndexed`. The index has no column that marks a title as the user's.
- (c) Core: a new processor entry point (seam: `ScreenshotProcessorTests`). App: a search-panel key and an inline editor.
- (d) Re-analysis uploads the screenshot again, so it must pass `UploadConsent.decide`. A file taken before the grant is refused unless a `ProcessExistingAuthorization` covers it. That means either widening that authorization or adding a new one, and either way changes the single choke point and the text of CODING_STANDARDS #2. Also open: `restoredByUndo` files; re-routing a renamed file (#4).

### 6. Clean-up help
- (a) `ContentFingerprint` is size + mtime + the first 64 KiB. A second exact copy is skipped **without an index row**, so the index can't see byte-identical duplicates. Nothing in `Sources` or `App` trashes or deletes a user file (`removeItem` only touches app-support files). `UndoLog` records only `move` and `undo` lines.
- (b) Missing: visual-duplicate hashing (needs pixels, so the app or the preparer), any record of opens, macOS last-used dates (Spotlight metadata, app-only), a trash operation, and a matching undo kind.
- (c) Core: pure candidate rules (age, opened, duplicate groups) with an injected clock. App: metadata reads, the bin action and a review UI.
- (d) This collides directly with CODING_STANDARDS #1, "No code path deletes a user file". It needs explicit user confirmation for every batch and an undo record for each trashed file.

### 7. More capture types
- (a) `ScreenshotDetector.imageExtensions` is png, jpg, jpeg, heic and tiff, and only screenshot name prefixes match. `ImagePreparer` (URL → `ImagePayload`, png/jpeg/webp) is the seam. The index key is `path TEXT NOT NULL UNIQUE`.
- (b) **Recordings** need: `.mov` and localized "Screen Recording" prefixes, frame extraction (AVFoundation, app-only), a frame-choice rule, a cost per frame, a media-kind column, and prompt wording (the prompt currently says "screenshot"). **Clipboard** needs: polling for changes (the app is notified of nothing), and writing the image to a file before the pipeline can see it.
- (c) Core: the detector and a capture kind. App: a video preparer and a clipboard monitor.
- (d) Clipboard writes must create files without replacing anything (`NoReplaceRename`). Clipboard images come from any app, so they probably need their own opt-in. Filename and folder exclusions can't match a clipboard capture. Pause must still apply. Newer macOS may prompt when an app reads the pasteboard; that needs a cited note in `docs/research/` and is unverified.

### 8. Signed, notarized builds with auto-update
- (a) `App/project.yml` uses `CODE_SIGN_IDENTITY "-"`, `ENABLE_HARDENED_RUNTIME: NO` and no sandbox. CI ad-hoc signs it; no release workflow.
- (b) Missing: Developer ID and notarization secrets, hardened runtime (check `ManagedProcess` still launches uv/Python), an updater, a release workflow.
- (c) CI and `project.yml` only.
- (d) Keychain items written by ad-hoc builds may prompt or become unreadable once the signature changes; check this on a real Mac. Sparkle would break the rule "No third-party dependencies" ([architecture](architecture.md), 2026-11-21).

## Conflict hotspots (2026-11-28, 295df83)
| File / type | Features |
|---|---|
| `ScreenshotIndex.swift` (migration numbers, positional `row()`) | 1, 3, 5, 6, 7 |
| `ScreenshotProcessor.swift` | 4, 5, 6, 7 |
| `AppCoordinator.swift` (841 lines) | 3, 4, 5, 6, 7, 8 |
| `AppSettings.swift` (CodingKeys + `init(from:)`) | 4, 6, 7, 8 |
| Search panel: `SearchKey`, `SearchView.swift` (583 lines), `SearchWindowState` | 1, 2, 5, 6 |
| `UploadConsent` + CODING_STANDARDS #2 | 5, 7 |
| `SettingsView.swift` General tab | 4, 6, 7, 8 |
| `ContentType` (chips ⌘1–⌘7, prompts, Clairic schema cost) | 1, 4, 7 |
| `UISnapshotTests` (one test lists every snapshot) | every UI feature |
| `ci.yml`, `project.yml` | 3, 8 |

## Suggested build order (2026-11-28)
0. **Prefactor PR(s)** below, merged first.
1. **Wave 1, in parallel:** #1 Filters, #2 Copy text, #8 Signing. #8 touches only CI and the project file, and it unblocks the real-Mac checks for #3.
2. **Wave 2, in parallel:** #5 Fix or re-run (after Parag's consent decision and #1/#2's panel changes) and #4 Subfolders; both touch the processor.
3. **Wave 3:** #3 Shortcuts and Spotlight (after the change feed, and after #8 if intents need signing), and #7 capture types, in parallel.
4. **Wave 4:** #6 Clean-up, after Parag's bin decision.

## Prefactors and environment (2026-11-28)
1. **Named index columns:** one column table driving insert, bind and read; a test that migration versions are unique and contiguous; numbers claimed at merge.
2. **Settings decode:** a round-trip test so no key is left out of `init(from:)`; new keys on their own lines.
3. **Index change feed** (`AsyncStream` of row changes), used by Spotlight, search refresh and clean-up.
4. **Split `AppCoordinator`** (841 lines): file actions and search actions into their own types.
5. **Move the search key map into core** with a collision test, so ⌘ assignments get tested on Linux.
6. **One consent-generalization PR** before #5 and #7, turning `ProcessExistingAuthorization` into a "user-requested upload". It updates CODING_STANDARDS #2 in the same PR, so the rule never exists in two copies.
7. **CI lint** (CODING_STANDARDS says mechanical rules belong in CI): no AppKit, ImageIO or CoreServices imports in core; no `removeItem`, `trashItem` or `moveItem` outside `FileOrganizer`/`UndoLog`; no `.analyze(` outside `ScreenshotProcessor`.
8. **Test helpers:** an `IndexedScreenshot` row builder; one shared coordinator harness for app tests.
9. **Split `UISnapshotTests`** per screen.
10. **Environment:** free disk above 15 GB, or agents rely on CI alone; one `SCRATCH` per agent. The app has never run on a real Mac (README), and #3, #7 and #8 need one.
