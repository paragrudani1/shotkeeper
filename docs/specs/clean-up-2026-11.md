# Clean-up spec (wave 4, 2026-11-28)

Parag's requirements are copied verbatim below. Do not edit them. Everything after them is synthesis by the design
sub-agent (2026-11-28) and must not contradict them. Add dated implementation notes and deviations to the wiki
(`docs/wiki/clean-up.md`, once it exists), not here.

## Requirements (Parag, 2026-11-28)

> 2026-11-28: "Clean-up help: find duplicates and offer to bin old screenshots you never opened." (approved: "let's do all of it")

> 2026-11-28 (decision): "Move to Trash: shows the list and moves what you tick to the Trash after you confirm. You can get them back from the Trash or with Undo. The rule gets a written exception."

---

## Basis

- Code state: origin/main at `0e755e8`. It includes PR #9 (prefactor A: `ScreenshotIndex.columns`, the `changes()`
  feed, `IndexedScreenshot.testRow`, the settings round-trip test) and PR #10 (prefactor B: `FileActions` with one
  `FileActions+<Feature>.swift` per feature, `SearchResultActions`, `WorkspaceActions`, `SearchKeyMap` in core,
  `scripts/lint.sh`). If later merges change their shape, follow the merged code, not this text.
- Survey: `docs/wiki/roadmap-survey.md`, feature 6, the hotspots table and prefactors 3, 4 and 7.
- Decisions: `docs/wiki/workflow.md`, 2026-11-28 ("Clean-up: move to Trash…", wave order).
- Index rules: `docs/wiki/prefactor-index.md` (column table, migration numbers claimed at merge, `shippedColumns`,
  change feed). App structure and lint: `docs/wiki/prefactor-app.md`.
- **Comes after waves 1 and 2**, which change the same index, undo log and search panel:
  - `docs/specs/search-filters-and-text-2026-11.md` (wave 1): the OCR `text_status` column and
    `TextRecognitionRunner`, the search refresh from the change feed, ⇧⌘ keys.
  - `docs/specs/subfolders-and-retitle-2026-11.md` (wave 2): subfolders inside the organized folder,
    "Sort Existing" (`sortPlan`/`sort` on `ScreenshotProcessor`, one undo record per move, Undo All), `title_source`,
    Analyse Again (`reanalyze(rowID:)`), the `Moved back` toast wording, and the open cost of `UndoLog.undo(id:)`
    reading the whole log per record.
  This spec reuses wave 2's pattern on purpose: plan (pure, read-only), then run (one file at a time, undo record
  right after each move), with one summary toast and Undo All.

### Code facts this spec relies on (origin/main `0e755e8`)

- `ContentFingerprint` is `v1:<size>:<mtime ms>:<FNV-1a 64 of the first 64 KiB>`. It is a "skip what we already did"
  key, not a content identity: a copy made with a fresh modification time gets a different fingerprint.
- `ScreenshotProcessor.process`: when a file's fingerprint matches a final row at another path whose file still
  exists, the file is skipped as `.alreadyIndexed` **with no index row**. A copy with a different mtime gets its own
  row and is analysed (and uploaded) again.
- `FileOrganizer` is the only mover (no-replace `NoReplaceRename`, injected primitive for tests). Nothing in
  `Sources` or `App` trashes or deletes a user file. `UndoLog` writes only `move` and `undo` lines, and its revert is
  a no-replace `FileOrganizer.move(to → from)`.
- `scripts/lint.sh` rule `file-op` already lists `trashItem` and `recycle(`. It allows file-op calls only in
  `FileOrganizer`, `NoReplaceRename` and `UndoLog`, plus lines with a reasoned `lint-allow` marker.
- `ScreenshotIndex.search(_ query:)`, `recentProcessed` and the menu count consider only `status = 'done'` rows.
  `lookup(byHash:)` does not filter on status.
- Nothing records that a screenshot was opened.

## Problem Statement

Screenshots pile up. Shotkeeper names and indexes them, so they are easy to find, but nothing ever goes away. After a
few months the user has hundreds of screenshots they took for a moment (a code to type in, a map, a confirmation)
and never looked at again, plus copies of the same file: one Shotkeeper organized, another left on the Desktop by a
Finder "Duplicate", a drag or a sync conflict. Finding these by hand means opening folders, sorting by date and
comparing files by eye, so nobody does it.

Deleting files is also the one thing Shotkeeper has promised never to do. AGENTS.md and CODING_STANDARDS #1 say no
code path deletes a user file. Parag decided that clean-up may move files to the Trash, only those the user ticked
and confirmed, with a way back. That needs a written exception, and the exception must be narrow enough that the
promise still means something.

## Solution

A **Clean Up** window lists two kinds of screenshots in the watched folder and the organized folder:

- **Duplicates**: files whose bytes are identical. They are shown in groups. One copy in each group is marked
  **Keep** (the one Shotkeeper organized, unless the user picks another). The other copies can be ticked.
- **Never opened**: screenshots taken more than a chosen time ago (3 months by default) that the user has never
  opened, in Shotkeeper or (as far as macOS knows) anywhere else.

The user ticks what should go and presses **Move to Trash…**. A confirmation says how many files and how much space,
and that they can be put back from the Trash or with Undo. After confirming, Shotkeeper checks each file once more
and moves it to the Trash. A file that changed since it was listed is left alone. A summary toast says what happened
and offers **Undo All**. Undo puts every file back where it was, with its name, and search shows it again with its
title and tags. Nothing is ever deleted: Shotkeeper never empties the Trash and never removes anything from it.

