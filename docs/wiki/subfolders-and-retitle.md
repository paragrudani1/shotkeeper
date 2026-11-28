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
- 2026-11-28 (ticket 03): **queue: job kinds, front placement, per-kind dedupe.** `ProcessingQueue` jobs are
  `QueueJob.process(URL)` or `.reanalyze(rowID:)`; `enqueue(_:atFront:userRequest:)` replaces `enqueue(_:userRequest:)`
  and the `JobHandler` gets `(QueueJob, UserUploadRequest?)`, so the coordinator dispatches on the kind (its
  `.reanalyze` branch does nothing until ticket 08, since nothing enqueues that kind yet). A job is a duplicate only
  with the same kind and key: a second `.reanalyze` of a queued or running row does nothing (story 63), while
  `.process(a)` and `.reanalyze` of the row at `a` are different jobs. `atFront` puts the job after earlier front
  jobs (they keep their order) and before every other waiting job; it never pre-empts the running job and still
  takes a rate-limit token (story 52). A job already waiting keeps its place, and still takes on a later user
  request, as before. The user request lives as long as the job, either kind; consent stays in
  `UploadConsent.decide`. Tests: `ProcessingQueueTests` (`testAFrontJobBehindFiftyWaitingJobsRunsNextAndStillTakesAToken`,
  `testASecondReanalyzeOfARunningRowDoesNothing`, `testAReanalyzeJobKeepsItsRequestThrough…`).
- 2026-11-28 (ticket 03): **per-job state for the app.** `ProcessingQueue.jobStates` / `jobStateUpdates()` give each
  queued or running job's `QueueJobState`: `.queued`, `.running`, or `.held(QueueHold)` (`.needsAttention(text)`,
  `.paused(until:)`, `.offline`). An attempt already sent when the user pauses stays `.running`. Ended jobs are
  absent; done or failed comes from the handler (ticket 08 maps both to the row). The menu's `QueueStatus` is
  unchanged except `.processing(current:)` is now `URL?`: nil while a `.reanalyze` job is the one shown. `lastFailure`
  records `.process` failures only. The file-only `Handler` init fails a `.reanalyze` job at once
  (`QueueJobError.noReanalyzeHandler`).
- 2026-11-28 (ticket 03): **deviation: two existing tests changed beyond the enqueue call.** Their `jobHandler`
  closures now take a `QueueJob` (`ScreenshotProcessorTests.testAUserUploadRequestLastsTheWholeJobAcrossRetries`,
  `CoordinatorPartsTests.testStartWatchingRequeuesPendingRowsOnce`). The ticket has the handler dispatch on the kind,
  so that is the handler's call shape changing, not a weaker test.
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

