# UI polish (spec: [../specs/ui-polish-2026-11.md](../specs/ui-polish-2026-11.md))

Implementation decisions for the four UI polish PRs. The spec holds the requirements; this page records how they were
built and where we deviated, with dates and commits.

## PR 1: rename toast + menu bar menu (branch `t3/ui-pr1-toast-menu`)

Core: `02e6420`. App and CI snapshots: `83ba0ee`; first macOS compile fixes `6fd83d6`. First green run with
snapshots: 44934052047 (21 views × light/dark). Reviewing them caught that the "was:" line was cut in the middle
because the whole text column kept clear of the close button; now only the top row does.

### Core rules (`Sources/ShotkeeperCore/Feedback/`, Linux-tested)
- 2026-11-21 (`02e6420`): toast batching is `ToastBatcher`. A "burst" starts when the counted files in the last 10 s
  exceed 3 (the 4th file turns the toast into "Renamed 4 screenshots", counting the 3 already shown singly); it continues
  while each next file arrives within 10 s of the previous one. "Process existing screenshots" calls `beginRun(urls)`:
  every file of that run goes into one summary however slowly it arrives; files outside the run keep their own toasts.
- 2026-11-21 (`02e6420`): what counts: renamed or moved files, and files skipped by an exclude rule. Kept names (low
  confidence), already-indexed, missing, paused and restored files neither count nor show a toast. A lone excluded file
  shows nothing (a toast would draw attention to a file the user wanted ignored).
- 2026-11-21 (`02e6420`): "a file restored by Undo is never processed again" is a `restored_by_undo` column (index
  migration 2). `ScreenshotProcessor` checks it before fingerprinting, so it holds after a restart, when the watcher sees
  the restored name appear, and even if the file is edited later. Undo of a file without an index row adds a minimal
  `skipped` row so the flag persists. Caveat: the flag is per path; a different file later created at exactly that
  path would also be skipped (macOS names screenshots by second, so this is not expected in practice).
- 2026-11-21 (`02e6420`): "Edit name" is `ScreenshotProcessor.rename(_:to:)`: the pipeline's `FilenameSanitizer` (so
  `/` becomes " - ", generic names like "Screenshot" are refused), the original extension, `FileOrganizer` collisions
  ("Name 2.png"), an undo record, the index row moved and its title set to the new name (search finds it). If the undo
  record cannot be written, the file is put back (no-replace) and the error is reported.
- 2026-11-21 (`02e6420`): the toast's Undo reverts every record of that toast newest first (pipeline rename + any
  "Edit name" renames), so it always ends at the original screenshot name.
- 2026-11-21 (`02e6420`): the countdown resumes with what was left, but at least 1.5 s, so the toast does not vanish the
  instant the pointer leaves it.
- 2026-11-21 (`02e6420`): status dot: green = idle/processing, gray = paused, orange = offline or held ("Needs attention",
  e.g. token missing), red = hard failure (index did not open, local server gave up). The spec says "orange =
  offline/attention, red = error"; a held queue is the "attention" case because the user can fix it in Settings.
- 2026-11-21 (`02e6420`): `TimeLabel` words ("Yesterday", "today") are English like all UI text; times and dates come
  from `DateFormatter` templates with the injected locale. Tests normalize U+202F (ICU puts a narrow no-break space
  before AM/PM).
- 2026-11-21 (`02e6420`): `UserFacingError` maps every core error to a short phrase; retryable analyzer errors
  (offline, 429, 5xx) do not produce a toast because the queue retries them and the menu shows "Offline".
  `StatusText.describe` now falls back to it instead of `String(describing:)`.

### App
- 2026-11-21 (`83ba0ee`): the menu is an `NSStatusItem` + a borderless non-activating `MenuPanel` hosting SwiftUI,
  not `MenuBarExtra`. A `MenuBarExtra` menu cannot show the status dot, 22 pt thumbnails, right-aligned times or a
  progress bar, and its window style has no reliable way to close after an action. The panel closes on resign-key,
  Esc, or after any action; ↑/↓ move a highlight shared with the mouse, Return activates, ⌥Return reveals a recent
  file, ⌘Z/⌘,/⌘Q work while it is open. ⌥⌘S is shown but not bound in the panel: the global hotkey handles it.
