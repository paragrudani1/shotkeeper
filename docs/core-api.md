# ShotkeeperCore API map (for the macOS app)

What core gives you, what the app must implement, and how to wire it. Core is Foundation-only and is tested on Linux.
Decisions and their reasons: [wiki/core-implementation.md](wiki/core-implementation.md).

## The app implements
| Protocol | Where | macOS implementation |
|---|---|---|
| `ImagePreparer` | `Pipeline/ImagePreparer.swift` | ImageIO: downscale to `settings.maxImageLongSide`, encode PNG/JPEG, fill in pixel size. `PassthroughImagePreparer` is for tests/CLI only (sends the file as-is, PNG/JPEG/WebP; HEIC/TIFF throw `.unsupportedType`). |
| `FileMetadataWriter` | `Files/FinderMetadata.swift` | `getxattr`/`setxattr` on the given name; return nil for ENOATTR. Core builds the binary-plist payloads. |
| `CredentialStore` | `Settings/CredentialStore.swift` | Keychain (generic password, service "Shotkeeper", account `key.rawValue`). |
| `ScreenshotAnalyzer` | `Analysis/` (other task) | Built from settings + credentials; core ships the Clairic and local analyzers. |
| Folder watching | app only | FSEvents on `settings.watchedFolderOverride` or the `com.apple.screencapture location` (default Desktop). For each created/renamed file, `ScreenshotDetector(customPrefix:).isScreenshot(url)` → `queue.enqueue(url)`. |
| Server process | app only | Run `MLXRuntimePlan` commands with `Process`; apply `IdlePolicy` and `RestartPolicy`. |

## Wiring
```swift
let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Shotkeeper")
let index = try ScreenshotIndex(fileURL: support.appendingPathComponent("index.sqlite"))
let undoLog = UndoLog(fileURL: support.appendingPathComponent("undo.jsonl"))
let processor = ScreenshotProcessor(
    analyzer: { currentAnalyzer() },              // re-read per screenshot: backend switches apply at once
    imagePreparer: ImageIOPreparer(), metadataWriter: XattrWriter(),
    index: index, undoLog: undoLog,
    settings: { settingsStore.current })           // AppSettings, read once per screenshot
let queue = ProcessingQueue(
    configuration: .init(concurrency: 1, requestsPerMinute: settings.requestsPerMinute),
    probe: { await localServerHealthy() },         // optional; e.g. GET MLXRuntimePlan.healthURL(port:)
    handler: { _ = try await processor.process($0) })
for await status in await queue.statusUpdates() { menuBar.show(status) }
```
At launch, re-enqueue `index.entries(withStatus: .pending)` and `.failed` if you want retries across restarts.
`requestsPerMinute` is fixed per queue: rebuild the queue when the user changes it.

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
    `recent(limit:)`, `entries(withStatus:limit:)`, `search(_:limit:)` (empty → recent), `stats()`. Thread-safe.
  - `IndexedScreenshot`: one row; `note` explains kept names / non-fatal problems. `ProcessingStatus`: pending/done/failed/skipped.
  - `ContentFingerprint.compute(for:)`: size + mtime + first 64 KiB (not a security hash).
- **Queue/**
  - `ProcessingQueue` (actor): `enqueue`, `pause(until:)`, `resume()`, `statusUpdates()`, `status`, `waitUntilIdle()`,
    `succeededCount`, `failedCount`, `lastFailure`.
  - `QueueStatus`: `.idle`, `.processing(current:remaining:)`, `.paused(until:)`, `.offline`, `.error(message)`.
    `.error` means held on `unauthorized`/`notConfigured`: show "Fix settings", call `resume()` after the user fixes them.
  - `QueueClock`/`SystemQueueClock`, `BackoffPolicy`, `TokenBucket`.
- **Pipeline/**
  - `ScreenshotProcessor`: `process(_:) -> ProcessingOutcome` (`.processed(finalURL:renamed:moved:)` or `.skipped(SkipReason)`),
    `undoLast()`, `undo(id:)`. Throws analyzer/preparer errors after recording `failed` in the index; the file is untouched.
- **Settings/**
  - `AppSettings`: all settings with defaults; `encoded()` / `AppSettings.decode(_:)` (missing/bad keys → defaults).
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
