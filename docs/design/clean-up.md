# Design: Clean Up (wave 4, 2026-11-28)

Design pass for [../specs/clean-up-2026-11.md](../specs/clean-up-2026-11.md) (the "spec"). It uses the frontend-design
skill as adapted in [../wiki/workflow.md](../wiki/workflow.md), "UI design step". The identity is fixed by
[../specs/ui-polish-2026-11.md](../specs/ui-polish-2026-11.md) (the "polish spec"). It stays consistent with the
approved wave 1 and wave 2 designs ([search-filters-and-text.md](search-filters-and-text.md),
[subfolders-and-retitle.md](subfolders-and-retitle.md)). Facts about the Trash come from
[../research/trash-and-last-used.md](../research/trash-and-last-used.md) (the "research note").

- Mockup for review: [clean-up-mockup.html](clean-up-mockup.html) (static, 1:1, light above dark, under 700 px wide).
  The CI snapshot PNGs of the real SwiftUI views stay the acceptance check.
- Baseline: CI snapshots from run 46132776343 (main at `0e755e8`), and `App/Shotkeeper/UI/ToastView.swift`,
  `MenuContentView.swift`, `WindowPresenter.swift`, `Brand.swift` and `Sources/ShotkeeperCore/Feedback/Toast.swift`.
- Spelling is American (Parag, 2026-11-28).
- Departures are marked inline: **[Δ polish]** against the polish spec, **[Δ spec]** against the clean-up spec and
  **[Δ wave 2]** against the wave 2 design. Section 14 lists them all again.

## 1. Brief, as I read it

- **Subject:** the one place where Shotkeeper lets files go. Everything else in the app adds names, tags and folders.
  This window takes screenshots away, to the Trash.
- **Audience:** the same one person, who knows the menu and the search panel, opens this window every few months, and
  doesn't remember the rules between visits.
- **Primary job:** look at two short lists, agree with what's ticked or change it, and move those files to the Trash,
  knowing exactly how many, which ones and how to get them back.
- **What must be true:** nothing moves by accident. Before the move, the window says what will happen. After it, it
  says what happened and offers the way back in the same words.

## 2. Plan

### Tokens (inherited, nothing new)

| Role | Light | Dark | Source |
|---|---|---|---|
| Brand fill (Move to Trash… button, countdown bar) | #5856D6 | #5E5CE6 | polish spec |
| Brand text (Keep pill, "Moved back" label) | #4644C0 | #A5A4FF | `Brand.indigoText` |
| Brand tint (selected row, Keep pill fill) | indigo 14% | indigo 34% (row), 22% (pill) | polish spec, tag chips |
| Warning text (out of date, left in place) | #8A4600 | #FFB340 | `Brand.warningText` |
| Error text (index error) | #C4281C | #FF7B72 | `Brand.errorText` |
| Secondary text | label 72% | label 72% | `Brand.secondaryText` |
| Hairline (row and group separators) | label 10% | label 10% | existing panels |

- **Type:** SF only, on the existing scale: 13 semibold (section titles, group titles, row titles), 13 (file names,
  body), 12 (row metadata, section notes, buttons), 11 (Keep pill, small notes). No new size.
- **Radii:** window (system) → thumbnails 8 → buttons 6 → Keep pill capsule.
- **Native first:** a regular titled `NSWindow` from `WindowPresenter`, a SwiftUI `List` with pinned section headers,
  system checkboxes (system accent color, as the polish spec says for normal controls), a menu `Picker` for the age,
  a native sheet alert for the confirmation, and the existing toast. The only custom pieces are the Keep pill, the
  footer stack and the brand primary button.

### Layout: one list or two places?

The window shows two kinds of findings, and ticks can be in both. Three ways to lay them out:

**A. One scrolling list with two sections, a fixed footer (chosen)**

```
┌ Clean Up ─────────────────────────────────────────────────────────────┐
│ Looks in Desktop and in Screenshots, with its subfolders.             │
│ Nothing moves until you confirm.                        [Check Again] │
├───────────────────────────────────────────────────────────────────────┤
│ Duplicates                                   [Select All] [Select None]│  ← pinned
│ 9 extra copies in 4 groups, 21.4 MB. One copy in each group is kept.  │
│ ▣ Invoice from Acme Cloud Services          3 copies, 2.4 MB each     │
│   (Keep) Invoice from Acme Cloud Services.png  Screenshots › Receipts │
│   [✓]    Screenshot 2026-11-21 at 15.10.02.png  Desktop  Not in search│
│   [✓]    Invoice from Acme Cloud Services 2.png  Screenshots › Receipts│
│ …                                                                     │
│ Never opened                                 [Select All] [Select None]│  ← pinned
│ Taken more than [3 months ⌄] ago and never opened. 38 screenshots, …  │
│ [ ] ▣ Boarding pass for flight to Lisbon            Jul 2, 2026  1.1 MB│
│ …                                                                     │
├───────────────────────────────────────────────────────────────────────┤
│ ▣▣▣ 12 ticked, 34.2 MB  [Show Only Ticked]          [Move to Trash…]  │
└───────────────────────────────────────────────────────────────────────┘
```