- 2026-11-21 (`83ba0ee`): the menu bar glyph is drawn in code (`MenuBarGlyph`, template): 4 round-capped viewfinder
  corners + a filled 4-point sparkle. Idle shows the glyph; processing/paused/offline/attention keep the SF Symbols they
  had before, as the spec asks ("changes state the way it does today"). The pulse is 4 frames (bigger sparkle, normal,
  bigger, normal) over ~0.5 s after each rename or batch update.
- 2026-11-21 (`83ba0ee`): the toast goes to the screen under the mouse pointer (`ToastPlacement.screenForNewScreenshot`).
  macOS records no display in the screenshot file and has no API for it; after ⌘⇧4/⌘⇧5 the pointer is on the captured
  screen. The controller API takes the screen explicitly (`show(_:on:)`) so a better source can be passed later.
- 2026-11-21 (`83ba0ee`): the toast is placed in the screen's `visibleFrame` (above the Dock), 16 pt from the right and
  bottom edges. The spec says "of the screen"; using the full frame would put it under the Dock.
- 2026-11-21 (`83ba0ee`): focus: `ToastPanel` is `.nonactivatingPanel` + borderless, `canBecomeKey` only while editing.
  "Edit name" calls `makeKey()` (key without activating Shotkeeper). After Save/Cancel the panel is ordered out and
  back in so the window server gives key back to the front app. Esc is caught in `sendEvent` (not during IME
  composition); Return is the field's `onSubmit`. Hover uses an AppKit tracking area with `.activeAlways`, because
  Shotkeeper is never the active app. Buttons accept the first mouse click (`FirstMouseHostingView`).
- 2026-11-21 (`83ba0ee`): deviation: the toast's buttons are not reachable with the keyboard. The toast must never
  take focus from the front app (spec), so it cannot be tabbed into. Undo has a keyboard path through the menu (⌘Z);
  "Edit name" does not. VoiceOver users can still reach the buttons with the VoiceOver cursor (check on a Mac).
- 2026-11-21 (`83ba0ee`): while the user types a name, a new toast does not replace it; the newest waits and shows
  after Save/Cancel.
- 2026-11-21 (`83ba0ee`): error toasts show even with "Show a toast after each rename" off: the setting is about
  confirmations. With toasts off, the menu's ⌘Z Undo reports through the menu message instead.
