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
- 2026-11-28 (ticket 04): **sort new screenshots into subfolders.** `SubfolderRule` (`Files/SubfolderRule.swift`) is
  `AppSettings.subfolderRule` (default `.off`, unknown stored value → `.off`). The pure router
  `relativeFolder(contentType:source:existing:)` returns the folders below the organized folder; `existing(parent)` lists
  the names already there, so reuse is tested without a disk. The pipeline's destination and placement live in
  `Pipeline/ScreenshotProcessor+Subfolders.swift` (`destination(for:settings:)`, `place(_:stem:into:notes:)`), which
  Analyze Again must reuse. `ProcessingReport.sortedInto` / `RenamedToast.sortedInto` carry the subfolder to the toast.
  Tests: `SubfolderRuleTests`, `SubfolderSettingsTextTests`, `ScreenshotProcessorSubfolderTests`, `ToastTests`
  (`testASortedScreenshotSaysWhereItWent`, `testSortedLabelAndVoiceOver`), `SettingsTests`
  (`testSubfolderRuleIsOffByDefaultAndAnUnknownStoredValueIsOff`, `testEveryPropertyRoundTrips`).
- 2026-11-28 (ticket 04): **a new source folder is named from `SourceFacet.displayName`**, as wave 1 ticket 03 requires
  (`SourceKey.rawValue` is a matching key only), not from this screenshot's own spelling as the spec's "named from the
  raw spelling" reads: the pipeline looks up the facet with the source's key in `index.sources()` and uses its display
  name (the most common trimmed spelling), else this screenshot's trimmed spelling when the index has none. Once the
  folder exists it is reused by key, so the first name given still stays (spec: "the first spelling seen stays").
  Test: `testANewSourceFolderIsNamedFromTheIndexDisplayNameNotTheKey`.
- 2026-11-28 (ticket 04): **folder-name cleaning beyond the spec's list**, for safety: a run of `/` and `:` becomes one
  " - " ("https://x" → "https - x", not "https - - - x"); runs of whitespace collapse; line separators and
  bidirectional controls (U+202A–202E, U+2066–2069) are dropped with the control characters; the 60-character cap is
  also capped at 255 UTF-8 bytes (60 emoji can be 1500 bytes); a name left with only dashes, dots and spaces
  ("../.." → "-") counts as unknown, like an empty one. macOS reserves no names besides `.` and `..`; a name a volume
  refuses falls back to the organized folder. Tests: `SubfolderRuleTests` "Folder names from hostile sources".
- 2026-11-28 (ticket 04): **the existing-name listing sees only real folders**: not hidden names, not symbolic links
  (`attributesOfItem`, which does not follow links), and a subfolder is created one level at a time below the organized
  folder, never through a link. A link or file with the folder's name → the organized folder itself, note
  `subfolder not created (“Receipts” is a file, not a folder)`. Type folders are reused in any letter case ("receipts"),
  like source folders, so Linux tests and case-sensitive volumes behave like APFS. Tests:
  `testAFileNamedLikeTheSubfolderSendsTheScreenshotToTheOrganizedFolder`,
  `testALinkNamedLikeTheSubfolderIsNotFollowedOutOfTheOrganizedFolder`, `testATypeFolderIsReusedInAnyLetterCase`.
- 2026-11-28 (ticket 04): **the fallback also covers a move into the subfolder that fails** after the folder exists
  (note `subfolder not used (…)`), not only a folder that can't be made: the spec's aim (story 15) is that the move
  still happens. If the organized folder fails too, today's rule: kept name and place, `kept name: rename failed (…)`.
  Test: `testWhenTheOrganizedFolderFailsTooTheFileKeepsItsNameAndPlace`. "Permission denied" is not tested on Linux:
  the Docker tests run as root; it takes the same path as the file in the way (real-Mac check).
- 2026-11-28 (ticket 04): **watching invariant** is kept by the existing code and now documented on `FolderWatcher` and
  `ExistingScreenshotScanner` ("a recursive watch/scan must exclude the organized folder"). Tests:
  `FolderWatcherTests.testEmitsRenamedScreenshotAndIgnoresHiddenAndNested` (existing),
  `ExistingScreenshotScannerTests.testScreenshotsInSubfoldersAreNotFound` (new, app, CI only).
- 2026-11-28 (ticket 04): **Settings and toast details the design leaves open.** With renaming off, the example shows
  the macOS name ("Screenshots › Receipts › Screenshot 2026-11-21 at 16.24.00.png"). A sorted file whose name was kept
  reads "Sorted into Receipts: <name>." in VoiceOver (no "Renamed and"); unsorted toasts now read "Renamed: <name>." /
  "Moved: <name>.", the label and name as one element. Copy uses the repo's straight apostrophe ("Can't find").
  `GeneralSettingsTab(organizedFolderStatus:)` is injectable because the snapshots' organized folder does not exist on
  the CI Mac. The "Sort Existing Screenshots…" row is left for ticket 05.
- 2026-11-28 (ticket 04): **interplay with 06.** PR #27 (06, open) splits `process` into `destinationFolder(for:settings:)`
  and `place(_:stem:into:notes:)` in `ScreenshotProcessor.swift`. Whichever merges second keeps 04's
  `destination(for:settings:)` and `place(_:stem:into:notes:)` (`+Subfolders`) as the one helper and adds the seam 1
  test "Analyze Again moves to the new type's folder". Both make the stored properties internal (one comment line
  differs).

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
- 2026-11-28 (ticket 04): `SCRATCH=.build/linux-w2-04 scripts/test-linux.sh` green after merging `t3/wave2` (ticket 03), 562 tests; `scripts/lint.sh` ok
  (no new `lint-allow`). Real-Mac checks (Finder shows the folders; "slack" reused for "Slack" on APFS; Undo from the
  toast and the menu leaves the empty folder; Settings does not jump) are open for ticket 10.