**B. A sidebar** ("Duplicates", "Never opened") with one list at a time.

**C. A segmented control** at the top switching between the two lists.

**Why A:** in B and C, ticks in the hidden list are out of sight while the button counts them. A user who ticked
three old screenshots, switched to Duplicates and pressed Move to Trash… would bin files they can't see. In A every
tick is on the same scroll, the footer counts both, and "Show Only Ticked" puts all of them on one screen. The cost
of A is a long scroll when both lists are big; pinned section headers keep Select All/None and the age picker in
reach.

### Keep: how one copy per group is marked

| Option | Verdict |
|---|---|
| **A. The kept copy shows a "Keep" pill where the others have a checkbox; any other copy has "Keep This Copy" (on hover, on the selected row, ⌘K, context menu) (chosen)** | One control per row. The pill sits in the checkbox column, so "kept" and "ticked" are read in the same place and can never both be on. |
| B. Two columns: a Keep radio button and a tick checkbox on every row | Exact, but two similar round and square controls per row; the kept row needs a disabled checkbox next to it. Busy for the commonest case (accept the default). |
| C. Drag a copy to the top of its group to keep it | No keyboard or VoiceOver equivalent without building one anyway. |

**Changing Keep swaps the two copies' states.** The new kept copy loses its tick, and the old kept copy takes the tick
the new one had. So the count in the footer doesn't jump, and choosing "keep the Desktop copy instead" in a group
that was all ticked gives the natural result: the other copy goes. The VoiceOver announcement says it (§11).

### The one bold choice: the stack

Ticked screenshots gather into a **fanned stack of thumbnails** at the left of the footer, the deck the batch toast
already uses (in the footer: three 28 pt thumbnails, offset 4 pt, so it fits the 54 pt bar). The same stack travels
through the flow:

1. **Footer:** it shows the last three ticked screenshots next to "12 ticked, 34.2 MB". Ticking a row drops its
   thumbnail onto the top of the stack (160 ms, the only animation in this window). Unticking lifts it off.
2. **Confirmation:** the same stack, at 64 pt, is the alert's icon, where the app icon would be.
3. **Result toast:** the same stack is the toast's thumbnail, as for "Renamed 37 screenshots".
4. **Undo:** the "Moved back" toast shows the stack again.

Why this is the place for boldness: the risk in this window is losing track of what is ticked while scrolling a long
list. The stack keeps "what will go" on screen as pictures, not only as a number, and the user sees the same pictures
again when they confirm and when they undo. It reuses the toast's deck, so it's Shotkeeper's own visual, not a new
one. With Reduce Motion on, the stack changes without movement.

Everything else is quiet: native window, list, checkboxes, picker, alert, and the existing toasts.

### Review against the brief (what I changed after the first draft)

- **Draft:** a thumbnail on every copy in a duplicate group. **Changed** to one thumbnail per group: the copies are
  byte-identical, so three copies showed the same picture three times and pushed the thing that differs (the folder)
  to the right. The group's thumbnail sits on the group's title. **[Δ spec: "each copy with thumbnail … and size"]**
- **Draft:** "macOS has no record" on every never-opened row. **Changed:** the research note shows the API can't tell
  "never opened" from "no record", so every listed row would carry the same note. It is said once, in the section
  note. A per-row note comes back only if the real-Mac test 8 finds a clean split by disk (§5.5). **[Δ spec]**
- **Draft:** the confirmation as a custom sheet listing every file. **Changed** to a native alert with the stack as
  its icon. The list is already the window; a second list in a sheet would be scrolled past. The alert's job is the
  count, the size, the surprises and the way back.
- **Draft:** Move to Trash as the confirmation's default button, like wave 2's Sort. **Changed** to Cancel (§7).
- **Draft:** clicking the footer stack filtered the list to the ticked rows. **Changed** to a labelled "Show Only
  Ticked" button next to it: a hidden affordance is no use for a safety check.
- **Checked against the skill's list of defaults:** no all-caps labels, no eyebrows, no "→" in labels, no monospace,
  no middle dots in new copy, no cards. Duplicate groups are rows with a hairline, not boxed cards.

## 3. Hierarchy

1. **The rows** and their checkboxes: what will go.
2. **The footer**: the stack, the count and size, and the one primary button.
3. **Section headers**: title, counts, Select All/None, the age picker.
4. **The header line**: where it looks and the promise "Nothing moves until you confirm".
5. Notes (Not in search, Search will show this copy, Changed since the list was made): small, inline, only when they
   apply.

## 4. Entry point and menu

