# Wave 1: search filters and Copy Text

Spec `../specs/search-filters-and-text-2026-11.md` (on `t3/roadmap-2026-11`, PR #12, until it merges), tickets in
`../specs/search-filters-and-text-2026-11/tickets/`. Integration branch `t3/wave1-search`. API map:
[../core-api.md](../core-api.md).

## Decisions
- 2026-11-28 (`c1c79ce`, ticket 01): **deviation from the spec: one migration, not two.** The spec gives filters and
  OCR one migration each, with whichever merges second renumbering. Ticket 01 owns the only wave 1 migration
  (version 3). It adds the four text columns, rebuilds FTS and creates the filter indexes, so tickets 02 and 03 add no
  migration and no two wave 1 tickets claim a version number in parallel. Reason: the ticket split (2026-11-28).
- 2026-11-28 (`c1c79ce`): **migration 3.** It runs `addColumns("recognized_text", "text_status", "text_recognized_by",
  "text_error")`, then drops the three FTS triggers and `screenshots_fts` and creates them again with `recognized_text`
  as the sixth FTS column (`AFTER UPDATE OF` lists it). Next it runs the FTS5 `'rebuild'` command
  (https://www.sqlite.org/fts5.html, "The 'rebuild' Command") and creates three indexes:
  - `screenshots_taken_at` on `COALESCE(captured_at, processed_at)`. The date filter (02) must use exactly that
    expression, or SQLite does not use the index.
  - `screenshots_source_app_or_site`.
  - `screenshots_text_pending`, a partial index `WHERE text_status = 'pending'`.

  Rows from before the migration keep every value, get NULL text columns (not requested), and are found by FTS again.
- 2026-11-28 (`c1c79ce`): **one FTS list.** `ScreenshotIndex.ftsColumns` holds the FTS columns with their bm25
  weights (10, 6, 3, 1, 2, 0.5). The FTS table, its triggers (`rebuildFTS(_:)`) and `bm25Weights` are built from it.
  Migration 1 keeps its literal SQL (shipped). A later change to the list needs a new migration that rebuilds FTS,
  and migration 3 then needs its own frozen copy of today's list.
- 2026-11-28 (`c1c79ce`): **`TextStatus.noText` is stored as `none`.** The spec's value is `none`, but a Swift case
  named `.none` on `TextStatus?` would read as Optional's nil in `textStatus == .none`.
- 2026-11-28 (`c1c79ce`): **the conditional write.** `setRecognizedText(_:recognizedBy:id:ifContentHash:)` updates
  only the four text columns, and only while `content_hash` and `text_status = 'pending'` still match. It returns
  whether it applied and publishes `.updated` only then. The written state depends only on the result:
  - `.text`: `done`, with the text and `text_error` NULL.
  - `.noText`: `none`, with both NULL.
  - `.failed(reason:)`: `failed`, with the text NULL and the reason in `text_error`.

  `text_recognized_by` is set for every result, failures included. The analysis and `status` are never touched.
  Recognized text goes only into `recognized_text`: the doc comments say a failure reason never contains it, and the
  index logs nothing.
- 2026-11-28 (`c1c79ce`): `newestPendingTextRow()` orders by `COALESCE(captured_at, processed_at)` DESC, then id
  DESC (spec: newest `pending` first).
- 2026-11-28 (`c1c79ce`): **`save` writes the text columns like every column.** A fresh `IndexedScreenshot` built
  without them clears a row's text and status. That is the spec's intent: the processor (ticket 04) sets `pending`
  on a new analysis. Until 04 lands, re-processing a file leaves its text status NULL.
- 2026-11-28 (`1d9f0e2`, ticket 04): **privacy rule: recognized text never leaves the Mac.** It goes only into
  `recognized_text` in the index, and reaches the pasteboard only through the user's Copy Text. It is never put in
  `AnalysisContext` or a prompt (either backend, wave 2's re-analyse included), Finder tags or comment, the undo log,
  `note`, `text_error`, `lastError`, a log, or CLI output. Reviewers check it under CODING_STANDARDS #2, and no new
  send path may carry it. Today core and the app log nothing, and the CLI does not read the index.
  `testASuccessfulAnalysisQueuesTheTextAndTheAnalyzerGetsNoRecognizedText` pins `AnalysisContext` to its two fields.
- 2026-11-28 (`1d9f0e2`): **the runner.** `TextRecognitionRunner` (core actor). `start()` subscribes to `changes()`
  first, then reads every `pending` row, newest first, one at a time, in a utility-priority task. Each change wakes
  it again. `stop()` starts no new row; a read already running finishes and is stored. `drain()` returns at once if
  a pass is already running, so two passes never read the same row. The coordinator creates it in `openStorage()`,
  starts it in `startServices()` (not gated on the backend being ready) and stops it in `stopServices()`.
- 2026-11-28 (`1d9f0e2`): **failure reasons.** A missing file gives `failed` with "file missing", and the
  recognizer is not called. A recognizer error gives `failed` with "could not read the text (<domain> <code>)" (for
  example `com.apple.Vision 9`). The error's description is never used, because it could quote text.
- 2026-11-28 (`1d9f0e2`): **truncation is marked in the text.** The spec says "marked truncated", but there is no
  column for that. Text longer than 100,000 characters keeps the whole lines that fit and then gets
  `RecognizedText.truncationMarker` ("[Text cut here: longer than 100,000 characters]") as its last line. Search,
  Copy Text and the user all see it. If even the first line does not fit, its first 100,000 characters are kept.
- 2026-11-28 (`1d9f0e2`): **reading order.** Lines are sorted by vertical centre. A line joins the row of the
  highest line not yet placed when the two centres are less than half the smaller box height apart. Each row is
  read left to right, and every line stays on its own "\n" line. `NormalizedBox` uses Vision's convention
  (normalized, origin at the bottom left), so the app passes `boundingBox` through unchanged.
- 2026-11-28 (`1d9f0e2`): **Vision constants are PROVISIONAL.** `VisionTextSettings.current` = Apple's defaults
  (`.accurate`, `minimumTextHeight` 1/32, language correction on), so `text_recognized_by` =
  `vision-r3-accurate-h1/32-lc1`. Automatic language detection is on with `.accurate`. These are not chosen values:
  PR #18 must not merge until Parag's results are in `../research/vision-ocr-settings.md` and the constants are set
  from them. `VisionTextRecognizer` uses exactly the request setup of `scripts/measure-vision.swift`. The pixel floor
  is `VisionTextSettings.MinimumTextHeight.pixelFloor(n).relativeHeight(pixelHeight:)`, the same formula as the
  script's.
- 2026-11-28 (`1d9f0e2`): **the processor sets `pending`.** Only on the final `done` save after a successful
  analysis. The entry is new, so old text, `text_recognized_by` and `text_error` are cleared. That ends ticket 01's
  "until 04 lands" gap. A failed analysis leaves `text_status` NULL. `rename(_:to:)` and undo keep the row's text.
- 2026-11-28 (`1d9f0e2`): Pause does not stop reading, by construction: the runner takes no settings (spec decision
  8). Rows restored by Undo are read like any other, and the runner renames nothing
  (`testARowRestoredByUndoIsReadLikeAnyOtherAndStaysWhereItIs`).

## Verification
- 2026-11-28 (`c1c79ce`): `SCRATCH=.build/linux-w1-01 scripts/test-linux.sh` green, 420 tests (412 before). Checked
  by hand that the new tests fail without the change they cover:
  - recognized-text weight raised from 0.5 to 20: the ranking test fails;
  - `'rebuild'` removed: the version-2 migration test fails;
  - `recognized_text` left out of `AFTER UPDATE OF`: the conditional-write search test fails.
- 2026-11-28: PR #10's `scripts/lint.sh` (run from its branch) reports only the existing violations in files this
  branch does not touch, none in the changed files.
- 2026-11-28 (`1d9f0e2`, ticket 04): `SCRATCH=.build/linux-w1-04 scripts/test-linux.sh` green, 456 tests.
  `scripts/lint.sh` ok. Every slice was written red first. Checked by hand: removing the runner's `!stopped` guard
  fails `testStopEndsReadingAfterTheCurrentRow`. The app's `VisionTextRecognizerTests` (Vision on a generated image)
  runs only in `macos-app` CI.
- 2026-11-28 (ticket 04), open real-Mac checks for Parag: a new screenshot's words become searchable within seconds;
  rename toast timing is unchanged; Vision works on macOS 14; memory stays bounded while reading.
