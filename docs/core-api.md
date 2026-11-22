# ShotkeeperCore API map (for the macOS app)

What core gives you, what the app must implement, and how to wire it. Core is Foundation-only and is tested on Linux.
Decisions and their reasons: [wiki/core-implementation.md](wiki/core-implementation.md).

## The app implements
| Protocol | Where | macOS implementation |
|---|---|---|
| `ImagePreparer` | `Pipeline/ImagePreparer.swift` | ImageIO: downscale to `settings.maxImageLongSide`, encode PNG/JPEG, fill in pixel size. `PassthroughImagePreparer` is for tests/CLI only (sends the file as-is, PNG/JPEG/WebP; HEIC/TIFF throw `.unsupportedType`). |
| `FileMetadataWriter` | `Files/FinderMetadata.swift` | `getxattr`/`setxattr` on the given name; return nil for ENOATTR. Core builds the binary-plist payloads. |
| `CredentialStore` | `Settings/CredentialStore.swift` | Keychain (generic password, service `dev.shotkeeper.Shotkeeper` (the bundle id), account `key.rawValue`): `KeychainCredentialStore`. |
| `ScreenshotAnalyzer` | `Analysis/` (other task) | Built from settings + credentials; core ships the Clairic and local analyzers. |
| Folder watching | app only | FSEvents on `settings.watchedFolderOverride` or the `com.apple.screencapture location` (default Desktop). For each created/renamed file, `ScreenshotDetector(customPrefix:).isScreenshot(url)` → `queue.enqueue(url)`. |
| Server process | app only | Run `MLXRuntimePlan` commands with `Process`; apply `IdlePolicy` and `RestartPolicy`. |

## Wiring
```swift
let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Shotkeeper")
let index = try ScreenshotIndex(fileURL: support.appendingPathComponent("index.sqlite"))
let undoLog = UndoLog(fileURL: support.appendingPathComponent("undo.jsonl"))
let box = LockedValue(AnalyzerSnapshot(analyzer: makeAnalyzer(settings), settings: settings))  // replaced whole on rebuild
let requests = ProcessExistingRequests()
let processor = ScreenshotProcessor(
    snapshot: { box.value },                       // analyzer + the settings it was built from, read together
    imagePreparer: ImageIOPreparer(), metadataWriter: XattrWriter(),
    index: index, undoLog: undoLog)
let queue = ProcessingQueue(
    configuration: .init(concurrency: 1, requestsPerMinute: settings.requestsPerMinute),
    probe: { await localServerHealthy() },         // optional; e.g. GET MLXRuntimePlan.healthURL(port:)
    jobHandler: { url, request in                  // request: carried by the job, every attempt
        _ = try await processor.process(url, processExisting: requests.authorization(for: request)) })
// Process Existing: queue.enqueue(url, processExisting: requests.request(for: target, madeIn: generationAtClick))
for await status in await queue.statusUpdates() { menuBar.show(status) }
```
For the toast, the handler calls `processor.processWithReport(url)` and feeds a `ScreenshotEvent` to a `ToastBatcher`
on the main actor; on a thrown error it sends `.failed(originalURL:problem:)` when `UserFacingError.shouldNotify(error)`,
then rethrows so the queue still decides about retries (see `AppCoordinator.buildQueue`).
At launch, re-enqueue `index.entries(withStatus: .pending)` and `.failed` if you want retries across restarts.
Change the rate with `queue.setRequestsPerMinute(_:)` (in place; queued jobs and pause/hold state are kept). Do not rebuild the queue for it.