- 2026-11-21 (`83ba0ee`): the sound is the system "Pop", at most once per 2 s so a batch is not a drum roll.
- 2026-11-21 (`83ba0ee`): indigo text in dark mode is #A5A4FF, a value not in the spec: both spec indigos are below
  3.3:1 on dark materials and the spec requires 4.5:1 for text (#A5A4FF gives 5.1–7.4:1). Light mode uses the spec's
  #4644C0. Fills (countdown bar, primary buttons) use #5856D6 / #5E5CE6 as specified.
- 2026-11-21 (`83ba0ee`): a move without a rename (rename off, move on) is labelled "Moved" instead of "Renamed".
- 2026-11-21 (`83ba0ee`): the indefinite "Pause" item left the menu (the spec lists only "Pause for 10 Minutes" /
  "Resume"); Settings still has it.
- 2026-11-21 (`83ba0ee`): "View in Search" opens the search panel (empty query = recent first). Filtering to the batch
  needs the PR 2 search window; the batch toast already carries the paths.

### What CI cannot check (Parag, on a real Mac)
Focus staying in the front app while a toast shows and after editing a name; placement on several screens; hover
pausing the countdown; the edit field selecting the whole name, Return/Esc and IME input; the first click on toast
buttons; the menu panel's hover highlight, keyboard navigation and closing; the glyph pulse; the sound; VoiceOver
reading the recent rows and icon buttons.

## PR 2: search window (branch `t3/ui-pr2-search`)

Core: `f713f00`. App, panel, Quick Look and snapshots: `590d438`; fixture compile fix `c45f342`; preview layout fix
after the snapshot review `c73d98e`. The first snapshots (run 44938009639) showed the preview's Source/Type/Taken/Folder
values clipped by the button row; spacing was tightened so a 2-line description plus the grid fits in 540 pt
(checked in run 44938734784, all 7 search states × light/dark).

### Core rules (`Sources/ShotkeeperCore/Search/`, `Index/ScreenshotIndex.swift`, Linux-tested)
- 2026-11-21 (`f713f00`): `ScreenshotIndex.search(ScreenshotQuery)` combines the FTS text, the chip's `content_type`
  and an optional list of batch paths with AND (paths go in as one JSON array via `json_each`, so a batch of hundreds
  of files is one binding). It returns the page plus `matchCount` and `totalCount` for the footer.
- 2026-11-21 (`f713f00`): search shows `done` rows only. `totalCount` is therefore the menu's "N screenshots in the
  index". Pending, failed and minimal restored-by-undo rows have no analysis to show. Before, the empty query listed
  them through `recent()`. `ContentType.other` has no chip and shows under All.
- 2026-11-21 (`f713f00`): the row and preview title is the file's current name (stem), like the menu's recent rows,
  not the model's title. After an Undo or with rename off, the user sees the name Finder shows. The model's title
  still matches in the search.
- 2026-11-21 (`f713f00`): `SearchWindowState` holds the window's rules:
  - Esc clears the text and the chip first and closes only when both are empty. The spec says "clears the query
    first". The chip counts as part of the query, matching "Clear search", which clears both.
  - Ignores stale answers.
  - A new query selects the best match; the same query run again (reopen) keeps the selected file.
- 2026-11-21 (`f713f00`): row time is relative ("Just now", "12 min ago", "3 h ago", then "Yesterday"/"Mon"/"Nov 14").
  The source falls back to the type name ("Receipt") when the model reported none. The VoiceOver name is the spec's
  "Tweet semiconductor flashcards, x.com, today 4:24 PM" (`TimeLabel.spoken`).
- 2026-11-21 (`f713f00`): the batch toast's "View in Search" shows that batch: "This batch · 37 screenshots", newest
  first, all of its files (up to 1000). Any edit of the text or chip leaves the batch and searches the whole index.
  Esc in the batch view closes. Hiding the window ends it. Files moved or undone since are no longer in the batch
  (their paths changed).
- 2026-11-21 (`f713f00`): Space vs typing. The field keeps focus (spec), so Space opens Quick Look only when the field
  is empty or the user just moved the selection (↑/↓ or a click). Otherwise it types a space; typing switches back.
  ⌘Y (the Finder shortcut) always toggles Quick Look.
- 2026-11-21 (`f713f00`): index errors are a real state, never the empty state. `UserFacingError` maps SQLite result
  codes ("the index file is damaged", "the disk is full", "the index is busy…"), never SQLite's own message (it can
  hold SQL or a path). The menu's "Could not open the index: …" uses the same text.