- 2026-11-28 (`d885459`, review of PR #27): **reanalyze reads the row again after `analyze`.** The row read before
  `send` was saved with its old path, and `save` upserts by path, so a hand rename or an Undo during the analysis left
  two rows: one at the file, one at a path with no file. Now `reanalyze` looks the row up by id after `send` and runs
  the name rules on that fresh row: a name typed meanwhile is kept and the model's title is the suggestion
  (`.yourName`); a row restored meanwhile is index only (`.restoredByUndo`). If the row is gone, or its file is gone
  (moved outside Shotkeeper, the index could not follow), it returns `.refused(.missing)` and writes nothing.
  Remaining window: the steps after the second read are synchronous (no `await`), so a rename can only race them from
  another thread. Tests: `testARenameByHandDuringTheAnalysisKeepsTheTypedName`,
  `testAnUndoDuringTheAnalysisLeavesTheFileWhereUndoPutIt`, `testAFileMovedAwayDuringTheAnalysisIsNotWritten` (all
  three failed before the fix; saving the old row again fails the first two).
- 2026-11-28 (`d885459`): **status: refused in core.** New `ReanalysisRefusal.notDone(ProcessingStatus)`, checked
  before the send and again after it. Search shows only `done` rows, so the panel should never offer a pending or
  failed row. But a `process` run can take the path while the job waits or runs (it saves `pending`, then `done` or
  `failed`), and writing over its row would race it. Ticket 08 needs wording for `.notDone` (nothing was written).
  It may also disable Analyze Again for such a row, but core is what enforces the rule. Test:
  `testARowThatIsNotDoneIsRefusedBeforeOrAfterTheAnalysis`.
- 2026-11-28 (`d885459`): **a content change keeps `title_source = user` in reanalyze**, unlike `process`, which
  resets it to `model` (spec "Index schema"). `process` sees a path whose bytes were replaced, which is usually a new
  screenshot. Analyze Again is the user asking about *this* file, whose name they typed, and spec step 7 keeps a
  user's name and offers the model's title as `suggestedTitle`. Resetting it would rename their file unasked; "Use
  This Name" is one click away. Test: `testAUserNamedFileWhoseContentChangedKeepsTheUsersName`.
- 2026-11-28 (`d885459`): **notes are replaced, not piled up.** `ScreenshotProcessor.note(after:adding:touchedFile:)`
  drops earlier "kept name: …" parts (from `process` and from `place`'s "kept name: rename failed (…)") and, when this
  run wrote Finder metadata again (not restored rows), "Finder metadata not written (…)". Then come this run's notes
  and one "analyzed again". "renamed by the user" and "undo record not written" still hold, so they stay. The kept
  reason itself is in the outcome (`titleKept`); reanalyze does not write `process`'s "kept name: title confidence…"
  notes. Test: `testStaleNotePartsAreReplacedNotAppended`.
- 2026-11-28 (`d885459`): `UserUploadAuthorization.target` is `public let`, so an issued authorization cannot be
  pointed at another target. Nothing assigned it.

## Verification
- 2026-11-28 (`1312ab1`, ticket 02): `SCRATCH=.build/linux-w2-02 scripts/test-linux.sh` green, 433 tests;
  `scripts/lint.sh` ok.
- 2026-11-28 (ticket 03): `SCRATCH=.build/linux-w2-03 scripts/test-linux.sh` green after merging ticket 02, `scripts/lint.sh` ok;
  `ProcessingQueueTests` passed 15 runs in a row.
- 2026-11-28 (review of PR #25): `attempt` publishes job states when the attempt ends too, so a pause or hold set
  during an attempt that then fails (429/5xx) shows `.held` at once, not `.running` until resume
  (`testAnAttemptThatFailsAfterAPauseShowsAsHeldNotRunning`). `waitUntil` in the queue tests now fails loudly on
  timeout. For ticket 08: always pass `atFront: true` (a job already waiting at the back is not promoted), and look
  up `.process` jobs by standardized URL.
- 2026-11-28 (`7569cb2`, ticket 06): `SCRATCH=.build/linux-w2-06 scripts/test-linux.sh` green, 457 tests;
  `scripts/lint.sh` ok, no new `lint-allow`. Each key reanalyze test was checked to fail with its rule broken
  (order of restored/your name, `text_status` reset, original-name consent time, a write before `analyze`).
- 2026-11-28 (ticket 06, after merging `t3/wave2` with PR #25 and wave 1 03): green again, 548 tests; lint ok. PR #25's
  `QueueJob.reanalyze(rowID: Int64)` matches `reanalyze(rowID:request:)` as is. New
  `ReanalyzeTests.testAReanalyzeJobKeepsItsRequestAcrossRetries` runs a `.reanalyze` job with a user request through
  the real queue (429, then success). This is the handler shape ticket 08 puts in `AppCoordinator`.
- 2026-11-28 (`d885459`, review of PR #27): `SCRATCH=.build/linux-w2-06f scripts/test-linux.sh` green, 555 tests;
  `scripts/lint.sh` ok. Mutation checks, each restored afterwards: removing the second date read after prepare fails
  `testAFileReplacedWhilePreparingIsJudgedByItsOwnDates` (reanalyze's copy of the `process` test). Saving the
  pre-send row fails the rename and Undo tests. Dropping the post-send status check fails
  `testARowThatIsNotDoneIsRefusedBeforeOrAfterTheAnalysis`. Appending notes again fails
  `testStaleNotePartsAreReplacedNotAppended`. Resetting `title_source` on a hash change fails
  `testAUserNamedFileWhoseContentChangedKeepsTheUsersName`. The `macos-app` CI job is still pending.
