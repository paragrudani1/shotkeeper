# ShotkeeperCore API map (for the macOS app)

What core gives you, what the app must implement, and how to wire it. Core is Foundation-only and is tested on Linux.
Decisions and their reasons: [wiki/core-implementation.md](wiki/core-implementation.md).

## The app implements
| Protocol | Where | macOS implementation |
|---|---|---|
| `ImagePreparer` | `Pipeline/ImagePreparer.swift` | ImageIO: downscale to `settings.maxImageLongSide`, encode PNG/JPEG, fill in pixel size. `PassthroughImagePreparer` is for tests/CLI only (sends the file as-is, PNG/JPEG/WebP; HEIC/TIFF throw `.unsupportedType`). |
| `FileMetadataWriter` | `Files/FinderMetadata.swift` | `getxattr`/`setxattr` on the given name; return nil for ENOATTR. Core builds the binary-plist payloads. |
| `CredentialStore` | `Settings/CredentialStore.swift` | Keychain (generic password, service `dev.shotkeeper.Shotkeeper` (the bundle id), account `key.rawValue`): `KeychainCredentialStore`. |
| `ScreenshotAnalyzer` | `Analysis/` (other task) | Built from settings + credentials; core ships `CloudflareClairicAnalyzer` and `OpenAICompatibleAnalyzer` (profile `.localServer` for local/custom endpoints, `OpenRouterBackend.configuration(apiKey:model:)` for OpenRouter). |
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

### Where the macOS app does it (2026-11-28)
`AppCoordinator` is the wiring point; its parts each have a file and a small host protocol the coordinator implements:
| Part | File | Owns |
|---|---|---|
| `FolderCapture` (`coordinator.capture`) | `App/Shotkeeper/Coordinator/FolderCapture.swift` | Folder watcher, `ScreenshotDetector`, re-queue of `pending` rows, Process Existing (`ProcessExistingRequests`). |
| `FileActions` (`coordinator.fileActions`) | `App/Shotkeeper/Coordinator/FileActions.swift` | `undoLast()`, `undo(ids:)`, `rename(_:to:)` through `ScreenshotProcessor`. |
| Test Connection | `App/Shotkeeper/Coordinator/ConnectionTest.swift` | `testConnection(settings:secrets:)` (generated image only). |
| `SearchResultActions` | `App/Shotkeeper/Platform/SearchResultActions.swift` | Open / Copy Image / Reveal on a search result. `WorkspaceActions`: the `NSWorkspace`/pasteboard calls. |
Change the rate with `queue.setRequestsPerMinute(_:)` (in place; queued jobs and pause/hold state are kept). Do not rebuild the queue for it.