### App
- 2026-11-21 (`590d438`): `SearchPanel` is now borderless (no traffic lights) + non-activating, 880×540, radius 16,
  `.popover` material through `MaterialContainerView` (extracted from the toast's container). Not resizable, not
  movable by its background (a drag on a result drags the file).
- 2026-11-21 (`590d438`): placement. Horizontally centered on the screen under the pointer, with the panel's center
  one third down from the top of the visible frame, moved only as far as needed to stay on screen
  (`SearchPlacement`). "Upper third" cannot hold a 540 pt panel on most screens, so the center sits on that line.
- 2026-11-21 (`590d438`): the list is a `ScrollView` + `LazyVStack` with our own selection, not `List(selection:)`.
  A List draws the system accent selection, and clicking it moves the keyboard focus out of the field; the spec wants
  the indigo tint (14% / 34%) and ↑/↓ with the focus in the field. `scrollTo` without an anchor keeps the selection
  visible. Rows expose `.isSelected`, a select default action and an "Open" action to VoiceOver.
- 2026-11-21 (`590d438`): Quick Look is `QLPreviewPanel`, ordered front without taking the keyboard, one level above
  the floating panel. The search panel is its controller (informal protocol overrides on `SearchPanel`, `nonisolated`
  + `MainActor.assumeIsolated` because the category is not main-actor annotated). If the user clicks into Quick Look,
  that is not a focus loss: focus loss is checked on the next run-loop turn and ignores a key `QLPreviewPanel`.
- 2026-11-21 (`590d438`): keys. ⌘C copies the image unless the field has selected text (then the text is copied).
  Return and Space go to a focused button instead when Full Keyboard Access has moved focus out of the field. ⌘R
  reveal stays as an unlisted shortcut. The footer shows exactly the spec's five hints. The IME guard (`sendEvent`)
  also covers Space.
- 2026-11-21 (`590d438`): drag. A row or the preview image gives `NSItemProvider(contentsOf:)` for the file (Finder
  copies it, Mail attaches it).
- 2026-11-21 (`590d438`): Copy also posts a VoiceOver announcement "Copied"; the pill itself is hidden from
  accessibility. "Process Existing Screenshots…" in the empty state hides the panel and starts the scan (the batch
  toast reports progress).
- 2026-11-21 (`590d438`): when the index failed to open at launch, the search function throws `IndexUnavailableError`
  with the coordinator's `indexProblem`, and the window shows "The screenshot index could not be opened".

### Review fixes (review of `685c06c`, commit `544e24a`)
- 2026-11-21: ⌘ keys moved to `SearchPanel.performKeyEquivalent` (`commandKeyHandler`). AppKit routes ⌘ keys through key
  equivalents and the main menu (SwiftUI's Edit > Copy owns ⌘C), so the `sendEvent` key-down path could miss them.
  `sendEvent` now handles only unmodified keys (↑/↓/Return/Esc/Space). The IME guard is on both paths. A ⌘ shortcut
  matches the typed character when it is an ASCII letter or digit (QWERTY, Dvorak), else the physical key (Cyrillic
  and Greek layouts, AZERTY "&" for 1). ⌘C still copies text when the field has a selection.
- 2026-11-21: ⌘1…⌘7 select the chips (All…Design); the chip tooltips show the shortcut (core `SearchChip.help`).
- 2026-11-21: focus after Quick Look. A click into Quick Look's panel activates Shotkeeper.
  - `show()` remembers the front app, and hiding the window re-activates it when Shotkeeper is active.
  - The app delegate also answers Quick Look's controller lookup while the search panel is visible. When Quick Look
    is key, the search panel (never main) is not in the chain Quick Look searches.
  - Quick Look is shown with `orderFrontRegardless()`.
- 2026-11-21: Copy Image writes ONE pasteboard item with `.png` and `.fileURL`. A PNG file goes in as its own bytes;
  JPEG/HEIC/TIFF screenshots are converted to PNG. Before, the image was an NSImage (TIFF) plus a URL as two items.
- 2026-11-21: drag is an AppKit drag source (`FileDragArea`/`FileDragView`) over the row and the preview image.
  - It writes `public.file-url` (an `NSURL` writer) and offers only `.copy`, ignoring modifier keys, so Finder never
    moves the user's file (CODING_STANDARDS #1).
  - It replaces SwiftUI `NSItemProvider(contentsOf:)`, which becomes a file promise that Slack desktop and Chrome often
    refuse.
  - The same view handles clicks: select on the first mouse-down (no double-click delay) and open on the second.
    This replaces the SwiftUI tap gestures that the review's nit was about.
- 2026-11-21: Open, Copy and Reveal check that the file still exists. A file moved or deleted after indexing shows
  "This file is no longer there. It was moved or deleted after it was indexed." on the image for 3 s (VoiceOver
  announces it). A failed copy says "The image could not be copied.". The panel stays open.
- 2026-11-21: hiding a batch view searches again at once, so its rows are not what the next open shows first. The
  scroll-into-view follows the selected row's id. The preview title is no longer selectable (text selection took the
  keyboard focus from the field).
- 2026-11-21 (`f713f00`, deviation): with only a chip set, no match reads "No Tweet screenshots" / "Choose All to see
  every screenshot." The spec's "No screenshots match “<query>”" needs typed text; a chip alone has none.

### What CI cannot check (Parag, on a real Mac)
- ⌘C copies the image (paste into Preview or Slack), and copies the text when field text is selected. Same for ⌘R and
  ⌘Y, also on a Russian layout.
- ⌘1…⌘7 switch the chips.
- After clicking into Quick Look and closing search, the app that was in front gets the keyboard back.
- Dragging a row or the preview into Slack desktop and Chrome attaches the file. Into Finder it copies, never moves,
  even with ⌘ held.
- Focus: the panel takes the keyboard without activating Shotkeeper, and clicking another app hides it.
- Quick Look:
  - Space/⌘Y open it above the panel.
  - ↑/↓ update it.
  - Space/Esc close it.
  - Clicking into it does not hide search.
- Dragging a row or the preview into Finder/Mail.
- ⌘C pastes the image into Preview/Slack.
- Japanese/Chinese input with Return/Space.
- Multi-screen placement.
- VoiceOver reading rows, chips (selected state) and buttons.
- The material look (snapshots draw an opaque background).

## PR 3: first-run setup (branch `t3/ui-pr3-setup`)

Core: `6afa5aa` (`Sources/ShotkeeperCore/Setup/`, `Brand/IconGeometry.swift`). App, gate wiring and snapshots: `65add2b`.

### Core rules (Linux-tested, `SetupTests.swift`)
- 2026-11-21 (`6afa5aa`): `SetupFlow` is the step machine. Back on steps 2–4 only. Primary button per step:
  "Get Started"; "I Agree" (disabled until the box is ticked); step 3 "Continue" once the selected card's input is
  complete, else "Skip" (the spec names no step-3 button; "Skip" is the user's "Skip on step 3"); step 4 "Skip"
  while waiting or after a problem, "Continue" after a result or when no model is connected; "Finish".
  Step 3 is complete for Clairic with an account ID and a token (typed now or already in the Keychain), for local
  once the install was started (it finishes in the background).
- 2026-11-21 (`6afa5aa`): consent gate = core `BackendGate`. Clairic and custom endpoints need account/token or
  URL/model AND `hasSeenPrivacyNotice`; local needs nothing (nothing leaves the Mac). A custom endpoint on 127.0.0.1
  still needs consent (the app cannot tell where a URL ends up). `AnalyzerFactory` now asks the gate instead of
  repeating the checks. The flag keeps its name (no migration, so existing consents stay valid); it now means
  "accepted", and only step 2's "I Agree" sets it. Before, the old single-page setup set it on "Use …" for any
  backend, including local. *Superseded by the review fixes below (`4472f0b`): consent is per destination.*
- 2026-11-21 (`6afa5aa`): the Clairic card's cost is computed, not copied: `ClairicPricing` = the measured
  8,242 tokens for a 1280×800 screenshot ([clairic-field-schema](clairic-field-schema.md)) × $0.24/M (standard
  price after the promo ends 2026-12-01) = $1.98 → **"About $2 for 1,000 screenshots"**. Deviation: the spec's
  mockup says "$1"; the task said to compute it from the measured cost. It follows `maxImageLongSide`.
- 2026-11-21 (`6afa5aa`): `SetupCards` words the two cards from `BackendRecommender` (recommendation by RAM as
  before) and `ModelCatalog` (disk "about N GB" = download size rounded). 16–23 GB: Clairic [Recommended]
  "Best for this Mac (16 GB)…", local [Experimental] "Private, but slow and lower quality on 16 GB…". ≥ 24 GB: local
  [Recommended] (+ [Experimental] while the build is not verified with mlx-lm), Clairic "Fast, nothing to download…".
  Below 16 GB the local card is shown disabled with "Needs a Mac with at least 16 GB of memory. This Mac has 8 GB."
  A custom endpoint has no card; it stays in Settings → Model.
- 2026-11-21 (`6afa5aa`): `TryIt` maps the coordinator's pipeline events (the same `ScreenshotEvent`s the toast
  gets) to step 4: a processed file → result card (tags from the index row; a kept name shows "kept its name"
  instead of a struck-through old name); a failed file, an excluded or a paused one → a readable problem while it
  keeps waiting; missing/already indexed/restored files change nothing. A shown result stays.
- 2026-11-21 (`6afa5aa`): `ConnectionTestText` maps Test Connection errors to sentences ("Cloudflare did not accept
  the token. Check the account ID, and that the token has Workers AI Read and Edit permissions.", "Could not reach
  Cloudflare…", HTTP 404 → "could not find this account"). Server messages never reach the text. Settings' test
  buttons use it too.
- 2026-11-21 (`6afa5aa`): `IconGeometry` holds the icon shape as unit-square numbers: squircle radius 22.5%, corner
  stroke 5.6%, sparkle 27% (spec), corner inset 22% and arm 16% (not in the spec; chosen to match the mockup's
  proportions). The menu bar glyph's PR 1 numbers moved into `IconGeometry.menuBarGlyph` unchanged. The icon fill is
  #5856D6 in both appearances (an app icon does not follow dark mode). PR 4 should export the SVG and the asset
  catalog from this type.

### App
- 2026-11-21 (`65add2b`): **watching waits for a usable backend.** The coordinator starts the folder watcher (and
  re-queues `pending` rows) only when `BackendGate` says ready, re-checked after every settings or secret change.
  Before, the watcher ran from launch and screenshots taken before setup waited in a held queue, to be uploaded
  once credentials appeared. (Review fix `4472f0b`: a watcher started for Local still saw screenshots while the
  user switched to Clairic before consenting; those are now skipped, see below.) Once started it keeps running for the session, so a token removed later still shows
  "Needs attention" and the error toast. "Process Existing Screenshots…" also refuses before setup ("Finish setup
  first: …"). While not watching, the menu shows an orange "Not watching yet" + the reason, and "Finish Setup…"
  (also after consent when step 3 was skipped).
- 2026-11-21 (`65add2b`): setup is `SetupView` + `SetupModel` over `SetupServices` (closures; `live` wires the
  coordinator, snapshots pass fixed values). A fixed 720×520 window titled "Set Up Shotkeeper", opened at first
  launch while `hasSeenPrivacyNotice` is false (as before), from the menu's "Finish Setup…" and from Settings →
  General "Run setup again…" (moved there from the Model tab). Every open starts at step 1; a re-run pre-ticks
  step 2's box, preselects the configured card and shows the current login-item setting.
- 2026-11-21 (`65add2b`): the token is held only in the window's `tokenDraft` and goes to the Keychain on step 3's
  Continue (`AppCoordinator.saveClairicSetup`); the draft is then cleared. Test Connection sends the typed account
  ID and token with the generated test image only and stores nothing.
- 2026-11-21 (`65add2b`): step 4 listens through `AppCoordinator.addEventObserver` (called from `handle(_:)`, next to
  the toast), registered while the window is open. The rename toast still shows too. When step 3 was skipped (no
  usable backend), step 4 shows "No model connected" with "Go Back to connect one, or do it later in Settings →
  Model." and the primary button reads "Continue". With the local model downloading, the waiting zone shows the
  download progress. The dashed zone is not a drop target: the spec only describes its look, and the result must
  come from a real new screenshot.
- 2026-11-21 (`65add2b`): keys. Return = primary (when enabled), Esc = Back on steps 2–4 (deviation: steps 1 and 5
  have no Esc action; the window's close button closes). The cards are `Button`s with `.isSelected`; ←/→/↑/↓ switch
  the card that has focus. As in every Mac app, Tab reaches buttons, checkboxes and the cards only with System
  Settings → Keyboard → "Keyboard navigation" on; text fields are always in the Tab loop.
- 2026-11-21 (`65add2b`): "Change Shortcut…" opens Settings → General (where PR 4's recorder goes), which now shows a
  read-only "Search shortcut ⌥⌘S" row. `SettingsNavigation` switches the tab even when Settings is already open.
- 2026-11-21 (`65add2b`): "Open Shotkeeper when I log in" is applied on Finish through `updateSettings`, which calls
  `LaunchAtLogin` (SMAppService). It is on for a first run. A failure (app not in /Applications) shows as the menu
  message, not in the closed window.
- 2026-11-21 (`65add2b`): `AppIconView` (72 pt in step 1) and `MenuBarGlyphView` (step 5) are SwiftUI shapes over
  `IconGeometry`; `MenuBarGlyph` (the status item's template image) draws the same geometry with AppKit.
- 2026-11-21 (`65add2b`): text colours added for 4.5:1: error text light #C4281C / dark #FF7B72 (systemRed is 3.6:1
  on white), warning text (Experimental badge, local note) light #8A4600 / dark #FFB340.

### Review fixes (review of `80113d7`, commit `4472f0b`)
- 2026-11-21: **consent per destination.** New key `acceptedUploadDestinations` (`cloudflare`, `customEndpoint`) +
  `acceptedCustomEndpointHost`. `BackendGate` checks the selected backend's destination; a custom endpoint only for
  the allowed host (another host is asked again; the port does not matter). Step 2's "I Agree" grants `.cloudflare`
  only (its text names Cloudflare) and still sets `hasSeenPrivacyNotice`, which now only means "setup's privacy step
  was done" (setup opens at launch while false; the menu shows "Finish Setup…").
- 2026-11-21: **upgrade.** A settings file without the new key is migrated once at load: the old flag counts only
  for the destination of the backend stored with it (Clairic → `.cloudflare`; custom → `.customEndpoint` for the
  stored URL's host; Local → nothing, because the old setup set the flag for Local too). Once the key exists it is
  never re-seeded. Test: `SettingsTests.testUpgradeSeedsConsentOnlyForTheStoredBackend`.
- 2026-11-21: **skip, don't hold.** Without consent for the destination, `ScreenshotProcessor` returns
  `.skipped(.awaitingConsent)` (like Pause: not indexed, file untouched) before reading the file. Before, the
  analyzer threw `.notConfigured`, the queue held the file, and "I Agree" resumed the queue and uploaded a screenshot
  taken before the consent (path: Local first so watching started, then Clairic). While watching with consent
  missing, the menu says "Skipping new screenshots: sending them is not allowed yet" + "Finish Setup…".
  A skipped file can still be processed later by an explicit "Process Existing Screenshots…" after consent.
- 2026-11-21: **Settings → Model confirmation.** While the selected backend's destination is not allowed, Model shows
  "Screenshots will be sent to gpu-box.lan. Nothing is sent until you allow it." + "Allow…", which opens a
  confirmation naming the destination (core `BackendGate.consentPrompt`). It opens by itself when the backend is
  switched; while a URL is typed only the row updates (no dialog per keystroke). Clairic can be allowed there too
  (the dialog names "your Cloudflare account"), for users who chose Local in setup and switch later.
- 2026-11-21: **step 4 timing.** `SetupFlow.tryItOpenedAt` is set when step 4 opens; `TryIt.apply` ignores a
  processed file whose index `capturedAt` (or a failed file whose creation date) is more than 5 s
  (`TryIt.slack`) before it, so a backlog file finishing then is not shown as "your" screenshot. An unknown date
  is not a reason to hide a result or a problem.
- 2026-11-21: **Return on step 3.** "Skip" is a secondary button without the default action
  (`SetupPrimaryButton.isDefaultAction`); Return in a field moves to the next empty field (Account ID → token).
  Once the card is complete, "Continue" is the default again.
- 2026-11-21: **re-run with a custom endpoint**: a third card "Custom endpoint — Keeps using <host>" is shown and
  preselected, and Continue keeps it, so Return no longer switches the backend to Clairic.
- 2026-11-21: nits. The VoiceOver announcement goes to the setup window (after ⌘⇧4 another app is key), else the
  app. Each Test Connection run is tagged; editing the account ID or token drops the running result. The Keychain
  is read once per `credentialsRevision`, not per render. On a re-run the login checkbox shows the real login item
  (`SMAppService` status), and Finish applies it every time (`LaunchAtLogin.apply`, no-op when it already matches).
  Space ticks the checkboxes on steps 2 and 5 (`keyboardShortcut(.space, modifiers: [])`; those steps have no text
  field). The unavailable card's reason is primary text (secondary measured ~3.9:1 on the card in light mode).
- 2026-11-21: **restart during a local download.** The download runs in the app; quitting stops it. After a
  restart the model shows "Not installed" (no completion marker), screenshots are held with "Needs attention: …not
  installed", and Settings → Model → "Install and download" continues: `hf download` resumes the files already on
  disk ([app-implementation](app-implementation.md)). Setup does not reopen for it. No automatic resume yet.
- 2026-11-21 (deviation, narrowed): without "Keyboard navigation", "Change Shortcut…" on step 5 and the Settings
  "Allow…" button are reachable only with the mouse or VoiceOver; Return, Esc, Space (checkboxes) and the text
  fields work without it.

### What CI cannot check (Parag, on a real Mac)
- First launch opens setup; the window is 720×520, not resizable, comes to the front, and the app stays a menu-bar
  app (no Dock icon) while it is open.
- Return = primary, Esc = Back; Return in the token field continues. With "Keyboard navigation" on: Tab reaches the
  cards, checkboxes and buttons, Space selects a card, ←/→ switch cards; VoiceOver reads "selected" on the chosen card,
  "Setup progress, Step 3 of 5" on the dots.
- Test Connection with a real account ID and token (success line), with a wrong token (red text).
- Continue: the token is in the Keychain (Keychain Access, service `dev.shotkeeper.Shotkeeper`), then a ⌘⇧4
  screenshot shows the result card in step 4 (and the toast). Before setup is done, a screenshot is not renamed
  and the menu says "Not watching yet".
- Local on a 16 GB Mac: Install and Download, progress, Cancel; Continue while it downloads; step 4's download line.
- "Change Shortcut…" brings Settings → General to the front over setup; "Run setup again…" there opens step 1.
- "Open Shotkeeper when I log in": with the app in /Applications, it appears in System Settings → General → Login Items.
- The 72 pt icon and the menu bar glyph in step 5 look sharp on a Retina screen.
- (review fixes) Step 3 with an empty token: Return in Account ID moves to the token field and does not skip.
  Space ticks the step 2 and step 5 checkboxes with "Keyboard navigation" off.
- (review fixes) Settings → Model → Custom with a URL: the "Screenshots will be sent to <host>" dialog appears;
  nothing is renamed before "Allow"; changing the host asks again.
- (review fixes) Pick Local in setup, then Clairic in Settings without allowing it: a new screenshot keeps its
  name, the menu says "Skipping new screenshots…", and allowing it later does not rename the earlier one.
- (review fixes) Upgrade from a build with the old setup: a Clairic user keeps working without being asked again;
  a Local user who switches to Clairic is asked.
- (review fixes) A VoiceOver announcement "It works…" when the step 4 result appears while another app is in front.

### Snapshot review
- 2026-11-21: run 44945029445 (21 setup/icon images × light/dark) matched the spec except the 8 GB state: the
  unavailable local card was a disabled button, and its reason text was dimmed twice to unreadable. It is now a
  plain view with secondary text; VoiceOver reads "…, not available on this Mac. Needs a Mac with at least 16 GB…".
  The `menu-setup-unfinished` fixture now shows the "Not watching yet" header the real menu shows.
