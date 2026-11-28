# Wave 1: search filters and Copy Text (2026-11-28)

Implementation notes and departures for the [wave 1 spec](../specs/search-filters-and-text-2026-11.md) (on
`t3/roadmap-2026-11`, PR #12, until it merges) and the approved [design](../design/search-filters-and-text.md).
Tickets in `../specs/search-filters-and-text-2026-11/tickets/`. Integration branch `t3/wave1-search`. API map:
[../core-api.md](../core-api.md). The spec's requirements are not edited; deviations go here.

## Ticket 01: migration 3, recognized-text columns, FTS (2026-11-28, PR #13)

### Decisions
- 2026-11-28 (`c1c79ce`, ticket 01): **deviation from the spec: one migration, not two.** The spec gives filters and
  OCR one migration each, with whichever merges second renumbering. Ticket 01 owns the only wave 1 migration
  (version 3). It adds the four text columns, rebuilds FTS and creates the filter indexes, so tickets 02 and 03 add no
  migration and no two wave 1 tickets claim a version number in parallel. Reason: the ticket split (2026-11-28).
- 2026-11-28 (`c1c79ce`): **migration 3.** It runs `addColumns("recognized_text", "text_status", "text_recognized_by",
  "text_error")`, then drops the three FTS triggers and `screenshots_fts` and creates them again with `recognized_text`
  as the sixth FTS column (`AFTER UPDATE OF` lists it). Next it runs the FTS5 `'rebuild'` command
  (https://www.sqlite.org/fts5.html, "The 'rebuild' Command") and creates three indexes:
  - `screenshots_taken_at` on `COALESCE(captured_at, processed_at)`. The date filter (02) must use exactly that
    expression, or SQLite does not use the index.
  - `screenshots_source_app_or_site`.
  - `screenshots_text_pending`, a partial index `WHERE text_status = 'pending'`.

  Rows from before the migration keep every value, get NULL text columns (not requested), and are found by FTS again.
- 2026-11-28 (`c1c79ce`): **one FTS list.** `ScreenshotIndex.ftsColumns` holds the FTS columns with their bm25
  weights (10, 6, 3, 1, 2, 0.5). The FTS table, its triggers (`rebuildFTS(_:)`) and `bm25Weights` are built from it.
  Migration 1 keeps its literal SQL (shipped). A later change to the list needs a new migration that rebuilds FTS,
  and migration 3 then needs its own frozen copy of today's list.
- 2026-11-28 (`c1c79ce`): **`TextStatus.noText` is stored as `none`.** The spec's value is `none`, but a Swift case
  named `.none` on `TextStatus?` would read as Optional's nil in `textStatus == .none`.
- 2026-11-28 (`c1c79ce`): **the conditional write.** `setRecognizedText(_:recognizedBy:id:ifContentHash:)` updates
  only the four text columns, and only while `content_hash` and `text_status = 'pending'` still match. It returns
  whether it applied and publishes `.updated` only then. The written state depends only on the result:
  - `.text`: `done`, with the text and `text_error` NULL.
  - `.noText`: `none`, with both NULL.
  - `.failed(reason:)`: `failed`, with the text NULL and the reason in `text_error`.

  `text_recognized_by` is set for every result, failures included. The analysis and `status` are never touched.
  Recognized text goes only into `recognized_text`: the doc comments say a failure reason never contains it, and the
  index logs nothing.
- 2026-11-28 (`c1c79ce`): `newestPendingTextRow()` orders by `COALESCE(captured_at, processed_at)` DESC, then id
  DESC (spec: newest `pending` first).
- 2026-11-28 (`c1c79ce`): **`save` writes the text columns like every column.** A fresh `IndexedScreenshot` built
  without them clears a row's text and status. That is the spec's intent: the processor (ticket 04) sets `pending`
  on a new analysis. Until 04 lands, re-processing a file leaves its text status NULL.

### Verification
- 2026-11-28 (`c1c79ce`): `SCRATCH=.build/linux-w1-01 scripts/test-linux.sh` green, 420 tests (412 before). Checked
  by hand that the new tests fail without the change they cover:
  - recognized-text weight raised from 0.5 to 20: the ranking test fails;
  - `'rebuild'` removed: the version-2 migration test fails;
  - `recognized_text` left out of `AFTER UPDATE OF`: the conditional-write search test fails.
- 2026-11-28: PR #10's `scripts/lint.sh` (run from its branch) reports only the existing violations in files this
  branch does not touch, none in the changed files.

## Ticket 02: date filter (2026-11-28, PR #16, branch `t3/w1-02-date-filter`)

### What was built
- Core `DateFilter` (`Sources/ShotkeeperCore/Search/DateFilter.swift`): `.today`, `.yesterday`, `.last7Days`,
  `.last30Days`, `.days(from:through:)` over `CalendarDay` (year, month, day). `interval(now:calendar:)` gives
  `[start of first day, start of the day after the last)` via `Calendar.startOfDay`, so a DST day is one whole local
  day (23 or 25 hours). A reversed custom range is swapped when resolved; the stored filter keeps the user's order.
- `ScreenshotQuery.date`; `ScreenshotIndex.search(_:limit:now:calendar:)` adds
  `COALESCE(captured_at, processed_at) >= ? AND < ?` and resolves "today" on each call. The app passes the search
  model's `now()` and `time.calendar` (see "one clock and calendar" below).
- `SearchWindowState`: `date`, `setDateFilter(_:)`, `clearFilters()`, `datePicker` (core `DatePickerState`), the
  Date pill's title/value/tooltip, `noMatchButtons` and `help(for:)`, `Announcement` strings, and `now`/`time` for date
  wording (the view model sets `now` before each search).
- `SearchKeyMap`: ⌘D (`.dateFilter`, character `d`, physical key 2) and ⌫ (`.deleteBackward`, plain key 51).
- App: `SearchFilterViews.swift` holds `FilterPill`, `DateFilterPill`, `InPanelPicker` (the shared in-panel list
  container), `PickerRow` and `DatePickerPanel`. `SearchView` adds the pill to row 2, the picker overlay (anchored to
  the pill by `FilterPillAnchorKey`) and the no-match buttons. `SearchPanelController.handleInDatePicker` routes keys
  while the picker is open. Ticket 03 adds `SearchFilterKind.source` and its pill and picker on the same pieces.

### Decisions and departures
- 2026-11-28: **Esc order** is: close an open picker, then clear text, chip and date in one press, then close the
  panel (`SearchWindowState.escape()`, `EscapeOutcome.closedPicker`). Design §6 [Δ polish].
- 2026-11-28: **the picker's state is in core** (`DatePickerState`: highlight, custom range shown, From/To days), not
  only in the view, so the keys, Esc order and ⌫ are tested on Linux (`SearchDatePickerTests`).
- 2026-11-28: **order with a date filter and no text is newest *taken* first**
  (`COALESCE(captured_at, processed_at) DESC`), so the list agrees with the times its rows show. Without a date filter
  the approved "Recent" order (most recently processed first) is unchanged. Without this, an old screenshot run through
  Process Existing today would sort above today's screenshots in "Last 30 days" while its row says "Nov 14".
- 2026-11-28: **"Text and any filter" in design §5 is read as "text and a date (or, after 03, a source)".** Text plus
  only a type chip keeps the approved polish-spec state ("Try other words…", one "Clear search" button), as the
  existing `testNoMatchEmptyIndexAndClearSearch` pins. With a date filter: filters only → "Clear filters"; text and
  filters → "Clear filters" then "Clear search".
- 2026-11-28: custom range VoiceOver value is "October 3 to October 17" (one day: "October 3"). The design gives
  values only for the presets.
- 2026-11-28: range labels use `DateIntervalFormatter` (template `MMMd`, or `yMMMd` when a day is outside the current
  year) in core `TimeLabel.days`; swift-corelibs on Linux gives the design's "Oct 3 – 17", "Oct 28 – Nov 3",
  "Dec 28, 2025 – Jan 4, 2026" (tests normalize the thin spaces ICU puts around the dash).
- 2026-11-28: ⌫ is a plain key in `SearchKeyMap`; the controller returns false for it (the field deletes) unless the
  date list is open. While the custom range is shown, ↑/↓, ⌫ and Space go to the focused date field and ↩ is Apply.
- 2026-11-28: with a picker open, ⌘1–7, ⌘R, ⌘Y and Space (in the list) are swallowed; ⌘C is passed on (it may copy
  a date field's selected text) and never copies the image behind the picker.
- 2026-11-28: the type chips keep their own VoiceOver container "Type"; the Date pill sits outside it in row 2.
- 2026-11-28: no SQL index is added here: ticket 01 (PR #13) owns the one migration with the
  `COALESCE(captured_at, processed_at)` expression index, `screenshots_taken_at`.
- 2026-11-28 (merge of `t3/wave1-search` into this branch): **the date filter uses `screenshots_taken_at`.** The filter
  and its order use `COALESCE(s.captured_at, s.processed_at)`, the index's expression. `ScreenshotIndex.searchSQL`
  (internal) builds the statements `search` runs; `DateFilterQueryPlanTests` runs `EXPLAIN QUERY PLAN` on them over a
  migrated file index. Result (SQLite in the `swift:6.4.3-noble` image):
  - date only, and date with a type chip, both the page and the count:
    `SEARCH s USING INDEX screenshots_taken_at (<expr>>? AND <expr><?)`, no `USE TEMP B-TREE FOR ORDER BY` (newest
    taken first is read from the index);
  - text and a date: `SCAN screenshots_fts VIRTUAL TABLE INDEX 0:M6`, `SEARCH s USING INTEGER PRIMARY KEY`, then a temp
    B-tree for the bm25 order. FTS narrows first and the date is checked per match; expected, not asserted.

  Checked that the test fails when the expression is changed to `COALESCE(s.processed_at, s.captured_at)` (plan
  becomes `SCAN s` with a temp B-tree).
- 2026-11-28: **one clock and calendar for the index and the panel** (review should-fix). `SearchViewModel` passes
  its `now()` (the same instant it stores in `state.now` for the wording) and `time.calendar` to the search function,
  which calls `index.search(_:limit:now:calendar:)`. The model's default `TimeLabel` uses
  `Calendar.autoupdatingCurrent`, so a time-zone change while the app runs moves "today" for the rows and the pill
  alike. Before, the index used `Calendar.current` per call and the panel a `TimeLabel()` calendar captured at launch.
- 2026-11-28: a custom range across years reads both years to VoiceOver ("December 28, 2025 to January 4, 2026"),
  like `takenPhrase`; `TimeLabel.day(_:now:alongside:spelled:)` gives both.
- 2026-11-28: the date picker hangs 6 pt under row 2 (design): the pill's bottom + row 2's 8 pt bottom padding + 6.

### Real-Mac checks (CI can't see these)
- The picker opens without activating Shotkeeper or taking key status from the panel; a click outside it (inside the
  panel) closes it; clicking another app hides the panel and the picker.
- Focus: the date list takes the focus when it opens (typed letters don't edit the search text behind it), the From
  field takes it when the custom range expands, and the search field gets it back when the picker closes.
- ⌘D on QWERTY, Dvorak and Russian layouts; ⌫ in the date list clears the date; ⌫ in the field still deletes.
- `DatePicker(.field)` editing inside the non-activating panel: digits, ↑/↓ on the focused part, Tab From → To →
  Apply, ↩ applies.
- ↩ applies a value just typed into a date field (type a day, press ↩ at once, without Tab): the range searched is
  the typed one, not the field's previous value.
- VoiceOver reads the pill as "Date, any time" / "Date, last 7 days", the ✕ as "Clear date", and announces "Date
  cleared", "Filters cleared" and "Search cleared".

## Ticket 03: source filter (2026-11-28, branch `t3/w1-03-source-filter`)

### What was built
- Core `SourceKey` and `SourceFacet` (`Sources/ShotkeeperCore/Search/SourceKey.swift`), a public API so wave 2's
  ticket 04 can reuse the rule that "x.com" and "X" are one source. `ScreenshotIndex.sources()`; `ScreenshotQuery.source`
  and its filter in `search`.
  `SourceKey.rawValue` is a matching key only, never a display or folder name (it is lowercased, folded and may have
  lost its domain); folder and display names come from `SourceFacet.displayName`.
- `SearchWindowState`: `source`/`sourceName`, `setSource(_:)`, the loaded list (`sources`, `setSources(_:)`), the Source
  pill wording, and the picker (`SourcePickerState` in `Search/SourcePicker.swift`, beside `DatePickerState`).
  `SearchKeyMap`: ⌘S (`.sourceFilter`, character `s`, physical key 1).
- App: `SearchSourceFilterViews.swift` (`SourceFilterPill`, `SourcePickerPanel`) on ticket 02's `FilterPill`,
  `InPanelPicker` and `PickerRow` (which gained a count, a VoiceOver label and a tooltip; `FilterPill` gained `maxWidth`
  and `isDisabled`). `SearchView` hangs either picker with one helper. `SearchPanelController.handleInSourcePicker`
  routes keys while it is open. `SearchViewModel.reloadSources()` runs on each `show()` (and `showBatch` when the panel
  was hidden), off the main actor.

### Decisions and departures
- 2026-11-28: **the normalization rule** (`SourceKey`). Trim, fold case and diacritics, drop a leading `www.`; when what
  is left is one name plus one top-level domain, drop the domain. "One top-level domain" is read as: exactly two
  dot-separated labels, no whitespace, the last label two or more ASCII letters. So `x.com` → `x`, `github.com` →
  `github`, `www.nytimes.com` → `nytimes`; `bbc.co.uk` and `docs.google.com` stay as they are. No alias table (Twitter
  ≠ X). Without a TLD list, a name like "Node.js" also becomes `node` (it only merges with a source spelled "Node").
  Tests go through `sources()` (`SourceListTests`).
- 2026-11-28 (review fix): the rule also folds width ("ＧｉｔＨｕｂ" = "GitHub", "ｘ.ｃｏｍ" → `x`) and collapses runs of
  whitespace to one space ("Google  Chrome" = "Google Chrome"); ß folds to "ss", dotted İ to i, dotless ı stays its
  own letter. The top-level-domain step skips a first label containing `:` or `/`, so "https://github.com" stays a URL
  instead of becoming `https://github`. Tests: `testFullWidthLettersAreFolded`, `testRunsOfWhitespaceCollapseToOneSpace`,
  `testUnicodeEdgeCasesKeepTheirMeaning`, `testAURLKeepsItsDomain`. `reloadSources()` cancels the previous load first.
- 2026-11-28 (wave 2 PR #30 review fix): `SourceKey.fold` also drops invisible format characters (general category
  Cf: U+200E, U+200F, U+061C, U+FEFF, U+00AD, U+2060, …), so "\u{200E}Slack" = "Slack" and the list shows no look-alike
  duplicates. U+200C/U+200D are kept so emoji ZWJ sequences survive. They are removed per word after the whitespace
  split, so a lone mark between spaces leaves one space. Tests: `testInvisibleFormatCharactersAreFoldedAway`,
  `testEmojiZWJSequencesAreKept`. U+200C has no test: swift-foundation's diacritic folding on Linux already drops it
  before this step (macOS not checked). The display name is still the most common trimmed raw spelling, marks included.
- 2026-11-28: the display name is the most common **trimmed** spelling ("Slack " and "Slack" count as one spelling).
  "Alphabetical" for the tie-break and the list's name order ignores case and diacritics, then falls back to Unicode
  order, so it never depends on the locale.
- 2026-11-28: the filter resolves the key against the raw spellings of rows **of any status**, then the query keeps
  `done` rows. `SELECT DISTINCT source_app_or_site` reads only the `screenshots_source_app_or_site` index, and the filter
  itself uses that index (`SourceFilterQueryPlanTests`; checked that `LOWER(...)` on the column makes it `SCAN s`).
- 2026-11-28: **a source with no text lists newest taken first**, like a date (ticket 02's rule): the footer then says
  "N of M", not "Recent", and the list agrees with the times its rows show.
- 2026-11-28: the Source pill is disabled only when the loaded list is empty **and** no source is chosen. Not before the
  list has loaded (nil), so it doesn't flash disabled, and never while a source is chosen, so a gone source can always
  be cleared. ⌘S on a disabled pill beeps and is consumed (it never reaches the menu).
- 2026-11-28: a disabled SwiftUI button shows no tooltip, so the disabled pill's reason is set on the pill's capsule
  (`help(ifSet:)`). Real-Mac check below.
- 2026-11-28: **the chosen source keeps its name** in the state (`sourceName`). When the reloaded list still has it, the
  name follows the list's display name; when it is gone, the pill, the picker's pinned row (count 0, checked) and the
  no-match sentence keep the old name.
- 2026-11-28: while narrowing, "Any source" is hidden, so the first match is the first row and "sl ↩" picks Slack. The
  pinned gone source is narrowed like the others. ↩ with no match does nothing and leaves the picker open. The narrow
  field starts empty each time the picker opens. When the list reloads while the picker is open, the highlighted row is
  kept if it is still there.
- 2026-11-28: **keys while the source picker is open:** ↑/↓ move, ↩ chooses, Esc closes (core Esc order), ⌫ clears the
  source only when the narrow field is empty (else it deletes), Space and ⌘C go to the narrow field, ⌘S closes, ⌘D
  switches to the date picker (and ⌘S in the date picker switches back), ⌘R/⌘Y/⌘1–7 are swallowed. One picker at a time:
  opening one closes the other (`isPickerOpen`, `closePickers()`).
- 2026-11-28: **IME in the narrow field** needs no new code: `SearchPanel.sendEvent` and `performKeyEquivalent` skip the
  key handler while the first responder has marked text, and the narrow field's field editor is then the first
  responder. The narrow field has no `onSubmit`; ↩ is handled only by the panel, so ↩ in the candidate list commits the
  text and never chooses a source. Real-Mac check below.
- 2026-11-28: no-match wording follows design §5: "No screenshots from Slack", "No screenshots from Slack taken in the
  last 7 days", "No Receipt screenshots from Stripe taken in the last 30 days"; with text, "Your filters limit this
  search to screenshots from X." A source counts like a date for the buttons ("Clear filters", plus "Clear search" with
  text). A chip alone keeps the approved states.
- 2026-11-28: the Source pill's VoiceOver value when disabled is the reason ("No screenshot has an app or site yet.");
  VoiceOver adds "dimmed" itself. "Source cleared" is announced for the ✕ and for ⌘S ⌫.

### Real-Mac checks (CI can't see these)
- The narrow field takes the focus when the picker opens (typed letters don't edit the search text) and the search field
  gets it back when it closes, by a choice, Esc, ⌘S or a click outside.
- Japanese IME in the narrow field: type "すらっく", ↩ in the candidate list commits and does not choose a source; the
  next ↩ chooses the highlighted one.
- ⌘S on QWERTY, Dvorak and Russian layouts; ⌘S beeps when the pill is disabled; ⌘S ⌫ clears the source; ⌫ with text in
  the narrow field deletes a letter.
- VoiceOver: the pill reads "Source, any source" / "Source, Slack"; picker rows read "Slack, 64 screenshots" with the
  selected trait on the current one; "Source cleared" is announced.
- The disabled pill shows its tooltip on hover; a long name truncates at 180 pt and shows the full name on hover.
- The list scrolls with ↑/↓ past the eighth row.

## Ticket 06: Copy Text (⇧⌘C and the badge) (2026-11-28, branch `t3/w1-06-copy-text`)

### What was built
- Core: `SearchResultItem` carries `recognizedText`, `textStatus` and `textError`. `SearchWindowState.copyTextOutcome`
  (`CopyTextOutcome`: copy / read first / no text / failed with "file missing" told apart / wait / not available),
  `copyTextBadge` (`CopyTextBadge`: Copy Text, Reading text…, Read text again, with their tooltips and VoiceOver
  wording), and the late-copy rule (`requestCopyText(pasteboardChangeCount:)`, `waitingTextCopy`,
  `resolveWaitingTextCopy(pasteboardChangeCount:)`). Tests: `SearchCopyTextTests` (rows saved to an in-memory index,
  late copies through the index's conditional write).
- `SearchKeyMap`: ⇧⌘C → `.copyText`, a new trigger `.shiftCommand(Character)`, matched like ⌘ keys on the lowercased
  ASCII character, else key code 8. Shift is accepted for C only. ⌘C is unchanged.
- App: `WorkspaceActions.copyText` (one `NSPasteboardItem`, `.string` only), `SearchResultActions.copyText()` and
  `resolveWaitingTextCopy()`, the pills `.textCopied` ("✓ Text copied", the "✓ Copied" 1.4 s) and `.noText` (3 s,
  `text.viewfinder`), `CopyTextBadgeView.swift` (the badge), and four snapshots: `search-text-copied`,
  `search-text-reading`, `search-text-failed` and `search-text-none`.

### Decisions and departures
- 2026-11-28: **departure from the spec: Copy Text is a badge on the preview image, not a button in the button row**
  (design §2 "The one bold choice", approved by Parag). It sits bottom-right of the 220 pt image frame, inset 10 pt:
  a 26 pt capsule, black 72%, with the "⇧⌘C" keycap. The button row keeps its four buttons and the footer keeps its
  five hints. The keycap is shown only on "Copy Text": on a failed row ⇧⌘C shows the error rather than re-reading,
  and the mockup shows no keycap on the reading or failed badges.
- 2026-11-28: **interim until ticket 07: a never-read row (`textStatus` NULL) shows no badge, and ⇧⌘C beeps.** Core
  already returns `.readFirst(id:)` for it. Ticket 07 performs the read and changes `copyTextBadge` for NULL from
  hidden to `.copyText`, as design §5 asks (one line and its test in `SearchCopyTextTests`).
- 2026-11-28: **until ticket 07, a click on "Read text again" does what ⇧⌘C does**: it shows "The text could not be
  read." (or the missing-file sentence). The re-read itself is 07's.
- 2026-11-28: "file missing" is recognised by `textError == "file missing"` (`SearchWindowState.fileMissingReason`).
  That is the spec's reason and the value of PR #18's `TextRecognitionRunner.fileMissingReason`. Core can't reference
  that constant until #18 merges; whoever merges second should make one of them use the other.
- 2026-11-28: **the open panel refreshes on index changes.** While the panel is shown, `SearchPanelController`
  subscribes to `ScreenshotIndex.changes()` (cancelled on hide). An `.updated` change of a listed row runs the search
  again, so the badge goes from "Reading text…" to "Copy Text" without reopening. That refresh is also the moment a
  waiting copy is resolved (`SearchViewModel.resultsApplied`). The spec assumed "an open search refreshes" on the
  `.updated` change, but no ticket built it.
- 2026-11-28: **late copy.** ⇧⌘C on a `pending` row records the pasteboard's `changeCount`. The copy is performed
  after a refresh only if the panel still shows that row and the `changeCount` is unchanged. Moving the selection, a
  query that selects another row, or hiding the panel drops the request at once, and coming back to the row does not
  revive it. Pressing ⇧⌘C again replaces the request (only the last one counts).
- 2026-11-28: a waiting copy whose row ends `none` or `failed` shows that state's pill: the user asked to copy, so
  they learn why nothing was copied. A dropped copy shows nothing (design §5).
- 2026-11-28: a `done` row without text (empty or whitespace only) counts as "no text". The runner never stores one,
  but the badge and the pasteboard should not offer an empty copy.
- 2026-11-28: **badge clicks are handled by `FileDragView`.** The drag view lies over the whole image and is told the
  badge's frame (anchor preference `CopyTextBadgeFrameKey`). A press on the badge never starts a drag and is never
  reported as an image click. The next press on the image counts as a single click, so badge then image is not a
  double-click that opens the file. A release on the badge runs Copy Text. The SwiftUI `Button` underneath gives
  VoiceOver and Full Keyboard Access the same action. This works whichever of the two SwiftUI's hit testing picks
  (`testAClickOnTheBadgeIsNotAClickOnTheImage`).
- 2026-11-28 (corrected in the review fixes): ⇧⌘C is ignored while either picker, date or source, is open (design §6;
  `testTheDatePickerIgnoresShiftCommandC`, `testTheSourcePickerIgnoresShiftCommandC`). In Quick Look's panel it does
  what it does in the search panel.
- 2026-11-28 (review fix): **index-change refreshes are coalesced.** A listed row's `.updated` change calls
  `SearchViewModel.refreshAfterIndexChange()`, which searches after the typing debounce (150 ms), so a burst of changes
  (ticket 07 marking many rows) runs one search. When a search is already scheduled and has not started (typing, a
  chip, an earlier change), the change schedules nothing: that search reads the index afterwards anyway, and the typing
  debounce is neither cancelled nor pushed back. A change that arrives while a search runs schedules the next one; the
  running one's answer is dropped (a detached SQLite query can't be stopped, but at most one runs per 150 ms). Tests:
  `testABurstOfChangesRunsOneSearch`, `testAChangeWhileTypingKeepsTheTypedSearch`,
  `testAfterHideAnIndexWriteRunsNoSearch`, `testAWriteToAnUnlistedRowRunsNoSearch`.
- 2026-11-28 (review fix): **the list follows the selected row when a refresh moves it.** It scrolls on a change of the
  selected id or of its index, so a re-sort that keeps the row (followed by path) but moves it keeps it in view.
- 2026-11-28 (review fix): **the badge's tooltip is set by `FileDragView`.** The drag view lies over the badge, so the
  badge's SwiftUI `.help` never gets the hover. `FileDragView` registers a tooltip rectangle (`addToolTip`) over the
  badge's frame, re-measured when its height changes, and answers with the badge's help (`badgeHelp`). Test:
  `testTheDragViewShowsTheBadgeTooltip`. Real-Mac check below.
- 2026-11-28 (review fix): **the "Read text again" symbol is white**, like the problem pill's
  `exclamationmark.triangle.fill`: design §3 gives the overlay pill and badge black 72% with white content. The
  literal orange (#FFB340) is gone.
- 2026-11-28 (review fix, PR #23 snapshot check): **filter pills hug their content.** `.frame(maxWidth: 180)` made
  the Source pill 180 pt whenever row 2 offered more. `FilterPill` now sits in `HuggingMaxWidth`, a one-child
  `Layout` that proposes the child's ideal width capped at `maxWidth` (and at the parent's offer), so a short name fits
  its text and a long one truncates at the tail at 180 pt (design §4). The Date pill (no `maxWidth`) hugs as before.
  Test: `testTheSourcePillHugsItsValueUpTo180Points` (measured in a 600 pt offer). New snapshot `search-source-long`.
- 2026-11-28: **privacy.** The recognized text reaches only the pasteboard, through the user's ⇧⌘C or badge click.
  `SearchResultActions` logs nothing. The announcement is "Text copied" and the pills never contain the text.

### Real-Mac checks (CI can't see these)
- ⇧⌘C on QWERTY, Dvorak and Russian layouts copies the text; ⌘C still copies the image, or the field's selected text.
- The copy pastes as plain text only into TextEdit (rich text mode) and Slack, with line breaks kept.
- Late copy: press ⇧⌘C on a row still being read, then copy something else in another app before it finishes. The
  clipboard keeps the other copy, and the badge turns to "Copy Text".
- The badge over a light and over a dark screenshot. A click on it doesn't start a drag; a click on it and then on the
  image doesn't open the file.
- The badge's tooltip shows on hover ("Copy the text in this screenshot (⇧⌘C)", the reading and failed wording), and
  hovering the image outside the badge shows none.
- With the panel open while ticket 07 reads many rows, the list doesn't flicker or jump, and typing stays responsive.
- VoiceOver reads the badge as "Copy Text" / "Reading text" / "Read text again" (with its hint), and announces "Text
  copied", "No text found in this screenshot." and "The text could not be read.".
- Quick Look (Space): does macOS Live Text let the user select part of the text? Record the result here (spec
  "Which key copies the text"; design §9).