## User Stories

Finding duplicates
1. As a user, I want Shotkeeper to find screenshots that are exact copies of each other, so that I can get rid of the extra copies.
2. As a user, I want "exact copy" to mean byte-for-byte identical, so that two screenshots that only look alike are never offered as duplicates.
3. As a user, I want copies found even when their dates differ (a copy made with `cp`, a sync conflict "Name 2.png"), so that the dates don't hide them.
4. As a user, I want copies Shotkeeper skipped without indexing (the second copy of a file it already processed) to be found too, so that the copies it never showed me in search are covered.
5. As a user, I want copies grouped, with one copy kept in each group, so that I can never bin every copy by mistake.
6. As a user, I want the kept copy to default to the one Shotkeeper organized and indexed, so that the copy with the good name and the search entry stays.
7. As a user, I want to choose a different copy to keep, so that I can keep the one in the place I prefer.
8. As a user, I want to see each copy's folder, name, date and size, so that I can tell which is which.
9. As a user, I want the extra copies in each group ticked for me, so that clearing duplicates is one confirmation.
10. As a user, I want search to keep finding the kept copy, even if I keep a copy Shotkeeper had not indexed, so that the title and tags aren't lost.
11. As a user, I want only image files that are copies of a screenshot Shotkeeper knows, so that my other files are never listed.

Finding old screenshots I never opened
12. As a user, I want a list of screenshots older than a time I choose that I never opened, so that I can bin the ones I took and forgot.
13. As a user, I want to choose how old is "old" (1 month, 3 months, 6 months, 1 year), so that the list matches how I work.
14. As a user, I want the age counted from when the screenshot was taken, not when Shotkeeper processed it, so that "Process Existing" doesn't make old screenshots look new.
15. As a user, I want opening, Quick Look, revealing, copying, copying text, dragging out and renaming in Shotkeeper to count as opening, so that screenshots I used are never listed.
16. As a user, I want a screenshot I opened in Finder or another app to count as opened too, when macOS recorded it, so that the list isn't only about Shotkeeper.
17. As a user, I want to see when Shotkeeper started recording opens, so that I know older opens may be missing.
18. As a user, I want screenshots I restored with Undo left out of this list, so that a file I told Shotkeeper to leave alone stays alone.
19. As a user, I want a screenshot that is listed as a duplicate not to be listed again here, so that each file appears once.
20. As a user, I want nothing in this list ticked for me, so that binning old screenshots is always my own choice.
21. As a user, I want "Select All" and "Select None" for the list, so that a long list is quick to handle.
22. As a user, I want to Quick Look a listed screenshot without it counting as opened, so that checking a file doesn't remove it from the list.

Moving to the Trash
23. As a user, I want nothing to move until I press "Move to Trash…" and confirm, so that clean-up never surprises me.
24. As a user, I want the confirmation to say how many files and how much space, so that I know what I'm confirming.
25. As a user, I want the files moved to the Trash, not deleted, so that I can get them back from the Trash.
26. As a user, I want a file that changed since the list was made to be left alone, so that a file I edited is never binned from a stale list.
27. As a user, I want a duplicate binned only if its kept copy is still there and still identical, so that I never lose the last copy.
28. As a user, I want files outside my watched and organized folders never touched, so that clean-up can't reach the rest of my Mac.
29. As a user, I want a file on a disk that has no Trash left alone, with the reason, so that nothing is ever deleted instead.
30. As a user, I want a summary that says how many files went to the Trash and why any were left, so that I know the result.
31. As a user, I want to stop a long run, so that a mistake doesn't run to the end.
32. As a user, I want binned screenshots gone from search, the menu's Recent list and the index count at once, so that search never offers a file in the Trash.
33. As a user, I want Shotkeeper never to empty the Trash or remove anything from it, so that the Trash stays mine.

Getting files back
34. As a user, I want Undo All in the summary toast, so that one click puts everything back.
35. As a user, I want the menu's Undo to put back the files from my last clean-up, so that I can undo after the toast is gone.
36. As a user, I want a put-back file at its old place with its old name, so that nothing about it changed.
37. As a user, I want a put-back screenshot to come back in search with its title, tags and text, without being analysed or uploaded again, so that Undo is free and private.
38. As a user, I want Finder's "Put Back" (or dragging the file out of the Trash to where it was) to work as well as Undo, so that I can use the Trash the way I always do.
39. As a user, I want a clear message when Undo can't put a file back because the Trash was emptied, so that I know it's gone.
40. As a user, I want a clear message when Undo can't put a file back because another file now has its place, and the file left in the Trash, so that nothing is replaced.
41. As a user, I want a put-back screenshot not to be renamed, moved or analysed again, so that Undo puts things exactly as they were.

Trust
42. As a user, I want the list to be read-only until I confirm, so that opening Clean Up is always safe.
43. As a user, I want the list to refresh, or tell me it is out of date, when files change while it is open, so that I don't act on old information.
44. As a VoiceOver user, I want the groups, the Keep choice, the ticks and the result announced, so that I can use Clean Up without seeing it.
45. As a keyboard user, I want to tick, untick, Quick Look and confirm without the mouse, so that clean-up is quick.

## Implementation Decisions

### Where clean-up looks (scope)

- **Clean-up scope** is a pure core value built from the settings snapshot: the watched folder (direct children only,
  as the watcher sees it) and the organized folder (any depth, wave 2 subfolders included). Nothing else.
