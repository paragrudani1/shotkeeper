# Design: search filters and Copy Text (wave 1, 2026-11-28)

Design pass for [../specs/search-filters-and-text-2026-11.md](../specs/search-filters-and-text-2026-11.md) (the
"wave 1 spec"), made with the frontend-design skill as adapted in [../wiki/workflow.md](../wiki/workflow.md), "UI
design step". The visual identity is fixed by [../specs/ui-polish-2026-11.md](../specs/ui-polish-2026-11.md) (the
"polish spec"): SF system font, semantic colours, indigo only for brand moments. This note decides layout, hierarchy,
copy, states and keys inside that identity.

- Mockup for review: [search-filters-and-text-mockup.html](search-filters-and-text-mockup.html) (static, light and
  dark). CI snapshot PNGs of the real SwiftUI view stay the acceptance check.
- Baseline: CI snapshots from run 45052894155 (main, `search-*-light/dark.png`) and
  `App/Shotkeeper/UI/SearchView.swift` as of `b15d96e`.
- Changes against the polish spec are marked **[Δ polish]**. Changes against the wave 1 spec are marked
  **[Δ wave 1]**. Everything is collected again in the last section.

## 1. Brief, as I read it

- **Subject:** a Spotlight-style panel that finds one screenshot among hundreds, used many times a day, mostly from
  the keyboard, for a few seconds at a time.
- **Audience:** one person (Parag) who knows the panel. ⌥⌘S, type, ↑↓, ↩ is muscle memory.
- **Primary job:** get from "I remember roughly when and where" to the right screenshot, then to its picture or its
  words, without the mouse.
- **What must not change:** the default panel. With no filter set it must look and behave as it does today (wave 1
  spec, "Default"). New controls must be quiet until used.

## 2. Plan

### Tokens (inherited, nothing new)

| Role | Light | Dark | Source |
|---|---|---|---|
| Brand fill (selected chip, active filter, primary button) | #5856D6 | #5E5CE6 | polish spec |
| Brand text (check marks, tag text) | #4644C0 | #A5A4FF | `Brand.indigoText` |
| Selection tint (list rows, picker rows) | indigo 14% | indigo 34% | polish spec |
| Neutral fill (unselected chip, inactive filter, keycap) | label 7% | label 7% | `SearchChipStyle` |
| Secondary text | label 72% | label 72% | `Brand.secondaryText` |
| Overlay pill and badge | black 72%, white text | same | "✓ Copied" pill |

- **Type:** SF only. The existing scale is kept: 20 (field), 18 semibold (preview title), 16 semibold (message
  title), 13 (body, picker rows), 12 (chips, filters, subtitles), 11 (keycaps, metadata labels). No new size.
- **Radii follow the nesting:** panel 16 → preview image 12 → picker 10 → rows 10 (list) and 6 (picker) → capsules
  for chips, filters, pills and the badge.

### Layout alternatives

The panel has two places to grow: row 2 (the chip row, which has about 450 pt free on its right) and the preview.
Four ways to fit the date and source filters:

