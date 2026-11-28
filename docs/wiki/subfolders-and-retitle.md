# Wave 2: subfolders, Edit name and Analyze Again

Spec `../specs/subfolders-and-retitle-2026-11.md`, design `../design/subfolders-and-retitle.md` and tickets in
`../specs/subfolders-and-retitle-2026-11/tickets/` (all on `t3/roadmap-2026-11` until they merge). Integration
branch `t3/wave2`. API map: [../core-api.md](../core-api.md). Each ticket appends its dated lines here; the page is
not created twice.

## Decisions
- 2026-11-28 (`24d5560`, ticket 01): **consent: `UserUploadAuthorization`.** The Process Existing authorization is
  renamed, not duplicated: `UserUploadAuthorization(target:)` means "the user asked, while `target` was selected and
  allowed, to send these particular files" ("Process Existing Screenshots…", later "Analyze Again").
  `UserUploadRequest(s)` keep the generation stamp, `invalidateAll()` on a backend, endpoint or grant change, and
  `authorization(for:)`; `processExisting:` parameters are `userRequest:` (`ProcessingQueue.enqueue(_:userRequest:)`,
  `ScreenshotProcessor.process(_:userRequest:)`). There is no reason field: `UploadConsent.decide` never branches on why
  the user asked, and a user request never lifts `.destinationNotAllowed`. Later tickets only issue a
  `UserUploadRequest`. CODING_STANDARDS #2 now names the authorization. Tests: `UploadConsentTests`
  (`testAUserRequestNeverLiftsDestinationNotAllowed`, `testAUserRequestForAnotherTargetDoesNotCount`,
  `testAnInvalidatedUserRequestCountsAsNone`, `testAFileTakenBeforeTheGrantIsAllowedOnlyWithAUserRequest`).
- 2026-11-28 (ticket 01): **deviation: command identifiers keep "ProcessExisting".** The ticket's check
  `git grep -n ProcessExisting` over `Sources App Tests CODING_STANDARDS.md docs/core-api.md` still finds names of the
  user-facing command in `App/` (`beginProcessExistingRun`, `afterProcessExistingScan`, `onProcessExisting`,
  `showsProcessExisting`, and app test names such as `testProcessExistingWaitsForSetup`). They name the "Process
  Existing Screenshots…" command, not the authorization, and the ticket keeps the command and changes only type and
  parameter names. `Sources`, `Tests`, `CODING_STANDARDS.md` and `docs/core-api.md` have no match.
