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

### What CI cannot check (Parag, on a real Mac)
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
