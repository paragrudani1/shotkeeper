# 09: When Undo can't put a file back, and Finder's Put Back

**What to build:** the way back works when it goes around Shotkeeper or fails. If the user empties the Trash (or
iCloud or Finder's 30-day rule does), Undo says "It's no longer in the Trash; the Trash may have been emptied", the
menu stops offering it and the screenshot's row is removed. If a file now has its name, or its folder is gone, or the
Trash can't be reached, Undo says so, replaces nothing, keeps the file in the Trash and keeps Undo in the menu (Reveal
in Finder shows it in the Trash). If the user uses Finder's Put Back, or drags the file back, search shows it again
with its title and tags, and nothing is analyzed.

**Blocked by:** 07 (trash records exist in real use; the success path of undo). Uses 01's `remove(id:)` and
`markPutBack` and 03's `gone` lines.

**Status:** ready-for-agent

**Sources:** spec "Undo and put-back" (watcher race, undo errors), "When the Trash was emptied, or the user put files
back by hand", stories 38–40; design §8 ("Can't move back"), §4 (reconcile on open), §14 spec departure 10; research
§3 ("The move back", "Detecting that the Trash was emptied", "Answer to spec question 3"), §4. The research wins over
the spec here (README).

**Test seam:** seam 1 (`ScreenshotProcessor.undo`/`undo(ids:)`, `reconcileTrash()`, `process`), with the fake Trash
and a primitive that can return `ENOENT`, `EEXIST` and `EPERM`; `Feedback` tests for the messages.

**Likely touches:** core `ScreenshotProcessor` (`process` put-back rule, `undo` errors), `ScreenshotProcessor+CleanUp.swift`
(`reconcileTrash`), `UndoLog` (`markGone`), `Feedback/UserFacingError.swift`, `Feedback/Toast.swift`; app
coordinator launch hook, `FileActions+CleanUp.swift` (reconcile on open and after a failed undo), `ToastSnapshots`.

- [ ] Undo errors, chosen in this order (research §3): source missing in the Trash (`ENOENT` on the source) →
      `fileNotAtDestination`, "It's no longer in the Trash…", a `gone` line, the menu target moves to the previous
      record; `EEXIST` → `originalPathOccupied`; destination folder missing → "The folder <name> no longer exists"
      (**Undo never recreates a folder**); `EPERM` → "Can't reach the Trash… Nothing changed" (**never treated as
      gone**). The last three keep the record undoable and the file in the Trash. Undo All reports per file.
- [ ] `reconcileTrash()` at launch, when Clean Up opens and after a `fileNotAtDestination` undo, per `trashed` row:
      still in the Trash → nothing; gone and the same fingerprint at `trashed_from` → `markPutBack`; gone from both
      (`ENOENT` only) → `remove(id:)` (`.removed`) and a `gone` line; `EPERM` or any other error → keep the row
      (research §3). Files moved elsewhere aren't followed. It never lists the Trash, only `lstat`s stored paths
      (research §4).
- [ ] `process` put-back rule: before any analysis, a file whose path equals a trashed row's `trashed_from` with the
      same fingerprint puts that row back and returns `.alreadyIndexed`, whether the watcher or the index update runs
      first. This is what makes Finder's Put Back into the watched folder restore the row.
- [ ] Seam 1 tests: emptied Trash removes the row; a hand put-back restores it (outside the watched folder through
      reconcile, inside it through `process`; the stub analyzer records no call); occupied path keeps the file in the
      Trash and the record undoable; gone file → error, `gone` line, menu target moves; `EPERM` keeps the row.
- [ ] Error toasts per design §8 with Reveal in Finder (selects the file in the Trash) for name taken and folder gone.
- [ ] New CI snapshots, light and dark: `toast-cant-move-back-emptied`, `toast-cant-move-back-name-taken`,
      `toast-cant-move-back-folder-gone`.
- [ ] Real-Mac checks: research **1** (Finder's Put Back of a batch, then search shows the rows again), **5** (Undo of
      an evicted iCloud Desktop file after it re-syncs; emptying the Trash then Undo), **7** (`lstat` and rename back
      without Full Disk Access; the `EPERM` message if TCC blocks it); "Reveal in Finder" selects a file in the Trash.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green; `docs/core-api.md`; dated
      wiki lines.
- [ ] **Done only when `macos-app` CI is green** on the PR.