- A file is **in scope** only if all of these hold:
  - its symlink-resolved, standardized path is a direct child of the watched folder, or below the organized folder
    (compared by path components, not string prefix);
  - it is a regular file, not a symlink, not hidden (no component starting with "."), not inside a package, and not a
    `FileOrganizer` temp file;
  - its extension is one of `ScreenshotDetector.imageExtensions`;
  - in the watched folder: it has an index row, or `ScreenshotDetector` calls it a screenshot. So a Desktop that is
    also the watched folder never offers the user's own photos.
- The walk does not follow symlinked folders and skips hidden folders, so the Trash itself is never walked even if
  the organized folder is the home folder.
- Scope is checked twice: when listing, and again for each file right before it moves, against the settings snapshot
  at that moment. If the user changed the watched or organized folder in between, a file outside the new scope is
  skipped as "outside your folders".

### Exact duplicates

- **Definition:** two in-scope files are duplicates when their bytes are identical.
- **The fingerprint is not good enough** for this, for two reasons:
  - it includes the modification time, so the commonest copies (`cp`, a sync conflict) don't match;
  - it covers only the first 64 KiB, so two different screenshots of the same size with the same top rows would match.
- **How groups are found (listing):**
  1. Stat every in-scope file and group by size. A size seen once can't be a duplicate, and in practice most are
     seen once (compressed PNGs rarely share an exact byte count), so most files are never read.
  2. For each size with two or more files, compute a full-content digest: FNV-1a 64 over every byte, in core, as a
     sibling of `ContentFingerprint`. SHA-256 isn't available to core on Linux without a dependency (the
     fingerprint's own comment), and the digest only groups. It is not the safety check.
  3. Files with equal size and digest form a group.
  4. **Before each move, the copy about to be binned is compared byte for byte with the group's kept copy.** That
     comparison is the guarantee. A digest collision can at worst list two different files together; it can never
     bin one.
- **Nothing is stored:** no digest column. Digests are computed only for size collisions, at listing time, so a
  stored one would mostly go stale and need its own invalidation. Measure on a real Mac with a few thousand files; if
  listing is slow, add a cache keyed by fingerprint then, with a dated wiki line.
- **A group is listed only if at least one copy has a `done` index row.** So a group is always anchored on a
  screenshot Shotkeeper knows, and two identical images the user keeps for their own reasons are never offered.
  Rowless copies are included: in the watched folder (the ones `.alreadyIndexed` skipped) and in the organized folder.
- **Which copy is kept by default**, in order:
  1. a copy restored with Undo (the user told Shotkeeper to leave it alone);
  2. a copy with a `done` row;
  3. a copy inside the organized folder;
  4. the oldest capture date;
  5. the shortest path, then alphabetical (so the choice is deterministic).
  The user can pick any other copy as Keep. Exactly one copy per group is always Keep, so a group can never be
  ticked away completely.
- **Rows of binned duplicates:**
  - A binned copy with a `done` row is marked trashed (below), so Undo brings its analysis back.
  - If the user keeps a **rowless** copy and bins the only copy with a row, the row **follows the kept copy**
    (`updatePath`, publishes `.updated`) instead of being marked trashed. Search keeps the screenshot, now at the
    kept path. Undo of that move puts the file back as a rowless copy, as it was before.
- **Pending, failed or skipped rows** (queued, retrying, restored without analysis) are never listed as copies to
  bin. They may still be the Keep copy.

### Near-duplicates: out of scope

Visually similar screenshots (the same window a minute apart, a re-capture) are not offered. Reasons:

- Finding them needs pixels: decoding every image and a perceptual hash. That is ImageIO/Vision, app-only, so the
  core couldn't test the rule on Linux.
- It costs a full decode of every screenshot, not a stat.
- "Looks alike" is exactly the case where two files hold different information (two chat screenshots of the same
  thread, before and after a reply). Binning one loses content, and a user reviewing a long list of near-identical
  thumbnails is the setting for that mistake.
- A byte-identical copy loses nothing when binned. That is the only kind this spec offers.

A later spec could list near-duplicates for review with nothing pre-ticked; it would need its own research note.

### "Never opened"

- **Recorded by Shotkeeper:** a new index column `last_opened_at REAL` (nullable). It is set to now by every explicit
  action the user takes on one screenshot in Shotkeeper:
  - Open (search ↩, menu Recent row), Quick Look in the search panel (Space/⌘Y), Reveal in Finder (⌘R);
  - Copy image (⌘C), Copy Text (wave 1, ⇧⌘C), dragging a result out;
  - Edit name (toast and search, wave 2), Analyse Again (wave 2).
  Not counted: appearing in results, being selected or shown in the preview, a toast appearing, an Undo, and
  anything done inside the Clean Up window (Quick Look there is for deciding, story 22).
- **Which actions count is a core rule**, not scattered app calls: each core search action (`SearchKeyMap`'s action
  enum) says whether it counts as an open. The app's `SearchResultActions`, the menu's Recent rows and `FileActions`
  call one core entry point, `recordOpened(rowID:)`, after the action succeeds.