**A. Filter pills at the end of the chip row (chosen)**

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 🔍  invoice                                                              ⊗    │
│ (All)(Tweet)(Article)(Code)(Chat)[Receipt](Design)     [📅 Last 30 days ✕][▭ Stripe ✕] │
├─────────────────────────┬────────────────────────────────────────────────────┤
│ ▣ Invoice from Stripe…  │ ┌────────────────────────────────────────────────┐ │
│ ▣ Stripe payout Oct     │ │                                                │ │
│                         │ │                                 [⌗ Copy Text ⇧⌘C]│ │
│                         │ └────────────────────────────────────────────────┘ │
│                         │ Invoice from Stripe for October                    │
│                         │ [Open] [Copy Image] [Reveal in Finder] [Quick Look]│
├─────────────────────────┴────────────────────────────────────────────────────┤
│ 2 of 214 screenshots                     ↑↓ Select  ↩ Open  Space  ⌘C  esc   │
└──────────────────────────────────────────────────────────────────────────────┘
```

**B. Tokens inside the search field** (Mail and Finder style)

```
│ 🔍  invoice  [Stripe ✕] [Last 30 days ✕]                                  ⊗    │
│ (All)(Tweet)(Article)(Code)(Chat)[Receipt](Design)                             │
```

**C. A filter bar as a third row**

```
│ 🔍  invoice                                                              ⊗    │
│ (All)(Tweet)(Article)(Code)(Chat)[Receipt](Design)                             │
│ Date: [Last 30 days ⌄]   Source: [Stripe ⌄]                                    │
├──────────────────────────────────────────────────────────────────────────────┤
```

**D. Filters in the footer, next to the count**

```
├──────────────────────────────────────────────────────────────────────────────┤
│ 2 of 214  [Last 30 days ⌄] [Stripe ⌄]             ↑↓ Select  ↩ Open  …  esc   │
```

**Why A:**

- All three filters (type, date, source) live in one row, so "which filters are on" is answered by one glance at one
  line (story 14). The rule is simple: what is indigo in row 2 is narrowing the results.
- It costs no height. The preview's height budget is already tight (wiki ui-polish, PR 2: the grid was clipped once).
- It leaves row 1 to the typed words. B makes long queries collide with tokens and needs token editing inside a plain
  SwiftUI `TextField`, which SwiftUI does not offer there. B also invites parsing typed words into filters, which the
  spec does not ask for.
- C adds 32 pt of chrome that is visible even when no filter is used, which breaks "the panel looks exactly as today".
- D puts controls in the strip that is for status and key hints, as far from the field as possible.

**How the pickers open.** Two options for the list a pill opens:

- **A1. A native pop-up menu** (`NSMenu`). Native, but it cannot hold a type-to-narrow field for many sources, it
  can't show a custom date range, and a menu's tracking loop in a non-activating panel is a real-Mac risk.
- **A2. An in-panel picker (chosen).** A small list drawn inside the search panel itself (a SwiftUI overlay, not a
  popover and not a second window), anchored under its pill. It never takes key-window status, so the panel keeps the
  keyboard (wave 1 spec: "pop-up lists in a non-activating panel must not take key status from the field"). It can hold
  a narrow field and the custom range.

### The one bold choice: the Copy Text badge on the image

Copy Text is not another button in the row under the preview. It is a small dark capsule in the bottom-right corner
of the preview image, in the place where macOS puts the Live Text button on images in Preview, Safari and Photos:

```
┌────────────────────────────────────────────────────────┐
│                                                        │
│                     (screenshot)                       │
│                                                        │
│                                 ┌────────────────────┐ │
│                                 │ ⌗  Copy Text  ⇧⌘C  │ │
│                                 └────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

Why this is worth the boldness:

- **The text belongs to the image.** The badge sits where the words are, and it reads as "Shotkeeper has read this
  picture". It is the only place in the panel that shows the new capability.
- **It carries every text state** in the same spot: ready, reading (spinner), could not be read. "No text" hides it
  (polish spec PR 4: "hide every button that does not apply"). The result pills ("✓ Text copied") appear on the same
  image, so the action and its feedback are in one place.
- **It shows ⇧⌘C.** The footer keeps its five approved hints (wave 1 spec), so the badge is the one place where the
  shortcut is visible, not only in a tooltip.
- **The button row stays at four.** A fifth button needs about 500 of the 517 pt available, with no room left.
- It uses the panel's existing overlay language (the "✓ Copied" capsule: black 72%, white 12–13 pt semibold), so it
  is bold in placement, not in colour. No new colour, no indigo.

Everything else stays quiet: the filter pills reuse the chip style, the pickers look like native menus, and the
no-match and empty states reuse `SearchMessageView`.

### Review against the brief (what I changed after the first draft)

