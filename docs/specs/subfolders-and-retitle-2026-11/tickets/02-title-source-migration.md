# 02: Index migration: `title_source` (a name the user typed is marked)

**What to build:** the index remembers whether a screenshot's title is the model's or one the user typed. After this
ticket, the toast's "Edit name" marks the row as the user's; a new screenshot is marked as the model's; a file whose
content changed starts again as the model's. Names the user fixed in the toast before this feature are found by the
backfill. Nothing visible changes yet: Analyze Again (06) is what reads the mark.

**Blocked by:** None (can start immediately). Core only.

**Status:** ready-for-agent

**Sources:** spec "Index schema (on top of prefactor A)", "Rename by hand from the search window" (the `title_source`
bullet), stories 57–58; `docs/wiki/prefactor-index.md` (how to add a column).

**Owns the wave 2 migration.** This is the only wave 2 ticket that adds a migration version. Wave 1 takes 3 (wave 1
ticket 01, PR #13), so write version 4, and at merge time re-check the highest version on the target branch and claim
the next free one. The `columns` entry, the migration line and the `shippedColumns` pair go in together.

**Test seam:** seam 1, `ScreenshotProcessor` (`TempDir`, in-memory `ScreenshotIndex`, real `UndoLog`), plus one more
case in `ScreenshotIndexTests` for the migration. Rows from `IndexedScreenshot.testRow`.

**Likely touches:** core `Index/ScreenshotIndex.swift` (column table, `migrations`), `IndexedScreenshot`
(`titleSource`, a small `TitleSource` enum `model`/`user`), `Pipeline/ScreenshotProcessor.swift` (`process` sets
`model`, `rename(_:to:)` sets `user`), `ScreenshotIndexTests` (`shippedColumns`), `ScreenshotProcessorTests`,
`docs/core-api.md`.

- [ ] Column `title_source TEXT` with the new `addedIn`: NULL or `model` = the model's title (or the original name);
      `user` = typed by the user. The every-column round-trip and `shippedColumns` tests pass with the new pair.
- [ ] The same migration backfills `user` where `note` contains "renamed by the user" (written by `rename(_:to:)`
      since `02e6420`) and leaves every other row NULL. Test: a database at the previous version with one such row and
      one plain row opens with `user` and NULL. `testDatabaseFrom295df83OpensWithEveryValueKept` still passes.
- [ ] `process` writes `model` on a new row; a re-processed path (content changed) is written as `model`.
- [ ] `rename(_:to:)` writes `user`. The one exception is "Use This Name" (08): a rename to the model's suggested
      title writes `model` (spec: "This one path clears the user's mark"). The suggestion is not stored, so the caller
      must say so; an explicit parameter (e.g. `rename(_:to:asSuggestedTitle:)`, default false) is recommended over
      comparing strings. Add it and its test here so the core API is complete.
- [ ] No other column: no rule or folder column, no Analyze Again count or history, no copy of the previous analysis.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green.
- [ ] `docs/core-api.md` and a dated line in `docs/wiki/subfolders-and-retitle.md` (create it if first) with the
      migration number actually claimed.
- [ ] **Done only when `macos-app` CI is green** on the PR (AGENTS.md: Linux green does not prove the macOS build).
- CI snapshots: none.
- Real-Mac checks: none (core only). The migration runs on Parag's real index at the first wave 2 build; the wave 2
  final check opens it and confirms rows are kept.