## Types by folder
- **Files/**
  - `ScreenshotDetector`: `isScreenshot(filename:)`. Localized default names plus `customPrefix`; ignores the hidden (leading ".") temp file macOS writes first.
  - `ExcludeRules`: `rules: [Rule]` (`.filenameGlob`, `.filenameContains`, `.folder`), `pause(for:from:)`, `resume()`,
    `exclusion(for:capturedAt:now:)`. Pausing = screenshots captured or processed in the window are skipped (not held).
  - `FileOrganizer`: `organize(_:stem:into:) -> URL` (rename and/or move, "Title 2.png" on collision, never
    overwrites), `move(_:to:)` (exact target or `.destinationExists`). Errors: `FileOrganizerError`.
  - `FilenameStyle(casing:datePrefix:)` (`AppSettings.filenameStyle`): `stem(from:capturedAt:timeZone:)` = `FilenameSanitizer`
    then Sentence case (first letter only; default) / Title Case / kebab-case, plus the optional "2026-11-21 " date prefix.
    The pipeline and `ScreenshotProcessor.rename(_:to:)` (toast "Edit name") both use it.
  - `UndoLog`: `append(from:to:)`, `records()`, `undo(id:)`, `undoLast()`. Errors: `UndoError`
    (`.originalPathOccupied`, `.fileNotAtDestination`, …). Prefer `ScreenshotProcessor.undoLast()`, which also fixes the index.
  - `FinderMetadata`: attribute names, `tagsPayload`, `commentPayload`, `decode*`, `mergedTags`, `apply(tags:comment:to:using:)`.
    Note: Finder's Get Info shows comments from `.DS_Store`, so an xattr-only comment may not appear there; Spotlight indexes it.
  - `_FilenameSanitizerStub.swift`: delete at merge (the analyzers task owns `FilenameSanitizer`).
- **Index/**
  - `ScreenshotIndex`: `save(_:) -> id` (upsert by path), `updatePath(from:to:)`, `lookup(byPath:)`, `lookup(byHash:)`,
    `recent(limit:)`, `recentProcessed(limit:)` (`done` only), `entries(withStatus:limit:)`, `search(_:limit:)` (empty → recent),
    `stats()`, `markRestoredByUndo(path:)`. Thread-safe. Schema version 3 (2 added `restored_by_undo`; 3 adds the
    recognized-text columns, rebuilds FTS with `recognized_text`, and adds the filter and pending-text indexes).
  - `changes() -> AsyncStream<IndexChange>`: every committed row change from the call on, in commit order (unbounded
    buffer, also for a stream held but not iterated; one subscription per call, ended by dropping the stream or
    cancelling its iteration; finishes when the index is freed). `IndexChange`: `kind` (`.inserted` / `.updated`
    / `.removed`), `id` (stable across path changes) and `path` (after the change; for `.removed`, the path it had).
    `save` → inserted or updated (also for an identical row); `updatePath` → updated, plus removed for a stale row it replaced; `markRestoredByUndo`
    → updated; `setRecognizedText` → updated, only when it applied. For Spotlight, search refresh and clean-up.
  - Recognized text (wave 1): `setRecognizedText(_ result: TextRecognitionResult, recognizedBy:id:ifContentHash:) -> Bool`
    is the conditional write: it applies only while the row's `content_hash` equals `ifContentHash` and its
    `textStatus` is `.pending`, and sets `.text(s)` → `.done`, `.noText` → `.noText` (text nil), `.failed(reason:)` →
    `.failed` (reason in `textError`, never recognized text), plus `textRecognizedBy`. Nothing else in the row changes.
    `newestPendingTextRow()`: the runner's next row (newest `COALESCE(captured_at, processed_at)`, then id).
    Search matches recognized text too (AND over all FTS columns) at the lowest weight: `ScreenshotIndex.ftsColumns`
    holds the FTS columns and their bm25 weights (title 10, tags 6, description 3, key_text 1, source 2,
    recognized_text 0.5); the FTS table, triggers and `bm25Weights` come from it.
  - SQL indexes (migration 3): `screenshots_taken_at` on `COALESCE(captured_at, processed_at)` (date filter: use that
    exact expression), `screenshots_source_app_or_site`, and `screenshots_text_pending` (partial, `text_status = 'pending'`).
  - Columns (internal): `ScreenshotIndex.columns` declares each column once (SQL, migration, bind, read). Adding one:
    an entry with the next `addedIn`, `SQLiteMigration(version: n, statements: addColumns("new_column"))`, and
    `n: ["new_column"]` in the test-side `shippedColumns`.
  - `search(_ query: ScreenshotQuery, limit:now:calendar:) -> ScreenshotSearchResult` (search window): text +
    `contentType` chip + optional batch `paths` + optional `date: DateFilter`, AND-combined, `done` rows only; returns
    `rows`, `matchCount` and `totalCount` for the footer. The date filter compares
    `COALESCE(captured_at, processed_at)` (the `screenshots_taken_at` index) with `date.interval(now:calendar:)`, resolved
    on each call; the app passes the search model's `now()` and `time.calendar`. With a date or a source and no text:
    newest taken first. `source: SourceKey` is resolved to the raw `source_app_or_site` spellings with that key and
    filtered with `IN (SELECT value FROM json_each(?))` (the `screenshots_source_app_or_site` index); a key with no rows
    left finds nothing. `searchSQL(_:sourceSpellings:now:calendar:)` (internal) builds the statements, for query-plan tests.
  - `sources() -> [SourceFacet]` (wave 1 ticket 03): the source list, one facet per `SourceKey` over `done` rows
    (`key`, `displayName` = most common trimmed spelling, alphabetical tie-break; `count` over the whole index), sorted by
    count then name; rows without a source left out.
  - `IndexedScreenshot`: one row; `note` explains kept names / non-fatal problems. `ProcessingStatus`: pending/done/failed/skipped.
    Text fields: `recognizedText`, `textStatus: TextStatus?` (nil = never requested; `.pending` / `.done` /
    `.noText` (stored `none`) / `.failed`), `textRecognizedBy`, `textError`. `save` writes them like every column, so a
    fresh entry without them clears old text.
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
  - `TimeLabel.relative(_:now:)` ("Just now", "12 min ago", "3 h ago", then `short`), `dateTime(_:)`; date filter
    wording `days(_:_:now:)` ("Oct 3 – 17", "Dec 28, 2025 – Jan 4, 2026") and `day(_:now:alongside:spelled:)`.
  - Date filter (wave 1, 2026-11-28): `DateFilter` (`.today`, `.yesterday`, `.last7Days`, `.last30Days`,
    `.days(from:through:)` over `CalendarDay`); `interval(now:calendar:)` = whole local days `[start, end)`;
    `label`, `spokenValue`, `takenPhrase(now:time:)`. `SearchWindowState`: `date`, `setDateFilter(_:)`,
    `clearFilters()`, `datePicker: DatePickerState?` (highlight, custom range, From/To; `DatePickerState(today:current:calendar:)`),
    `noMatchButtons`, `now`/`time` for the wording. `SearchKeyMap`: ⌘D (`.dateFilter`) and ⌫ (`.deleteBackward`).
  - Source filter (wave 1 ticket 03, 2026-11-28): **`SourceKey`** (`Search/SourceKey.swift`), the one rule that two
    spellings are one source: `SourceKey(_ raw:)` (nil when blank) trims, folds case and diacritics, drops a leading
    `www.` and a lone top-level domain (`x.com` → `x`; `bbc.co.uk`, `docs.google.com` kept); no alias table.
    `SourceKey.fold(_:)` is the folding alone (the picker's narrow field uses it). `SourceFacet` (`key`, `displayName`,
    `count`). `SearchWindowState`: `source`, `sourceName`, `setSource(_ facet:)`, `sources` (nil until loaded) and
    `setSources(_:)`, Source pill wording (`sourcePillTitle`/`Value`/`Help`, `sourcePillIsDisabled`), the picker
    `sourcePicker: SourcePickerState?` (`narrowText`, `rows: [SourcePickerRow]`, `highlighted`, `noMatchMessage`,
    `deleteClearsSource`) with `toggleSourcePicker()` (false = disabled, beep), `setSourceNarrowText`,
    `moveSourceHighlight`, `chooseSource`, `chooseHighlightedSource`, `clearSourceFromPicker`; `isPickerOpen`,
    `closePickers()`. `SearchKeyMap`: ⌘S (`.sourceFilter`).
  - Copy Text (wave 1 ticket 06, 2026-11-28): `SearchResultItem` carries `recognizedText`, `textStatus`, `textError`.
    `SearchWindowState.copyTextOutcome: CopyTextOutcome` (`.copy(text)` for `done`, `.readFirst(id:)` for never read,
    `.noText`, `.failed(fileMissing:)`, `.wait(id:)` for `pending`, `.notAvailable`; `message` gives the pill text);
    `copyTextBadge: CopyTextBadge?` (`.copyText`, `.reading`, `.readAgain` with `title`, `shortcut`, `help`,
    `accessibilityLabel`/`Hint`; nil hides it); late-copy rule: `requestCopyText(pasteboardChangeCount:)` remembers a
    `.wait` as `waitingTextCopy` (only the last counts; moving the selection, a new query or hiding drops it), then after
    each refresh `resolveWaitingTextCopy(pasteboardChangeCount:) -> LateTextCopy?` (`.waiting`, `.dropped`,
    `.perform(outcome)`). `SearchKeyMap`: ⇧⌘C (`.copyText`, trigger `.shiftCommand("c")`).
  - `SearchKeyMap` (added 2026-11-28): the search window's key table. `bindings` (`SearchKeyBinding`: a `SearchKeyTrigger`
    `.plain(keyCode:)` or `.command(Character)` → a `SearchKey`: up, down, open, close, space, copyImage, reveal,
    quickLook, `chip(_)`), `plain(keyCode:modifiers:)` (no ⌘⌥⌃⇧), `command(keyCode:modifiers:characters:)` (typed ASCII
    letter/digit, else the ANSI physical key via `physicalCharacter(_:)`), `commandShortcutText(for:)` ("⌘C"),
    `reservedCommandCharacters` (A V X Z H M Q stay free). `SearchKeyMapTests` fail when two actions share a key. The app
    only translates `NSEvent`s (`SearchPanel.swift`) and performs the action (`SearchPanelController.handle`).
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
    A new setting needs a `CodingKeys` case and an `init(from:)` line; `SettingsTests.testEveryPropertyRoundTrips` checks both.
    `showRenameToast` (default true) and `playRenameSound` (default false) drive the toast and the sound.
    Toggle Finder metadata with `writeFinderMetadata`. Show the Clairic privacy notice until `hasSeenPrivacyNotice`.
  - `filenameCasing`, `filenameDatePrefix` (→ `filenameStyle`), `searchShortcut: HotKeyShortcut` (default ⌥⌘S; a stored
    shortcut that `HotKeyRules` refuses decodes as the default).
  - `HotKeyShortcut(keyCode:modifiers:)` (`kVK_*` key code + `Modifiers`): `displayString` ("⌥⌘S"), `spokenName`.
    `HotKeyRules.problem(with:)` → `HotKeyProblem?` (needs ⌘ or ⌃, plain ⌘ is left to apps, known macOS shortcuts);
    `registrationProblem(status:)` for a `RegisterEventHotKey` failure; `HotKeyProblem.message(for:)`.
  - `CredentialStore`, `CredentialKey.cloudflareAPIToken`, `.customEndpointAPIKey`, `InMemoryCredentialStore`.
- **Runtime/**
  - `ModelCatalog.all` (4-bit, 3-bit, 2-bit `ModelVariant`s with pinned revisions, sizes, min RAM, warnings).
  - `BackendRecommender.recommend(physicalMemoryBytes:)` (use `ProcessInfo.processInfo.physicalMemory`) →
    `BackendRecommendation(recommended:alternatives:notes:)` with ready-to-show titles, details, and warnings.
  - `MLXRuntimePlan(applicationSupport:uvPath:python3Path:)`: `installCommands`, `isSupportedPython(versionOutput:)`
    (needed only without uv), `downloadCommand(for:)`, `localModelDirectory(for:)`, `serverCommand(model:port:)`,
    `healthURL(port:)`, `chatCompletionsURL(port:)`. Commands are argv arrays: run them without a shell.
  - `DownloadStats(totalBytes:)`: `record(bytes:at:)` → `bytesText` ("4.1 of 9.1 GB"), `speedText`, `timeLeftText`, `summary`
    (speed over the last 10 s). `DiskSpaceCheck.evaluate(availableBytes:downloadBytes:alreadyOnDisk:needsRuntime:)` →
    `.enough` / `.notEnough` with a `message` (rest of the download + 1 GB runtime + 2 GB margin; unknown free space allows).
  - `IdlePolicy(idleTimeoutMinutes:)`: `shouldStop(lastActivity:now:inFlight:)`. `RestartPolicy`: `recordCrash(at:)` →
    `.restart(after:)` / `.giveUp`; `reset()` when the user retries.
