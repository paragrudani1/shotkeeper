# Subfolders and fix or re-run a title spec (wave 2, 2026-11-28)

Parag's requirements are copied verbatim below. Do not edit them. Everything after them is synthesis by the design
sub-agent (2026-11-28) and must not contradict them. Add dated implementation notes and deviations to the wiki
(`docs/wiki/subfolders-and-retitle.md`, once it exists), not here.

## Requirements (Parag, 2026-11-28)

> 2026-11-28: "Sort into subfolders: put screenshots into folders by app or content type (for example Receipts, Code, Chats). Today there is only one organized folder." (approved: "let's do all of it")

> 2026-11-28: "Fix or re-run a title: rename by hand, or analyse a screenshot again, from the search window." (approved: "let's do all of it")

> 2026-11-28 (decision, consent for re-analysis): an explicit "Analyse Again" on one screenshot is the user's request to upload it, but only if the current backend's destination is allowed at that moment; otherwise it asks first. CODING_STANDARDS #2 is reworded once, in this work, so the rule never exists in two copies.

---

## Basis

- Code state: branch `t3/roadmap-2026-11` at `d8e5b17`, which includes main `b5c2984` (PR #9, prefactor A: the
  `ScreenshotIndex.columns` table, the `changes()` feed, `IndexedScreenshot.testRow`, the settings round-trip test).
- Survey: `docs/wiki/roadmap-survey.md`, features 4 and 5, the hotspots table and prefactors 4–7.
- **Depends on PR #10 (prefactor B), not merged on 2026-11-28** (head `06d1aea`, `docs/wiki/prefactor-app.md` on
  `origin/t3/prefactor-app`). This spec assumes its shape:
  - `FileActions`, with one `FileActions+<Feature>.swift` extension per feature. This work adds two:
    `+Subfolders` and `+Retitle`. `+Retitle` gives `FileActions` the queue, as that page says.
  - `SearchResultActions`, the search panel's action set.
  - `SearchKeyMap` in core with `SearchKeyMapTests`.
  - `scripts/lint.sh`: `file-op` (moves only in `FileOrganizer`, `NoReplaceRename`, `UndoLog`) and `analyze`
    (`.analyze(` only in `ScreenshotProcessor`).
  If PR #10 merges with a different shape, follow the merged code, not this text.
- **Depends on wave 1** (`docs/specs/search-filters-and-text-2026-11.md`, design `docs/design/search-filters-and-text.md`,
  both approved 2026-11-28). This spec uses:
  - `SourceKey`, the source normalization;
  - ⇧⌘ support in `SearchKeyMap`, added for ⇧⌘C;
  - search refresh from the change feed;
  - the OCR `text_status` column.
  Wave 1 changes the same search panel first, so this wave's panel work starts after wave 1's panel PR merges.
- Consent: `docs/wiki/ui-polish.md`, "Consent choke point" and "review 4" (2026-11-22). Toast, Edit name, the
  restored-by-undo rule and the undo log: the same page, "Core rules" (2026-11-21).
- Parag moved the consent change into this work on 2026-11-28, after dropping feature 7 (`docs/wiki/workflow.md`).
  It is no longer a separate prefactor PR.

## Problem Statement

**Subfolders.** Shotkeeper can move every processed screenshot into one "organized folder". After a few months that
folder holds hundreds of files with good names but no structure. Receipts sit next to code snippets and chat
screenshots. When the user browses in Finder rather than searching, they want to open "Receipts" and see only
receipts, or open "Slack" and see only Slack. They don't want to drag files into folders by hand.

**Titles.** Sometimes the model's title is wrong or too vague ("Settings window dialog"). Sometimes the screenshot was
processed with an older backend, or with low confidence, so the file kept its original name. Today the only fix is the
toast's "Edit name", and only during the toast's 4 s. Once the toast is gone, the user has to rename the file in
Finder. The index never learns the new name, so search keeps showing the old title. Shotkeeper also has no way to
look at a screenshot again: a file that was analysed once is skipped forever (`.alreadyIndexed`).

## Solution

**Subfolders.** Settings gains a "Sort into subfolders" choice under "Move into the organized folder":

- **Off**: today's behaviour, and the default.
- **By type**: Tweets, Articles, Code, Chats, Receipts, Designs and Other.
- **By app or site**: Slack, GitHub, x.com…
- **By type, then app or site**: for example Chats/Slack.

New screenshots go straight into the right subfolder inside the organized folder. Shotkeeper creates the subfolder
when it doesn't exist yet. A move never replaces a file: a clash becomes "Name 2.png", as today. Every move can be
undone. Screenshots already in the organized folder stay where they are. If the user wants them sorted too, "Sort
Existing Screenshots…" first says how many files it will move, then moves them, with one Undo All.

**Titles.** In the search window, the selected screenshot gets two new actions:

- **Edit name** (⌘E). The title in the preview becomes a text field. ↩ saves, Esc cancels. Saving renames the file
  with the same rules as the toast's "Edit name", updates the index so search shows the new name at once, and can be
  undone.
