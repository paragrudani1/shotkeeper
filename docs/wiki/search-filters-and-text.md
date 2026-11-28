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

## Verification
- 2026-11-28 (`c1c79ce`): `SCRATCH=.build/linux-w1-01 scripts/test-linux.sh` green, 420 tests (412 before). Checked
  by hand that the new tests fail without the change they cover:
  - recognized-text weight raised from 0.5 to 20: the ranking test fails;
  - `'rebuild'` removed: the version-2 migration test fails;
  - `recognized_text` left out of `AFTER UPDATE OF`: the conditional-write search test fails.
- 2026-11-28: PR #10's `scripts/lint.sh` (run from its branch) reports only the existing violations in files this
  branch does not touch, none in the changed files.
