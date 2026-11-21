# UI/UX polish spec (approved by Parag, 2026-11-21)

Source: Parag's approved mockups, relayed by the orchestrator on 2026-11-21. Copied verbatim; do not edit the
requirements. Add dated implementation notes to `docs/wiki/ui-polish.md`, not here.

Keep the Clairic cost settings exactly as they are (7 fields, 1280 px); Parag decided that.

## Process
- Build in 4 PRs, in this order. Each PR: CI green (linux-core + macos-app) before the merge, use gh-shotkeeper, and merge pinned to the tested head.
  1. Rename toast + menu bar menu
  2. Search window
  3. First-run setup (onboarding)
  4. Settings + accessibility + app icon + filename-style and hotkey settings
- If Parag reports real-use bugs from his Mac while you work, they come first.
- Keep the core portable. New logic goes into the core with tests where it can (for example: filename style, recent-items list, toast batching rules, undo label text).
- After each PR: a short report. It must say what Parag must check on his real Mac, because CI cannot check visual behavior.
- An independent review sub-agent checks PR 2 and PR 3 against this spec and CODING_STANDARDS.md before the merge.

## Global style
- Brand accent: indigo. Light #5856D6, dark #5E5CE6 (systemIndigo). Indigo text on light backgrounds: #4644C0. Normal controls use the system accent color. Indigo is only for the brand moments: icon, onboarding, toast label, selected chips, primary buttons in our own panels.
- System font (SF). Only semantic colors otherwise. Correct in light and dark mode.
- Accessibility (all PRs): an accessibilityLabel on every icon-only control and image, every control works with the keyboard, help tooltips on icon buttons, and VoiceOver names for rows ("Tweet semiconductor flashcards, x.com, today 4:24 PM"). Minimum text contrast 4.5:1.

## PR 1a: Rename toast (new; today there is no feedback)
- A non-activating floating panel at the BOTTOM-RIGHT of the screen where the screenshot was taken, 16 pt from the edges. Width 308 pt, corner radius 14, material background, a soft shadow. It does not take focus from the front app.
- Contents: a 52×52 thumbnail (radius 9); a small indigo label with a sparkle symbol, "Renamed"; the new name (14 pt semibold, up to 2 lines); "was: <old name without extension>" (11 pt secondary, 1 line); a close button (x, top-right, accessibility label "Close"); buttons "Undo" and "Edit name"; a thin 3 pt indigo countdown bar at the bottom.
- Timing: it closes after 4 s. The timer stops while the pointer is on the toast or while you edit. Show one toast at a time; a new screenshot replaces the old toast.
- Edit name: the name becomes a text field in the toast, with the full name selected. Enter saves (rename the file + update the index + an undo entry), esc cancels. The row shows "↩ Save · esc Cancel", "Cancel" and "Save" (primary). Use the same filename sanitizing and collision rules as the pipeline.
- Undo in the toast: restores the original name. The label changes to "Original name restored", and the subline says "Shotkeeper will not rename this file again". Add that rule to the core (a file restored by Undo is not processed again) if it is not there.
- Batch ("Process existing screenshots", or more than 3 files within 10 s): ONE summary toast: a stack of 3 small thumbnails, "Renamed 37 screenshots", "2 skipped by your exclude rules" (only when > 0), buttons "View in Search" (primary, opens search filtered to that batch or sorted by recent) and "Undo All".
- Errors: a toast with a warning symbol, for example "Could not rename: Cloudflare token is missing" + "Fix Settings…".
- Setting: "Show a toast after each rename" (on by default). Sound: off by default, with a switch "Play a sound after a rename".

