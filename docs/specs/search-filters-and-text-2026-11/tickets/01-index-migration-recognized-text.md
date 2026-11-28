# 01: Index migration: recognized text in search, filter indexes

**What to build:** the one index migration for wave 1. After it, a row's recognized text (written through a new
conditional write) is found by search and ranked below title, tag and description hits, and date and source
filters have SQL indexes to stay fast (story 23). Existing databases open with every row kept and `text_status` NULL.
No text is recognized yet (that is 04); tests write text directly through the index.

**Blocked by:** None (can start immediately). Core only; it does not need PR #10.

**Status:** ready-for-agent

**Sources:** spec "Index schema change", "FTS match and ranking", "Text recognition: when it runs" (conditional
writes); `docs/wiki/prefactor-index.md` (how to add a column: `columns` entry + migration line + `shippedColumns`).

**Owns the migration.** This is the only wave 1 ticket that adds a migration version (the next free number on main,
3 as of `d8e5b17`). It adds the OCR columns *and* the filter indexes, so 02 and 03 add no migration.
**Deviation from the spec** ("two migrations, whichever merges second renumbers"): one migration, so no two wave 1
tickets claim a number in parallel. Record it as a dated line in `docs/wiki/search-filters-and-text.md` (create the
page and its index line if this ticket merges first).

**Test seam:** seam 1, `ScreenshotIndex` public API, in-memory (prior art `ScreenshotIndexTests`, rows from
`IndexedScreenshot.testRow`).

**Likely touches:** `ScreenshotIndex` (column table, `migrations`, FTS triggers, `bm25Weights`, a new conditional
text write), `IndexedScreenshot` (four fields), a `TextStatus` enum, `ScreenshotIndexTests`, `TestSupport`
(`shippedColumns`). Hotspot: `ScreenshotIndex.swift` (survey); no other wave 1 ticket edits its migrations.

- [ ] Four columns in the column table with the new `addedIn`: `recognized_text`, `text_status`
      (NULL / `pending` / `done` / `none` / `failed`), `text_recognized_by`, `text_error`. `IndexedScreenshot` gains
      them; the every-column round-trip and `shippedColumns` tests pass with the new line.
- [ ] The same migration drops the three FTS triggers and `screenshots_fts`, recreates them with `recognized_text` as
      the sixth FTS column (the `AFTER UPDATE OF` list includes it), and runs the FTS5 `'rebuild'` command (cite
      https://www.sqlite.org/fts5.html, "The 'rebuild' Command"). One constant holds the FTS column list used by the
      triggers and the weights.
- [ ] Weights `10, 6, 3, 1, 2, 0.5`. Test pins the order: a title hit ranks above a hit only in recognized text.
- [ ] Recognized text is part of the AND match: a two-term query matches when one term is in the title and the other
      only in the recognized text.
- [ ] Migration test: a database at the previous version with rows opens, its rows are still found by FTS, and they
      have `text_status` NULL. `testDatabaseFrom295df83OpensWithEveryValueKept` still passes.
- [ ] SQL indexes in the same migration: an expression index on `COALESCE(captured_at, processed_at)`, an index on
      `source_app_or_site`, and a partial index on `text_status` where it is `'pending'`. A test checks they exist by name
      (not the SQL text).
- [ ] Conditional write "set text for row *id* if its `content_hash` still equals *h* and status is `pending`":
      sets `done` (text), `none` (text NULL) or `failed` (`text_error`), returns whether it applied, and publishes
      `.updated` only when it applied. Tests: a stale hash and a non-pending status are refused and change nothing.
- [ ] A query for "newest `pending` row" (by `COALESCE(captured_at, processed_at)` descending) for the runner (04).
- [ ] `text_error` and logs never contain recognized text (stated in the doc comment; reviewers check CODING_STANDARDS #2
      in spirit).
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` green; `scripts/lint.sh` green once PR #10 is on main.
- [ ] `docs/core-api.md` and a dated wiki line updated.
- [ ] **Done only when `macos-app` CI is green** on the PR (AGENTS.md: Linux green does not prove the macOS build).
- Real-Mac checks: none (core only).