- 2026-11-28 (review of PR #17): `UserUploadAuthorization.init(target:)` is **internal**, so app code can only get an
  authorization from `UserUploadRequests.authorization(for:)`. An authorization built at the click would skip the
  generation check, and with it the rules "a request made before the destination was allowed never counts" and
  "dropped on a backend/endpoint/grant change, even X → Y → X". Left for ticket 08: make
  `request(for:madeIn:)` refuse a target that is not allowed at the click, so the "asks first" branch cannot be
  forgotten. Open for Parag: CODING_STANDARDS #2 could add "…and the destination has not changed since", which the
  code already enforces.
- 2026-11-28 (`1312ab1`, ticket 02): **index migration 4: `title_source`.** Claimed version 4 (wave 1 took 3; no
  other migration on `t3/wave2` or `t3/wave1-search` when pushed). `title_source TEXT`: NULL or `model` = the model's
  title (or the original name), `user` = typed by the user (`TitleSource`, `IndexedScreenshot.titleSource`). The
  same migration runs `UPDATE screenshots SET title_source = 'user' WHERE note = 'renamed by the user' OR note GLOB '*; renamed by the user'`
  (the note `rename(_:to:)` has appended at the end since `02e6420`; GLOB is case-sensitive; tightened in review), so names fixed in the
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
- 2026-11-28 (review of PR #20): the backfill matches the phrase only as the whole note or its last `; ` part,
  because `process` notes can quote an error that contains the model's title ("kept name: rename failed (…)").
  Undo after a hand rename leaves `title_source = user` with the typed title while the file is back at the model's
  name; this is harmless only because ticket 06 checks `restored_by_undo` **before** `title_source` (spec step 7),
  and ticket 06 must keep that order.
- 2026-11-28 (`7569cb2`, ticket 06): **Analyze Again in core: `ScreenshotProcessor.reanalyze(rowID:request:)`** in
  `ScreenshotProcessor+Reanalyze.swift`. `request:` is a `UserUploadAuthorization?` like `process(_:userRequest:)`: the
  `.reanalyze` job (PR #25) passes `UserUploadRequests.authorization(for:)` of its request at each attempt. It keys on
  the row id (new `ScreenshotIndex.lookup(id:)`) and reads the path at each call. Order as the spec: missing →
  exclude/Pause → fingerprint + prepare → `decide` on the snapshot read once → `analyze` → apply → name → place →
  undo → Finder → `updatePath` → `save`. Nothing is written before the analysis succeeds, so a throw leaves the row
  byte-for-byte as it was. `restored_by_undo` is checked **before** `title_source`, as the PR #20 note asks.
- 2026-11-28 (`7569cb2`): **one send path.** `.analyze(` stays only in `ScreenshotProcessor.swift`: `process` and
  `reanalyze` both call `consentedJob(capturedAt:userRequest:)` (THE `decide` call on the snapshot it reads) and
  `send(_:context:with:)`, which takes only the `ConsentedJob` that `consentedJob` makes (fileprivate init). No
  `lint-allow`. They also share `destinationFolder(for:settings:)` (today `moveEnabled ? organizedFolder : nil`):
  **ticket 04 puts the subfolder rule there**, and whichever of 04/06 merges second adds the "Analyze Again moves to
  the new type's folder" test (04 had not merged, so `testAnalyzeAgainAppliesTodaysMoveSettings` covers the
  organized folder only).
- 2026-11-28 (`7569cb2`): **choices the spec left open.**
  - Consent capture time for a re-analysis is the earliest of the file's dates, the time in its **original** name and
    the stored `capturedAt`: a renamed file has lost the time in its name, and earlier fails closed
    (`testARenamedFileIsJudgedByItsOriginalNameToo`).
  - A kept name (restored, your name, low confidence, unusable, rename failed) keeps the row's old title **and its
    confidence**, so the title still matches the file name. With renaming off, the row gets the model's title, as
    `process` stores it.
  - Restored rows are **index only**: no rename, no move, and no Finder tags/comment either (the user's "leave this
    file alone"). `suggestedTitle` is only returned for `.yourName`, and only when it gives a usable file name
    (otherwise "Use This Name" would throw `unusableName`).
  - The note keeps earlier parts, adds this run's notes (e.g. "kept name: rename failed (…)"), and ends with one
    "analyzed again" (not repeated on later runs). `text_status = pending` on a hash change leaves the old
    `recognizedText` until the runner reads it again, as the spec says.
  - "Same title as before" (design §5.3) is `.updated(renamed: false, titleKept: nil)`.
- 2026-11-28 (`7569cb2`): **deviation: `TitleKeptReason.renameFailed`**, a sixth reason beside the ticket's five.
  Without it a `FileOrganizer` failure (EIO, too many collisions) would look like "the title is the same as before".
  Ticket 08 needs wording for it (design §5.3 has none; "The name stays: it could not be renamed" fits the
  "Moved, name kept by rule" pattern). Test: `testARenameFailureKeepsTheNameAndTheOldTitle`.

## Verification
- 2026-11-28 (`1312ab1`, ticket 02): `SCRATCH=.build/linux-w2-02 scripts/test-linux.sh` green, 433 tests;
  `scripts/lint.sh` ok.
- 2026-11-28 (`7569cb2`, ticket 06): `SCRATCH=.build/linux-w2-06 scripts/test-linux.sh` green, 457 tests;
  `scripts/lint.sh` ok, no new `lint-allow`. Each key reanalyze test was checked to fail with its rule broken
  (order of restored/your name, `text_status` reset, original-name consent time, a write before `analyze`).
