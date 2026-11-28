# Design: subfolders, Edit name and Analyse Again (wave 2, 2026-11-28)

Design pass for [../specs/subfolders-and-retitle-2026-11.md](../specs/subfolders-and-retitle-2026-11.md) (the "wave 2
spec"). It uses the frontend-design skill as adapted in [../wiki/workflow.md](../wiki/workflow.md), "UI design step".
The identity is fixed by [../specs/ui-polish-2026-11.md](../specs/ui-polish-2026-11.md) (the "polish spec"), and the
search panel builds on the approved wave 1 design, [search-filters-and-text.md](search-filters-and-text.md) (the "wave 1
design"). This note decides layout, hierarchy, copy, states and keys within those.

- Mockup for review: [subfolders-and-retitle-mockup.html](subfolders-and-retitle-mockup.html) (static, light and dark,
  under 700 px wide). The CI snapshot PNGs of the real SwiftUI views stay the acceptance check.
- Baseline: CI snapshots from run 46130600513 (main, after PR #9), and `App/Shotkeeper/UI/SearchView.swift`,
  `SettingsView.swift`, `ToastView.swift` and `Feedback/Toast.swift` at `58c4fb9`.
- Departures are marked inline: **[Δ polish]** against the polish spec, **[Δ wave 1]** against the wave 1 design and
  **[Δ spec]** against the wave 2 spec. Section 12 lists them all again.

## 1. Brief, as I read it

- **Subject:** two maintenance jobs on a library of named screenshots. One is a Finder concern: put files into folders.
  The other is a search-panel concern: fix the one title that's wrong.
- **Audience:** one person who knows the panel by heart (⌥⌘S, type, ↑↓, ↩), and who opens Settings rarely.
- **Primary jobs:**
  - Settings: choose a rule once and understand what it will do before the next screenshot.
  - Panel: spot a bad title, fix it in place, by hand or by asking the model again, without losing your place.
- **Must not change:** the default panel's look. The four-button row, the footer's five hints, row 2 (chips and wave 1
  pills) and the image with its Copy Text badge all stay as approved.

## 2. Plan

### Tokens (inherited, nothing new)

| Role | Light | Dark | Source |
|---|---|---|---|
| Brand fill (primary buttons, countdown bar) | #5856D6 | #5E5CE6 | polish spec |
| Brand text (status label "Analysed again", toast label) | #4644C0 | #A5A4FF | `Brand.indigoText` |
| Warning text (held, refused) | #8A4600 | #FFB340 | `Brand.warningText` |
| Error text (failed, unusable name) | #C4281C | #FF7B72 | `Brand.errorText` |
| Secondary text | label 72% | label 72% | `Brand.secondaryText` |
| Neutral fill (icon button hover, secondary button) | label 8% | label 8% | `PanelSecondaryButtonStyle` |
| Overlay pill | black 72%, white text | same | "✓ Copied" pill |

- **Type:** SF only, on the existing scale: 18 semibold (preview title and its editor), 14 semibold (toast name),
  13 (body, alert text), 12 (status line, buttons, metadata values), 11 (toast label, keycaps, metadata labels). No new
  size.
- **Radii:** panel 16 → image 12 → consent card 12 → field 6 and buttons 6 → capsules for pills.
- **Native first:** Settings uses a stock `Picker` (menu style), `LabeledContent`, a `ProgressView` and a sheet alert.
  The only custom surfaces are inside our own panels, which already have custom styles.

### Where the two new actions go (the real layout choice)

The preview's button row holds four buttons in about 410 of its 517 pt (wave 1 design: a fifth needs about 500). Two
more don't fit. Three ways:

**A. Two icon buttons at the end of the title (chosen)**

```
┌───────────────────────────────────────────────────────────┐
│ ┌───────────────────────────────────────────────────────┐ │
│ │                    (screenshot)                       │ │
│ │                                  [⌗ Copy Text  ⇧⌘C]   │ │
│ └───────────────────────────────────────────────────────┘ │
│ Settings window dialog                            [✎] [✦] │
│ The macOS Settings window with the General pane open.     │
│ (#settings) (#macos)                                      │
│ Source    Type     Taken                 Folder           │
│ Finder    Design   Nov 21, 2026 at 3:10  Screenshots › Designs│
│ [Open] [Copy Image] [Reveal in Finder] [Quick Look]       │
└───────────────────────────────────────────────────────────┘
```

**B. A "More" button (`ellipsis.circle`) at the end of the button row**, opening a menu with Edit Name and Analyse
Again.

```
│ [Open] [Copy Image] [Reveal in Finder] [Quick Look]  [⋯] │
```

**C. A second button row** under the first: "Edit name", "Analyse Again".

```
│ [Open] [Copy Image] [Reveal in Finder] [Quick Look]       │
│ [Edit name] [Analyse Again]                               │
```

**Why A:**

- Both actions change the **title**, so they sit on the title. "Edit name" turns the very text next to it into a
  field, so the button and its effect are in one spot, the way the Copy Text badge sits on the picture it reads.
- It costs no height. C adds 32 pt to the tightest column in the panel (wiki ui-polish, PR 2: the grid was clipped
  once).
- B hides both actions in a menu, and an `NSMenu` tracking loop in a non-activating panel is the risk the wave 1
  design already avoided for the pickers.
- The cost of A: icon-only buttons need tooltips and VoiceOver labels (polish spec, accessibility), and the title loses
  56 pt of width. It already wraps to 2 lines, so long titles still fit.

Icon buttons: 22×22 pt, 13 pt symbol in `.secondary`, no fill until hover or press (label 8% / 16%, radius 6),
top-aligned with the title's first line, 4 pt apart, 8 pt from the title.
- Edit name: `pencil`.
- Analyse Again: `sparkles`, the brand's sparkle (toast label, menu bar glyph), which reads as "the model names it".
  It is not `arrow.clockwise`, which reads as "reload the view".

### Where results go: one status line under the title

Both actions report in one place: a single line between the title and the description, the **status line**. It is
absent when there is nothing to say, so the default preview is unchanged.

- 12 pt, leading 12 pt symbol. The first phrase is semibold in the state's colour (brand text, warning or error), and
  the rest is regular secondary text. An optional small button sits at the end (`PanelSecondaryButtonStyle`, or the
  brand primary style for "Use This Name").
- At most 2 lines. A third line truncates at the tail, and the full text is in the tooltip and the VoiceOver label.
- It belongs to the row: it stays while the row is selected, comes back when you return to the row, and is cleared
  when the panel hides (the toast reports anything that finishes while the panel is hidden, §7).
- Short confirmations that need no reading ("✓ Renamed") use the existing centred pill on the image instead, for
  1.4 s, like "✓ Copied".

### The one bold choice: the title turns over in place

When Analyse Again gives a new title, the old title doesn't just vanish. It **moves down into the status line, shrinks
from 18 to 12 pt and is struck through**, while the new title fades in where it was:

```
before                                      after (300 ms)
Settings window dialog            [✎] [✦]   Invoice from Acme Cloud Services     [✎] [✦]
                                            ✦ Analysed again   S̶e̶t̶t̶i̶n̶g̶s̶ ̶w̶i̶n̶d̶o̶w̶ ̶d̶i̶a̶l̶o̶g̶
```

- **This is Shotkeeper's own picture.** Setup's welcome card shows exactly this: a struck-through old name next to the
  new one in indigo semibold (polish spec, PR 3 step 1). Analyse Again is that promise kept a second time, so it gets
  the app's own before-and-after, not a generic success tick.
- **It is motion that answers an action** (the skill's rule): one move, once, when the user's request completes.
  Nothing animates on load.
- With Reduce Motion on, the two titles cross-fade and nothing moves.
- Everything else in this wave stays quiet: native Settings rows, stock alert, existing toast layouts, existing pill.

### Review against the brief (what I changed after the first draft)

- **Draft:** a "Named by you" badge after hand-edited titles. **Cut.** It would be on screen for every edited row
  forever, to explain something that matters only on Analyse Again. That moment explains itself instead ("Kept your
  name", §5.3), and the Analyse Again tooltip says it in advance. The spec left this choice to the design pass.
- **Draft:** an "Undo" button at the end of every Analyse Again result line. **Cut.** Undo already lives in the menu
  (⌘Z, "Undo: <title>") and in the toast when the panel is hidden. A third Undo in the panel would need a key the field
  doesn't take (⌘Z undoes typing), so it would be a mouse-only duplicate.
- **Draft:** the consent question as a sentence inside the status line, with Allow and Cancel at its end. **Changed**
  to a card over the preview (§6). Consent is the one moment in this wave that must not be skimmed, and in Settings it
  is a dialog. A line under a title reads like a notice.
- **Draft:** sort progress only in the Settings row. **Changed:** also in the menu bar status line (with Stop), like
  wave 1's "Reading text: N left", because Settings may be closed while hundreds of files move.
- **Checked against the skill's list of defaults:** no all-caps labels, no eyebrows, no "→" in labels, no monospace
  data labels, no cards for the sake of cards (the only new card is the consent question). New copy adds no middle dots.

## 3. Hierarchy

1. **The title** (18 pt semibold): what the user came to fix. It becomes the field while editing.
2. **The status line**: present only after an action. It uses colour only for its first phrase.
3. **The two icon buttons**: quiet until hover, never louder than the title.
4. **The list row indicator**: a 12 pt spinner or clock at the row's end, seen when scanning the list.
5. Footer and key hints: unchanged.

## 4. Settings › General

### Layout

The "New screenshots" section gains two rows directly under "Move into the organized folder", plus an example row.
Nothing new shows unless an organized folder is set and moving is on (polish rule: hide what doesn't apply).

```
New screenshots
┌──────────────────────────────────────────────────────────────────────┐
│ Rename with a descriptive title                                 (●)  │
│ Move into the organized folder                                  (●)  │
│ Sort into subfolders                              [ By type      ⌃⌄] │
│ Example                Screenshots › Receipts › Invoice from Acme.png│
│                        Folders: Tweets, Articles, Code, Chats,       │
│                        Receipts, Designs and Other.                  │
│ Screenshots already there stay where they are.                       │
│                                       [Sort Existing Screenshots…]   │
│ Write Finder tags and comment                                   (●)  │
│ Minimum title confidence                    ━━━━━●━━━━━━━━━━    0.50 │
└──────────────────────────────────────────────────────────────────────┘
```

- **Alternative considered:** its own "Subfolders" section after "New screenshots". It was rejected because the
  setting only exists because of the move toggle: it is hidden with it, so it belongs right under it. A separate
  section would sit next to the "Filename style" section, which also hides with its toggle, and make the page jump
  more.
- "Sort into subfolders" is a menu `Picker` with the choices **Off**, **By type**, **By app or site** and **By type,
  then app or site**. The default is Off.
- The **Example** row and the **Sort Existing** row show only when the rule isn't Off.
- The example uses the organized folder's real name, the current filename style and the date prefix: kebab-case gives
  "Screenshots › Receipts › invoice-from-acme.png". The value is `Brand.secondaryText`, with middle truncation.
- The note under the example names what the rule does with the edge cases:

| Rule | Example | Note |
|---|---|---|
| By type | Screenshots › Receipts › Invoice from Acme.png | Folders: Tweets, Articles, Code, Chats, Receipts, Designs and Other. |
| By app or site | Screenshots › Mail › Invoice from Acme.png | One folder per app or site. Screenshots from an unknown app go to Other. |
| By type, then app or site | Screenshots › Receipts › Mail › Invoice from Acme.png | Screenshots from an unknown app stay in the type folder. |

- The row "Screenshots already there stay where they are." plus the button **Sort Existing Screenshots…** says the
  "left alone" rule (story 20) right where the user would worry about it.

### Organized folder missing or unreadable

The example row is replaced by a warning row (orange `exclamationmark.triangle.fill`, warning-text colour), and Sort
Existing is disabled:

| Problem | Text |
|---|---|
| Missing | Can't find “Screenshots”. Choose the organized folder again above. |
| Unreadable | Shotkeeper can't open “Screenshots”. Allow access in Finder (Get Info › Sharing & Permissions), or choose another folder. |

New screenshots still follow the spec's fallback (organized folder root, else kept in place with a note). The row only
explains why sorting can't happen.

### Sort Existing Screenshots…: the flow

The action keeps one verb all the way through: **Sort Existing Screenshots…** → **Sort** → **Sorting** → **Sorted**.

1. **Counting.** On click, the plan runs. If it takes over 0.3 s, the button is disabled and a small spinner appears
   before it, with the row text "Counting screenshots…".
2. **Confirm** (a sheet alert on the Settings window: a normal window, so the native alert is right here):

```
┌─────────────────────────────────────────────┐
│ Sort 180 screenshots into subfolders?       │
│                                             │
│ They move into folders by type inside       │
│ “Screenshots”, with their names unchanged.  │
│ Nothing is uploaded.                        │
│                                             │
│ 34 are already in the right folder.         │
│ 6 were moved or renamed in Finder and are   │
│ left alone.                                 │
│                                  [Cancel] [Sort] │
└─────────────────────────────────────────────┘
```

| Part | Text |
|---|---|
| Title | Sort 180 screenshots into subfolders? |
| Message, line 1 | They move into folders by type inside “Screenshots”, with their names unchanged. Nothing is uploaded. ("by type" / "by app or site" / "by type, then app or site") |
| Message, counts | 34 are already in the right folder. · 6 were moved or renamed in Finder and are left alone. (each sentence only when its count is above 0; "1 is already…", "1 was moved…") |
| Buttons | Sort (default, ↩) · Cancel (Esc) |

3. **Nothing to sort** (empty plan): an informational alert, with one button.

| Situation | Title | Message |
|---|---|---|
| All in place | Nothing to sort | All 214 screenshots in “Screenshots” are already in the right folder. |
| Some missing | Nothing to sort | 208 are already in the right folder. 6 were moved or renamed in Finder and are left alone. |
| Folder empty or none indexed | Nothing to sort | Shotkeeper hasn't put any screenshots in “Screenshots” yet. |

   Button: OK.

4. **Running.** The Settings row becomes a progress row, and the menu shows the same progress:

```
│ Sorting: 120 of 180 left   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   [Stop] │
```

| Place | Text |
|---|---|
| Settings row | Sorting: 120 of 180 left · a linear `ProgressView` · Stop |
| Menu status, second line | Sorting into subfolders: 120 left |
| Menu item (under Process Existing Screenshots…) | Stop Sorting |

**[Δ polish: menu status line state and item]**

5. **Done:** a batch toast (§7), then a menu last message.

| Outcome | Toast title | Toast subline | Menu last message |
|---|---|---|---|
| Finished | Sorted 180 screenshots | (none) | Sorted 180 screenshots into subfolders |
| With failures | Sorted 177 screenshots | 3 could not be moved | Sorted 177 screenshots. 3 could not be moved: <first reason>. |
| Stopped | Sorted 60 screenshots | Stopped, 120 left where they are | Stopped sorting. 60 screenshots were sorted. |
| Stopped after 0 | (no toast) | | Stopped sorting. No screenshots were moved. |

- Files that disappear during the run count as "left alone", not as failures (spec: skipped as missing).
- Toast buttons: **View in Search** (primary, the batch view) and **Undo All**.

## 5. Search preview

### 5.1 Default (idle)

```
│ Invoice from Acme Cloud Services for November     [✎] [✦] │
│ November invoice for cloud hosting, total $248.12, …       │
│ (#invoice) (#acme) (#billing)                              │
│ Source   Type     Taken                    Folder          │
│ Mail     Receipt  Nov 21, 2026 at 3:10 PM  Screenshots › Receipts │
```

- **Folder line:** inside the organized folder it shows the path from the organized folder down, joined with " › ":
  "Screenshots › Receipts", "Screenshots › Chats › Slack". Anywhere else it shows the folder name, as today. Middle
  truncation, with the full path in the tooltip and the VoiceOver value ("Folder: Screenshots, Chats, Slack").
- **No "Named by you" mark** (§2, review). The Analyse Again tooltip mentions it when it applies.

| Element | Tooltip | VoiceOver label (hint) |
|---|---|---|
| ✎ | Edit name (⌘E) | "Edit name" |
| ✦ | Analyse this screenshot again (⇧⌘E) | "Analyse Again" ("Sends this screenshot to <destination short name> again") |
| ✦, title is the user's | Analyse this screenshot again (⇧⌘E). Your name is kept. | same, hint adds "Your name is kept." |
| ✦, local model | Analyse this screenshot again on this Mac (⇧⌘E) | hint "Runs on this Mac" |

Destination short names for the hint: "your Cloudflare account", "OpenRouter", the custom endpoint's host.

### 5.2 Edit name

```
│ ┌──────────────────────────────────────────────────────┐   │
│ │ Settings window dialog▌                              │   │  ← 18 pt field, text selected
│ └──────────────────────────────────────────────────────┘   │
│ ↩ Save  esc Cancel                       [Cancel] [Save]   │
│ The macOS Settings window with the General pane open.      │
```

- The title is swapped for a `TextField` (rounded border, 18 pt semibold, the same baseline). It holds the stem
  without the extension, all selected, like the toast. The two icon buttons hide while editing.
- Under it, one row: the key hint on the left (11 pt secondary, the toast's wording, without its middle dot), and
  **Cancel** (secondary) and **Save** (brand primary) on the right.
- **Saving:** Save and the field are disabled. A 12 pt spinner replaces the key hint only if the rename takes over
  0.3 s (it's a local rename, so usually never).
- **Unusable name:** the editor stays open with the text selected, and the hint row's left side becomes the error in
  error-text colour: "Choose a name with letters or numbers." (spec copy). VoiceOver announces it.
- **Success:** the editor closes, the title shows the new name and the image shows the pill **✓ Renamed** for 1.4 s.
  The row stays selected (spec: kept by row id). If the new name no longer matches the query, the status line says
  "Renamed. It no longer matches your search, so the next screenshot is selected." while the selection moves, and the
  same text is announced.
- **Name clash:** the same pill, plus a status line that stays: "Renamed to “Invoice from Acme 2”: “Invoice from Acme”
  is already in this folder." (`checkmark.circle` in secondary).
- **File missing:** the editor closes, nothing is renamed, and the existing problem pill appears on the image: "This
  file is no longer there. It was moved or deleted after it was indexed."
- **Other error:** the editor stays open, and the error line shows "Could not rename: <readable message>." (toast
  wording).
- **Cancel** (Esc, the Cancel button, a click on another row, typing in the search field, a chip, a filter, hiding the
  panel): the title comes back unchanged, and nothing is saved.

### 5.3 Analyse Again: every state

The action keeps its name all the way through: **Analyse Again** → **Waiting to analyse…** / **Analysing…** →
**Analysed again**, in the status line, the toast and VoiceOver. Status line contents:

| State | Symbol and colour | Status line | Button | ✦ button |
|---|---|---|---|---|
| Idle | (none) | (none) | | enabled |
| Asking for consent | (card, §6) | (none) | | pressed look |
| Queued | `clock` secondary | **Waiting to analyse…** | | disabled, tooltip "Already waiting to analyse this screenshot" |
| Analysing | 12 pt spinner, brand text | **Analysing…** | | disabled, tooltip "Analysing this screenshot" |
| Held, offline | `wifi.slash` warning | **Waiting to analyse:** you're offline. It starts when the connection is back. | | disabled |
| Held, needs attention | `exclamationmark.triangle.fill` warning | **Waiting to analyse:** <queue reason, e.g. "Cloudflare API token is not set">. | Fix Settings… | disabled |
| Renamed | `sparkles` brand text | **Analysed again** ~~Settings window dialog~~ | | enabled |
| Renamed and moved | `sparkles` brand text | **Analysed again, now in Receipts** ~~Settings window dialog~~ | | enabled |
| Moved, name kept by rule | `sparkles` brand text | **Analysed again, now in Receipts.** The name stays: <reason below>. | | enabled |
| Same title as before | `sparkles` brand text | **Analysed again.** The title is the same as before. Description and tags are updated. | | enabled |
| Kept, low confidence | `sparkles` brand text | **Analysed again.** The name stays: the new title is a low-confidence guess. | | enabled |
| Kept, rename off | `sparkles` brand text | **Analysed again.** The name stays: renaming is off in Settings. | | enabled |
| Kept, unusable title | `sparkles` brand text | **Analysed again.** The name stays: the model gave no usable title. | | enabled |
| Kept your name | `sparkles` brand text | **Analysed again. Kept your name.** Suggested: “Acme invoice for November” | Use This Name | enabled |
| Kept restored name | `sparkles` brand text | **Analysed again. Kept the original name** because you restored it with Undo. Description and tags are updated. | | enabled |
| Refused, excluded | `eye.slash` warning | **Not analysed:** it matches your exclude rule “1Password”. Screenshots that match a rule are never sent. | | enabled |
| Refused, paused | `pause.circle` warning | **Not analysed:** Shotkeeper is paused until 3:42 PM. Resume from the menu bar first. ("is paused." when there's no end time) | | enabled |
| Refused, missing | `exclamationmark.triangle.fill` warning | **Not analysed:** this file is no longer there. It was moved or deleted after it was indexed. | | enabled |
| Failed | `exclamationmark.octagon.fill` error | **Could not analyse again:** <readable message>. The screenshot is unchanged. | Fix Settings… (only when the problem needs Settings) | enabled |
| Request dropped | `exclamationmark.triangle.fill` warning | **The destination changed. Analyse again.** (spec copy) | | enabled |
| Not available (⇧⌘E or click while disabled) | `exclamationmark.triangle.fill` warning | **Analyse Again needs a model:** <gate reason, e.g. "Cloudflare API token is not set">. | Fix Settings… | disabled |
| Not available, unidentified endpoint | same | **Analyse Again is off:** the custom endpoint's address is incomplete, so it can't be allowed. Check the URL in Settings › Model. | Fix Settings… | disabled |

Notes:

- **Analysing:** the title dims to 45% and the description, tags and grid stay as they are. On a result, the title
  turns over (§2), and the description, tags, type and source cross-fade to their new values.
- **Kept your name**, with **Use This Name**: the suggestion and the button sit on a second line under "Analysed
  again. Kept your name.", so the button never wraps into the middle of the quote. The button calls
  `rename(_:to: suggestedTitle)`. Its result is the
  ordinary Edit name success (pill **✓ Renamed**, status line cleared), and a clash gives the clash line. The
  suggestion is quoted in the line, truncated in the middle if long, with the full title in the tooltip.
- **A disabled ✦ still explains itself:** a click on it or ⇧⌘E shows the "Not available" line (and beeps for ⇧⌘E). A
  keyboard user never sees tooltips, so the reason has to reach the panel. **[Δ spec: the spec only lists a disabled
  action with the reason in its tooltip]**
- **"Fix Settings…"** opens Settings on the right tab (Model for backend problems, General for paused), like the error
  toast.
- **Paused until:** the time uses `TimeLabel` (the menu's "Paused until 3:42 PM").
- **The exclude rule's name** is the rule's own display text from Settings › Exclusions. Without one, the line says
  "it matches one of your exclude rules".
- **Pills:** none for Analyse Again. Everything goes in the status line, so the image's centre stays free for
  "✓ Copied", "✓ Renamed" and wave 1's text pills.

### 5.4 Result list row

```
│ ▣ Settings window dialog                 ◌ │  ← analysing / renaming: 12 pt spinner
│   Finder · 2 min ago                       │
│ ▣ Invoice from Acme…                     ◷ │  ← queued or held: `clock`, secondary
│   Mail · 1 h ago                           │
```

- The indicator sits at the row's trailing edge, centred vertically, and the title truncates 18 pt earlier while it
  shows. Analysing or saving a name shows a spinner. Waiting or held shows `clock` (warning colour when held).
- No indicator for results: the status line and the new title say it.
- VoiceOver appends the state to the row label: "…, waiting to analyse", "…, analysing", "…, renaming".

## 6. The consent question (in the panel)

### Choice

| Option | Verdict |
|---|---|
| **A. A card drawn inside the panel, over the preview (chosen)** | It never takes key-window status, like wave 1's pickers, so the panel stays key and Shotkeeper never activates. Its size fits the question. |
| B. A separate alert window (`NSAlert`, or `confirmationDialog` on the panel) | It activates Shotkeeper. The panel hides on focus loss (polish spec), which would leave the alert floating with no panel behind it. A sheet on a borderless non-activating panel is untested territory (appkit-gotchas: standard panels are not non-activating). |
| C. A sentence in the status line with Allow and Cancel | Quiet enough to skim. Consent must not be skimmed (§2, review). |

### Layout

```
┌──────────────── list ────────────┬───────────── preview (dimmed 30%) ─────────────┐
│                                  │   ┌──────────────────────────────────────────┐ │
│                                  │   │ ✋  Screenshots will be sent to           │ │
│                                  │   │     http://gpu-box.lan:8080.             │ │
│                                  │   │                                          │ │
│                                  │   │     Allow it to analyse this screenshot  │ │
│                                  │   │     now. Shotkeeper then also sends each │ │
│                                  │   │     new screenshot there to name it.     │ │
│                                  │   │     Older screenshots are sent only when │ │
│                                  │   │     you ask.                             │ │
│                                  │   │                      [Cancel] [Allow]    │ │
│                                  │   └──────────────────────────────────────────┘ │
└──────────────────────────────────┴────────────────────────────────────────────────┘
```

- The card is 380 pt wide, centred in the preview column, with radius 12, the window background (opaque, so the text
  is crisp over any screenshot), a 0.5 pt border at label 12% and the system menu shadow. The preview behind it dims
  with black 30% (light) / 40% (dark). The list stays as it is, so the user sees which screenshot is meant.
- `hand.raised.fill` in orange, the symbol of the Settings consent row, so it reads as the same question.
- **Title:** the exact `ConsentRequest.prompt` plus a period, the same text the Settings dialog uses:
  - "Screenshots will be sent to your Cloudflare account."
  - "Screenshots will be sent to OpenRouter (<model>)." (whatever `openRouterConsentPrompt` returns)
  - "Screenshots will be sent to http://gpu-box.lan:8080."
- **Message:** "Allow it to analyse this screenshot now. Shotkeeper then also sends each new screenshot there to name
  it. Older screenshots are sent only when you ask." **[Δ spec: the title is Settings' question word for word; the
  message says what happens to this screenshot, which the Settings message doesn't cover]**
- **Buttons:** Cancel (secondary) and **Allow** (brand primary). The labels are the same as Settings. Allow grants
  through the existing path, and then the request is issued: the card closes and the status line goes straight to
  "Waiting to analyse…" or "Analysing…", which shows the flow continuing.
- The card shows the `ConsentRequest` captured at the press (spec). If the settings change while it is open, Allow
  grants nothing and the status line shows "The destination changed. Analyse again."
- Closes on Allow, Cancel, Esc, a click outside it (counts as Cancel), a selection change and hiding the panel. Cancel
  leaves no status line: nothing happened.

## 7. Toasts

### Single screenshot, sorted into a subfolder

```
┌──────────────────────────────────────┐
│ ▣  ✦ Sorted into Receipts         ⊗  │
│    Invoice from Acme Cloud Services  │
│    for November                      │
│    was: Screenshot 2026-11-28 at 09… │
│                   [Undo] [Edit name] │
│▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀      │
└──────────────────────────────────────┘
```

- The **label** carries the place: "Sorted into Receipts", "Sorted into Chats › Slack" (middle truncation inside the
  label width). It replaces "Renamed" / "Moved" only when a subfolder was used. The name and the "was:" line already
  show the rename. **[Δ polish: label text; Δ spec: the spec's example "in Receipts" becomes the label "Sorted into
  Receipts"]**
- Why the label and not a fourth line: the toast's height stays as approved, and the word "Sorted" matches the
  setting's name ("Sort into subfolders").
- When the subfolder couldn't be made and the file went to the organized folder root, the label is the usual
  "Renamed" / "Moved". The note is in the index, and a toast is no place for it.
- VoiceOver: "Renamed and sorted into Receipts: Invoice from Acme Cloud Services for November."
- Undo: one Undo reverts the move and the rename (existing rule: newest first, ends at the original name and place).

### Batch: "Sorted N screenshots"

```
┌──────────────────────────────────────┐
│ ▣▣▣  Sorted 180 screenshots       ⊗  │
│      Stopped, 120 left where they are│
│              [Undo All] [View in Search] │
│▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀          │
└──────────────────────────────────────┘
```

The existing batch layout, with the copy from §4 step 5. Undo All's tooltip: "Move them all back".

### Restored after a sort undo: "Moved back"

| Case | Label (`arrow.uturn.backward`) | Title | Subline |
|---|---|---|---|
| One file, name unchanged | Moved back | Invoice from Acme | Back in “Screenshots”. Shotkeeper will not move this file again. |
| Undo All of a sort | Moved back | 180 screenshots are back where they were | Shotkeeper will not sort these files again |
| Undo All, some failed | Moved back | 178 of 180 screenshots are back | 2 could not be moved back: moved, renamed or name taken |
| Rename and move undone | Original name restored | (existing) | (existing) |

The restored files can't be sorted again: "will not move this file again" is the toast's promise, made true by
`restored_by_undo` (spec story 25). VoiceOver announces "Moved back".

### Analyse Again finished while the panel was hidden

| Outcome | Label (`sparkles`) | Name line | Subline | Buttons |
|---|---|---|---|---|
| Renamed (and maybe moved) | Analysed again (or "Analysed again, now in Receipts") | new name | was: <old name> | Undo · Edit name |
| Kept your name | Analysed again | your name | Kept your name. Suggested: “…” | Use This Name |
| Kept by rule, same title, restored | Analysed again | current name | The name stays: <reason> | (none) |
| Failed, refused, dropped | error toast | "Could not analyse again: <message>" / "Not analysed: <reason>" / "The destination changed. Analyse again." | | Fix Settings… when it applies |

- These show **even when "Show a toast after each rename" is off**: the user asked for this one screenshot, so the
  answer isn't an unrequested confirmation (existing rule: error toasts ignore the setting too). **[Δ polish:
  setting scope]**
- Edit name in this toast uses the toast's own editor, as for a new screenshot (spec, UI area 9).

## 8. Menu bar

- **Undo label for a move-only record** (same stem, other folder: a sort move, or an Analyse Again move with the name
  kept): **"Undo Move: Invoice from Acme"**, so "Undo: Invoice from Acme" doesn't suggest a rename that never
  happened. Rename records keep "Undo: <title>". A record that renamed and moved also keeps "Undo: <title>". This is a
  pure rule in `MenuText.undoItem`. **[Δ polish: "Undo: <title>" gains a variant]**
- A hand rename from the panel and an Analyse Again rename are ordinary rename records: "Undo: <new title>".
- Sorting: the status line and "Stop Sorting" (§4).

## 9. Keyboard

### Keys

| Key | Field focused (default) | Editing the name | Consent card open | Wave 1 picker open |
|---|---|---|---|---|
| ⌘E | Edit name for the selection | Ignored | Ignored | Ignored |
| ⇧⌘E | Analyse Again for the selection (beep plus the reason line when unavailable) | Ignored | Ignored | Ignored |
| ↩ | Open | Save | Allow | Choose (wave 1) |
| esc | Clear, then close | Cancel the edit | Cancel | Close the picker |
| ⌘A ⌘C ⌘V ⌘X ⌘Z | As today | Edit the field's text | Ignored | As wave 1 |
| ↑ ↓ | Move the selection | Caret to start or end (field default) | Ignored | Move the highlight |
| ⌘C ⌘R ⌘Y ⌘D ⌘S ⇧⌘C ⌘1–7 Space | As today and wave 1 | Ignored (⌘C copies the field's selection) | Ignored | As wave 1 |
| Tab (Full Keyboard Access) | Next control | Field → Cancel → Save | Cancel → Allow | As wave 1 |

- **⌘E and ⇧⌘E are accepted** as the spec proposes. E for "edit" is easy to learn. The Shift version of the same
  letter makes "do it again with the model" a deliberate two-modifier press, harder to hit than ⌘E (story 43) and
  next to ⇧⌘C's grip. ⌘G, the fallback, would read as "Find Next" to Mac users. Matching follows the existing rule
  (ASCII character, else key code 14), with the IME guard.
- The footer keeps its five hints (spec). The keys are shown in the tooltips (§5.1). The editor's own hint row shows
  "↩ Save  esc Cancel" while it is open, so the keys are on screen when they matter.
- **Esc order:** consent card → name editor → picker → clear text and filters → close the panel. Only one of the
  first three can be open at a time. **[Δ polish and Δ wave 1: Esc order gains two steps at the front]**

### Focus **[Δ polish: focus leaves the search field while editing]**

- The name field takes the keyboard focus while editing and gives it back to the search field on Save or Cancel. Same
  reason as wave 1's picker field: IME and text editing keys need a real field. The panel stays key and never
  activates Shotkeeper.
- The consent card doesn't take focus. The search field keeps it, and the key handler routes ↩ and Esc to the card
  while it is open. Typing goes nowhere (ignored) while the card is open, so the query can't change under the
  question.
- **Focus order with Full Keyboard Access:** search field → clear → chips → Date → Source → results → Copy Text badge →
  Edit name → Analyse Again → status line button (Use This Name / Fix Settings…) → tags → Open → Copy Image →
  Reveal in Finder → Quick Look. **[Δ wave 1: two stops inserted after the badge]**
- With Full Keyboard Access off, every new control has a key: ⌘E, ⇧⌘E, ↩ / Esc in the editor and card. **Use This
  Name and Fix Settings… have no key.** Use This Name is the same as ⌘E plus pasting the suggestion, and Fix Settings
  is ⌘, from the menu. This is recorded as a deviation (appkit-gotchas: "every control works with the keyboard").

### VoiceOver announcements

| Moment | Announcement |
|---|---|
| Editor opens | (focus moves; VoiceOver reads "New name, Settings window dialog, text field") |
| Saved | "Renamed to Invoice from Acme 2" |
| Unusable name | "Choose a name with letters or numbers." |
| Consent card opens | "Screenshots will be sent to your Cloudflare account. Allow or Cancel." |
| Queued | "Waiting to analyse" |
| Started | "Analysing" |
| Renamed | "Analysed again. Renamed to Invoice from Acme Cloud Services for November." |
| Kept your name | "Analysed again. Kept your name. Suggested name: Acme invoice for November." |
| Other results, refusals, failures | the status line's full text |
| Sort undo | "Moved back" |
| Sort finished | the toast title |

## 10. Light and dark

- Same structure in both modes. Only semantic colours change. The status line's coloured first phrase uses brand text
  (#4644C0 / #A5A4FF), warning text (#8A4600 / #FFB340) or error text (#C4281C / #FF7B72), all at least 4.5:1 on the
  panel material (values from `Brand`).
- The struck-through old title uses `Brand.secondaryText` with a 1 pt strike in the same colour, as in setup's welcome
  card.
- Icon buttons use `.secondary` (non-text, 3:1 allowed) and the hover fill at label 8%.
- The editor field uses the system rounded-border style (white field in light, #1E1E1E-ish in dark, system focus ring
  in the accent colour, not indigo).
- The consent card is opaque window background (#FFFFFF light, #2C2C2E dark), and the dim behind it is black 30% /
  40%. Allow is brand indigo with white text (5.1–5.7:1).
- The Settings rows and the alert are fully native and follow the system.
- Snapshots draw opaque backgrounds (existing `opaqueBackground`), so the material blur is checked on a Mac.

## 11. Real-Mac checks and CI snapshots

**Real Mac:**
- ⌘E is not taken by the field ("Use Selection for Find") or the SwiftUI default menus.
- The editor in the non-activating panel: it takes focus, IME works (↩ in the candidate list doesn't save), and
  focus returns to the search field.
- The consent card never activates Shotkeeper, and ↩ / Esc reach it.
- The title turn-over animation, and Reduce Motion.
- The Settings sheet alert over the Settings window, and the progress row with Stop.
- Finder showing the subfolders, Undo All of a large sort, and the "Moved back" toast.
- VoiceOver announcements from §9.

**New CI snapshot states** (light and dark):
- `settings-general-subfolders-off`, `-by-type`, `-by-app`, `-two-level`, `-folder-missing`, `-sorting`;
- `sort-confirm`, `sort-nothing`;
- `search-edit-name`, `search-edit-name-error`, `search-edit-name-clash`;
- `search-analyse-waiting`, `-analysing`, `-held`, `-renamed`, `-kept-your-name`, `-kept-restored`, `-excluded`,
  `-paused`, `-failed`, `-dropped`, `-unavailable`, `search-consent`;
- `search-row-indicators`;
- `toast-sorted`, `toast-sort-batch`, `toast-sort-stopped`, `toast-moved-back`, `toast-analysed-again`,
  `toast-analysed-kept-your-name`;
- `menu-sorting`, `menu-undo-move`.

## 12. Departures

Against the polish spec ([../specs/ui-polish-2026-11.md](../specs/ui-polish-2026-11.md)):

1. The preview title gains two icon buttons (Edit name, Analyse Again). The four-button row is unchanged.
2. A new status line under the preview title, and a "✓ Renamed" image pill next to "✓ Copied".
3. Focus leaves the search field while the name editor is open (PR 2: "focus stays in the field").
4. Esc order: consent card, then name editor, before the wave 1 order.
5. The toast label "Sorted into Receipts" replaces "Renamed" / "Moved" when a subfolder was used. The restored toast
   gains "Moved back" next to "Original name restored".
6. Analyse Again result toasts show even with "Show a toast after each rename" off.
7. The menu's "Undo: <title>" gains "Undo Move: <title>" for move-only records. The status line gains "Sorting into
   subfolders: N left", plus a "Stop Sorting" item.
8. The preview's Folder value shows a path inside the organized folder ("Screenshots › Receipts").
9. Settings › General gains the subfolder picker, an example, a note and the Sort Existing row inside "New
   screenshots".
10. Use This Name and Fix Settings… in the panel have no key (a recorded keyboard deviation).

Against the wave 1 design ([search-filters-and-text.md](search-filters-and-text.md)):

1. Full Keyboard Access order gains Edit name, Analyse Again and the status line button after the Copy Text badge.
2. The Esc order gains two steps in front of "close the picker".
3. ⌘E and ⇧⌘E are added to the list of keys ignored while a picker is open.

Against the wave 2 spec ([../specs/subfolders-and-retitle-2026-11.md](../specs/subfolders-and-retitle-2026-11.md)):

1. The consent card's title is Settings' question word for word, but its message is new: it says this screenshot is
   sent now. The spec says "the same question Settings asks".
2. A disabled Analyse Again also explains itself in the status line on click or ⇧⌘E, not only in its tooltip.
3. The toast says "Sorted into Receipts" as its label, rather than adding "in Receipts" to the text.
4. Sort progress also appears in the menu bar, with "Stop Sorting".
5. No "Named by you" mark (the spec left this open). The Analyse Again tooltip and the result line say it instead.
6. "Undo Move: <title>" for move-only records (the spec asked the design pass to check this label).

Open point for Parag: the UI spells "Analyse" (British, from Parag's decision text), while existing copy says "analyzed"
(setup: "The test image was analyzed."). This note uses "Analyse" / "Analysed again" for this feature only. Say if the
older copy should be aligned.