- **Analyse Again** (⇧⌘E) sends that one screenshot to the current backend again. It then updates the title,
  description, tags, type and source, and renames and sorts the file the way a new screenshot would be. A name the
  user gave by hand is kept. If the current destination is allowed right now, the request itself is the user's
  permission to upload that file. If it isn't allowed, Shotkeeper asks first, with the same question Settings asks.

## User Stories

Subfolders: setting and rule
1. As a user, I want to turn on sorting into subfolders inside my organized folder, so that Finder shows my screenshots grouped.
2. As a user, I want to sort by content type (Tweets, Articles, Code, Chats, Receipts, Designs, Other), so that all my receipts are in one place.
3. As a user, I want to sort by the app or site a screenshot came from, so that all my Slack screenshots are in one place.
4. As a user, I want to sort by type and then by app or site (Chats/Slack, Code/GitHub), so that big types are split further.
5. As a user, I want sorting off by default, so that nothing changes until I choose it.
6. As a user, I want the subfolder setting to appear only when moving into the organized folder is on, so that Settings doesn't offer something that can't apply.
7. As a user, I want to see an example path for the rule I pick ("Organized/Receipts/Invoice from Acme.png"), so that I know what will happen before the next screenshot.
8. As a user, I want type folders to have plain plural names, so that they read naturally in Finder.
9. As a user, I want screenshots of type "Other" to go to an "Other" folder, so that nothing is left loose next to the folders.
10. As a user, I want screenshots whose app or site is unknown to go to a predictable place, so that I can find them.
11. As a user, I want "X" and "x.com", or "GitHub" and "github.com", to land in one folder, so that one app doesn't get two folders.
12. As a user, I want a folder I already have with that name (in any letter case) to be reused, so that Shotkeeper doesn't make "slack" next to "Slack".
13. As a user, I want app names that contain "/" or ":" or start with "." to become safe folder names, so that no hidden or broken folders appear.
14. As a user, I want a screenshot whose name was kept (low title confidence) to be sorted anyway, so that the type still puts it in the right folder.
15. As a user, I want a screenshot to stay in the organized folder itself if its subfolder can't be created, so that the move still happens and nothing is lost.

Subfolders: safety and undo
16. As a user, I want a move into a subfolder never to replace a file already there, so that I never lose a screenshot.
17. As a user, I want every move into a subfolder in the undo log, so that the toast's Undo and the menu's Undo put the file back.
18. As a user, I want empty subfolders left alone after an undo, so that Shotkeeper never deletes anything.
19. As a user, I want subfolders never to be watched or processed again, so that a sorted screenshot is never analysed twice.

Subfolders: existing screenshots
20. As a user, I want screenshots already in my organized folder left where they are when I turn sorting on or change the rule, so that nothing moves without my say.
21. As a user, I want a "Sort Existing Screenshots…" command, so that I can sort what is already there when I choose.
22. As a user, I want that command to tell me how many files it will move, how many are already in place and how many it can't find, before it starts, so that I know what I'm starting.
23. As a user, I want that command to sort using what the index already knows, without uploading anything, so that it is free and private.
24. As a user, I want that command to skip files I moved or renamed myself in Finder since, so that my own organisation is kept.
25. As a user, I want that command to skip files I restored with Undo, so that "Shotkeeper will not rename this file again" also means it won't move them.
26. As a user, I want that command to keep the names of files exactly as they are, so that a name I gave by hand survives.
27. As a user, I want one summary toast with "Undo All" after sorting existing screenshots, so that one click puts everything back.
28. As a user, I want to stop a long sort, so that a mistake doesn't run to the end.
29. As a user, I want search to show each file's new folder right after it moves, so that "Reveal in Finder" and the Folder line are correct.

Rename by hand from the search window
30. As a user, I want to rename the selected screenshot from the search window, so that I can fix a bad title whenever I find it.
31. As a keyboard user, I want one key to start editing the name, so that I don't need the mouse.
32. As a user, I want the field to start with the current name selected, so that I can type a new one straight away.
33. As a user, I want ↩ to save and Esc to cancel while editing, so that it works like the toast's "Edit name".
34. As a user, I want Esc while editing to cancel only the edit, not clear my search or close the panel, so that I don't lose my place.
35. As a user, I want the list keys (↑↓, ↩ Open, Space, ⌘C) to stay inside the field while I edit, so that typing never opens or copies something by accident.
36. As a user, I want the same name rules as everywhere else (sanitizing, my filename style, "Name 2" on a clash), so that names stay consistent.
37. As a user, I want a clear message when the name I typed is unusable, and to stay in the editor, so that I can fix it.
38. As a user, I want a clear message when the file was moved or deleted since, so that I know why the rename did nothing.
39. As a user, I want search to show the new name at once and keep it selected, so that I see my change took effect.
40. As a user, I want the menu's "Undo: <title>" to undo my rename, so that a typo is easy to reverse.
41. As a user, I want leaving the panel while editing to change nothing, so that a half-typed name is never saved.