- **Recorded by macOS (app only):** Finder's "Last opened" date, the Spotlight attribute `kMDItemLastUsedDate`, read
  in the app through a small core port (`LastUsedDates`, URL → `.date(Date)` / `.never` / `.unknown`) and passed into
  the plan. It is read at listing time and never stored, because it changes outside Shotkeeper.
  - **Needs a research note before code** (`docs/research/`, AGENTS.md "no guessing"): which opens update it (Finder,
    `open`, an app's Open dialog, Quick Look in Finder, Shotkeeper's own `NSWorkspace.open`); whether it can be read
    without Spotlight indexing; what it returns on a volume with Spotlight off.
  - `.unknown` (unreadable, Spotlight off) does not hide a file. It is listed with the note "macOS has no record".
    The user ticks every file here themselves, and the Trash keeps it, so listing is the safe direction. See
    "Decisions".
  - Rejected: the file's access time. Shotkeeper itself reads every file (fingerprint, OCR), and APFS updates access
    time lazily, so it says nothing about the user.
- **"Never opened"** = no `last_opened_at` in the index, and macOS's last-used date is `.never` or `.unknown`. A file
  opened once, however long ago, is not listed (Parag's words: "never opened").
- **Before this feature, Shotkeeper recorded no opens.** The migration leaves `last_opened_at` NULL for every
  existing row. So, for the first months, Shotkeeper's half of the rule is weaker than it will be. The app records
  the first launch with this feature as `AppSettings.opensRecordedSince` (one new `CodingKeys` line; the round-trip
  test covers it), and the list says "Opens in Shotkeeper recorded since <date>". Nothing is hidden because of it;
  macOS's date covers the earlier time.
- **A save never erases an open:** the upsert keeps the later of the stored and the saved `last_opened_at`, so a
  stale copy of a row saved by `process` or `reanalyze` can't undo a `recordOpened` that ran in between. This is a
  per-column merge rule in the column table, the first one; it gets a test. A row whose file content changed
  (`process` makes a new entry) starts again with NULL, since the opened file was a different image.

### "Old"

- **Age** = now − `captured_at` (the file's creation date, as the pipeline stores it). A row with no `captured_at`
  uses the file's creation date at listing time, then its modification date.
- **Choices:** 1 month, 3 months, 6 months, 1 year. **Default: 3 months.** Chosen in the Clean Up window and
  remembered as `AppSettings.cleanUpAge` (one `CodingKeys` line). The clock is injected, as in every core time rule.
- **Candidates:** rows with `status == done`, not `restored_by_undo`, file present at the indexed path, in scope,
  older than the age, never opened, and not already listed as a duplicate. Files without an index row are not in
  this list: Shotkeeper can't say anything about a file it never indexed.
- Nothing in this list is pre-ticked.

### The plan (core, read-only)

- **`ScreenshotProcessor.cleanUpPlan(age:lastUsed:) -> CleanUpPlan`**, in its own extension file next to wave 2's
  `sortPlan`. It reads the index, walks the scope, stats files, hashes only size collisions, asks the `LastUsedDates`
  port, and returns:
  - `duplicateGroups`: each with its copies and the default Keep;
  - `neverOpened`: candidates, oldest first;
  - `opensRecordedSince`, and counts of what was skipped and why (unreadable, outside scope, still processing).
  Each candidate carries the URL, the row id if any, the size, the capture date, the fingerprint read at listing,
  and its location (watched or organized).
- **It writes nothing:** no file, no index row, no undo line, no settings. The dry-run test (below) proves it.
- It runs off the main actor and can be cancelled. The app shows progress while it runs.

### Moving to the Trash: the one choke point

- **`FileOrganizer.trash(_ url:) throws -> URL`** returns the item's URL in the Trash. It is the only code in the
  repository allowed to put a user file in the Trash.
  - The default primitive is `FileManager.trashItem(at:resultingItemURL:)` on macOS. The primitive is injected, like
    `renameNoReplace`, so Linux tests use a fake that does a no-replace move into a temp "Trash" folder and renames
    on a clash. On Linux the default primitive throws "no Trash on this system"; it is never called in tests.
  - **It never falls back to deleting.** A volume without a Trash, a permission error, or a missing resulting URL
    throws, and the file stays where it was.
  - If the primitive moved the file but returned no URL, the file can't be put back with Undo. `trash` throws
    `.trashedWithoutLocation`, and the run reports that file as "in the Trash; put it back from there". The research
    note must say whether that can happen.
  - **Research before code** (same note as the last-used date): `trashItem` on a clash in the Trash (renames,
    never replaces), on external volumes (`.Trashes`), on network volumes and iCloud Drive folders, and **whether
    Finder's "Put Back" works for items moved with `trashItem`**. If it doesn't and `NSWorkspace.recycle` does,
    Parag's "get them back from the Trash" is better served by `recycle`. That one is app-only and asynchronous, so
    the primitive would live in one app file, injected into `FileOrganizer` the same way. The lint rule below then
    names that file instead. Either way there is exactly one file.
- **`scripts/lint.sh` changes in that one place:**
  - A new rule, `trash`: `trashItem(` and `recycle(` are allowed **only** in the file that holds the primitive
    (`FileOrganizer`, or the app file if the research picks `recycle`). Not in `NoReplaceRename` or `UndoLog`, and
    **no `lint-allow: trash` marker is accepted anywhere**: there is no "our own files" case for the Trash.
  - `file-op` drops `trashItem` and `recycle` from its pattern. They move to the new rule, and nothing else changes.
  - The header and the `file-op` message change from "never deleted" to "never deleted; moved to the Trash only by
    FileOrganizer.trash after the user confirmed (CODING_STANDARDS #1)".
  - Self-test cases: `trashItem` in `FileOrganizer` passes; in `UndoLog` it fails; `recycle(` in an app file fails;
    a `// lint-allow: trash (x)` marker still fails. The expected count is updated.

### The run

- **`ScreenshotProcessor.moveToTrash(_ selection: TrashSelection, dryRun: Bool) -> TrashReport`.** A selection is
  the ticked candidates, each with its reason: `.duplicate(keep: candidate)` or `.neverOpened`. With `dryRun: true`
  it runs every check below and reports what would happen, but moves nothing and writes nothing. The confirmation
  uses the dry run to show final counts ("12 files, 34 MB; 1 changed since the list was made"). It is also the
  dry-run test's subject.
- **For each file, in order, with cancel checked between files:**
  1. **Checks**, against the current settings snapshot and the disk:
     - in scope;
     - still at the listed path;
     - fingerprint equal to the one read at listing (the cheap "changed since listing" check: size, mtime and the
       first 64 KiB);
     - its row, if it had one, still `done` and not `restored_by_undo`;
     - for a duplicate: the Keep copy still exists at its listed path, is in scope, is not in this selection, and is
       **byte-identical** to this file (full comparison, streamed).
     A failed check skips the file with a reason: `changedSinceListed`, `missing`, `outsideFolders`,
     `keptCopyMissing`, `keptCopyDiffers`, `stillProcessing`, `restoredByUndo`.
  2. **Move:** `organizer.trash(url)`. A thrown error gives `failed(reason)`, for example `noTrashOnVolume`, and the
     file stays.
  3. **Undo record right after the move** (CODING_STANDARDS #1): `undoLog.appendTrash(from: original, to:
     trashURL, batch:)`. If it can't be written, the file is moved back from the Trash with the no-replace move and
     counted as failed. That is wave 2's rule for `sort`.
  4. **Index:** with a `done` row, one atomic `index.markTrashed(id:, trashPath:)` (below). For the "row follows the
     kept copy" case, `updatePath(from: binned, to: kept)`. Rowless file: nothing.
- **Report:** counts of trashed, skipped (per reason), failed, bytes moved, the undo record ids and the batch id.
- **Nothing here uploads anything:** consent, Pause, exclusion rules and the queue are not involved. Clean-up never
  calls `analyze`.

### Undo and put-back

- **`UndoLog` gains a record kind.** `UndoRecord.kind` is `.move` (today's, and the decode default for old lines
  without a kind) or `.trash`. A trash line is `{"kind":"trash","id","timestamp","from","to","batch"}`. Undo of a
  trash record uses the existing revert: the file must still be at `to` (in the Trash), nothing may be at `from`, and
  then a no-replace `FileOrganizer.move`. An `undo` line follows, as today.
- **`batch`:** an optional UUID on records written by one clean-up run (wave 2's sort can use it too). `records()`
  and `lastUndoable()` keep working per record. The menu's "Undo: …" offers the **whole last batch** when the newest
  record has one, labelled from the count ("Undo: Move to Trash (12 screenshots)"), and runs `undo(ids:)` newest
  first. See "Decisions": this changes the menu for wave 2's sort too.
- **`ScreenshotProcessor.undo` branches on kind:**
  - `.move`: unchanged (`recordRestored`, sets `restored_by_undo`).
  - `.trash`: **does not** set `restored_by_undo`. Putting a file back means "as it was", and the file was never
    renamed by this record. It calls `index.markPutBack(trashPath: to, originalPath: from)`: status back to `done`,
    path back, `trashed_from` cleared, publishes `.updated`. A rowless copy gets no row, as before.
- **Watcher race:** a file put back into the watched folder may reach `process` before or after the index update.
  `process` handles both. Before any analysis it checks for a trashed row whose `trashed_from` equals the file's
  path, with the same fingerprint. If it finds one, it puts that row back (as `markPutBack`) and returns
  `.alreadyIndexed`. This same rule is what makes **Finder's "Put Back"** into the watched folder restore the row.
- **Undo errors** reach the user as `UserFacingProblem`s:
  - `fileNotAtDestination` on a trash record: "It's no longer in the Trash. The Trash may have been emptied." The
    log then gets a `gone` line for that record, so the menu's Undo stops offering it and earlier records become
    reachable again. `gone` lines are ignored by `records()`, like undone ones.
  - `originalPathOccupied`: "A file named <name> is already there. The screenshot is still in the Trash." Nothing is
    replaced, and the record stays undoable.
  - Undo All reports per file, as `undo(ids:)` does today.

### When the Trash was emptied, or the user put files back by hand

- **`ScreenshotProcessor.reconcileTrash()`** runs at launch, when Clean Up opens, and after an undo fails with
  `fileNotAtDestination`. For each `trashed` row:
  - the file is still at `path` (in the Trash): nothing to do;
  - it is gone from the Trash and a file with the same fingerprint is at `trashed_from` (Finder's "Put Back", or a
    drag back, into a folder the watcher doesn't see): put the row back (`markPutBack`);
  - gone from both: the screenshot is gone for good. **`index.remove(id:)`** deletes the row (publishes `.removed`)
    and the matching undo record gets a `gone` line. This is a new index API; prefactor A left delete APIs to the
    feature that needs one. It deletes index data, never a file.
  - The file is somewhere else in the Trash or on disk: not followed. The row is removed once the trash path is
    empty, as above.
- macOS may empty the Trash by itself (Finder's "Remove items from the Trash after 30 days"). The user owns that
  setting; Shotkeeper doesn't read or change it.

### Index schema and change feed (on top of prefactor A and waves 1–2)

- **One migration, number claimed at merge** (the second PR to merge renumbers). The `columns` entries, the
  `addColumns("last_opened_at", "trashed_from")` migration line and the `shippedColumns` line are added together,
  per `docs/wiki/prefactor-index.md`:
  - `last_opened_at REAL`: see "Never opened"; keeps the later value on upsert.
  - `trashed_from TEXT`: the original path of a row whose file is in the Trash; NULL otherwise.
- **`ProcessingStatus.trashed`**, a new status value (TEXT, so no schema change). A trashed row has `status =
  trashed`, `path` = the file's path in the Trash (path keeps meaning "where the file is now", and stays unique), and
  `trashed_from` = where it was.
  - Already excluded by the existing `status = 'done'` filters: search (results and counts), Recent, the menu's
    index count, wave 2's `sortPlan`.
  - Must be excluded explicitly (each gets a test):
    - `lookup(byHash:)` ignores trashed rows. Otherwise a fresh copy of a binned screenshot would be skipped as
      `.alreadyIndexed` and never indexed. Such a copy is analysed as new; see "Out of scope".
    - wave 1's `newestPendingTextRow()` skips trashed rows;
    - wave 2's `reanalyze` refuses a row that isn't `done` (`.refused(.missing)`);
    - `recordOpened` ignores trashed rows.
  - Rule for later waves: **every entry point that acts on a row requires `status == done`**. Wave 3's Spotlight
    sync treats a non-`done` row as absent.
  - Downgrade risk: an older build reads `trashed` as `.pending` (its decode default) and would queue the file in the
    Trash at launch. With manual-only updates (auto-update spec) a downgrade means installing an older build by hand.
    Noted in the wiki, not guarded in code.
- **New index APIs** (all publish under the index lock after the commit, as prefactor A does):
  - `recordOpened(id:at:)`: `.updated`;
  - `markTrashed(id:trashPath:)`: `.updated`, with path, status and `trashed_from` written in one statement;
  - `markPutBack(trashPath:originalPath:)`: `.updated`;
  - `remove(id:)`: `.removed`.
  - The search window's feed refresh drops a binned row and shows a put-back one with no extra code.
  - Opens publish `.updated` like any row write. If the design pass sees the search results flicker on Quick Look,
    the search refresh coalesces events; the feed contract is not changed.

### App side

- **`FileActions+CleanUp`** (the file PR #10 reserved, named for Trash, not Bin): it runs `cleanUpPlan`,
  `moveToTrash` and the batch undo, and shows the summary toast through `ToastBatcher` ("Moved 12 screenshots to the
  Trash" with **Undo All** and, when files were skipped, the reasons). The menu's batch Undo lives here too.
- **`CleanUpReviewState`** (core, new): the window's state. It holds the plan, the age choice, the per-group Keep,
  the ticks (duplicate extras pre-ticked, never-opened unticked), Select All/None per section, the totals for the
  button and confirmation, the dry-run result, the running/stopped/finished state and the "list is out of date"
  flag. The flag is set by index change-feed events for listed rows, and by a failed check during a run. The SwiftUI
  view only renders it, as `SearchWindowState` does for search.
- **`LastUsedDates`** real implementation: an app type reading `kMDItemLastUsedDate` (per the research note).
- **Recording opens:** `SearchResultActions`, the menu's Recent rows and `FileActions` call
  `recordOpened(rowID:)` for the actions whose core action says "counts as opened". Quick Look in the Clean Up
  window does not.

### The written exception (lands in the same PR as `FileOrganizer.trash`)

The rule is reworded in both places in the same PR as the code, and the old wording isn't left anywhere.

**AGENTS.md**, "Rules", first bullet. Draft:

> - Never delete or overwrite a user file. Moves/renames must fail rather than replace. **One written exception:**
>   Clean Up may move a screenshot to the Trash, only after the user ticked it and confirmed, only through
>   `FileOrganizer.trash`, never outside the watched or organized folders, with an undo record per file
>   (CODING_STANDARDS #1, `docs/specs/clean-up-2026-11.md`). Nothing empties the Trash or deletes from it.

**CODING_STANDARDS.md #1.** Draft:

> 1. **User files are sacred.** Every rename/move goes through `FileOrganizer` (no-replace primitives). No code path
>    deletes a user file; on any error the file stays where it was, and the undo log is written as soon as a move
>    happens. **One exception, moving to the Trash (Parag, 2026-11-28):** `FileOrganizer.trash` is the only call
>    that puts a user file in the Trash, and only Clean Up calls it. It may run only when (a) the user ticked that
>    file in Clean Up's list and confirmed, (b) the file is in the watched folder or anywhere below the organized
>    folder, checked again right before the move, (c) its fingerprint still equals the one listed, and for a
>    duplicate the kept copy still exists and is byte-identical, and (d) a `trash` undo record is written right
>    after the move, or the file is put back. Nothing empties the Trash, removes a file from it, or falls back to
>    deleting when a volume has no Trash. `scripts/lint.sh` (rule `trash`) allows the system Trash call in one file
>    only, with no `lint-allow` exceptions.

The same PR:
- updates the `file-op` message and header in `scripts/lint.sh`, and the `FileOrganizer` and `UndoLog` doc comments
  ("Never overwrites and never deletes a user file" gains "; moves to the Trash only from `trash(_:)`");
- updates `WorkspaceActions`'s comment ("Nothing here moves, renames or deletes a file") only if it changes;
- adds `docs/core-api.md` entries;
- adds a dated decision line to `docs/wiki/workflow.md` that points at the new wording, and starts
  `docs/wiki/clean-up.md`.

### Build order

1. **Research note** (trash primitive, Put Back, last-used date): no code before it.
2. **Core PR:** migration, `trashed` status, index APIs, `ContentDigest`, scope, `cleanUpPlan`, `FileOrganizer.trash`
   with the injected primitive, `moveToTrash` with dry run, undo kinds and batches, `reconcileTrash`, the `process`
   put-back rule, `recordOpened`, `CleanUpReviewState`, the lint rule, **and the written exception**. The
   exception lands with the first code that can trash.
3. **Design pass** (below), in parallel with 2.
4. **App PR:** window, confirmation, toasts, menu batch undo, `LastUsedDates`, opens wiring, the real primitive,
   snapshots.

## UI surfaces for the design pass (behaviour and states only)

The design pass (`docs/wiki/workflow.md`, "UI design step") writes `docs/design/clean-up.md` and a mockup. It works
within the polish spec's identity and the approved wave 1 and 2 designs. Layout, copy and where things sit are its
call; the behaviour below is not.

1. **Entry point:** a "Clean Up…" item in the status menu (recommended), opening a regular window. It is not part of
   the non-activating search panel: the list needs checkboxes, a confirmation sheet and focus. If the design pass
   prefers a Settings button as well, both open the same window.
2. **Clean Up window:**
   - two sections, Duplicates and Never opened, each with a count and total size;
   - the age choice for Never opened (1 month, 3 months, 6 months, 1 year);
   - a note "Opens in Shotkeeper recorded since <date>" and, per file, "macOS has no record" when that applies;
   - one primary button, **Move to Trash…**, with the ticked count (disabled at 0).
   - States:
     - scanning (progress, cancellable);
     - no watched or organized folder set (say which, with a way to Settings);
     - a folder missing or unreadable;
     - nothing found in either section, or in one;
     - many results (hundreds of rows, thousands of files scanned);
     - list out of date (offer Refresh);
     - running (progress, Stop);
     - finished with skips or failures.
3. **Duplicate group row:** each copy with thumbnail, name, folder (watched / organized › subfolder), date and size.
   A Keep choice (exactly one per group) and a tick on the others. A copy that isn't in search (rowless) is marked
   as such. Keeping a rowless copy says that the search entry will follow it.
4. **Never-opened row:** thumbnail, title, date taken, folder, size, tick. Quick Look (Space) from the list does not
   count as opened.
5. **Confirmation:** count, total size, and that files can be put back from the Trash or with Undo. It shows the dry
   run's surprises before confirming ("1 file changed since the list was made and will be left"). Default button is
   Cancel or Move to Trash: the design pass's call, with the destructive-action convention in mind.
6. **Result toast:** "Moved N screenshots to the Trash" with Undo All; skipped and failed counts with readable
   reasons; a single-file variant.
7. **Menu bar:** "Undo: Move to Trash (N screenshots)" for the last batch; the design pass checks the wording next to
   wave 2's sort batch.
8. **Undo messages:** put back; can't put back (Trash emptied); can't put back (a file is in its place, still in
   the Trash).
9. **Keyboard and VoiceOver:** Space ticks, ⌘Y Quick Look, ↑↓ moves, a key or menu to change Keep, ⌘⌫ (Finder's
   Move to Trash key) opens the confirmation, Esc cancels the sheet. Announcements for scan finished, ticks, Keep
   changes and the result.
10. **CI snapshots, new states:** every window state above, both row kinds, the confirmation with and without dry-run
    surprises, and each toast.

## Testing Decisions

- **Good tests** drive public behaviour through the highest seam and check what the user would see: which files are
  where on disk (watched folder, organized folder, the fake Trash), their bytes, what the index rows say, which undo
  records exist, and what the window state says. They don't check SQL, private helpers or call counts. No test needs
  the network, a Mac, the real Trash or Spotlight. Fixtures use `IndexedScreenshot.testRow` and `TempDir`.
- **Seam 1: `ScreenshotProcessor`** (existing; prior art `ScreenshotProcessorTests`, and wave 2's `sortPlan`/`sort`
  tests). Fixture: `TempDir` with a watched folder, an organized folder (with subfolders) and a fake Trash folder;
  in-memory `ScreenshotIndex`; real `UndoLog`; `FileOrganizer` with the fake trash primitive; a fake `LastUsedDates`;
  an injected clock. Through `cleanUpPlan`, `moveToTrash`, `undo`/`undo(ids:)`, `reconcileTrash`, `process` and
  `recordOpened`, it covers:
  - **the dry-run test:** `cleanUpPlan`, then `moveToTrash(dryRun: true)` over everything listed, leave the tree
    byte-identical (every path, size, mtime and content digest compared before and after), the undo log unchanged,
    the index unchanged (no feed events), and the fake Trash empty;
  - duplicates: copies with different mtimes found; same size but different bytes not grouped; a forced digest
    collision (injected digest) is listed but refused at the byte comparison; groups without a `done` row not
    listed; rowless copies included; default Keep order; one Keep per group;
  - scope: files outside both folders, in a watched-folder subfolder, symlinks, hidden files, non-screenshots on a
    Desktop-like watched folder, a symlinked folder inside the organized folder: never listed, never moved; a scope
    change between listing and the run skips;
  - never opened: age boundaries with the injected clock; `captured_at` vs file dates; `recordOpened` hides a row;
    macOS `.date` hides it, `.never` and `.unknown` don't; restored rows excluded; duplicates not listed twice;
    `last_opened_at` survives a stale save;
  - the run: changed fingerprint, missing file, row no longer `done`, kept copy gone or different → skipped with the
    reason, file untouched; a primitive error leaves the file in place; no-Trash error never deletes; undo-record
    failure puts the file back; cancel between files; the row follows a kept rowless copy;
  - undo: put back with name and place, row `done` again with title and tags and no `restored_by_undo`; a batch
    undone newest first; original path occupied → file stays in the Trash, record still undoable; file gone from
    the Trash → error, `gone` line, menu target moves to the previous record;
  - reconcile: emptied Trash removes the row (`.removed`); a hand put-back restores it; the `process` put-back rule
    (a file reappearing at `trashed_from`) restores the row and analyses nothing (the stub analyzer records no call);
  - a fresh copy of a binned screenshot is processed, not skipped as `.alreadyIndexed`;
  - change-feed events for trash, put-back and removal, in commit order.
- **Seam 2: `CleanUpReviewState`** (new, core; prior art `SearchWindowTests`): ticks and pre-ticks; Keep switching
  (the old Keep becomes tickable, the new one unticked); Select All/None; totals; the dry-run result on the
  confirmation; out-of-date on a feed event for a listed row; running → stopped/finished; each report reason's
  message.
- **Seam 3: `scripts/lint.sh --self-test`** (existing): the new `trash` cases listed above.
- **Not new seams, one more case each in existing tests:**
  - `ScreenshotIndexTests`: the migration and `shippedColumns`; `trashed` rows absent from search, Recent, counts and
    `lookup(byHash:)`; `remove(id:)`; the later-value upsert rule for `last_opened_at`.
  - `UndoLogTests`: old lines without a kind decode as `.move`; trash records; batches; `gone` lines.
  - `SearchKeyMapTests` (or the core action enum's test): which actions count as an open.
  - `SettingsTests`: the round-trip test picks up `cleanUpAge` and `opensRecordedSince`.
  - `FileOrganizerTests`: `trash` with the fake primitive (clash in the Trash renames, never replaces; error leaves
    the file).
- **App side, CI snapshots and a real Mac only:** the real `trashItem` (or `recycle`) primitive, Finder's Put Back,
  `kMDItemLastUsedDate` values after Finder/Preview/Quick Look opens, external and network volumes, the window and
  confirmation focus, VoiceOver.

## Out of Scope

- Near-duplicates (visually similar screenshots); see above.
- Emptying the Trash, deleting anything, or any "delete immediately" option.
- Automatic or scheduled clean-up, reminders or badges ("You have 200 old screenshots").
- Files outside the watched folder (direct children) and the organized folder (any depth); files Shotkeeper never
  indexed in the Never opened list.
- Reusing a binned screenshot's analysis for a fresh copy of it (the copy is analysed as new).
- A size or storage dashboard; sorting the list by size.
- Clean-up from the CLI.
- Spotlight and Shortcuts (wave 3), auto-update.

## Further Notes

- **Cost:** listing stats every in-scope file and reads only same-size files in full. The organized folder could in
  theory be a large folder (the home folder); the walk reports progress and can be cancelled. Measure on a real Mac
  and record the numbers in the wiki.
- **Wave 2's known cost** (`UndoLog.undo(id:)` reads the whole log per record) also applies to Undo All here. If
  wave 2 adds a batch undo that reads the log once, this uses it.
- **Hotspots touched:** `ScreenshotIndex` (migration number at merge), `ScreenshotProcessor` (extension file only,
  plus the put-back rule in `process` and the `undo` branch), `UndoLog`, `AppSettings` (two lines), `FileActions`
  (its own extension file), `SearchResultActions` (open recording), the status menu, `scripts/lint.sh`,
  `UISnapshotTests` (own file per screen).
- Waves 1 and 2 must land first: this spec adds conditions to wave 1's OCR runner and wave 2's `reanalyze`, and uses
  wave 2's subfolders in scope and Keep display.

## Decisions Parag might disagree with

1. **Exact duplicates only** (byte-identical), with a byte-for-byte comparison right before each move; no
   near-duplicates.
2. **Duplicates must include a screenshot Shotkeeper indexed;** rowless copies in the watched folder and image files
   anywhere in the organized folder can be offered as extra copies.
3. **Default Keep:** restored copy, then indexed, then organized, then oldest. The extra copies are **pre-ticked**;
   Never opened is **not**.
4. **"Opened" = any explicit action on one screenshot in Shotkeeper** (open, Quick Look, reveal, copy, copy text, drag,
   rename, Analyse Again), **or** macOS's last-used date. Quick Look inside Clean Up doesn't count.
5. **"Never" means never:** a file opened once, long ago, is not listed.
6. **macOS has no record → still listed,** with a note, rather than hidden.
7. **Old = 3 months by default** (1/3/6/12 months), counted from when it was taken.
8. **Restored-by-Undo screenshots** are never in Never opened and are the preferred Keep.
9. **The index keeps a binned row** (status `trashed`) so Undo or Finder's Put Back brings back title, tags and text
   for free. The row is deleted once the file has left the Trash.
10. **Menu Undo takes back the whole last clean-up**, not one file; wave 2's sort batches get the same treatment.
11. **`FileManager.trashItem` in core `FileOrganizer`,** unless the research shows Finder's Put Back needs
    `NSWorkspace.recycle`; then one app file holds it. Either way, the lint allows it in exactly one file with no
    exceptions.
12. **A separate Clean Up window from the status menu,** not a mode of the search panel.