- A **"Clean Up…"** item in the status menu, directly under "Process Existing Screenshots…" (both act on files already
  there). Shown once setup is finished; hidden before (polish rule: hide what doesn't apply). No Settings button.
  **[Δ polish: new menu item]**
- It opens the **Clean Up** window (`WindowPresenter`, id `clean-up`), or brings it to the front if it's open. It
  activates Shotkeeper, like Settings.
- Window: title "Clean Up", default content size 680 × 600 pt, minimum 560 × 420, resizable, frame remembered.
- On open: `reconcileTrash()`, then the check (scan) starts at once. Opening an open window doesn't start a new check.

## 5. The Clean Up window

### 5.1 Header (fixed, 52 pt)

```
│ Looks in Desktop and in Screenshots, with its subfolders.                   │
│ Nothing moves until you confirm.                              [Check Again] │
```

| Case | Line 1 | Line 2 |
|---|---|---|
| Both folders | Looks in Desktop and in Screenshots, with its subfolders. | Nothing moves until you confirm. |
| Watched folder only | Looks in Desktop. No organized folder is set. | same |
| Organized folder only | Looks in Screenshots, with its subfolders. No watched folder is set. | same |
| Same folder for both | Looks in Desktop, with its subfolders. | same |

- Folder names are the folders' display names without quotes, as Settings shows them. Full paths in the tooltip.
- **Check Again** (⇧⌘R, `PanelSecondaryButtonStyle`): runs the check again. Ticks on files that are still listed and
  unchanged are kept; Keep choices too.
- Under the header, a 0.5 pt hairline. Banners (§6) go between the header and the list.

### 5.2 Duplicates section

Pinned header (two lines):

```
│ Duplicates                                         [Select All] [Select None] │
│ 9 extra copies in 4 groups, 21.4 MB. One copy in each group is kept.          │
```

- "Duplicates" 13 semibold. Line 2, 12 pt secondary: "<N> extra copies in <G> groups, <size>. One copy in each group
  is kept." ("1 extra copy in 1 group"). The size is the total of the extra copies, ticked or not.
- **Select All** ticks every extra copy that can be ticked; **Select None** unticks all of them. Keep is untouched.
  Both are small secondary buttons, disabled when they would change nothing.
- Duplicate extras are **pre-ticked** (spec).

**Group** (one per set of identical files):

```
│ ▣  Invoice from Acme Cloud Services                    3 copies, 2.4 MB each │
│ ┃  (Keep)  Invoice from Acme Cloud Services.png     Screenshots › Receipts   │
│ ┃                                                          Nov 21, 2026      │
│ ┃  [✓]     Screenshot 2026-11-21 at 15.10.02.png    Desktop    Not in search │
│ ┃                                                          Nov 21, 2026      │
│ ┃  [✓]     Invoice from Acme Cloud Services 2.png   Screenshots › Receipts   │
│ ┃                                                          Nov 23, 2026      │
```

- **Group title row** (52 pt): the group's 44 pt thumbnail (radius 8, thin border, polish list size), the title of the
  copy Shotkeeper indexed (13 semibold, 1 line, tail truncation), and on the right "3 copies, 2.4 MB each" (12 pt
  secondary). The title row isn't tickable: it's a label for the group.
- **Copy rows** (32 pt), indented to the title's left edge, with a 2 pt hairline bracket at the thumbnail's center
  running down the group, so the copies read as one set:
  - column 1 (52 pt): the **Keep pill** or a checkbox;
  - the file name with extension (13 pt, middle truncation, so "… 2.png" stays visible);
  - the folder (12 pt secondary): "Desktop", or inside the organized folder "Screenshots › Receipts" (wave 2's
    form), middle truncation, full path in the tooltip;
  - the date the copy was made (12 pt secondary, "Nov 21, 2026"), right-aligned.
  - A note between folder and date when it applies (11 pt secondary): **Not in search** (rowless copy).
- **Keep pill:** "Keep", 11 pt semibold, indigo text on the indigo tag fill, capsule, 20 pt tall. Tooltip says why
  it's the kept copy:

| Why | Tooltip |
|---|---|
| Restored with Undo | Kept: you restored this copy with Undo |
| Has the search entry | Kept: Shotkeeper named this copy and search shows it |
| In the organized folder | Kept: it's in the organized folder |
| Oldest | Kept: it's the oldest copy |
| Chosen by the user | Kept: you chose this copy |

- **Keep This Copy:** a small secondary button at the row's right end, shown on hover and on the selected row, in
  place of the date. ⌘K and the context menu do the same. It swaps states (§2).
- **Keeping a rowless copy** while the indexed copy is ticked: the kept row's note changes from "Not in search" to
  **Search will show this copy** (11 pt, brand text). If the indexed copy is unticked again, the note goes back.
- **A copy Shotkeeper is still naming** (pending, retrying, or restored without analysis): its checkbox is disabled,
  note **Still being named**. It can still be the Keep copy. **[Δ spec: such copies are shown, not hidden; they can't
  be ticked]**

### 5.3 Never opened section

Pinned header (three lines):

```
│ Never opened                                       [Select All] [Select None] │
│ Taken more than [3 months ⌄] ago and never opened. 38 screenshots, 52.1 MB.    │
│ Shotkeeper has counted opens since Nov 28, 2026. Before that, it relies on     │
│ macOS, which records opens from Finder but not from every app.                 │
```

- Line 2: a sentence with an inline menu `Picker` (choices "1 month", "3 months", "6 months", "1 year"; default 3
  months, remembered). Changing it re-lists this section only, keeping ticks on files still listed. While it
  re-lists, the counts show a 12 pt spinner.
- Line 3 (12 pt secondary): the note. When `opensRecordedSince` is today: "Shotkeeper started counting opens today.
  Before that, it relies on macOS, which records opens from Finder but not from every app."
- **Nothing here is pre-ticked** (spec).

**Row** (56 pt):

```
│ [ ]  ▣  Boarding pass for flight to Lisbon                 Jul 2, 2026   1.1 MB │
│         Screenshots › Travel                                                    │
```

- Checkbox, 44 pt thumbnail, title (13 semibold, 1 line) with the folder under it (12 pt secondary), then "date taken"
  and size right-aligned in fixed columns (12 pt secondary, tabular figures).
- Oldest first (spec).

### 5.4 Rows: selection, ticks and the context menu

- Selection (one row) is the polish spec's indigo tint (14% light, 34% dark, radius 10, inset 4 pt), the same as
  search. Selection never ticks. A click on the checkbox ticks; a click elsewhere on the row selects.
- A ticked row looks like any other row: the checkbox is the state. Nothing is struck through or dimmed, because
  nothing has happened yet.
- **Context menu** on any file row: Tick / Untick, Keep This Copy (duplicates), Quick Look, Reveal in Finder. Quick
  Look and Reveal here don't count as opened (spec story 22, and "anything done inside the Clean Up window").
- **Show Only Ticked** (⌘T): the list shows only ticked rows, in their sections (duplicate groups keep their title
  and Keep row, so the user sees what stays). A line above the list says "Showing the 12 ticked screenshots." and the
  button reads **Show All**. Unticking a row in this view removes it after 0.5 s. **[Δ spec: addition]**

### 5.5 Never-opened note per row (only if the real-Mac test splits the cases)

If research test 8 shows that macOS gives no last-used date at all on some disks (Spotlight off), rows on those disks
get a note under the folder: **macOS keeps no record on this disk** (11 pt secondary, `questionmark.circle`). Until
then there is no per-row note.

### 5.6 Footer (fixed, 54 pt)

```
│ ▣▣▣  12 ticked, 34.2 MB   [Show Only Ticked]                [Move to Trash…] │
```

| State | Left | Right |
|---|---|---|
| Nothing ticked | Nothing ticked (secondary, no stack) | [Move to Trash…] disabled |
| Ticked | stack, "12 ticked, 34.2 MB" (13 pt), [Show Only Ticked] | [Move to Trash…] brand primary |
| Checking before the confirmation (over 0.3 s) | spinner, "Checking 12 files…" | button disabled |
| Moving | "Moving to the Trash: 4 of 12", linear progress bar | [Stop] |
| Done | "Moved 12 screenshots to the Trash." | [Undo All] |
| Done with files left | "Moved 11 screenshots to the Trash. 1 was left in place." | [Undo All] |
| Stopped | "Moved 4 screenshots to the Trash. Stopped, 8 were not moved." | [Undo All] |
| After Undo All | "12 screenshots are back where they were." | (none) |

- **Move to Trash…** is not the window's default button: ↩ never starts it (§11). Its VoiceOver label is "Move to
  Trash, 12 screenshots". **[Δ spec: the count sits next to the button, not in its label, so the action keeps the
  exact name "Move to Trash" from button to toast to Undo]**