Analyse Again
42. As a user, I want to analyse the selected screenshot again from the search window, so that I get a better title from the current backend.
43. As a user, I want one key for Analyse Again, harder to hit by accident than the everyday keys, so that I don't upload by mistake.
44. As a user, I want Analyse Again to upload without another question when my current backend's destination is already allowed, so that one press is enough.
45. As a user, I want Analyse Again to work on a screenshot taken before I allowed that destination, because I asked for this one file, so that old screenshots can be fixed.
46. As a user, I want to be asked first when my current destination isn't allowed, with the same question Settings asks, so that nothing is sent where I haven't agreed.
47. As a user, I want the request dropped if I change the backend, endpoint or grants before it runs, so that a file is never sent somewhere I didn't pick for it.
48. As a user of the local model, I want Analyse Again without any question, so that local stays simple.
49. As a user, I want Analyse Again to refuse a screenshot that matches one of my exclude rules, so that "never sent" stays true.
50. As a user, I want Analyse Again to refuse while Shotkeeper is paused, with a message saying so, so that Pause keeps meaning "send nothing now".
51. As a user, I want to see that the screenshot is waiting, being analysed, or held (offline, needs attention), so that I know what's happening.
52. As a user, I want my Analyse Again to go ahead of a long Process Existing run, so that I'm not waiting behind hundreds of files.
53. As a user, I want the new title, description, tags, type and source in search as soon as the analysis finishes, so that the screenshot is easier to find.
54. As a user, I want the file renamed with the new title under my current settings (rename on, confidence threshold, filename style), so that it matches a new screenshot.
55. As a user, I want the file kept under its current name when the new title is unusable or low-confidence, so that a bad answer never makes things worse.
56. As a user, I want the file moved to the subfolder its new type or source points to when sorting is on, so that the folders stay right.
57. As a user, I want a name I gave by hand kept when I analyse again, so that my fix isn't overwritten.
58. As a user, I want to see the title the model suggested when my name was kept, and use it with one click, so that I can still take the new title.
59. As a user, I want a screenshot I restored with Undo to keep its name and place when I analyse it again (only its description, tags, type and source change), so that the toast's promise holds.
60. As a user, I want a failed Analyse Again to leave the screenshot exactly as it was in search, so that a network error never loses a good analysis.
61. As a user, I want a clear reason when Analyse Again fails or is refused, so that I know what to fix.
62. As a user, I want the rename and move made by Analyse Again to be undoable, so that I can go back to the old name.
63. As a user, I want pressing Analyse Again twice on the same screenshot to start only one analysis, so that I'm not charged twice.
64. As a privacy-conscious user, I want the text Shotkeeper read from the image (wave 1 OCR) never sent with Analyse Again, so that the on-device text stays on the device.
65. As a VoiceOver user, I want Edit name, Analyse Again and their results announced, so that I know what happened.

## Implementation Decisions

### Subfolder rule (core, Linux-tested)

- **`SubfolderRule`**, a new settings value: `.off` (default), `.byType`, `.bySource`, `.byTypeThenSource`.
  - Stored as `AppSettings.subfolderRule`, one new `CodingKeys` line (prefactor 2). The existing
    `testEveryPropertyRoundTrips` covers it.
  - An unknown stored value decodes as `.off`, under the existing decode tolerance.
  - It applies only when `moveEnabled` is on and `organizedFolder` is set. It never creates folders anywhere else
    (not in the watched folder or next to the file).
- **A pure router**, `SubfolderRule.relativeFolder(contentType:source:existing:) -> [String]`. It returns the path
  components below the organized folder, `[]` for the organized folder itself. `existing` lists the subfolder names
  that already exist at each level, so name matching is pure.
  - The processor passes the result to `FileOrganizer.organize(_:stem:into:)`, which already creates missing
    folders.
  - The processor lists the existing names at each level. This is read-only, so `lint.sh`'s `file-op` rule is not
    involved.
- **Type folder names** are fixed core constants, plural English:
  - `.tweet` → **Tweets**, `.article` → **Articles**, `.code` → **Code**, `.chat` → **Chats**, `.receipt` →
    **Receipts**, `.design` → **Designs**, `.other` → **Other**.
  - No setting renames them; see "Decisions".
- **Source folder names:**
  - Raw `source_app_or_site` → `SourceKey` (wave 1's normalization: trim, fold case and diacritics, drop `www.`, drop
    a lone top-level domain).
  - If a folder already exists at that level whose name has the same `SourceKey`, that folder is used. When several
    match, the first in alphabetical order wins. This makes "X" reuse "x.com", and "slack" reuse "Slack". It also
    gives the same result on case-insensitive APFS and on case-sensitive Linux in tests.
  - Otherwise a new folder is named from the raw spelling. Rules for that name:
    - drop a leading `www.`;
    - replace `/` and `:` with " - ";
    - drop control characters;
    - trim spaces and dots at both ends;
    - cap at 60 characters, cut at a grapheme boundary.
    The first spelling seen stays the folder's name. It does not change later, unlike wave 1's display name, which
    follows the most common spelling.
  - A name that comes out empty, `.` or `..` counts as unknown.