- **Draft:** a fifth "Copy Text" button in the button row, plus a "Text" column in the metadata grid showing the
  status. **Changed:** two elements for one job, the row overflows, and the status would be shown far from the action.
  Replaced by the badge.
- **Draft:** a "Found in the text: …order #A-20417…" match snippet in the preview when only the OCR text matched.
  **Cut** (optional in the spec): it costs a line in the tightest part of the panel, and needs new core work
  (`snippet()` plus a which-column-matched check). Chanel's rule: this was the accessory to take off.
- **Draft:** inactive pills reading "Any date" and "Any source". **Changed** to "Date" and "Source": the pill names
  the filter when it's off and shows the value when it's on. VoiceOver still hears "any time" as the value.
- **Draft:** a hairline divider between the chips and the filter pills. **Cut:** the space between them already
  separates them, and the skill says structure must carry information. A rule here adds nothing.
- **Checked against the skill's list of defaults:** no all-caps labels, no eyebrows, no "→" in labels, no monospace
  data labels, no uniform cards. The `·` in "Recent · 214 screenshots" is existing approved copy and is kept. New copy
  doesn't add any.

## 3. Hierarchy

1. **The typed words** (row 1, 20 pt). Unchanged.
2. **The results and the selected screenshot** (list and preview image). Unchanged.
3. **Active filters**: indigo pills in row 2, the same weight as the selected chip. Seen at a glance, never louder
   than the results.
4. **The Copy Text badge** on the image: the one new element with presence.
5. **Inactive filter pills**, the footer count and key hints: quiet, neutral fill and secondary text.

## 4. Layout details

### Row 2

- Type chips stay on the left exactly as today. A flexible space follows, then the **Date** pill, 6 pt, then the
  **Source** pill, right-aligned to the 16 pt panel inset (in line with the clear button above).
- **Pill, inactive:** the chip style (24 pt capsule, label 7% fill, 12 pt medium, primary text), a leading symbol
  (`calendar`; `macwindow` for source) in secondary, the name ("Date", "Source") and a trailing `chevron.down`
  (8 pt, secondary).
- **Pill, active:** the selected-chip style (indigo fill, white 12 pt semibold, white symbol), the value ("Last 30 days",
  "Stripe") and a trailing `xmark` (9 pt bold, white 85%) in a 16 pt circular hit area that clears only that filter.
  The rest of the pill opens the picker.
- **Pill, open:** the pill keeps its look and gains a 2 pt focus ring in the system accent (the native focus ring),
  so it's clear which pill the picker belongs to.
