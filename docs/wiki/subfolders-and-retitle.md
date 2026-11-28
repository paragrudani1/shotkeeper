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

## Verification
- 2026-11-28 (`1312ab1`, ticket 02): `SCRATCH=.build/linux-w2-02 scripts/test-linux.sh` green, 433 tests;
  `scripts/lint.sh` ok.
- 2026-11-28 (ticket 03): `SCRATCH=.build/linux-w2-03 scripts/test-linux.sh` green after merging ticket 02, `scripts/lint.sh` ok;
  `ProcessingQueueTests` passed 15 runs in a row.