- **Unknown source** means nil, empty after cleaning, or one of a short core list of non-answers: "unknown", "n/a",
  "none", "screenshot", "image", "desktop". The list is a constant with a test.
  - `.bySource`: unknown goes to **Other**.
  - `.byTypeThenSource`: unknown goes to the type folder itself (Chats/), with no "Other" subfolder.
  - A source whose cleaned name equals a type folder name ("Code") is not treated specially. In `.bySource` mode the
    two can share a folder.
- **When the subfolder can't be made**, for example a *file* named "Receipts" exists there or permission is denied,
  the screenshot goes to the organized folder itself. The row's `note` gets "subfolder not created (…)". If that
  fails too, today's rule applies: the file keeps its name and place, with a note.

### Subfolders in the pipeline

- `ScreenshotProcessor.process` computes the destination folder after the analysis:
  `organizedFolder + rule.relativeFolder(…)`. Before, it was `organizedFolder`. Nothing else in the order changes:
  analyze → stem → organize → undo record → Finder metadata → index.
- A kept name (low confidence, no title, rename off) is still moved and sorted, as it is still moved today.
- **One undo record per move.** It is written right after the move, as today (CODING_STANDARDS #1). Undo puts the
  file back at its original path and name and sets `restored_by_undo`. The subfolder is left even when it is empty:
  nothing deletes folders.
- **Watching:** `FolderWatcher` and Process Existing's scan see only the watched folder's direct children
  (`StatusText.swift`; `docs/wiki/roadmap-survey.md` #4a). So a subfolder is never watched, even when the organized
  folder sits inside the watched folder. This spec keeps that as an invariant. A later change to recursive watching
  must exclude the organized folder.
- **Index and change feed:** no new column for subfolders. The move goes through `index.updatePath(from:to:)`, which
  publishes `.updated`, or `.removed` + `.updated` when a stale row is replaced (prefactor A). Search refresh, the
  preview's Folder line and wave 3's Spotlight sync follow from that feed. FTS is unaffected.

### Sorting existing screenshots

- **Left alone by default.** Turning sorting on or changing the rule moves nothing.
- **"Sort Existing Screenshots…"**, offered next to the rule when the rule isn't Off, works in two steps:
  1. **Plan** (core, pure over the index plus a file-existence check): `ScreenshotProcessor.sortPlan(settings:)`
     returns the moves, plus counts of files already in place and files missing.
     - Candidates are rows with `status == done`, `restored_by_undo == false`, and a path inside the organized
       folder: its root or any depth below it.
     - A row whose file isn't at its indexed path counts as **missing** and is skipped. These are files the user
       moved or renamed in Finder; the index can't follow moves inside the organized folder, which isn't watched.
     - A row already in its rule folder counts as **in place**.
     - The plan uses the stored `content_type` and `source_app_or_site`. Nothing is analysed or uploaded, so
       consent and Pause don't apply.
  2. **Run:** `ScreenshotProcessor.sort(_ plan:)` moves each file with `FileOrganizer.organize(url, stem: nil,
     into: folder)`, so the name never changes and a clash gives "Name 2".
     - For each file, in order: move, then undo record, then `index.updatePath`. If the undo record can't be
       written, the file is moved back (no-replace) and counted as failed. That is `rename(_:to:)`'s existing rule.
     - Before each move the run checks that the file is still at the path the plan read. If not, it is skipped as
       missing.
     - The run can be cancelled between files.
     - It reports moved, skipped and failed counts and the undo record ids.
- The app runs it through `FileActions+Subfolders`. `ToastBatcher.beginRun` gives one summary toast ("Sorted 180
  screenshots") with **View in Search** (the batch view) and **Undo All** (`undo(ids:)`, newest first).
- **Undo of a sort move** puts the file back at the organized path it had, not at the watched folder, and sets
  `restored_by_undo` (existing behaviour of `recordRestored`). The next "Sort Existing" then skips it (story 25).
  The restored toast says "Moved back" when only the folder changed and the name is the same. That is a pure core
  rule in `Feedback/`, next to the existing restored wording.
- Known cost: `UndoLog.undo(id:)` reads the whole log for each record, so Undo All of N files reads the log N times.
  Measure with 1,000 records in a test. If it takes more than about 1 s, add a batch undo to `UndoLog` that reads
  the log once. It would keep the same no-replace revert.

### Rename by hand from the search window

- **Same core entry point as the toast:** `ScreenshotProcessor.rename(_:to:)`. It uses `FilenameSanitizer` and the
  filename style, adds no date, keeps the original extension, gives "Name 2" on a clash, writes an undo record
  (puts the file back if that fails), moves the index row and sets its title. The rename stays in the current
  folder (`into: nil`), so a sorted file stays in its subfolder.
- **New:** the row records that its title is the user's (`title_source = user`, below). Both the toast's Edit name
  and the search window's Edit name set it.
- **Restored-by-undo rows** can be renamed by hand. The flag stays, so automatic processing still leaves the file
  alone.
- **Errors** reach the panel as `UserFacingProblem`s:
  - `ManualRenameError.unusableName` → "Choose a name with letters or numbers." (the editor stays open);
  - `FileOrganizerError.sourceMissing` → the existing missing-file message;
  - other errors → the error's readable message (no `String(describing:)`).
- **Search state (core):** `SearchWindowState` gains an editing state: `beginEditing()`, `commitEdit()`,
  `cancelEdit()`, `editingText`.
  - While editing, `escape()` cancels the edit first: edit, then the wave 1 order (picker → clear → close).
  - `windowHidden()` cancels the edit.
  - Starting a search, a chip, a filter or a selection change also cancels it.
  - After a successful rename, the change feed refreshes the results. `apply(_:for:)` keeps the selection on the
    same row `id`, even if the new name moves it in the ranking. If the row no longer matches the query, the
    selection moves to the nearest row and the panel announces it.
- **Keys:** `SearchKeyMap` gains `SearchKey.editName` on **⌘E** and `SearchKey.analyseAgain` on **⇧⌘E**. ⇧⌘E uses the
  ⇧⌘ trigger that wave 1 adds for ⇧⌘C (character lowercased, else the physical key, so the Russian layout works).
  - Neither is in `reservedCommandCharacters` or used by wave 1: ⌘C, ⌘R, ⌘Y, ⌘1–⌘7, ⌘D, ⌘S, ⇧⌘C.
  - ⌘E's macOS meaning, "Use Selection for Find", needs a Find menu, and this panel has none. Check on a real Mac
    that the field doesn't take ⌘E first.
  - `HotKeyRules` already refuses ⌘ + a letter as the global shortcut, so neither key can clash with it.
  - While the editor is open, every panel key binding is ignored except ↩ (save) and Esc (cancel). The editor
    behaves as a plain text field: ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z edit its text.
  - The footer keeps its five approved hints. The keys appear in the buttons' tooltips, as wave 1 did for ⇧⌘C.
  - Fallbacks if the design pass objects to ⇧⌘E: ⌘G ("again"), or no key (button only).

### Analyse Again (core)

- **A new processor entry point:** `ScreenshotProcessor.reanalyze(rowID:request:) -> ReanalysisOutcome`.
  - It gets past `.alreadyIndexed`. That is the only way to analyse a `done` row again.
  - It keys on the row `id`, not the path: at each attempt it reads the row's current path, so a hand rename made
    while the job waited doesn't make it miss the file.
- **Steps:**
  1. Look up the row by `id`. The file must exist at the row's path, otherwise `.refused(.missing)`.
  2. Run the exclusion check the pipeline runs (`ExcludeRules.exclusion(for:capturedAt:now:)`). A rule match gives
     `.refused(.excluded(rule))`; an active Pause gives `.refused(.paused(until:))`. No upload happens in either case.
  3. Fingerprint and prepare the image, as `process` does.
  4. The consent decision, `UploadConsent.decide`, on the snapshot read once right before `analyze`, with the user's
     request (below). A refusal gives `.skipped(.awaitingConsent)`, and nothing is written.
  5. `analyze` with the same `AnalysisContext` as the pipeline. It never contains wave 1's recognized text.
  6. Apply the analysis to a copy of the row: title, confidence, type, source, description, tags, `key_text`,
     `date_mentioned`, `produced_by` and billed tokens. Set `processed_at = now`, keep `status = done`, and add
     "analysed again" to `note`. If the content hash changed, update it and set wave 1's `text_status = pending`.
  7. **Name:**
     - `restored_by_undo`: the file is neither renamed nor moved (index only).
     - Else `title_source == user`: the title and file name stay. The model's title is returned in the outcome
       (`suggestedTitle`), and is not stored.
     - Else the pipeline's rename rule applies: `renameEnabled`, `minTitleConfidence` and the filename style, with
       the capture date for the date prefix. Below the threshold, or with no usable title, the file keeps its
       *current* name and the old title stays in the row.
  8. **Place:** the pipeline's move rule with today's settings: `moveEnabled`, the organized folder and the subfolder
     rule. Skipped for restored rows.
  9. Organize → undo record right after the move → Finder tags and comment → `updatePath` → `save`. Same order and
     the same failure handling as `process`.
- **Failure never makes the row worse.** If preparing or analysing fails, the row is left exactly as it was: still
  `done`, same analysis, and still in search. The error is returned and rethrown for the queue's retry rules. Unlike
  `process`, the row is not saved as `failed`, because a failed row would drop out of search.
- **`ReanalysisOutcome`:** `.updated(finalURL:, renamed:, moved:, titleKept: TitleKeptReason?, suggestedTitle:)`,
  `.refused(…)`, or `.skipped(.awaitingConsent)`. `TitleKeptReason` is `.yourName`, `.restoredByUndo`,
  `.lowConfidence`, `.renameOff` or `.unusable`. The panel's wording comes from this.
- **"Use suggested name"** (story 58) calls `rename(_:to: suggestedTitle)`. That sets the title back to the model's
  and `title_source` back to `model`. The rename goes through the same undo record and rules. This one path clears
  the user's mark: a rename that matches the model's suggestion exactly.
- **`lint.sh`:** `reanalyze` lives in `ScreenshotProcessor`, so the `analyze` rule holds. Moves still go only through
  `FileOrganizer`.

### Analyse Again: queue

- Analyse Again runs through `ProcessingQueue`, so it gets the rate limit, the 429/5xx retries and the offline and
  "Needs attention" holds.
- A job now carries a **kind**: `.process(url)` or `.reanalyze(rowID)`. The coordinator's handler dispatches on it.
- Duplicates are ignored per kind and key: a second Analyse Again on a queued or running row does nothing
  (story 63).
- **Ahead of the queue:** a `.reanalyze` job is placed before waiting `.process` jobs. It never pre-empts a running
  job, and it still takes a rate-limit token. That is one new `enqueue(_:atFront:)` option, covered by
  `ProcessingQueueTests`.
- The job carries the user's upload request for its whole life: retries and holds included, dropped when the job
  ends. That is the existing review-4 rule for Process Existing, unchanged.
- The app tracks state per row id (queued, analysing, held with the queue's reason, done, failed) from the queue's
  status and the job's result. `SearchWindowState` holds it for the selected row, so the panel and its tests read
  it from one place.

### Consent: one generalisation of the Process Existing authorisation

Parag's decision, quoted at the top: an explicit Analyse Again is the user's request to upload that file, but only
while the current backend's destination is allowed; otherwise it asks first.

- **Rename, don't add.** `ProcessExistingAuthorization` becomes **`UserUploadAuthorization(target:)`**, "the user
  asked, while `target` was selected and allowed, to send these particular files".
  - `ProcessExistingRequest` becomes `UserUploadRequest`, and `ProcessExistingRequests` becomes
    `UserUploadRequests`. They keep the generation stamp, `invalidateAll()` on any backend, endpoint or grant change,
    and `authorization(for:)`.
  - The `processExisting:` parameters become `userRequest:`.
  - Process Existing and Analyse Again both issue one. There are no two kinds and no reason field: `decide` must not
    branch on why the user asked. The UI keeps its own reason for its wording.
- **`UploadConsent.decide(target:grants:capturedAt:userRequest:)`.** The rule is unchanged in substance:
  - `.thisMac` → allow.
  - No grant covers the target → `.skip(.destinationNotAllowed)`. A user request never lifts this.
  - Taken at or after the grant → allow.
  - Else a user request for this very target → allow.
  - Else `.skip(.takenBeforeGrant)`.
  "Allowed at that moment" holds twice:
  - the request is issued only if the target is allowed at the click (`BackendGate`, through
    `UploadConsent.grant(for:in:)`);
  - `decide` runs again on the job's own snapshot right before `analyze`. A change in between invalidates the
    request, so a file taken before the grant is skipped.
- **"Otherwise it asks first":**
  - If the selected destination has no grant at the click, Analyse Again shows the existing consent question
    (`BackendGate.consentPrompt` / `ConsentRequest`). It names the destination the way Settings does, for example
    "Screenshots will be sent to http://gpu-box.lan:8080".
  - "Allow" grants through the existing granting path. The grant time is now, so the grant also covers future
    screenshots, exactly as in Settings. The dialog presents the `ConsentRequest` captured at the press, as Settings
    does (ui-polish 2026-11-22 nits). After granting, the request is issued with the new generation.
  - Cancel sends nothing.
  - An `unidentifiedEndpoint` can never be allowed, so Analyse Again is disabled, with the reason in its tooltip.
- **Readiness:** Analyse Again is offered only when the backend is ready (`BackendGate`), as Process Existing is.
  Setup not finished, the local model not installed or a missing token give a disabled action with the gate's reason.
  This is UI only. `decide` stays the one place that decides.
- **CODING_STANDARDS #2 is reworded in the same PR as the code**, and the old wording isn't left anywhere. Draft:

  > 2. **Consent before upload.** No image is sent anywhere off the Mac unless the user allowed that destination
  > and either the image was taken after the grant, or the user asked to send that image while that destination
  > was selected and allowed (a `UserUploadAuthorization`: "Process Existing Screenshots…", "Analyse Again"). The
  > only place that decides is `UploadConsent.decide`, called by `ScreenshotProcessor` on the same analyzer +
  > settings snapshot that uploads. A new send path that does not go through it is a blocker; so is a second copy
  > of the rule. Secrets never reach logs, settings JSON, error messages, argv or child-process environments.

  The same PR updates `UploadConsent`'s doc comments, `SkipReason.awaitingConsent`'s comment and `docs/core-api.md`.
  It adds a dated line to `docs/wiki/ui-polish.md` under the consent sections that says the Process Existing entries
  are superseded by name only. Old wiki entries stay as the record.

### Index schema (on top of prefactor A)

- **One migration**, its number claimed at merge (the second PR to merge renumbers). The `columns` entry, the
  migration line and the `shippedColumns` line are added together, per `docs/wiki/prefactor-index.md`.
  - `title_source TEXT`: NULL or `model` = the model's title (or the original name); `user` = typed by the user.
  - The same migration backfills `user` where `note` contains "renamed by the user". That is the note
    `rename(_:to:)` has written since `02e6420`, so names fixed in the toast before this feature are protected too.
- `IndexedScreenshot.titleSource` holds it. `process` sets `model` on a new row. A re-processed path (content changed)
  starts again as `model`, because the user's name described the old content.
- **Nothing else is stored:**
  - no rule or folder column (the path says where the file is);
  - no Analyse Again count or history;
  - no copy of the previous analysis, so Undo restores names and places, not old descriptions (see "Decisions");
  - no model suggestion while a hand name is kept.
- The change feed publishes `.updated` for every rename, move and re-analysis through the existing `save` and
  `updatePath`. No new event kinds.

### UI surfaces for the design pass (behaviour and states only)

The design pass (`docs/wiki/workflow.md`, "UI design step") writes `docs/design/subfolders-and-retitle.md` and a mockup.
It works within the polish spec's identity and wave 1's approved panel.

1. **Settings › General, "Sort into subfolders"** (under "Move into the organized folder"):
   - The picker has four choices. It is hidden when there is no organized folder or moving is off (polish rule: hide
     what doesn't apply).
   - An example path shows under it and follows the choice.
   - States: Off; each rule; an organized folder that is missing or unreadable (show why).
2. **"Sort Existing Screenshots…"**, next to the rule (hidden when Off):
   - A confirmation with the plan's counts: moves, already in place, can't be found, and "Nothing to sort" when the
     plan is empty.
   - Progress with Stop while it runs, then the summary toast.
   - States: plan loading, empty plan, running, stopped, finished with failures.
3. **Toasts:**
   - The single rename toast says where the file went when it was sorted ("in Receipts").
   - The "Sorted N screenshots" summary toast has View in Search and Undo All.
   - The restored toast says "Moved back" for a sort undo.
4. **Search preview, Edit name:**
   - Reached by the button and ⌘E. The title becomes a field with the name selected, plus Save and Cancel.
   - States: editing, saving, the unusable-name error (editor stays open), file missing, a "Name 2" clash (the
     result names the final name), success pill.
   - Esc and focus loss cancel.
5. **Search preview, Analyse Again:**
   - Reached by the button and ⇧⌘E.
   - States:
     - idle;
     - disabled with a reason (not ready, unidentified endpoint, no index);
     - asking for consent;
     - queued;
     - analysing;
     - held (offline / Needs attention, with the queue's reason);
     - result: renamed, name unchanged, kept your name + suggested title with "Use This Name", kept the restored
       name (index updated);
     - refused: excluded, paused, missing;
     - failed with a readable reason;
     - "The destination changed. Analyse again." when the request was invalidated.
6. **In-panel consent question.** The panel is non-activating, so the question must not take key status from the
   field, the same constraint as wave 1's pickers. It names the destination, and its actions are Allow (grants the
   destination) and Cancel. The design pass decides between in-panel and a separate alert, after checking
   `appkit-gotchas`.
7. **Result list row:** a quiet indicator while its screenshot is queued or analysing, and while it is being renamed.
8. **Preview metadata:** the Folder line shows the subfolder ("Organized › Receipts"). The design pass decides
   whether a hand-named title is marked ("Named by you").
9. **When the panel is hidden before Analyse Again finishes:** the rename toast shows the result instead of the
   panel's pill. Its Undo and Edit name work as for a new screenshot.
10. **Menu bar:** "Undo: <title>" (⌘Z) covers hand renames, Analyse Again renames and moves, and single sort moves.
    The design pass checks the label for a move-only record.
11. **Keyboard and VoiceOver:**
    - the Esc order (edit → picker → clear → close);
    - focus order with Full Keyboard Access;
    - announcements: "Renamed to …", "Analysing", "Analysed again", "Kept your name", "Moved back".
12. **CI snapshots, new states:** the subfolder picker, the sort confirmation, the editor, its error, each Analyse
    Again state above, and the consent question.

## Testing Decisions

- **Good tests** drive public behaviour through the highest seam and check what the user would see: where the file
  ends up on disk, its name, what the index row says, which undo records exist, and what the panel state says. They
  don't check SQL strings, private helpers or call counts. No test needs the network, a Mac or a real backend.
  Fixtures use `IndexedScreenshot.testRow`.
- **Seam 1: `ScreenshotProcessor`**, with `StubAnalyzer`, `TempDir`, an in-memory `ScreenshotIndex` and a real
  `UndoLog` (existing; prior art `ScreenshotProcessorTests`). Through `process`, `rename`, `reanalyze`, `sortPlan`
  and `sort`, it covers:
  - routing for each rule and type;
  - unknown sources;
  - folder reuse by `SourceKey` (an existing "x.com" for "X"; "slack" for "Slack");
  - name cleaning (`/`, `:`, leading dots, length, empty);
  - the fallback when the subfolder can't be made (a file named "Receipts");
  - no-replace clashes in a subfolder;
  - one undo record per move, and undo of a sorted file;
  - sorting existing files: plan counts; skips of missing, restored and in-place rows; names unchanged; cancel;
    undo-record failure puts the file back;
  - `title_source` set by `rename`, and kept by `reanalyze`, with `suggestedTitle` returned;
  - "Use suggested name" clears the mark;
  - restored rows updated in the index only;
  - low confidence keeps the current name;
  - Analyse Again moves to the new type's folder;
  - a failed analysis leaves the row identical and still `done`;
  - missing, excluded and paused refusals with no upload (the stub records nothing);
  - `text_status` reset only when the content changed;
  - the analyzer's request carries no recognized text;
  - change feed events for a move and a re-analysis.
- **Seam 2: `UploadConsent.decide`**, pure (existing; prior art `UploadConsentTests`). After the rename, every
  existing case passes unchanged under `userRequest:`. Added cases:
  - a user request never lifts `destinationNotAllowed`;
  - a request for another target doesn't count;
  - an invalidated request counts as none (through `UserUploadRequests`);
  - an Analyse Again on a file taken before the grant is allowed only with the request;
  - the snapshot-switch test (`testSwitchingToACloudBackendWhilePreparingDoesNotSendTheFile`) repeated for
    `reanalyze`.
- **Seam 3: `SearchWindowState` + `SearchKeyMap`** (existing; prior art `SearchWindowTests`, `SearchKeyMapTests`). It
  covers:
  - ⌘E and ⇧⌘E bound once and free of collisions, on non-Latin layouts too;
  - the editing state: begin, commit, cancel, and Esc order;
  - hide, search or selection change cancels;
  - selection kept by row `id` after a refresh;
  - the Analyse Again state machine (idle → asking → queued → analysing → held → result or failed), with each
    outcome's message.
- **Not new seams, one more case each in existing tests:**
  - `ScreenshotIndexTests`: the migration backfills `title_source` from the note, and leaves other rows NULL.
  - `SettingsTests`: the round-trip test picks up `subfolderRule`.
  - `ProcessingQueueTests`: a `.reanalyze` job goes ahead of waiting jobs, dedupes per row, and keeps its user
    request through retries and holds.
  - The `Feedback` toast tests: the "Moved back" wording.
- **App side, CI snapshots and a real Mac only:**
  - the editor inside the non-activating panel (focus, IME, ⌘E not taken by the field);
  - the in-panel consent question;
  - the Settings picker and the sort progress;
  - Finder showing the subfolders;
  - Undo All of a large sort.

## Out of Scope

- Clean-up of duplicates and old screenshots (wave 4), Spotlight and Shortcuts (wave 3), auto-update.
- Analyse Again on several screenshots at once, or on a whole folder.
- Editing tags, description, type or source by hand.
- Renaming the type folders, per-app folder choices, or a list of "apps that get their own folder".
- Moving screenshots back out of subfolders when sorting is turned off, other than Undo / Undo All.
- Deleting empty folders.
- Sorting screenshots that are in the watched folder (not moved) or anywhere outside the organized folder.
- Watching the organized folder or its subfolders.
- Undoing a re-analysis's description, tags or type.
- Analyse Again from the CLI or the menu bar.

## Decisions Parag might disagree with

1. **Rule modes:** Off, By type, By app or site, By type then app or site. The "mix" is the two-level mode, not a
   list of chosen apps.
2. **Type folder names are fixed:** Tweets, Articles, Code, Chats, Receipts, Designs, Other.
3. **Unknown app:** "Other" when sorting by app; the type folder itself in the two-level mode.
4. **Subfolders only inside the organized folder,** so they need "Move into the organized folder" on.
5. **Sort Existing** covers only files inside the organized folder that are where Shotkeeper put them, asks with
   counts first, and uploads nothing.
6. **Keys:** ⌘E Edit name, ⇧⌘E Analyse Again; the footer hints are unchanged.
7. **"Asks first" grants the destination for good** (the Settings question), not a one-time send for this file.
8. **A hand-typed name survives Analyse Again,** which offers the model's title as "Use This Name". Names fixed in
   the toast before this feature count too (backfill from the note).
9. **A file restored with Undo:** Analyse Again updates its description, tags, type and source only, never its name
   or place.
10. **Analyse Again applies today's rename and move settings,** so it can move a file to another subfolder.
11. **Undo restores names and places only,** not the previous description or tags.
12. **Analyse Again refuses** files matching an exclude rule, and refuses while paused.
13. **Analyse Again goes ahead of waiting jobs** in the queue.
14. **Leaving the panel while editing cancels the edit** (Finder would save).
15. **A failed Analyse Again leaves the row as it was,** not marked failed.
