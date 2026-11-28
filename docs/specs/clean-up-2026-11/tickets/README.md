# Wave 4 tickets: Clean Up (2026-11-28)

Tickets for the [spec](../../clean-up-2026-11.md) (all 12 decisions accepted by Parag, 2026-11-28), the approved
[design](../../../design/clean-up.md) (Parag, 2026-11-28, all departures accepted) and the
[Trash research](../../../research/trash-and-last-used.md). Made with the to-tickets skill, local layout: one file per
ticket, blocking edges as text. The spec's requirements are not edited here.

**Base:** clean-up is wave 4. Its integration branch is cut from wave 2's (`t3/wave2`, itself cut from
`t3/wave1-search`) and takes wave 2's tip as it moves. It builds on wave 1's `text_status` / OCR runner and the search
refresh from the change feed, and on wave 2's subfolders, Sort Existing with `undo(ids:)` and Undo All, the "Moved
back" toasts, the "Undo:" / "Undo Move:" menu labels, `reanalyze` and `title_source`, plus prefactor A (column table,
`changes()` feed, `testRow`) and prefactor B (`FileActions+<Feature>.swift`, `SearchResultActions`, `SearchKeyMap`,
`scripts/lint.sh`). If merged code has a different shape than the spec describes, follow the merged code.

Every ticket counts as done only when `macos-app` CI is green on its PR (AGENTS.md: Linux green does not prove the
macOS build), along with the Linux tests and `scripts/lint.sh`.

Spelling is American everywhere (Parag, 2026-11-28): the spec says "Analyse Again"; code, strings and snapshot names
say "Analyze Again".

## Tickets

| # | Ticket | Blocked by | Area |
|---|---|---|---|
| 01 | [Index migration: `last_opened_at`, `trashed_from`, `trashed` status](01-index-migration-opens-and-trash.md) | none | core |
| 02 | [Trash choke point and the written exception](02-trash-choke-point-and-exception.md) | none | core + lint + AGENTS.md + CODING_STANDARDS |
| 03 | [Undo batches and trash records; menu Undo takes the whole batch](03-undo-batches-and-trash-records.md) | wave 2 05 (on the base) | core + menu |
| 04 | [Record opens in Shotkeeper](04-record-opens.md) | 01 | core + search panel + menu Recent |
| 05 | [Clean Up window: find duplicates (read-only)](05-clean-up-window-duplicates.md) | none | core + new window + menu item |
| 06 | [Never opened section](06-never-opened-section.md) | 01, 04, 05 | core + window + `LastUsedDates` |
| 07 | [Move to Trash: dry run, confirmation, run, toast, Undo All](07-move-to-trash.md) | 01, 02, 03, 05 | core + window + toasts + menu |
| 08 | [The list goes out of date](08-list-out-of-date.md) | 05, 07 | core review state + window |
| 09 | [When Undo can't put a file back; Finder's Put Back](09-trash-emptied-and-put-back.md) | 07 | core + toasts |
| 10 | [Integrate clean-up and verify on a real Mac](10-integrate-and-verify.md) | 01–09 | integration |

```
01 ──┬──> 04 ──> 06
     │    05 ──┬─> 06
     │         │
01 ──┼─────────┼─> 07 ──┬──> 08
02 ──┤         │        └──> 09 ──> 10 (after 01–09)
03 ──┘         └─> 07
05 ──> 08
```

## What can run when

- **At once (integration branch cut):** 01, 02, 03 and 05 have no clean-up blockers. That is the four-agent cap
  (workflow, 2026-11-28). 01, 02 and 03 are core-only and touch different files (`ScreenshotIndex`; `FileOrganizer`
  + lint + rule docs; `UndoLog` + `MenuText`); 05 adds new files.
- **When 01 merges:** 04.
- **When 01, 02, 03 and 05 merge:** 07. **When 04 and 05 merge (and 01):** 06. 06 and 07 can run in parallel; both
  edit `CleanUpReviewState`, `CleanUpView` and `CleanUpSnapshots`, so put new views in their own files and let the
  second to merge rebase. Whichever merges second adds the window-level test for ticked never-opened rows in a run.