- **Pill, disabled** (source only): 40% opacity, no chevron, tooltip says why.
- **Long values:** the Source pill is at most 180 pt wide and truncates its value at the tail ("Microsoft Remote
  Desk…"). The full name is in the tooltip and the VoiceOver value. Worst case for the whole row: chips 400 + date
  130 + source 180 + gaps ≈ 720 of 848 pt.

### Picker (in-panel)

- Drawn inside the panel over the list and preview, right edge aligned with its pill's right edge, 6 pt under row 2.
  Menu material (`.menu`), radius 10, the system menu shadow, 0.5 pt border at label 12%.
- Rows 28 pt, 13 pt text, 6 pt radius highlight in the selection tint (indigo 14% / 34%), matching the result list
  rather than the system blue, so both lists in the panel look the same. The current value has a `checkmark` in brand
  text colour on the left.
- The picker closes on a choice, on Esc, on a click outside it, and when the panel hides.

**Date picker** (240 pt wide)

```
┌──────────────────────────────┐
│ ✓ Any time                   │
│   Today                      │
│   Yesterday                  │
│   Last 7 days                │
│   Last 30 days               │
│ ──────────────────────────── │
│   Custom range…              │
└──────────────────────────────┘
```

Choosing "Custom range…" expands the picker in place (no second window):

```
┌──────────────────────────────┐
│   …                          │
│ ──────────────────────────── │
│ ✓ Custom range               │
│   From  [ Nov 14, 2026 ⌃⌄ ]  │
│   To    [ Nov 28, 2026 ⌃⌄ ]  │
│                     [Apply]  │
└──────────────────────────────┘
```

- The fields are native `DatePicker(.field)` (`NSDatePicker` text field with stepper): type digits, ↑↓ change the
  focused part, Tab moves on. They start at the current custom range, else at "Last 7 days" (6 days ago to today).
- "Apply" uses the brand primary style (primary button in our own panel). A reversed range is swapped by core.
- Date options show no counts: the spec doesn't ask for them, and they'd cost five count queries per open.

**Source picker** (280 pt wide)

```
┌──────────────────────────────────┐
│ 🔍 Filter sources                │
│ ──────────────────────────────── │
│ ✓ Any source                     │
│   Slack                       64 │
│   X                           41 │
│   GitHub                      27 │
│   Mail                        18 │
│   Xcode                       12 │
│   Microsoft Remote Desktop     9 │
│   console.cloud.google.com     4 │
│   Figma                        3 │  ← 8 rows visible, then it scrolls
└──────────────────────────────────┘
```

- A narrow field on top (13 pt, placeholder "Filter sources"). Typing narrows by a folded substring match on the
  display name (case and diacritics folded, like `SourceKey`). The first match is highlighted, so "sl ↩" picks Slack.
- Counts are right-aligned in secondary text with tabular figures. They cover the whole index (wave 1 spec).
- Names truncate at the tail on one line. The full name is in the row's tooltip.
- A chosen source that no longer exists stays pinned under "Any source" with the count 0, checked.

### Preview: the Copy Text badge

- Bottom-right of the 220 pt image frame (the frame, not the letterboxed picture), inset 10 pt. Capsule, 26 pt tall,
  black 72%, white 12 pt semibold label, a leading symbol and a trailing keycap "⇧⌘C" in white 60% at 11 pt.
- It sits above `FileDragArea`: a click on it never starts a drag and never counts as a double-click on the image.
- The existing centered pills ("✓ Copied", file missing) keep their place. The text pills use the same place.

## 5. Copy

New strings use sentence case. One exception, flagged: **"Copy Text"** keeps title case to match its neighbour "Copy
Image" and the name used in the wave 1 spec. Menu items stay in title case like every other item in that menu
(polish spec PR 1b). **[Δ wave 1: casing only, the spec's name is kept]**

### Filter pills

| Element | Visible text | Tooltip | VoiceOver label, value |
|---|---|---|---|
| Date pill, off | Date | Filter by the day it was taken (⌘D) | "Date", "any time" |
| Date pill, on | Today · Yesterday · Last 7 days · Last 30 days · Oct 3 – 17 · Oct 3 | Change the date (⌘D) | "Date", "last 7 days" |
| Clear date | (✕) | Clear the date | "Clear date" |
| Source pill, off | Source | Filter by app or site (⌘S) | "Source", "any source" |
| Source pill, on | Stripe | Stripe. Change the source (⌘S) | "Source", "Stripe" |
| Clear source | (✕) | Clear the source | "Clear source" |
| Source pill, disabled | Source | No screenshot has an app or site yet. | "Source, dimmed", "No screenshot has an app or site yet." |

- The `·` in the table only separates alternatives here; it is not UI text.
- Custom range labels use `DateIntervalFormatter` (date only, medium) and drop the year when both days are in the
  current year: "Oct 3 – 17", "Oct 28 – Nov 3", "Dec 28, 2025 – Jan 4, 2026". One day reads "Oct 3".
- Announcements: choosing a value announces nothing extra (VoiceOver reads the pill's new value). Clearing one
  announces "Date cleared" / "Source cleared". Esc or "Clear search" announces "Search cleared". "Clear filters"
  announces "Filters cleared".

### Pickers

| Element | Text |
|---|---|
| Date rows | Any time · Today · Yesterday · Last 7 days · Last 30 days · Custom range… |
| Custom range fields | From · To |
| Custom range button | Apply (tooltip "Show screenshots from these days (↩)") |
| Source field placeholder | Filter sources |
| Source rows | Any source · then each source name, count right-aligned |
| Source row, VoiceOver | "Slack, 64 screenshots" (+ selected trait on the current one) |
| Narrowing finds nothing | No source matches “zz” |
| Picker, VoiceOver container | "Date" / "Source" |

### Footer

Unchanged: "Recent · 214 screenshots", "6 of 214 screenshots", "This batch · 37 screenshots", and the five key hints.
Any active date or source counts as a filter, so the footer reads "N of M screenshots" (wave 1 spec).

### No-match states

Core builds these (`SearchWindowState.noMatchMessage`). The phrase parts are: an optional type ("Receipt
screenshots"), an optional source ("from Stripe"), an optional date ("taken today", "taken yesterday", "taken in the
last 7 days", "taken in the last 30 days", "taken on Oct 3", "taken between Oct 3 and Oct 17").

| Situation | Title | Message | Buttons |
|---|---|---|---|
| Text, no filters | No screenshots match “zebra crossing” | Try other words from the title, from the text in the image, or a tag. | Clear search |
| Chip only, no text | No Tweet screenshots | Choose All to see every screenshot. | Clear search |
| Date and/or source (chip optional), no text | No screenshots from Slack taken in the last 7 days | Clear filters to see every screenshot. | Clear filters |
| … with a chip | No Receipt screenshots from Stripe taken in the last 30 days | Clear filters to see every screenshot. | Clear filters |
| Text and any filter | No screenshots match “invoice” | Your filters limit this search to Receipt screenshots from Stripe taken in the last 30 days. | Clear filters · Clear search |
| Chosen source no longer exists | (as above; the source still appears by name) | (as above) | (as above) |

- The first two rows are the approved text, unchanged.
- **"Clear filters"** resets type, date and source and keeps the typed words (the spec's `clearFilters()`). Tooltip:
  "Show every screenshot that matches the words". With no typed words it is the only button, because there is
  nothing else to clear. Tooltip there: "Show every screenshot".
- **"Clear search"** resets everything (wave 1 spec, story 16). Tooltip changes from "Clear the search text and the
  type" to "Clear the words and every filter". **[Δ polish: Clear search now also clears date and source; the no-match
  state can show two buttons]**
- With both buttons, "Clear filters" comes first: it keeps the user's words, which is the more likely wish. Both use
  the secondary style, and neither takes ↩ (↩ keeps meaning "open", and does nothing here, as today).
- **[Δ wave 1]** The spec's example "No Slack screenshots from the last 7 days" / "Clear filters to see every
  screenshot." becomes "No screenshots from Slack taken in the last 7 days". One sentence pattern ("from …", "taken …")
  works for every combination with a chip, a source and a date. The spec left the final wording to this pass.

### Empty index and errors

- Empty index: the approved empty state is unchanged. The Source pill is disabled with its tooltip. The Date pill
  stays enabled (harmless, and it keeps row 2 stable).
- Index errors: unchanged.

### Copy Text: badge, pills, announcements

| Text status | Badge | Click or ⇧⌘C does | Pill on the image | VoiceOver |
|---|---|---|---|---|
| `done` | `text.viewfinder` **Copy Text** ⇧⌘C | Copies at once | ✓ Text copied (1.4 s) | Badge "Copy Text"; announces "Text copied" |
| never read (NULL) | Same as `done` | Reads now, ahead of the queue; badge switches to reading; copies when ready (late-copy rule) | ✓ Text copied | Announces "Reading text" then "Text copied" |
| `pending` | spinner **Reading text…** | Waits, then copies (late-copy rule) | ✓ Text copied | Badge "Reading text"; announces "Text copied" |
| `none` | Hidden | ⇧⌘C only | No text found in this screenshot. (3 s) | Announces the same sentence |
| `failed` | `exclamationmark.triangle.fill` **Read text again** | Badge: re-queues the row ahead of the queue (badge switches to reading). ⇧⌘C: shows the error | The text could not be read. (3 s) | Badge "Read text again", hint "The text could not be read last time." |
| `failed`, file missing | Same as `failed` | Same | This file is no longer there. It was moved or deleted after it was indexed. (existing text) | Same |
| Late copy dropped (clipboard changed or row changed) | back to Copy Text | Nothing is written | none | none |

- Tooltips: "Copy the text in this screenshot (⇧⌘C)"; while reading: "Reading the text. It's copied when it's ready.";
  failed: "The text could not be read. Read it again."
- A never-read row looks the same as a ready one on purpose. The user doesn't need to know it hasn't been read: the
  press just takes a moment longer (wave 1 decision 2).
- The "No text found" pill uses the `text.viewfinder` symbol, not the warning triangle: nothing went wrong.
- After a successful re-read from "Read text again", the badge becomes "Copy Text". It does not copy by itself: the
  user didn't ask to copy.
- **[Δ wave 1]** The spec has "failed: message plus a retry". Here the retry is the badge itself ("Read text again"),
  and the message is the pill shown on ⇧⌘C and the badge's tooltip and VoiceOver hint. The spec's "Reading text…" for
  `pending` is the badge label.
- If several copy requests are waiting, only the last one counts (the late-copy rule already drops one that is no
  longer on screen).

### Read text in existing screenshots (menu bar menu)

The spec leaves the place to this pass. It goes in the menu, under "Process Existing Screenshots…", because it's the
same kind of one-off batch job. **[Δ polish: one more menu item, and a status line state]**

| Element | Text |
|---|---|
| Menu item | Read Text in Existing Screenshots… (hidden when no screenshot needs reading) |
| Confirm alert, title | Read the text in 180 screenshots? |
| Confirm alert, message | Shotkeeper reads them on this Mac, newest first. The text never leaves your Mac. You can stop at any time from the menu. |
| Confirm buttons | Read Text (default) · Cancel |
| Status line while running | Reading text: 142 left |
| Menu item while running | Stop Reading Text |
| Last message when done | Read the text in 180 screenshots |
| … with failures | Read the text in 178 screenshots. 2 could not be read. |
| Last message after Stop | Stopped reading text. 38 screenshots were read. |

## 6. Keyboard

The field keeps the focus, as today, except while a picker is open (below).

### Keys

| Key | With the field focused | With a picker open |
|---|---|---|
| ⌘D | Opens the date picker | Closes it (in the date picker) or switches to it (in the source picker) |
| ⌘S | Opens the source picker (beep when disabled) | Closes it, or switches to it |
| ↑ ↓ | Move the result selection | Move the highlight |
| ↩ | Open the selected screenshot | Choose the highlighted value, close, focus back to the field |
| esc | Clear text, chip, date and source; then close the panel | Close the picker without a change |
| ⌫ | Delete in the field | With an empty narrow field (or in the date list): clear this filter and close |
| ⇧⌘C | Copy Text for the selected result | Ignored |
| ⌘C, ⌘R, ⌘Y, Space, ⌘1–⌘7 | As today | Ignored (⌘C copies selected narrow-field text) |
| Tab | (Full Keyboard Access) next control | Custom range: From → To → Apply |

- **Clearing one filter from the keyboard:** ⌘D ⌫ clears the date, ⌘S ⌫ clears the source. Esc still clears
  everything at once.
- **Picking fast:** ⌘S, type "sl", ↩. ⌘D, ↓↓↓, ↩ for "Last 7 days".
- **Why ⌘D and ⌘S:** D for date, S for source, both reachable with the left hand next to ⌘C. Neither is used by the
  panel, the SwiftUI default menus (no Save in this app), or the text field. Avoided: ⌘C, ⌘R, ⌘Y, ⌘1–⌘7, ⇧⌘C, ⌘A/X/V/Z
  (Edit menu), ⌘W, ⌘Q, ⌘H, ⌘M, ⌘, and the global ⌥⌘S. ⌘F was considered and left out: in other apps it moves focus to
  a search field, and here the focus is already in one.
- Matching follows the existing rule: the ASCII character, else the physical key (`d` = key code 2, `s` = 1), so the
  Russian layout works. The IME guard covers both. If the user records ⌘D or ⌘S as the global search shortcut, the
  global shortcut wins; the recorder doesn't need to warn about this.
- **⇧⌘C** (wave 1 spec): accepted for `c` only with ⇧⌘, lowercased character, else key code 8. ⌘C keeps copying
  the image, or the field's selected text.
- **Esc order** gains one step at the front: close an open picker. Then clear everything, then close the panel.
  **[Δ polish: Esc order]**

### Focus while a picker is open **[Δ polish]**

- The polish rule is "focus stays in the search field". The source picker's narrow field takes the focus while the
  picker is open, and gives it back to the search field when the picker closes. The date picker's list and the custom
  range fields do the same.
- Why: narrowing many sources by typing (wave 1 spec) needs a real text field, so IME input and the text editing keys
  work. Routing keystrokes from the search field to the picker would hide the typed query or lose IME support.
- What stays true: the panel is still the key window and never activates Shotkeeper. The picker is part of the panel,
  not another window. The search field keeps its text, and a stale picker never stays open after the panel hides.

### Focus order (Full Keyboard Access on)

Search field → clear button (when shown) → All … Design → Date → clear date (when on) → Source → clear source (when
on) → result list → Copy Text badge → tags → Open → Copy Image → Reveal in Finder → Quick Look. With Full Keyboard
Access off, Tab doesn't reach buttons (appkit-gotchas, PR 3), and every control above has a key: ⌘1–⌘7, ⌘D, ⌘S,
⌫ in a picker, ⇧⌘C, ↩, ⌘C, ⌘R, Space.

## 7. States

| State | What the panel shows |
|---|---|
| Default (no filters) | As today, plus two quiet pills "Date" and "Source" at the end of row 2, and the Copy Text badge on the image when the selection has text. |
| Filters on, results | Indigo pills with values; footer "N of M screenshots"; the list is newest first when there's no text (story 12). |
| Picker open | The picker covers part of the list and preview. Results behind it don't change until a value is chosen. |
| Many sources | Picker scrolls after 8 rows; the narrow field filters. The list is loaded each time the panel opens. |
| Long source names | Tail truncation in the pill (max 180 pt) and the picker row; full name in tooltip and VoiceOver. |
| Chosen source gone | Pill keeps the name; picker pins it with count 0; no-match names it. |
| No match, filters only | "No screenshots from Slack taken in the last 7 days" + "Clear filters". |
| No match, text + filters | "No screenshots match “invoice”" + the filters sentence + "Clear filters" and "Clear search". |
| Empty index | Approved empty state; Source pill disabled with tooltip. |
| Batch view | Unchanged look. Choosing or clearing any filter leaves the batch (story 19). |
| Text reading | Badge "Reading text…" with a small spinner (the native `ProgressView`, 12 pt). |
| Text failed | Badge "Read text again" with a warning symbol. |
| No text | No badge; ⇧⌘C shows "No text found in this screenshot." |
| Panel hidden and reopened | Filters and text are kept (story 18); a picker is closed. |
| Tag clicked | The tag goes into the field, and the chip, date and source all reset (wave 1 decision 7). |

## 8. Light and dark

- Both modes use the same structure, and only semantic colours change. Active pills use #5856D6 (light) and
  #5E5CE6 (dark) with white text. The polish spec allows white on these for selected chips; computed contrast for
  12 pt semibold is about 5.6:1 (light) and 5.1:1 (dark).
- Check marks in the pickers use brand text (#4644C0 / #A5A4FF, at least 4.5:1).
- Picker counts and inactive pill symbols use `Brand.secondaryText` (label 72%), not `.secondary`, for 4.5:1.
- The badge and pills are black 72% with white text in both modes. Over a white screenshot that is about 9:1. Over
  a dark screenshot the capsule is still a visible shape because of the frame's 4% backdrop and its own edge, a 0.5 pt
  white 18% stroke (dark mode only).
- The picker uses the menu material. Snapshots draw an opaque background (`opaqueBackground`), so they show a flat
  #FFFFFF / #2C2C2E picker; the real blur is checked on a Mac.

## 9. Real-Mac checks (CI can't see these)

- The picker opens without Shotkeeper activating and without the panel losing key status; clicking outside the
  picker but inside the panel closes it; clicking another app hides the panel and the picker.
- The narrow field takes the focus and gives it back; IME (Japanese) in the narrow field; ↩ in the IME candidate
  list doesn't choose a source.
- ⌘D, ⌘S, ⇧⌘C on QWERTY, Dvorak and Russian layouts; ⇧⌘C pastes plain text only into TextEdit (rich mode) and Slack.
- `DatePicker(.field)` keyboard editing inside the non-activating panel.
- The badge over light and dark screenshots; a click on it doesn't start a drag.
- VoiceOver: pills read name and value, clear announcements, badge states, picker rows with counts.
- Quick Look (Space) on a screenshot: whether macOS Live Text lets the user select part of the text. Unverified
  (wave 1 spec); if it works, partial copy needs no Shotkeeper UI.

## 10. Snapshot states to add

The wave 1 spec lists "filters active, filtered no-match, the text-status pills, and the source list with many
entries". Concretely, light and dark: `search-filters-on`, `search-source-picker` (many sources, one long name),
`search-date-custom`, `search-no-match-filters` (text + filters), `search-no-match-filters-only`,
`search-text-reading`, `search-text-copied`, `search-text-failed`, `search-text-none`, `search-empty-index` (existing,
now with the disabled Source pill).

## 11. Changes against the approved specs

Against the polish spec ([../specs/ui-polish-2026-11.md](../specs/ui-polish-2026-11.md)):

1. Row 2 gains the Date and Source pills at its right end. Active pills use the selected-chip indigo, read as "selected
   chips" in the spec's list of brand moments.
2. A new element on the preview image: the Copy Text badge, plus "✓ Text copied" and two problem pills. The four
   approved buttons are unchanged.
3. The search field gives the focus to a picker while it is open (PR 2 rule: "focus stays in the field").
4. Esc order: close a picker first.
5. "Clear search" also clears date and source (from the wave 1 spec). The no-match state can show a second button,
   "Clear filters", and with filters but no text "Clear filters" replaces "Clear search".
6. The menu bar menu gains "Read Text in Existing Screenshots…", "Stop Reading Text" and the status line "Reading
   text: N left" (PR 1b).
7. Empty index: the Source pill is shown disabled.

Against the wave 1 spec ([../specs/search-filters-and-text-2026-11.md](../specs/search-filters-and-text-2026-11.md)):

1. No-match wording: "No screenshots from Slack taken in the last 7 days" instead of the example "No Slack
   screenshots from the last 7 days" (the spec left the final copy to this pass).
2. "Clear filters" button (keeps the words), using the spec's `clearFilters()`. Not in the stories, an addition.
3. The failed state's retry is the badge "Read text again". ⇧⌘C on a failed row shows the message without
   retrying.
4. ⇧⌘C is visible on the badge, not only in a tooltip.
5. "Copy Text" is a badge on the image rather than a button in the button row. It is still a button in the preview,
   as story 30 asks.
6. ⌘D and ⌘S open the pickers; ⌫ in an open picker clears that filter. (The spec left the keys to this pass.)
7. The pickers are drawn inside the panel and take the keyboard focus (not key-window status) while open.
