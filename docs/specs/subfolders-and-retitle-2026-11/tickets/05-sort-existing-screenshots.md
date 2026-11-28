# 05: Sort Existing Screenshots… (plan, run, Stop, Undo All)

**What to build:** with a rule chosen, the user clicks **Sort Existing Screenshots…** in Settings. Shotkeeper counts
first and asks "Sort 180 screenshots into subfolders?" (with how many are already in place and how many were moved
in Finder and are left alone), or says "Nothing to sort". On **Sort**, files move one by one with names unchanged and
nothing uploaded; progress shows in Settings and in the menu bar, with Stop. A summary toast "Sorted 180
screenshots" offers View in Search and Undo All; undoing gives the "Moved back" toast, and those files are never
sorted again. The menu says "Undo Move: <title>" for a move-only record.

**Blocked by:** 04 (the rule, the router and the Settings rows). Does not touch the search panel (View in Search
reuses the existing batch view).

**Status:** ready-for-agent

**Sources:** spec "Sorting existing screenshots" (all, including the Undo All cost note), stories 20–29, UI surfaces
2, 3 and 10; design §4 "Sort Existing Screenshots…: the flow", §7 "Batch" and "Restored after a sort undo", §8, §12
polish departures 5 and 7, spec departure 4.

**Test seam:** seam 1, `ScreenshotProcessor` through `sortPlan(settings:)`, `sort(_:)` and `undo(ids:)`; `MenuTextTests`
and the `Feedback` toast tests for wording.

**Likely touches:** core `Pipeline/ScreenshotProcessor.swift` (`sortPlan`, `sort`, a `SortPlan` / `SortReport` type,
possibly in their own file), `Files/UndoLog.swift` (batch undo only if the measurement asks for it),
`Feedback/Toast.swift` and `Feedback/MenuText.swift` (sorted / moved back / "Undo Move:"); app new
`Coordinator/FileActions+Subfolders.swift`, `Coordinator/StatusText.swift` (menu status line), `UI/MenuContentView.swift`
("Stop Sorting"), `UI/SettingsView.swift` or the 04 section file (button, counting, sheet alert, progress row),
`SettingsSnapshots`, `ToastSnapshots`, `MenuSnapshots`. Hotspot: menu files are also touched by wave 3 (none in wave 2).

- [ ] Plan (pure over the index plus a file-existence check): candidates are `done`, not `restored_by_undo`, with a
      path inside the organized folder at any depth. File not at its path → **missing** (skipped); already in its rule
      folder → **in place**. Uses stored `content_type` and `source_app_or_site`; nothing analyzed or uploaded, so
      consent and Pause don't apply.
- [ ] Run: each file via `FileOrganizer.organize(url, stem: nil, into:)` (name kept, clash → "Name 2"); per file: check
      it is still at the planned path (else skipped as missing), move, undo record, `index.updatePath`. Undo record
      fails → file moved back (no-replace) and counted failed. Cancellable between files. Reports moved, skipped,
      failed and the undo record ids.
- [ ] Undo of a sort move returns the file to its old organized path (not the watched folder) and sets
      `restored_by_undo`; the next plan skips it. Undo All runs newest first.
- [ ] Measure Undo All of 1,000 records in a test. If over about 1 s, add a batch undo to `UndoLog` that reads the log
      once, with the same no-replace revert. Record the number in the wiki either way.
- [ ] Seam 1 tests: plan counts; skips of missing, restored and in-place rows; names unchanged; cancel mid-run;
      undo-record failure puts the file back; a file vanishing mid-run counts as skipped, not failed.
- [ ] Settings flow (design §4): "Counting screenshots…" with a spinner after 0.3 s; the sheet alert with the exact
      title, message (rule wording "by type" / "by app or site" / "by type, then app or site") and count sentences
      (singular forms; each only when above 0); Sort (default) / Cancel; the three "Nothing to sort" variants with OK;
      the progress row "Sorting: 120 of 180 left" with a linear `ProgressView` and Stop. Disabled when the organized
      folder is missing or unreadable (04's warning row).
- [ ] Menu: status second line "Sorting into subfolders: 120 left" and a "Stop Sorting" item under Process Existing
      Screenshots…; last message per outcome from design §4 step 5.
- [ ] Toasts via `ToastBatcher.beginRun`: "Sorted N screenshots" with sublines for failures ("3 could not be moved")
      and Stop ("Stopped, 120 left where they are"), no toast when stopped after 0; buttons View in Search (primary)
      and Undo All (tooltip "Move them all back"). "Moved back" restored toasts for one file, Undo All, and Undo All
      with failures, exactly as design §7. Pure wording rules in `Feedback/`, tested.
- [ ] `MenuText.undoItem`: a move-only record (same stem, other folder) reads "Undo Move: <title>"; rename records,
      and records that renamed and moved, keep "Undo: <title>". Tested.
- [ ] VoiceOver: "Moved back" announced; the finished toast title announced.
- [ ] New CI snapshots, light and dark: `settings-general-subfolders-sorting`, `sort-confirm`, `sort-nothing`,
      `toast-sort-batch`, `toast-sort-stopped`, `toast-moved-back`, `menu-sorting`, `menu-undo-move`.
- [ ] Real-Mac checks: the sheet alert over the Settings window; the progress row and Stop; Stop Sorting from the menu
      with Settings closed; Finder after a real sort of a few hundred files; Undo All of that sort and the "Moved back"
      toast; View in Search opens the batch.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green (all moves through
      `FileOrganizer`); `docs/core-api.md` and dated wiki lines.
- [ ] **Done only when `macos-app` CI is green** on the PR.
