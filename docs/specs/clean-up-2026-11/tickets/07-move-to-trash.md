# 07: Move to Trash: dry run, confirmation, run, summary toast and Undo All

**What to build:** the user presses **Move to Trash…** (or ⌘⌫). Shotkeeper checks every ticked file once more and a
sheet alert says what will move ("Move 12 screenshots to the Trash?", kinds and size, the way back is Undo, any
surprises); Cancel is the default. On Move to Trash, files go to the Trash one by one, with progress and Stop. Each
file that changed, vanished, left the folders, or whose kept copy is gone or no longer identical is left in place
with the reason. Binned screenshots leave search, Recent and the count at once. A summary toast "Moved 12 screenshots
to the Trash" offers Undo All, which puts every file back with its name, and search shows it again with its title,
tags and text, nothing analyzed or uploaded.

**Blocked by:** 01 (`trashed` status, `markTrashed`, `markPutBack`), 02 (`FileOrganizer.trash` and the exception),
03 (trash records, batches, menu Undo), 05 (window and review state). Not blocked by 06: the core run takes both
reasons; whichever of 06 and 07 merges second adds the window-level test for ticked never-opened rows.

**Status:** ready-for-agent

**Sources:** spec "The run", "Undo and put-back" (`.trash` branch of `undo`, success path), "Rows of binned
duplicates", stories 23–37, 41, UI surfaces 5–7; design §5.6 (moving, done, stopped, after Undo All), §6 (moving,
finished), §7, §8 ("Moved to the Trash", "Moved back"), §9 (status line, Stop item), §10; research §1, §3 ("The
move back"), "What this changes in the spec". The research wins over the spec here (README).

**Test seam:** seam 1 (`ScreenshotProcessor.moveToTrash(_:dryRun:)` and `undo(ids:)`, fake trash primitive, real
`UndoLog`, stub analyzer) and seam 2 (`CleanUpReviewState`: dry-run result, running → stopped/finished, reason
messages); `Feedback` toast and `MenuText` tests for wording.

**Likely touches:** core `ScreenshotProcessor+CleanUp.swift` (`moveToTrash`, `TrashSelection`, `TrashReport`), the
`undo` branch on kind in `ScreenshotProcessor`, `CleanUpReviewState`, `Feedback/Toast.swift`, `Feedback/MenuText.swift`;
app `FileActions+CleanUp.swift`, `CleanUpView` (footer states, sheet alert, ⌘⌫ guard), `StatusText`,
`MenuContentView` ("Stop Moving to Trash"), `CleanUpSnapshots`, `ToastSnapshots`, `MenuSnapshots`.

- [ ] **The dry-run test:** `cleanUpPlan`, then `moveToTrash(dryRun: true)` over everything listed leaves the tree
      byte-identical (every path, size, mtime and digest), the undo log unchanged, the index unchanged (no feed
      events) and the fake Trash empty.
- [ ] Per file, cancel checked between files: checks against the current settings and disk (in scope, still at the
      path, fingerprint equal to the listing's, row still `done` and not restored, for a duplicate the Keep copy
      present, in scope, not in the selection and **byte-identical**, streamed) → skip reasons `changedSinceListed`,
      `missing`, `outsideFolders`, `keptCopyMissing`, `keptCopyDiffers`, `stillProcessing`, `restoredByUndo`. Then
      `organizer.trash`; an error → `failed(reason)`, file stays, **never deleted**. Then `appendTrash(…, batch:)`
      right after the move; if it fails the file goes back with the no-replace move and counts as failed. Then
      `markTrashed`, or `updatePath` when the row follows a kept rowless copy; rowless file: nothing.
- [ ] Seam 1 tests for each skip and failure; the forced digest collision refused at the byte comparison; a scope
      change between listing and run skips; cancel between files; the row follows a kept rowless copy; nothing
      calls `analyze`, consent, Pause or the queue.
- [ ] Undo of a trash record (success path): no-replace `renameNoReplace` from the stored Trash URL back to `from`
      (research §3: never `moveItem`, never copy across volumes; `EXDEV` is reported, the file stays), then
      `markPutBack`; **no** `restored_by_undo`; rowless copies get no row. Batch undone newest first. Tests: name,
      place, row `done` with title, tags and text, no analyzer call.
- [ ] Confirmation per design §7: dry run first ("Checking 12 files…" after 0.3 s); title, kinds and size; the way
      back promises **Undo, not Finder's Put Back** (research: Put Back is best-effort for batches, Apple bug
      r. 23153124); surprise lines including the iCloud Drive 30-day line (research §1); **Cancel is the default**,
      Move to Trash destructive; ⌘⌫ ignored for 0.5 s and on key repeat; "Nothing can be moved to the Trash" alert.
- [ ] Run and results per design §5.6, §6, §8, §9, §10: list dimmed while moving; footer progress and Stop; menu
      status "Moving to the Trash: 8 left" and "Stop Moving to Trash"; closing the window doesn't stop the run; toasts
      show even with "Show a toast after each rename" off; Undo All in the toast, the footer and ⌘Z; the window
      checks again after Undo All. One reason wording everywhere (design §6 table); `.trashedWithoutLocation` reported
      as "in the Trash, but Undo can't find it".
- [ ] VoiceOver: "Moving to the Trash", the result, "Moved back".
- [ ] New CI snapshots, light and dark: `cleanup-moving`, `cleanup-finished`, `cleanup-finished-left`,
      `cleanup-stopped`, `cleanup-confirm`, `cleanup-confirm-surprises`, `cleanup-confirm-one`,
      `cleanup-nothing-can-move`, `toast-trash-batch`, `toast-trash-one`, `toast-trash-left`, `toast-trash-stopped`,
      `toast-trash-none`, `toast-moved-back-trash`, `toast-moved-back-partial`, `menu-moving-to-trash`.
- [ ] Real-Mac checks (research list): **1** Put Back after a single file and a batch of 20, Finder Trash window
      closed then open (decides delay vs wording; record in the wiki); **2** resulting URL non-nil every time; **3**
      external APFS, HFS+, exFAT and FAT32 disks (same volume, first trash with no `.Trashes`, Undo back); **4**
      SMB share: `trashItem` must throw and the file must still be at its path (**ship gate**: clean-up doesn't ship
      until this passes); **5** iCloud Desktop, downloaded and evicted file (URL, Undo, re-sync); **6** two files
      with the same name trashed, both kept with their bytes; **7** without Full Disk Access: trash a Desktop file,
      `lstat` the resulting URL and rename it back; note any prompt and the errno. Design §13: Cancel default with ↩
      and Esc; the ⌘⌫ guard (held key, double tap); the stack as the alert icon; toasts with the window in front;
      ⌘Z in the window.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green (no new `trashItem` caller);
      `docs/core-api.md`; dated wiki lines.
- [ ] **Done only when `macos-app` CI is green** on the PR.
