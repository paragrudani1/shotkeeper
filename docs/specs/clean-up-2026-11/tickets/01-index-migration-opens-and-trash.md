# 01: Index migration: `last_opened_at`, `trashed_from` and the `trashed` status

**What to build:** the index can say "the user opened this screenshot" and "this screenshot's file is in the Trash",
and every place that acts on a row ignores a binned one. Nothing visible changes yet: a trashed row simply vanishes
from search, Recent and the count, and a fresh copy of a binned screenshot is indexed as new instead of skipped.

**Blocked by:** None (can start immediately once the clean-up integration branch exists). Core only.

**Status:** ready-for-agent

**Sources:** spec "Index schema and change feed (on top of prefactor A and waves 1–2)", "Never opened" (the
`last_opened_at` merge rule), "Rows of binned duplicates"; `docs/wiki/prefactor-index.md` (how to add a column).

**Owns the clean-up migration.** This is the only clean-up ticket that adds an index migration version. Wave 1 takes 3
and wave 2 takes 4, so write 5, and **at merge time** re-check the highest version on the target branch and claim the
next free one (`shippedColumns` versions must run 1, 2, 3… with no gap; a wave 3 migration merged first moves this
one up). The `columns` entries, the `addColumns("last_opened_at", "trashed_from")` line and the `shippedColumns` pair
go in together.

**Test seam:** existing tests, one more case each (spec "Not new seams"): `ScreenshotIndexTests` (migration,
`shippedColumns`, the new APIs, exclusions, the merge rule), plus seam 1 (`ScreenshotProcessor`) for the
`lookup(byHash:)` case and the wave 1/2 entry points. Rows from `IndexedScreenshot.testRow`.

**Likely touches:** core `Index/ScreenshotIndex.swift` (column table, migrations, new APIs), `IndexedScreenshot`
(`lastOpenedAt`, `trashedFrom`), `ProcessingStatus` (`.trashed`), the wave 1 OCR runner query, wave 2
`reanalyze`, `ScreenshotIndexTests`, `ScreenshotProcessorTests`, `docs/core-api.md`.

- [ ] Columns `last_opened_at REAL` and `trashed_from TEXT` (both nullable) in one migration; the every-column
      round-trip and `shippedColumns` tests pass; `testDatabaseFrom295df83OpensWithEveryValueKept` still passes;
      every existing row has both NULL after migrating.
- [ ] `ProcessingStatus.trashed` (TEXT, no schema change). A trashed row has `status = trashed`, `path` = the file's
      path in the Trash, `trashed_from` = where it was.
- [ ] First per-column merge rule in the column table: the upsert keeps the **later** of the stored and the saved
      `last_opened_at`, so a stale save from `process` or `reanalyze` can't erase an open. A row whose content changed
      (`process` makes a new entry) starts with NULL. Tested.
- [ ] New APIs, each publishing on the change feed under the index lock after the commit: `recordOpened(id:at:)`
      (`.updated`, ignores non-`done` rows), `markTrashed(id:trashPath:)` (`.updated`; path, status and
      `trashed_from` in one statement), `markPutBack(trashPath:originalPath:)` (`.updated`), `remove(id:)`
      (`.removed`; deletes index data, never a file). Feed events arrive in commit order (test).
- [ ] Trashed rows absent from search results and counts, Recent and the menu count (existing `done` filters, one
      test each), and excluded explicitly, each with a test: `lookup(byHash:)`; wave 1's `newestPendingTextRow()`;
      wave 2's `reanalyze` (`.refused(.missing)`); `recordOpened`.
- [ ] Seam 1 test: a fresh copy of a screenshot whose row is trashed is processed, not skipped as `.alreadyIndexed`.
- [ ] Rule for later waves recorded in the wiki: every entry point that acts on a row requires `status == done`
      (wave 3's Spotlight sync treats a non-`done` row as absent). Downgrade risk (an older build reads `trashed` as
      `.pending`) noted in the wiki, not guarded.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green; `docs/core-api.md`; start
      `docs/wiki/clean-up.md` if this merges first (see README, "Wiki page"), with the migration number actually
      claimed.
- [ ] **Done only when `macos-app` CI is green** on the PR (AGENTS.md: Linux green does not prove the macOS build).
- CI snapshots: none.
- Real-Mac checks: none (core only). The migration runs on Parag's real index at the first clean-up build; ticket 10
  confirms rows are kept.