## PR 1b: Menu bar menu
- Status at the top: a colored dot (green = watching, gray = paused, orange = offline/attention, red = error) + "Watching <folder name>"; second line, secondary: "Idle · 214 screenshots in the index" / "Processing: 3 left" / "Paused until 3:42 PM".
- Only while the local model downloads: "Downloading Inkling 2 Mini · 4.1 of 9.1 GB" + a progress bar.
- A "Recent" section header + the last 5 processed screenshots: a 22 pt thumbnail, title (truncated), time on the right ("4:24 PM", "Yesterday"). A click opens the file; ⌥-click reveals it in Finder.
- "Undo: <title>" ⌘Z. Disabled with the text "Undo" when there is nothing to undo.
- Show "Pause for 10 Minutes" only when not paused, and "Resume" only when paused. "Process Existing Screenshots…".
- "Search…" ⌥⌘S (show the current hotkey), "Settings…" ⌘,, "About Shotkeeper" (version), "Quit Shotkeeper" ⌘Q.
- Clear lastMessage after 30 s or after the next successful action. Do not show stale text.
- The menu bar icon: a template glyph of the new app icon (viewfinder corners + small sparkle). It changes state the way it does today, plus a short pulse after a rename.

## PR 2: Search window (non-activating floating panel, Raycast style)
- 880×540, radius 16, material, no traffic lights, centered in the upper third of the active screen. Hide on focus loss and on esc.
- Row 1 (60 pt): a magnifying glass, a 20 pt text field with the placeholder "Search screenshots by what is in them", and a clear button (x in a circle) when there is text.
- Row 2: type chips: All · Tweet · Article · Code · Chat · Receipt · Design. The selected chip is filled indigo with white text, the others have a light fill. They filter by content_type and combine with the text query.
- Body: a LEFT list of 330 pt and a RIGHT preview.
  - List row: a 44×44 thumbnail (radius 8, thin border), the title (13 pt semibold, 1 line), "<source> · <relative time>" (12 pt secondary). The selected row has an indigo tint background (14% light, 34% dark) and radius 10. The list scrolls and keeps the selection visible.
  - Preview: a large image (220 pt tall, radius 12, aspect fit, thin border); the title (18 pt semibold); the description (13 pt secondary); tag chips "#tag" (indigo text on a light indigo fill; a click puts the tag in the search field and resets the chip to All); a metadata grid: Source / Type / Taken / Folder; buttons "Open" (primary indigo), "Copy Image", "Reveal in Finder", "Quick Look".
  - ⌘C or Copy Image shows a "✓ Copied" pill on the image for 1.4 s.
  - Space opens QuickLook (QLPreviewPanel) for the selection. You can drag a result (the list row or the preview image) into other apps as a file.
- Footer (36 pt): left "Recent · 214 screenshots" or "6 of 214 screenshots"; right key hints with keycaps: ↑↓ Select, ↩ Open, Space Quick Look, ⌘C Copy, esc Close.
- Keys: ↑/↓ move the selection while the focus stays in the field; ↩ opens; esc clears the query first, then closes. Keep the IME composition guard.
- States: empty query = recent screenshots. No match = a centered icon, "No screenshots match “<query>”", "Try other words from the title, from the text in the image, or a tag.", and a "Clear search" button (clears the query and the chip). Empty index = an indigo viewfinder icon, "No screenshots yet", "Take a screenshot with ⌘⇧4. Shotkeeper gives it a name from its content, and it shows up here in a few seconds.", and a "Process Existing Screenshots…" button. If the index failed to open, show a real error state, not the empty state.
- Use native selection behavior where you can, but match the look above.

