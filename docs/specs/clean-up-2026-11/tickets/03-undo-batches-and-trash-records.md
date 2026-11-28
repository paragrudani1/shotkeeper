# 03: Undo batches and trash records; menu Undo takes back the whole last batch

**What to build:** the menu's Undo takes back a whole batch, not one file. After wave 2's Sort Existing, the menu
reads "Undo Sort: 180 screenshots" and ⌘Z moves all 180 back, newest first, with wave 2's "Moved back" toast. The undo
log can also hold trash records (written by 07) and `gone` lines (written by 09), and old logs still read as before.

**Blocked by:** wave 2 05 (Sort Existing, `undo(ids:)`, the "Undo Move:" label and the "Moved back" toasts), which
the integration branch already has. Independent of 01 and 02.

**Status:** ready-for-agent

**Sources:** spec "Undo and put-back" (`UndoLog` gains a record kind, `batch`), "Decisions" 10; design §9 "Menu bar"
(undo label grammar), §14 spec departure 4; wave 2 design §7 ("Undo Move: <title>"), wave 2 spec "Sorting existing
screenshots" (Undo All cost note).

**Test seam:** `UndoLogTests` and `MenuTextTests` (existing, more cases), plus seam 1 (`ScreenshotProcessor`
`undo(ids:)`) for the sort batch.

**Likely touches:** core `Files/UndoLog.swift` (`UndoRecord.kind`, `batch`, `appendTrash`, `gone` lines, batch
lookup), `Feedback/MenuText.swift` (labels), wave 2's `sort` (writes one batch id per run), app
`Coordinator/FileActions+Subfolders.swift` and the menu Undo action (`MenuContentView` / coordinator),
`MenuSnapshots`, `docs/core-api.md`.

- [ ] `UndoRecord.kind`: `.move` (today's, and the decode default for old lines without a kind) or `.trash`. A trash
      line is `{"kind":"trash","id","timestamp","from","to","batch"}`; `appendTrash(from:to:batch:)`. Undo of a trash
      record reuses the existing no-replace revert (`renameNoReplace` through `FileOrganizer.move`, research §3);
      the index side is 07's.
- [ ] `batch`: an optional UUID per record. Wave 2's `sort` writes one batch id per run. `records()` and
      `lastUndoable()` still work per record.
- [ ] `gone` lines: `markGone(id:)` appends one; `records()` ignores gone records like undone ones, so the menu's
      target moves to the previous record.
- [ ] Menu Undo: when the newest undoable record has a batch, the item offers the **whole batch** and runs
      `undo(ids:)` newest first. Labels (design §9, American spelling): "Undo Move to Trash: 12 screenshots", "Undo Move
      to Trash: <title>" (one file), "Undo Sort: 180 screenshots"; single records keep "Undo: <title>" and "Undo Move:
      <title>". Pure rules in `MenuText`, tested.
- [ ] If wave 2 added a read-once batch undo to `UndoLog`, the batch path uses it; otherwise measure undo of a
      1,000-record batch and record the number in the wiki (spec "Further Notes").
- [ ] Tests: old lines decode as `.move`; trash records round-trip; batches group; gone lines hide records; menu
      label per case; sort batch undone from the menu in one action.
- [ ] New CI snapshots, light and dark: `menu-undo-trash` (from a fixture trash batch) and, proposed (not in the
      design's list), `menu-undo-sort-batch`.
- [ ] Real-Mac checks: ⌘Z from the menu after a real Sort Existing of a few hundred files puts them all back and shows
      one "Moved back" toast.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green; `docs/core-api.md`; dated
      wiki line (the change to wave 2's sort menu).
- [ ] **Done only when `macos-app` CI is green** on the PR.
