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