- The done line stays until the user ticks something or checks again. **Undo All** here is the same action as the
  toast's and the menu's. **[Δ spec: a third place for Undo All]**

## 6. States

| State | What shows |
|---|---|
| **Checking** (the scan) | Body replaced by a centered block: 20 pt spinner, **Looking through Desktop and Screenshots…**, "1,240 files so far" (secondary), [Stop] (Esc, ⌘.). Second phase: **Comparing 86 possible copies…**, a determinate bar, "31 of 86". Header and footer stay; footer "Nothing ticked". |
| **Check stopped** | Centered: `stop.circle` secondary, **Check stopped**, "Nothing is listed until a check finishes.", [Check Again]. |
| **No folder set** | Centered: `folder.badge.questionmark` secondary, **Choose a folder to clean up**, "Clean Up looks in the watched folder and the organized folder. Neither is set.", [Choose Folders in Settings…] (opens Settings › General). |
| **A folder missing** | Warning banner under the header (`exclamationmark.triangle.fill`, warning text): "Can't find “Screenshots”, so its screenshots aren't listed. Choose it again in Settings." [Open Settings…]. The other folder is listed as usual. If both are missing, the centered state: **Can't find your folders**, "Desktop and Screenshots are missing. Choose them again in Settings." |
| **A folder unreadable** | Same banner: "Shotkeeper can't open “Screenshots”, so its screenshots aren't listed. Allow access in Finder (Get Info › Sharing & Permissions), or choose another folder." (wave 2 wording) |
| **Index empty** | Centered: indigo `viewfinder` (the search panel's empty state), **Nothing to clean up yet**, "Clean Up looks for copies and forgotten screenshots among the ones Shotkeeper has named. It hasn't named any yet.", [Process Existing Screenshots…]. |
| **Index error** | Centered: `exclamationmark.octagon.fill` in error text, **The screenshot index could not be opened** (search's title), "Without it, Clean Up can't tell which screenshots Shotkeeper knows, so nothing is listed." |
| **Nothing in Duplicates** | Under its header: "No duplicates. Every screenshot is the only copy of itself." (secondary, 13 pt, 40 pt tall). Header line 2 and Select buttons hidden. |
| **Nothing in Never opened** | Under its header (picker kept): "Every screenshot taken more than 3 months ago has been opened at least once." |
| **Nothing in either** | Both lines above, footer "Nothing ticked". No separate full-window state, so the age picker stays in reach. |
| **Many results** | Lazy list; pinned section headers; counts with grouping separators ("1,204 screenshots"); header line 2 gains "3,512 files checked at 4:24 PM." Show Only Ticked is the review tool. No pagination, no "show more". |
| **Skipped while listing** | If the plan skipped files (unreadable, still processing), the header line 2 adds: "14 files couldn't be read and aren't listed." / "6 are still being named and aren't listed." Only counts over 0. |
| **List out of date** | Warning banner: "3 screenshots changed since this list was made. They're unticked and can't be ticked until you check again." [Check Again]. Each changed row shows the note **Changed since the list was made** (warning text), its checkbox off and disabled. A changed duplicate group's whole group is locked the same way. **[Δ spec: changed rows are unticked automatically]** |
| **Out of date, other changes** | New screenshots or settings changes that don't touch a listed row: "Files changed since this list was made. Check again to include them." [Check Again]. Nothing is unticked. |
| **Moving** | List dimmed to 50% and disabled. Footer progress (§5.6). Closing the window doesn't stop the run; the toast reports. |
| **Finished** | Moved rows leave the list. A group with only its kept copy left leaves the list. Files left in place stay, unticked, with the note **Left in place: <reason>** (warning text). Footer done line. |

Readable reasons (left in place, toast sublines, row notes). One wording, used everywhere:

| Reason (core) | Text |
|---|---|
| `changedSinceListed` | changed since the list was made |
| `missing` | no longer there |
| `outsideFolders` | no longer in your folders |
| `keptCopyMissing` | the kept copy is gone |
| `keptCopyDiffers` | the kept copy is no longer identical |
| `stillProcessing` | Shotkeeper is still naming it |
| `restoredByUndo` | you restored it with Undo |
| failed, `noTrashOnVolume` | its disk has no Trash |
| failed, permission | Shotkeeper isn't allowed to move it |
| failed, undo record not written | Undo couldn't be recorded, so it was moved back |
| `trashedWithoutLocation` | it's in the Trash, but Undo can't find it. Put it back from the Trash in Finder. |
| failed, other | it couldn't be moved (<short readable error>) |

## 7. The confirmation

A native sheet alert on the Clean Up window (wave 2 used one for Sort).

```
┌──────────────────────────────────────────┐
│               ▣▣▣  (the stack, 64 pt)    │
│                                          │
│     Move 12 screenshots to the Trash?    │
│                                          │
│  9 extra copies and 3 screenshots you    │
│  never opened, 34.2 MB.                  │
│                                          │
│  Undo in the Shotkeeper menu puts them   │
│  back where they were, with their names  │
│  and tags, while they're in the Trash.   │
│  Shotkeeper never empties the Trash.     │
│                                          │
│  1 changed since the list was made and   │
│  will be left in place.                  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │              Cancel                │  │  ← default (↩), Esc
│  └────────────────────────────────────┘  │
│  ┌────────────────────────────────────┐  │
│  │           Move to Trash            │  │  ← destructive (red text), ⌘⌫
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

- Before it opens, the dry run runs (spec). The counts in the alert are what **will** move, so the title can say 11
  while 12 are ticked, and the surprise line says why.
- **Default button: Cancel.** Moving to the Trash is the most consequential action in the app, and the confirmation
  exists to catch a press the user didn't mean. ↩ arriving from habit (the press that opened the sheet, a key held
  down) lands on Cancel. Move to Trash takes a click, ⌘⌫ (Finder's key for this action), or Tab and Space with
  Keyboard navigation on. **[Δ wave 2: Sort's alert has Sort as default]**
- **⌘⌫ guard:** in the alert, ⌘⌫ is ignored for its first 0.5 s and when it's a key repeat, so holding or
  double-tapping the key that opened the sheet can't confirm it.
- Move to Trash uses the alert's destructive style (`hasDestructiveAction`, red text), not indigo: the alert is
  native, and the polish spec's indigo is for our own panels.

| Part | Text |
|---|---|
| Icon | the stack of the first three files that will move (one thumbnail for one file) |
| Title, several | Move 12 screenshots to the Trash? |
| Title, one | Move “Invoice from Acme Cloud Services” to the Trash? |
| What, both kinds | 9 extra copies and 3 screenshots you never opened, 34.2 MB. |
| What, copies only | 9 extra copies, 21.4 MB. The kept copy in each group stays where it is. |
| What, never opened only | 3 screenshots you never opened, 12.8 MB. |
| What, one | 2.4 MB. (for a copy: "The kept copy stays in “Screenshots › Receipts”.") |
| Way back | Undo in the Shotkeeper menu puts them back where they were, with their names and tags, while they're in the Trash. Shotkeeper never empties the Trash. (one file: "puts it back … while it's in the Trash") |
| Surprises, each only when over 0 | 1 changed since the list was made and will be left in place. · 2 are on a disk without a Trash and will be left in place. · The kept copy of 1 is gone, so its copy will be left in place. · 1 is no longer there. · 4 are in iCloud Drive, which deletes them from the Trash after 30 days. |
| Buttons | Cancel (default, ↩, Esc) · Move to Trash (destructive, ⌘⌫) |

- The way-back line promises **Undo**, not Finder's Put Back: Put Back is best-effort for batches (research note,
  Apple bug r. 23153124). Finder isn't mentioned, so nothing is promised that might not work.
- The iCloud line uses "deletes" on purpose: it's iCloud's rule, and the user must know it's permanent.
- Surprise sentences each start on a new line, as wave 2's alert does.

**Nothing would move** (every ticked file fails a check): no confirmation. An informational alert instead:

| Part | Text |
|---|---|
| Title | Nothing can be moved to the Trash |
| Message | The 3 ticked screenshots changed since the list was made. (or one line per reason, as above) |
| Buttons | Check Again (default) · Cancel |

## 8. Toasts

The existing batch layout (stack, title, subline, buttons, countdown, 4 s, paused on hover). Clean-up toasts show
**even when "Show a toast after each rename" is off**: the user asked for this move, so the answer isn't an
unrequested confirmation (wave 2's rule for Analyze Again results). **[Δ polish: setting scope]**

### Moved to the Trash

| Case | Title | Subline | Buttons |
|---|---|---|---|
| All moved | Moved 12 screenshots to the Trash | Undo puts them back where they were | Undo All |
| One file | Moved “Invoice from Acme Cloud Services” to the Trash | Undo puts it back in “Desktop” | Undo |
| Some left, one reason | Moved 11 screenshots to the Trash | 1 was left in place: changed since the list was made | Undo All |
| Some left, several reasons | Moved 9 screenshots to the Trash | 3 were left in place. Clean Up shows why. | Undo All |
| Stopped | Moved 4 screenshots to the Trash | Stopped. 8 were not moved. | Undo All |
| One in the Trash without a location | Moved 12 screenshots to the Trash | 1 is in the Trash, but Undo can't find it. Put it back from the Trash in Finder. | Undo All |
| None moved | error toast: "No screenshots were moved to the Trash: their disk has no Trash." / "…: 3 changed since the list was made." | | |

- **Undo All is the only button**, secondary style. "View in Search" doesn't apply: the files are gone from search.
  **[Δ polish: batch toast without its primary button]**
- Tooltip on Undo All: "Move them all back from the Trash".
- Thumbnails: the stack of the moved files.
- Sublines are 2 lines at most (the batch toast's 1 line becomes 2 here, so reasons don't truncate).

### Moved back (after Undo)

Label `arrow.uturn.backward` **Moved back**, as wave 2's sort undo. Not "Put back": that is Finder's command, and this
is Shotkeeper's Undo.

| Case | Title | Subline |
|---|---|---|
| All | 12 screenshots are back where they were | They're in search again with their titles and tags. |
| One | Invoice from Acme Cloud Services | Back in “Desktop”. |
| Some failed | 10 of 12 screenshots are back | 2 couldn't be moved back: no longer in the Trash. (several reasons: "2 couldn't be moved back: one is no longer in the Trash, one's name is taken.") |

A rowless duplicate comes back without a search entry, as before (spec). The subline still says "in search again"
for the batch only when at least one moved-back file has a row; otherwise "They're back as they were."

### Can't move back (error toast)

| Case | Title | Button |
|---|---|---|
| Trash emptied, one | Can't move “Invoice from Acme” back. It's no longer in the Trash; the Trash may have been emptied. | (none) |
| Trash emptied, all of a batch | Can't move the 12 screenshots back. They're no longer in the Trash; the Trash may have been emptied. | (none) |
| Name taken | Can't move “Invoice from Acme” back. A file named “Invoice from Acme.png” is already in “Desktop”. The screenshot is still in the Trash. | Reveal in Finder |
| Folder gone | Can't move “Invoice from Acme” back. The folder “Receipts” no longer exists. The screenshot is still in the Trash. | Reveal in Finder |
| Can't reach the Trash (`EPERM`) | Can't reach the Trash to move “Invoice from Acme” back. Nothing changed. Undo is still in the menu. | (none) |

- **Reveal in Finder** shows the file in the Trash (Finder selects it), so the user can rename what's in the way or
  drag it somewhere else. It uses the error toast's button slot. **[Δ polish: the error toast's button is not "Fix
  Settings…"]**
- Shotkeeper never recreates a folder the user deleted (research note): "Folder gone" is an answer, not a retry.
- "Trash emptied" removes the record from the menu's Undo (spec: `gone` line). "Name taken", "Folder gone" and
  `EPERM` keep it undoable.
- **No macOS record** isn't an undo state: it's covered by the Never opened section note (§5.3).

## 9. Menu bar

```
│ Undo Move to Trash: 12 screenshots                 ⌘Z │
│ Pause for 10 Minutes                                  │
│ Process Existing Screenshots…                         │
│ Clean Up…                                             │
```

- **Undo label grammar:** "Undo <action>: <object>", extending wave 2's "Undo Move: <title>":
  - **Undo Move to Trash: 12 screenshots** (batch), **Undo Move to Trash: Invoice from Acme** (one file);
  - wave 2's sort batch: **Undo Sort: 180 screenshots**.
  - It names the action the user pressed, word for word, which Finder does too ("Undo Move to Trash" in its Edit
    menu). **[Δ spec: the spec's example was "Undo: Move to Trash (12 screenshots)"; the spec asked the design pass to
    check this]**
- While moving: status line 2 "Moving to the Trash: 8 left" and an item **Stop Moving to Trash** under Clean Up…,
  like wave 2's sorting. **[Δ polish: status line state and item]**
- Last message after a run: the toast title ("Moved 12 screenshots to the Trash").

## 10. Undo from the window

- ⌘Z in the Clean Up window runs the menu's Undo (the last batch), so the key Finder users press after Move to Trash
  works where they are.
- After an Undo All of a clean-up batch while the window is open, the window checks again by itself (the files are
  back, so they belong in the list again), and the footer says "12 screenshots are back where they were."

## 11. Keyboard and VoiceOver

### Keys (Clean Up window)

| Key | Action |
|---|---|
| ↑ ↓ | Move the selection through file rows (headers and group titles are skipped) |
| Space | Tick or untick the selected row. On a Keep row or a locked row: beep, and VoiceOver says why |
| ⌘K | Keep This Copy (selected duplicate) |
| ⌘Y | Quick Look the selected file (doesn't count as opened) |
| ⌘R | Reveal in Finder (doesn't count as opened) |
| ⌘A | Select All in the selected row's section |
| ⇧⌘A | Select None in the selected row's section |
| ⌘T | Show Only Ticked / Show All |
| ⇧⌘R | Check Again |
| ⌘⌫ | Move to Trash… (opens the confirmation; beeps at 0 ticked) |
| ⌘Z | Undo the last clean-up (as the menu) |
| Esc, ⌘. | Stop, while checking or moving |
| ↩ | Nothing (no default button in this window) |
| ⌘W | Close |

- **Space ticks, it doesn't Quick Look** (spec). That differs from Finder and from Shotkeeper's search panel. The
  footer hint makes it visible (next bullet).
- **No default button.** appkit-gotchas recommends a `.defaultAction` so a screen works without Tab. Here that would
  make ↩ start the most consequential action. Every action has a key above instead. **[Δ appkit-gotchas advice,
  recorded]**
- Key hints: the polish spec's keycap row at the left of the footer would crowd the stack, so the hints live in the
  tooltips ("Tick or untick (Space)", "Keep This Copy (⌘K)", "Move to Trash (⌘⌫)") and in the context menu's key
  equivalents.
- With the confirmation open: ↩ and Esc → Cancel; ⌘⌫ → Move to Trash (with the guard, §7); Tab with Keyboard
  navigation on.
- **Full Keyboard Access order:** Check Again → banner button → list → section buttons (Select All, Select None, age
  picker) as they come → Show Only Ticked → Move to Trash… / Stop / Undo All.

### VoiceOver

- Each duplicate group is a container: "Duplicate group, Invoice from Acme Cloud Services, 3 identical copies, 2.4 MB
  each".
- Copy row: "Invoice from Acme Cloud Services 2.png, in Screenshots, Receipts, Nov 23, 2026, ticked". Kept row:
  "…, kept". Rowless: "…, not in search". Custom actions: Keep This Copy, Quick Look, Reveal in Finder.
- Never-opened row: "Boarding pass for flight to Lisbon, taken Jul 2, 2026, Screenshots, Travel, 1.1 MB, not ticked".

| Moment | Announcement |
|---|---|
| Check finished | "Found 9 duplicate copies and 38 screenshots never opened." / "Nothing to clean up." |
| Tick, untick | "Ticked. 13 ticked, 35.4 MB." / "Unticked. 12 ticked, 34.2 MB." |
| Space on Keep | "This copy is kept. Keep another copy to tick this one." |
| Keep changed | "Keeping the copy in Desktop. The copy in Screenshots, Receipts is ticked." (or "…is not ticked.") |
| Out of date | the banner text |
| Moving | "Moving to the Trash" (once), then the result |
| Result | the toast title and subline |
| Moved back / can't move back | the toast text |

## 12. Light and dark

- Same structure in both modes; only semantic colors change.
- Window background: system window background. Pinned section headers use the same background with a 0.5 pt hairline
  under them when content scrolls beneath.
- Selected row: indigo 14% (light) / 34% (dark). Keep pill: indigo text (#4644C0 / #A5A4FF) on indigo 12% / 22%,
  at least 4.5:1.
- Checkboxes, the picker, the progress bar and focus rings use the system accent color (polish spec: normal controls).
  Move to Trash… is brand indigo with white text (5.1–5.7:1).
- Warning banner: warning text (#8A4600 / #FFB340) on orange 10% / 14%. Notes "Changed since the list was made" and
  "Left in place: …" use warning text.
- The group bracket and separators: label 10%.
- The confirmation alert is fully native and follows the system.
- Snapshots draw opaque backgrounds (existing `opaqueBackground`); the toast material is checked on a Mac.

## 13. Real-Mac checks and CI snapshots

**Real Mac:**
- The alert's Cancel default with ↩, Esc; ⌘⌫ guard (held key, double tap); the stack as the alert icon.
- Space ticking in the `List` (it doesn't trigger Quick Look or scroll); ⌘Y Quick Look from a regular window, and that
  it doesn't set `last_opened_at`.
- Pinned section headers with the inline picker; scrolling 1,000 rows.
- Both settings of Keyboard navigation (appkit-gotchas): every action reachable.
- Toasts while the window is front; ⌘Z in the window; "Reveal in Finder" selecting a file in the Trash.
- VoiceOver announcements from §11.

**New CI snapshot states** (light and dark, one file per screen in `UISnapshotTests`):
- `cleanup-list` (both sections, one group with a rowless copy, selection), `cleanup-list-keep-rowless`,
  `cleanup-list-only-ticked`, `cleanup-list-many`;
- `cleanup-checking`, `cleanup-comparing`, `cleanup-check-stopped`;
- `cleanup-no-folders`, `cleanup-folder-missing`, `cleanup-folder-unreadable`, `cleanup-index-empty`,
  `cleanup-index-error`;
- `cleanup-empty-duplicates`, `cleanup-empty-never-opened`, `cleanup-empty-both`;
- `cleanup-out-of-date`, `cleanup-moving`, `cleanup-finished`, `cleanup-finished-left`, `cleanup-stopped`;
- `cleanup-confirm`, `cleanup-confirm-surprises`, `cleanup-confirm-one`, `cleanup-nothing-can-move`;
- `toast-trash-batch`, `toast-trash-one`, `toast-trash-left`, `toast-trash-stopped`, `toast-trash-none`;
- `toast-moved-back-trash`, `toast-moved-back-partial`, `toast-cant-move-back-emptied`,
  `toast-cant-move-back-name-taken`, `toast-cant-move-back-folder-gone`;
- `menu-undo-trash`, `menu-moving-to-trash`.

## 14. Departures

Against the polish spec ([../specs/ui-polish-2026-11.md](../specs/ui-polish-2026-11.md)):

1. A new menu item "Clean Up…" under Process Existing Screenshots….
2. The menu's undo label becomes "Undo Move to Trash: 12 screenshots" for a clean-up batch (and "Undo Sort: 180
   screenshots" for wave 2's sort batch).
3. The menu status line gains "Moving to the Trash: N left", plus a "Stop Moving to Trash" item.
4. Clean-up and undo toasts show even with "Show a toast after each rename" off.
5. The clean-up batch toast has Undo All only (no "View in Search"), and its subline may take 2 lines.
6. The error toast's button can be "Reveal in Finder", not only "Fix Settings…".
7. The window's key hints are in tooltips and the context menu, not a keycap row.

Against the clean-up spec ([../specs/clean-up-2026-11.md](../specs/clean-up-2026-11.md)):

1. One thumbnail and one size per duplicate group, not per copy (the copies are identical).
2. "macOS has no record" is said once in the Never opened note, not per file (the research note shows it would be on
   every row). A per-row note returns only if the real-Mac test splits the cases.
3. The ticked count sits beside Move to Trash…, not inside its label.
4. Menu undo wording "Undo Move to Trash: 12 screenshots" instead of "Undo: Move to Trash (12 screenshots)".
5. Undo All also in the window footer after a run, and ⌘Z in the window.
6. Rows that changed while the list was open are unticked and locked until Check Again (the spec only asks to flag it
   and offer a refresh).
7. A "Show Only Ticked" view (addition).
8. Copies still being named are shown in their group with a disabled checkbox, not left out.
9. The confirmation's Move to Trash key is ⌘⌫, ignored for 0.5 s and on key repeat.
10. Two undo messages the spec doesn't list, from the research note: "the folder no longer exists" and "can't reach
    the Trash".
11. Reveal in Finder from the list (does not count as opened).

Against the wave 2 design ([subfolders-and-retitle.md](subfolders-and-retitle.md)):

1. The confirmation's default button is Cancel; wave 2's Sort alert defaults to Sort.

Against [../wiki/appkit-gotchas.md](../wiki/appkit-gotchas.md) advice:

1. No `.defaultAction` in the window, on purpose: ↩ must never start Move to Trash. Every action has a key instead.
