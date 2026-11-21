# macOS app implementation decisions

App phase 2 (wiring the app to `ShotkeeperCore`), branch `app/phase2` pushed to `app/phase1` (PR #1), 2026-11-21.
Code: `App/Shotkeeper/{Coordinator,Runtime,UI,Platform}`. Core API: [../core-api.md](../core-api.md).

## Structure
- 2026-11-21: one `@MainActor @Observable AppCoordinator` owns settings, index, undo log, analyzer, queue, watcher and the
  local runtime. Menu, setup, settings and search views read it directly. `startServices()` (watching, login item,
  leftover-server cleanup, re-queue `pending` rows) is separate from `init` so unit tests build a coordinator in a temp
  folder with `InMemoryCredentialStore` and touch nothing on the system.
- 2026-11-21: settings are `~/Library/Application Support/Shotkeeper/settings.json` (core `AppSettings.encoded()`), written
  atomically by `SettingsStore` (lock-protected; the pipeline reads it per screenshot). A file that is not JSON is copied to
  `settings.json.unreadable` before defaults replace it. Index `index.sqlite`, undo log `undo.jsonl` in the same folder.
- 2026-11-21: the processor's `analyzer:` closure reads a lock box; `rebuildAnalyzer()` replaces it on backend, account,
  endpoint, model or secret changes, then calls `queue.resume()` if the queue was held in `.error`. `requestsPerMinute`
  is fixed per `ProcessingQueue`, so a change builds a new queue; the old one is resumed and drains its own jobs.
  Superseded 2026-11-21 (review, branch `app/review-fixes`): resuming the old queue ran its held screenshots while the
  user had paused. The coordinator now builds one queue and calls core's `ProcessingQueue.setRequestsPerMinute(_:)`.
- 2026-11-21: windows (setup, settings) are plain `NSWindow` + `NSHostingController` via `WindowPresenter`, not SwiftUI
  `Settings`/`Window` scenes: an LSUIElement app has to activate itself explicitly anyway, and `SettingsLink` from a
  menu-style `MenuBarExtra` is unreliable about bringing the window forward. Settings edits a draft and applies every change.

## Backends
- 2026-11-21: `AnalyzerFactory` (pure, unit-tested) maps settings to an analyzer. Missing account/token/URL/model gives an
  `UnconfiguredAnalyzer` that throws `.notConfigured(reason)`, so the queue holds in `.error` ("Needs attention: …")
  instead of failing screenshots.
  2026-11-21 (review): Clairic and custom-endpoint analyzers also stay `UnconfiguredAnalyzer` ("Finish setup to accept
  where screenshots are sent") until `hasSeenPrivacyNotice`, which only setup's "Use …" button sets. Before, a token and
  account ID entered in Settings → Model after "Later" made queued screenshots upload without the notice being accepted.
  "Test connection" is exempt: it sends only the generated image. Keychain items: service `dev.shotkeeper.Shotkeeper`, account `CredentialKey.rawValue`.
- 2026-11-21: setup labels the reduced-quality local option "Use local anyway (2-bit, lower quality, high memory use)"
  (app-side wording over the recommender's title; core unchanged). The Clairic token link is the Workers AI REST API
  guide, which says a custom token needs Workers AI Read + Edit (`docs/research/clairic/workers-ai-rest-api-2026-11-21.md`).
- 2026-11-21: "Test connection" analyzes a generated 640×400 receipt-like PNG (`ConnectionTestImage`), never a user file,
  with the unsaved token/key in an `InMemoryCredentialStore`; nothing is stored until the user confirms.

## Local runtime (`LocalModelRuntime` actor)
- 2026-11-21: install = `MLXRuntimePlan.installCommands` (uv if found in Homebrew/`~/.local/bin`/`~/.cargo/bin`, else a
  Homebrew python ≥ 3.11; `/usr/bin/python3` only when the Command Line Tools exist, since running it otherwise pops the
  install dialog). No automatic uv install: we do not pipe a remote script into a shell; the error tells the user how.
- 2026-11-21: download progress = max(last "Fetching N files: NN%" tqdm value from `hf download` output, bytes on disk
  under the model folder ÷ catalog size), capped at 99% until exit 0; a `.shotkeeper-download-complete` marker then
  records success (re-running `hf download` resumes).
- 2026-11-21: the server starts on demand (first local request) on `FreePort`, is polled with `HealthProbe` for up to
  10 min (first load of ~10 GB), stopped by `IdlePolicy`, restarted by `RestartPolicy` (gives up after 3 crashes in 10 min
  and holds the queue with a message). Requests send `model` = the local model path the server was launched with.
- 2026-11-21: crash leftovers: `runtime/server.pid` stores pid **and process start time** (`proc_pidinfo`); at launch and
  before every start the app kills that pid only if the start time still matches, so a reused pid is never killed.
- 2026-11-21 (review): the crash restart is a stored task that `stop()` cancels. Before, a restart scheduled just before
  a backend switch (or idle stop) relaunched the server a couple of seconds later.

## Pause semantics
- 2026-11-21: "Pause for 10 minutes" sets core's `ExcludeRules` pause window (screenshots captured in it are skipped,
  never analyzed) and pauses the queue until the same time. "Pause" (indefinite) only holds the queue; screenshots taken
  meanwhile are processed after "Resume".

## Search
- 2026-11-21: `SearchViewModel` debounces 150 ms and runs `ScreenshotIndex.search` off the main actor; empty query =
  recent. Keys are handled in `SearchPanel.sendEvent` (↑/↓/Return/Esc/⌘C/⌘R) before the text field sees them, because
  SwiftUI `onKeyPress` on a focused `TextField` does not reliably receive arrows on macOS.
  2026-11-21 (review): not while an input method has marked text (`SearchPanel.isComposingText`): ↑/↓/Return/Esc then
  pick, commit or cancel the Japanese/Chinese/Korean composition instead of moving, opening or closing. ⌘C writes the image and its
  file URL to the pasteboard. Thumbnails come from `QLThumbnailGenerator`, cached in an `NSCache`.

## Not verifiable without a Mac (2026-11-21)
CI builds and runs headless unit tests only. Unverified: menu-bar rendering, window focus/activation, the search panel's
key handling with a real keyboard, FSEvents on a real Desktop, Keychain prompts on an ad-hoc-signed build, SMAppService,
a live Clairic call, and the whole local runtime (uv install, `hf download` output format, mlx-lm loading the 2/3-bit
builds; see the open question in [core-implementation](core-implementation.md)).

## Process existing screenshots
- 2026-11-21 (review): the scan skips dataless files (iCloud `.notDownloaded`, or `SF_DATALESS` in `st_flags`), so an
  iCloud "Desktop & Documents" backlog is not downloaded and uploaded just because the button was pressed.
- 2026-11-21 (PR #2): accepting the privacy notice now rebuilds the analyzer. Before, with the consent gate in place,
  a user on the default Clairic backend who accepted the notice stayed held until another analyzer setting changed or
  the app restarted. Caught by `testAnalyzerIsRebuiltWhenSettingsOrSecretsChange`.