- **When 07 merges:** 08 and 09 in parallel (08 is the review state and window; 09 is undo, reconcile and toasts).
- **Last:** 10.
- Critical path: 05 → 07 → 09 → 10 (with 01, 02, 03 feeding 07).

## Ownership rules

- **Migration:** only 01 adds an index migration version. Waves 1 and 2 take 3 and 4, so 01 writes 5 and **claims
  the next free number at merge time** (a wave 3 migration merged first moves it up; `shippedColumns` versions run
  1, 2, 3… with no gap). No other clean-up ticket adds a column: no digest column (spec "Nothing is stored").
- **The exception and the Trash call:** only 02 changes the AGENTS.md "never delete or overwrite a user file" rule,
  CODING_STANDARDS #1 and the lint `trash` rule, in the **same PR as the first code that can call `trashItem`**
  (`FileOrganizer.trash`'s default primitive). Nothing else may call `trashItem` or `recycle`; no `lint-allow: trash`
  marker exists; 07 calls `FileOrganizer.trash` only. Ticket 10 greps for it.
- **`UndoLog` and menu Undo wording:** only 03 changes the record format and `MenuText.undoItem`. 07 writes trash
  records; 09 writes `gone` lines through 03's API.
- **`ScreenshotProcessor`:** clean-up code goes in its own `ScreenshotProcessor+CleanUp.swift` (05 plan, 06 plan half,
  07 run, 09 reconcile). Edits in the main file are small: 04 (`recordOpened`), 07 (`undo` branch on kind), 09
  (`process` put-back rule, undo errors).
- **`FileActions`:** 05 adds `FileActions+CleanUp.swift`; 06–09 extend it. 03 touches wave 2's
  `FileActions+Subfolders.swift` only for the batch id.
- **Search panel:** only 04 (one `recordOpened` call per counted action).
- **Settings:** 04 adds `opensRecordedSince`, 06 adds `cleanUpAge` (one `CodingKeys` line each).
- **Wiki page:** `docs/wiki/clean-up.md` is created by whichever of 01 or 02 merges first; every later ticket only
  appends dated lines (lesson from wave 1, workflow 2026-11-28: parallel tickets that each create the same page always
  conflict).

## Where the research wins over the spec

The research note came after the spec. Where they differ, tickets follow the research:

| Point | Spec said | Research says (tickets follow) | Ticket |
|---|---|---|---|
| Trash primitive | `trashItem` in core, or `recycle` in one app file if Put Back needs it | `trashItem` in core `FileOrganizer`: `recycle` has the same Put Back bug (DTS, r. 23153124) and no other advantage. Lint names `FileOrganizer` only. | 02 |
| Linux build | default primitive throws on Linux | `trashItem` doesn't exist in Linux Foundation: the default must sit **behind `#if canImport(Darwin)`** or core stops building on Linux | 02 |
| Put Back promise | stories 25/38: get them back "from the Trash" (Finder's Put Back) as well as Undo | **No Put Back promise.** Put Back is best-effort for batches. The confirmation, toasts and docs promise Undo only; Finder isn't mentioned | 07, 02 (rule wording) |
| Undo move back | "existing revert, no-replace `FileOrganizer.move`" | **`renameNoReplace` from the stored Trash URL**: atomic, never `moveItem`, never copies across volumes; `EXDEV` reported, file stays | 07, 09 |
| Undo errors | Trash emptied; name taken | Also **folder no longer exists** (Undo never recreates folders) and **can't reach the Trash** (`EPERM`). Source `ENOENT` checked before the destination | 09 |
| Gone vs blocked | gone from both → remove the row | Only `ENOENT` means gone; **`EPERM` never counts as emptied**, the row is kept | 09 |
| `LastUsedDates` | `.date` / `.never` / `.unknown`, per-file "macOS has no record" note | The API can't tell never from unknown: one "no record" case and **one note per section** (design), unless real-Mac check 8 splits it by disk. Read with `NSMetadataItem`; **never** read `com.apple.lastuseddate#PS` | 06 |
| `.trashedWithoutLocation` | keep if the research says it can happen | Apple documents no such case; **kept as a defensive check** | 02, 07 |
| iCloud Drive | Trash may be emptied by the user's setting | iCloud empties its items from the Trash after 30 days **regardless of Finder settings**: a line in the confirmation; reconcile copes | 07, 09 |
| Listing the Trash | hidden folders skipped | Listing `~/.Trash` is TCC-protected: the walk never touches `~/.Trash` or `.Trashes`; reconcile only `lstat`s stored paths | 05, 09 |
| File coordination | silent | Don't wrap `trashItem` in an `NSFileCoordinator` block (deadlock report) | 02 |
| Network volumes | "no Trash → error, never delete" | Apple is silent; real-Mac check 4 (SMB: must throw, file stays) is a **ship gate** | 07, 10 |

Design departures from the spec (accepted by Parag) that tickets build in: one thumbnail and size per group; the ticked
count beside the button; "Undo Move to Trash: 12 screenshots" / "Undo Sort: 180 screenshots"; Undo All also in the
footer and ⌘Z in the window; changed rows locked until Check Again; Show Only Ticked; still-being-named copies shown
disabled; Cancel as the confirmation's default and ⌘⌫ with a 0.5 s and key-repeat guard; no default button in the
window; two extra undo messages (design §14).

## Real-Mac checks (research "Must test", items 1–9)

| # | Check | Ticket |
|---|---|---|
| 1 | Put Back after one file and a batch of 20, Finder Trash window closed and open | 07 (trash), 09 (row comes back) |
| 2 | Resulting URL non-nil on every success | 07 |
| 3 | External APFS, HFS+, exFAT, FAT32 disks | 07 |
| 4 | SMB share: throws, file stays (**ship gate**) | 07 |
| 5 | iCloud Desktop, downloaded and evicted file | 07, 09 |
| 6 | Name clash in the Trash | 07 |
| 7 | TCC without Full Disk Access: trash, `lstat`, rename back | 07, 09 |
| 8 | `kMDItemLastUsedDate` after each kind of open; indexing off; Privacy list | 06 (04 for Shotkeeper's own opens) |
| 9 | `com.apple.quarantine` on system screenshots | 06 |

All of them run together in 10 and feed the per-release Mac checklist (workflow, 2026-11-28).

## Snapshot names (light and dark, one file per screen in `UISnapshotTests`)

- 03: `menu-undo-trash`; proposed `menu-undo-sort-batch` (not in the design's list)
- 05: `cleanup-list` (Duplicates only), `cleanup-list-keep-rowless`, `cleanup-list-only-ticked`, `cleanup-list-many`,
  `cleanup-checking`, `cleanup-comparing`, `cleanup-check-stopped`, `cleanup-no-folders`, `cleanup-folder-missing`,
  `cleanup-folder-unreadable`, `cleanup-index-empty`, `cleanup-index-error`, `cleanup-empty-duplicates`
- 06: `cleanup-empty-never-opened`, `cleanup-empty-both`; `cleanup-list` updated to both sections
- 07: `cleanup-moving`, `cleanup-finished`, `cleanup-finished-left`, `cleanup-stopped`, `cleanup-confirm`,
  `cleanup-confirm-surprises`, `cleanup-confirm-one`, `cleanup-nothing-can-move`, `toast-trash-batch`,
  `toast-trash-one`, `toast-trash-left`, `toast-trash-stopped`, `toast-trash-none`, `toast-moved-back-trash`,
  `toast-moved-back-partial`, `menu-moving-to-trash`
- 08: `cleanup-out-of-date`
- 09: `toast-cant-move-back-emptied`, `toast-cant-move-back-name-taken`, `toast-cant-move-back-folder-gone`
