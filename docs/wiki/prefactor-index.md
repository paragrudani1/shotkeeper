# Prefactor: index columns, settings round-trip, change feed

Branch `t3/prefactor-index`, based on `295df83`. Commits: `9200bc8` (index column table, change feed, test row builder),
`77b5447` (settings). Prefactors 1, 2, 3 and 8 (row builder only) from the roadmap survey of 2026-11-28, done before the
feature PRs so they can run in parallel. No user-visible change. API map: [../core-api.md](../core-api.md).

## Decisions
- 2026-11-28 (`9200bc8`): **one column table.** `ScreenshotIndex.columns` declares each column once: name, SQL
  definition, `addedIn` (the migration that adds it), bind and read closures. Migration 1's `CREATE TABLE`, later
  `ADD COLUMN` statements (`addColumns(addedIn:)`), the upsert, its bindings, the `SELECT` list and the row read all come
  from it. A row is read by walking the same list, so no hand-kept column positions remain.
- 2026-11-28 (`9200bc8`): **migrations stay an explicit list.** Adding a column = one `columns` entry plus
  `SQLiteMigration(version: n, statements: addColumns(addedIn: n))`. Versions are not derived from the columns on
  purpose: two PRs that both claim version 3 then collide on the same `migrations` line (or fail the
  unique-and-contiguous test), instead of silently sharing one version that a database already at 3 would never rerun.
  The second PR to merge renumbers ("numbers claimed at merge", survey).
- 2026-11-28 (`9200bc8`): **existing databases are unchanged.** Migrations 1 and 2 generate byte-identical SQL to
  `295df83`. `testDatabaseAtCurrentVersionOpensUnchanged` builds a database from a frozen copy of that SQL, then checks
  the version (2), every value of a full row, defaults of a sparse row, FTS search, a new save, and that its
  `sqlite_master` equals a new database's. Other guards: versions are `1...n`, every `addedIn` names a migration,
  columns are in `addedIn` order (ADD COLUMN appends), the migrated table equals `["id"] + columns`, and every column
  round-trips (a Mirror check makes a new `IndexedScreenshot` property fail the test until it is set there).
- 2026-11-28 (`9200bc8`): **change feed.** `changes() -> AsyncStream<IndexChange>`; `IndexChange` = kind
  (inserted / updated / removed) + row `id` + `path`. Published under the index lock after the write commits, so
  subscribers see commit order; a write that throws publishes nothing. `save` reads whether the path existed first (one
  extra `SELECT`) to tell inserted from updated. `updatePath` publishes `removed` for a stale row it replaced, then
  `updated`; same path or a missing source publishes nothing. Unbounded buffer (Spotlight must not miss a removal);
  streams finish when the index is freed. Subscribers sit behind their own lock because `onTermination` can run on any
  thread. Not added: old path on `updated`, a "changed fields" set, or delete APIs; Spotlight, search refresh and
  clean-up can add what they need.
- 2026-11-28 (`9200bc8`): **row builder.** `IndexedScreenshot.testRow(_:_:)` in `TestSupport.swift`: a `done` row with
  placeholder file fields, everything else set in a closure (so a new column never adds a parameter). Used by the new
  tests only: converting the existing `entry(...)` / `row(...)` helpers made them longer, not shorter, so they stay.
- 2026-11-28 (`77b5447`): **settings.** `CodingKeys` has one `case` per line, with a comment saying each new key goes
  on its own line. `testEveryPropertyRoundTrips` sets every stored property to a non-default value (checked with
  Mirror), then checks the encoded keys equal the properties (`CodingKeys`) and the decoded value equals the original
  (`init(from:)`). Dropping one `init(from:)` line made it fail (checked by hand, 2026-11-28).

## Verification
- 2026-11-28: `SCRATCH=.build/linux-pfa scripts/test-linux.sh` green, 409 tests. No app code changed.