## Types by folder
- **Files/**
  - `ScreenshotDetector`: `isScreenshot(filename:)`. Localized default names plus `customPrefix`; ignores the hidden (leading ".") temp file macOS writes first.
  - `ExcludeRules`: `rules: [Rule]` (`.filenameGlob`, `.filenameContains`, `.folder`), `pause(for:from:)`, `resume()`,
    `exclusion(for:capturedAt:now:)`. Pausing = screenshots captured or processed in the window are skipped (not held).
  - `FileOrganizer`: `organize(_:stem:into:) -> URL` (rename and/or move, "Title 2.png" on collision, never
    overwrites), `move(_:to:)` (exact target or `.destinationExists`). Errors: `FileOrganizerError`.
  - `UndoLog`: `append(from:to:)`, `records()`, `undo(id:)`, `undoLast()`. Errors: `UndoError`
    (`.originalPathOccupied`, `.fileNotAtDestination`, …). Prefer `ScreenshotProcessor.undoLast()`, which also fixes the index.
  - `FinderMetadata`: attribute names, `tagsPayload`, `commentPayload`, `decode*`, `mergedTags`, `apply(tags:comment:to:using:)`.
    Note: Finder's Get Info shows comments from `.DS_Store`, so an xattr-only comment may not appear there; Spotlight indexes it.
  - `_FilenameSanitizerStub.swift`: delete at merge (the analyzers task owns `FilenameSanitizer`).
- **Index/**
  - `ScreenshotIndex`: `save(_:) -> id` (upsert by path), `updatePath(from:to:)`, `lookup(byPath:)`, `lookup(byHash:)`,
    `recent(limit:)`, `recentProcessed(limit:)` (`done` only), `entries(withStatus:limit:)`, `search(_:limit:)` (empty → recent),
    `stats()`, `markRestoredByUndo(path:)`. Thread-safe. Schema version 2 (adds `restored_by_undo`).
  - `search(_ query: ScreenshotQuery, limit:) -> ScreenshotSearchResult` (search window): text + `contentType` chip +
    optional batch `paths`, AND-combined, `done` rows only; returns `rows`, `matchCount` and `totalCount` for the footer.
  - `IndexedScreenshot`: one row; `note` explains kept names / non-fatal problems. `ProcessingStatus`: pending/done/failed/skipped.
  - `ContentFingerprint.compute(for:)`: size + mtime + first 64 KiB (not a security hash).
- **Queue/**
  - `ProcessingQueue` (actor): `enqueue`, `pause(until:)`, `resume()`, `setRequestsPerMinute(_:)`, `statusUpdates()`, `status`, `waitUntilIdle()`,
    `succeededCount`, `failedCount`, `lastFailure`.
  - `QueueStatus`: `.idle`, `.processing(current:remaining:)`, `.paused(until:)`, `.offline`, `.error(message)`.
    `.error` means held on `unauthorized`/`notConfigured`: show "Fix settings", call `resume()` after the user fixes them.
  - `QueueClock`/`SystemQueueClock`, `BackoffPolicy`, `TokenBucket`.
- **Pipeline/**
  - `ScreenshotProcessor(snapshot:…)`: `process(_:processExisting:) -> ProcessingOutcome` (`.processed(finalURL:renamed:moved:)` or `.skipped(SkipReason)`; `.awaitingConsent` = `UploadConsent.decide` refused),
    `undoLast()`, `undo(id:)`. Throws analyzer/preparer errors after recording `failed` in the index; the file is untouched.
    - `processWithReport(_:) -> ProcessingReport` (`originalURL`, `outcome`, `undoRecordID`): what the toast needs.
    - `rename(_:to:) -> ManualRenameResult` (toast "Edit name"): `FilenameSanitizer` + original extension + `FileOrganizer`
      collisions ("Name 2.png"), undo record, index path and title. Throws `ManualRenameError.unusableName`, `FileOrganizerError`.
    - `undo(ids:) -> UndoBatchResult` (Undo / Undo All; newest first, keeps going), `lastUndoable()` (menu "Undo: <title>").
    - Undo flags the file in the index (`restoredByUndo`); `process` then returns `.skipped(.restoredByUndo)` for it forever,
      also after a restart and after the file changed.
- **Feedback/** (UI wording and rules for the toast and the menu; the app only renders)
  - `ToastBatcher`: `beginRun(_:)` (Process existing), `record(_ event: ScreenshotEvent, at:) -> ToastContent?`. One summary
    for > 3 counted files within 10 s or for a run; counts renamed/moved and excluded files.
  - `ToastContent`: `.renamed(RenamedToast)`, `.restored(RestoredToast)`, `.batch(BatchToast)`, `.error(ErrorToast)`, each
    with its label/title/subline/button text. `ToastCountdown`: 4 s, `pause(at:)`/`resume(at:)`, `fraction(at:)`.
  - `RecentItems.make(from:)` (last 5 `done`, newest first) → `RecentItem` with `accessibilityLabel(now:time:)`.
  - `TimeLabel(calendar:locale:)`: `short` ("4:24 PM", "Yesterday", "Mon", "Nov 14"), `spoken` ("today 4:24 PM"), `timeOrDateTime`.
  - `MenuText`: `status(queue:watchedFolderName:indexedCount:failure:now:time:) -> MenuStatusSummary` (`StatusDot` + two
    lines), `download(fraction:totalGB:)`, `undoItem(for:)`, `screenshots(_:)`.
  - `ExpiringMessage`: menu message that expires after 30 s or on `clearAfterSuccess()`.
  - `UserFacingError.problem(for:) -> UserFacingProblem` (short text, `needsSettings`; also `SQLiteError` codes → "the index file is damaged" etc.), `shouldNotify(_:)` (no toast for
    retryable errors). Use it instead of `String(describing: error)` anywhere in the UI.
- **Search/** (search window logic; the app renders `SearchWindowState` and runs the searches it asks for)
  - `SearchWindowState`: text, `SearchChip`, batch paths, items, selection, `phase` (`.loading`, `.results`,
    `.noMatch(SearchMessage)`, `.emptyIndex`, `.error(SearchMessage)`), `footerText`, `spaceOpensQuickLook`.
    Mutations (`setText`, `selectChip`, `clickTag`, `clearSearch`, `escape()`, `showBatch`, `windowHidden`) return
    true when `query` changed: run it with `resultLimit`, then `apply(_:for:)` or `fail(_:for:)` (stale answers are ignored).
  - `SearchResultItem`: title (file stem), `subtitle(now:time:)` ("x.com · 5 min ago"), `accessibilityLabel(now:time:)`,
    `hashtags`, `metadata(time:)` (Source / Type / Taken / Folder). `IndexUnavailableError` → the error state.
  - `TimeLabel.relative(_:now:)` ("Just now", "12 min ago", "3 h ago", then `short`), `dateTime(_:)`.
- **Setup/** (first-run setup; the app renders it)
  - **`UploadConsent.decide(target:grants:capturedAt:processExisting:) -> UploadDecision`** (`Setup/UploadConsent.swift`):
    THE consent decision (CODING_STANDARDS #2), pure. `.allow` for `UploadTarget.thisMac`; for `.cloudflare` /
    `.customEndpoint(identity)` only when a grant covers the target AND (`capturedAt >= grantedAt` OR a
    `ProcessExistingAuthorization` made for the same target); else `.skip(.destinationNotAllowed)` /
    `.skip(.takenBeforeGrant)`. `decide(settings:capturedAt:processExisting:)` for the selected backend.
    `effectiveCaptureTime(creationDate:modificationDate:nameDate:)` = the earliest, `.distantPast` when none (fails
    closed); the name time is `ScreenshotDetector.captureDate(fromFilename:timeZone:)`; the processor reads a file's
    dates (`effectiveCaptureTime(of:timeZone:)`) before and after preparing it and uses the earlier. `ScreenshotProcessor` is its
    only file-level caller: on the `AnalyzerSnapshot` read once after preparing the image, right before `analyze`.
    `ProcessExistingRequests` issues generation-stamped `ProcessExistingRequest`s and `invalidateAll()`s them on a
    backend/endpoint/grant change; `ProcessingQueue.enqueue(_:processExisting:)` carries one with its job for every
    attempt (retries, holds) and drops it when the job ends; a running job does not take on a later request. `UploadConsent.grant(for:in:)` is the shared matching rule.
  - `BackendGate.readiness(settings:hasClairicToken:) -> BackendReadiness` (`.ready`, `.needsConsent`,
    `.notConfigured(reason)`): what the UI shows and offers (the analyzer factory's hold, `mayWatch` for the folder
    watcher, Process Existing refused unless ready). `consentRequest(for:) -> ConsentRequest?` +
    `granting(_:expectedEndpoint:in:at:)` (rounded up to the next whole second) for Settings' confirmation. Grants:
    `AppSettings.uploadGrants`, `CustomEndpointIdentity` (scheme + host + port).
  - `SetupFlow` (5 `SetupStep`s, `showsBack`, `primary` title/enabled/`SetupPrimaryAction`, `advance()`, `back()`,
    `choose(_:)`), `SetupCards.make(physicalMemoryBytes:)` (the two step-3 cards), `ClairicPricing.perThousandText()`,
    `TryIt.apply(_:entry:to:)` (step 4 from a `ScreenshotEvent`), `ConnectionTestText.failure(_:backend:)`.
- **Brand/**
  - `IconGeometry.appIcon` / `.menuBarGlyph`: unit-square corners and sparkle of the app icon and the menu bar glyph.
- **Settings/**
  - `AppSettings`: all settings with defaults; `encoded()` / `AppSettings.decode(_:)` (missing/bad keys → defaults).
    `showRenameToast` (default true) and `playRenameSound` (default false) drive the toast and the sound.
    Toggle Finder metadata with `writeFinderMetadata`. Show the Clairic privacy notice until `hasSeenPrivacyNotice`.
  - `CredentialStore`, `CredentialKey.cloudflareAPIToken`, `.customEndpointAPIKey`, `InMemoryCredentialStore`.
- **Runtime/**
  - `ModelCatalog.all` (4-bit, 3-bit, 2-bit `ModelVariant`s with pinned revisions, sizes, min RAM, warnings).
  - `BackendRecommender.recommend(physicalMemoryBytes:)` (use `ProcessInfo.processInfo.physicalMemory`) →
    `BackendRecommendation(recommended:alternatives:notes:)` with ready-to-show titles, details, and warnings.
  - `MLXRuntimePlan(applicationSupport:uvPath:python3Path:)`: `installCommands`, `isSupportedPython(versionOutput:)`
    (needed only without uv), `downloadCommand(for:)`, `localModelDirectory(for:)`, `serverCommand(model:port:)`,
    `healthURL(port:)`, `chatCompletionsURL(port:)`. Commands are argv arrays: run them without a shell.
  - `IdlePolicy(idleTimeoutMinutes:)`: `shouldStop(lastActivity:now:inFlight:)`. `RestartPolicy`: `recordCrash(at:)` →
    `.restart(after:)` / `.giveUp`; `reset()` when the user retries.