## PR 3: First-run setup (replaces the single page)
- A 720×520 window, title "Set Up Shotkeeper". Footer: 5 step dots (indigo up to the current step) + "Step N of 5" on the left; "Back" (steps 2–4) and a primary button on the right.
- Step 1 Welcome: the app icon (72 pt); "Shotkeeper names your screenshots for you"; "It reads each new screenshot, gives it a clear name, and makes it easy to find again."; a before→after card: struck-through "Screenshot 2026-11-21 at 16.24.11.png" → indigo semibold "Tweet semiconductor flashcards.png"; 3 columns: "Clear names" / "Search by memory" (Press ⌥⌘S…) / "Safe" (It never deletes a file. You can undo every rename.). Button: "Get Started".
- Step 2 Privacy: "Your screenshots go to your Cloudflare account" + 4 rows with symbols: sent to Cloudflare Workers AI with your own account and token; Shotkeeper has no server, the index stays on this Mac; use Pause or exclude rules for private screenshots; on 24 GB+ Macs a local model keeps everything on the Mac. A checkbox "I understand that my screenshots are sent to my Cloudflare account." The primary button "I Agree" stays disabled until the box is ticked. Consent is stored only after this step. (If the user picks Local in step 3, the consent is not needed for uploads; keep the consent gate logic correct.)
- Step 3 Connect a model: two selectable cards (real buttons, keyboard and VoiceOver work, aria-pressed equivalent): "Cloudflare Clairic" [Recommended] "Best for this Mac (16 GB). About $1 for 1,000 screenshots." (compute the number from RAM and the measured cost) and "Inkling 2 Mini, on this Mac" [Experimental] "Private, but slow and lower quality on 16 GB. Needs about 10 GB of disk." Recommend by RAM as today. Clairic: Account ID and API token fields (the token goes to the Keychain on Continue), the link "How do I get these?" (Cloudflare Workers AI REST API get-started page), "Test Connection" with "Sending a test image…" → "✓ Connected. The test image was analyzed." or a red, readable error. Local: an orange note and "Install and Download (about N GB)".
- Step 4 Try it now: "Take a screenshot of anything on your screen with ⌘⇧4. Shotkeeper shows you the result here." A dashed indigo drop zone with a spinner and "Waiting for a new screenshot…". When the REAL first screenshot is processed, show a result card: a large thumbnail, "✓ It works", the old name struck through, the new name (16 pt semibold), and the tag chips. The primary button shows "Skip" while waiting and "Continue" after.
- Step 5 Done: "You are all set"; a row with a ⌥⌘S keycap, "Search your screenshots from any app.", "Change Shortcut…"; a row with the menu bar glyph, "Find Shotkeeper in the menu bar: recent screenshots, Undo and Pause."; a checkbox "Open Shotkeeper when I log in" (on). Button: "Finish".
- "Run setup again…" in Settings opens this flow.

## PR 4: Settings, accessibility, icon, new settings
- A standard SwiftUI Settings scene with toolbar tabs: General · Model · Exclusions · About. Grouped Form on every tab (the same layout everywhere).
- General: folder rows with a Finder icon + name (NSPathControl or similar), "Choose…" and "Clear"; rename/move/tag switches; "Filename style": Sentence case (default, "Tweet semiconductor flashcards") / Title Case / kebab-case + a switch "Add the date at the start (2026-11-21 …)"; toast and sound switches; "Search shortcut": a shortcut recorder (default ⌥⌘S, detect conflicts, show an error if registration fails); launch at login; pause/resume.
- Model: a segmented picker with short names "Clairic" / "Local" / "Custom"; the token fields save on change (no separate Save button, but confirm before "Remove saved token"); test connection; the local model install with bytes, speed and ETA, "Remove model", and a disk-space check before the download.
- Exclusions: an empty state ("No rules yet. Screenshots that match a rule are never sent, renamed or indexed.") + "Add Rule"; accessibility labels on the remove buttons.
- About: icon, version, links to the README and the privacy text, "Open log folder".
- App icon: option A from the mockups. A macOS squircle (radius ≈ 22.5% of the size), solid #5856D6 with a very subtle lighter top half (6% white), 4 white rounded viewfinder corners (stroke ≈ 5.6% of the size, round caps), and a white 4-point sparkle in the center (≈ 27% of the size). Make it as vector source (SVG in the repo) + a generated AppIcon asset catalog with all sizes. The menu bar glyph is the same shape as a template image (outline corners + filled sparkle).
- Hide every menu item and button that does not apply. No raw `String(describing: error)` text in the UI; map errors to short readable messages.
