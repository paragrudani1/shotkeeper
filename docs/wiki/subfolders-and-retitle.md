# Wave 2: subfolders, Edit name and Analyze Again

Spec `../specs/subfolders-and-retitle-2026-11.md`, design `../design/subfolders-and-retitle.md` and tickets in
`../specs/subfolders-and-retitle-2026-11/tickets/` (all on `t3/roadmap-2026-11` until they merge). Integration
branch `t3/wave2`. API map: [../core-api.md](../core-api.md). Each ticket appends its dated lines here; the page is
not created twice.

## Decisions
- 2026-11-28 (`1312ab1`, ticket 02): **index migration 4: `title_source`.** Claimed version 4 (wave 1 took 3; no
  other migration on `t3/wave2` or `t3/wave1-search` when pushed). `title_source TEXT`: NULL or `model` = the model's
  title (or the original name), `user` = typed by the user (`TitleSource`, `IndexedScreenshot.titleSource`). The
  same migration runs `UPDATE screenshots SET title_source = 'user' WHERE instr(note, 'renamed by the user') > 0`
  (the note `rename(_:to:)` has appended since `02e6420`; `instr` is exact, unlike `LIKE`), so names fixed in the
  toast before this feature count as the user's (spec decision 8). Every other row stays NULL. Not an FTS column, so
  FTS is untouched. No other column (no rule, folder, count, history or previous analysis). Test:
  `testVersionThreeDatabaseBackfillsTitleSourceFromTheRenamedByTheUserNote`.
- 2026-11-28 (`1312ab1`): **who writes it.** `process` builds every row with `.model`, so a path whose content
  changed starts again as the model's (failed rows too; nil and `model` mean the same). `rename(_:to:)` writes
  `.user` (toast and search window). A restored-by-Undo row renamed by hand keeps its flag. Confirming the unchanged
  name writes nothing, so the mark stays as it was.
- 2026-11-28 (`1312ab1`): **"Use This Name" is `rename(_:to:asSuggestedTitle: true)`** (default false), as the ticket
  recommends, not a string comparison. It writes `.model`, and the row's title is the suggestion as given (the
  model's title, as `process` stores it), not the sanitized file stem that a typed rename stores, because the spec
  says it "sets the title back to the model's". It adds no "renamed by the user" note. When the file already has
  that name, nothing moves and no undo record is written, but the mark is still cleared (the spec: a rename that
  matches the suggestion clears it). Test: `testRenamingToTheSuggestedTitleClearsTheUsersMark`. Checked by hand: dropping
  the unchanged-name branch fails it.

## Verification
- 2026-11-28 (`1312ab1`, ticket 02): `SCRATCH=.build/linux-w2-02 scripts/test-linux.sh` green, 433 tests;
  `scripts/lint.sh` ok.
