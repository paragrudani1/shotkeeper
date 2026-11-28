# Prefactor: index columns, settings round-trip, change feed

Branch `t3/prefactor-index`, based on `295df83`. Commits: `9200bc8` (index column table, change feed, test row builder),
`77b5447` (settings). Prefactors 1, 2, 3 and 8 (row builder only) from the roadmap survey of 2026-11-28, done before the
feature PRs so they can run in parallel. No user-visible change. API map: [../core-api.md](../core-api.md).

## Decisions
- 2026-11-28 (`9200bc8`): **one column table.** `ScreenshotIndex.columns` declares each column once: name, SQL
  definition, `addedIn` (the migration that adds it), bind and read closures. Migration 1's `CREATE TABLE`, later
  `ADD COLUMN` statements (`addColumns(_:)`), the upsert, its bindings, the `SELECT` list and the row read all come
  from it. A row is read by walking the same list, so no hand-kept column positions remain.
- 2026-11-28 (`9200bc8`): **migrations stay an explicit list.** Versions are not derived from the columns; the second
  PR to merge renumbers ("numbers claimed at merge", survey). The collision claim made here was wrong: see the
  correction below.
- 2026-11-28 (`9200bc8`): **existing databases are unchanged.** Migrations 1 and 2 generate byte-identical SQL to
  `295df83`. `testDatabaseFrom295df83OpensWithEveryValueKept` (renamed, see below) builds a database from a frozen
  copy of that SQL, then checks the version (2), every value of a full row, defaults of a sparse row, FTS search, a
  new save, and that its `sqlite_master` equals a new database's. Other guards: versions are `1...n`, every `addedIn` names a migration,
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
- 2026-11-28 (review fixes): **correction: two column PRs could share version 3.** With `addColumns(addedIn: 3)` both
  PRs added the identical line `SQLiteMigration(version: 3, statements: addColumns(addedIn: 3)),`, which git merges
  cleanly, and "keep both" in the `columns` conflict left both columns under 3. A database already at 3 would never get
  the second column, and every save would fail. Now the migration line names its columns
  (`addColumns("restored_by_undo")`, a precondition fails on an unknown name), so parallel lines differ and conflict.
  `testEachMigrationAddsItsShippedColumns` checks each migration's `ALTER` names equal the `addedIn` columns, and both
  equal a frozen test-side map `shippedColumns` (`[1: [...], 2: ["restored_by_undo"]]`) whose keys must equal the
  migration versions. Each column PR appends `n: [...]` to it (another line that conflicts between parallel PRs); a
  shipped version that gains a column fails. Adding a column = `columns` entry + migration line + `shippedColumns` line.
- 2026-11-28 (review fixes): **change-feed tests fail instead of hanging.** They do the writes, free the index, collect
  the whole stream and compare it exactly. Every wait goes through `awaitResult`, which fails with "timed out after
  10.0 s waiting for ..." (checked by hand: leaving the index alive fails in 10 s). The stream helper takes
  `AsyncStream<IndexChange>`: `AsyncSequence.Failure` needs macOS 15 and the package targets 14, which only macOS CI
  catches.
- 2026-11-28 (review fixes): **unsubscribe is tested.** Internal `subscriberCount`; tests check that a dropped stream and
  a cancelled iteration (stream still held) each remove their subscriber (making `removeSubscriber` a no-op fails both,
  checked by hand). The `changes()` doc says a held, un-iterated stream buffers without limit; `save` documents (and a
  test checks) that it publishes `.updated` for an identical row.
- 2026-11-28 (review fixes): the 295df83 database test asserts version 2 on the frozen database before opening and
  `migrations.last` after, so a new migration does not touch it; renamed to
  `testDatabaseFrom295df83OpensWithEveryValueKept`. `testVersionOneDatabaseMigratesWithRowsKept` also checks
  `migrations.last`.

## Verification
- 2026-11-28: `SCRATCH=.build/linux-pfa scripts/test-linux.sh` green, 409 tests. No app code changed.
- 2026-11-28 (review fixes): `SCRATCH=.build/linux-pfa2 scripts/test-linux.sh` green, 412 tests.
