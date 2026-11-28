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
  `COALESCE(captured_at, processed_at) >= ? AND < ?` and resolves "today" on each call. The app passes no clock, so
  the index uses `Date()` and `Calendar.current`, the same calendar as the app's `TimeLabel()`.
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

### Real-Mac checks (CI can't see these)
- The picker opens without activating Shotkeeper or taking key status from the panel; a click outside it (inside the
  panel) closes it; clicking another app hides the panel and the picker.
- Focus: the date list takes the focus when it opens (typed letters don't edit the search text behind it), the From
  field takes it when the custom range expands, and the search field gets it back when the picker closes.
- ⌘D on QWERTY, Dvorak and Russian layouts; ⌫ in the date list clears the date; ⌫ in the field still deletes.
- `DatePicker(.field)` editing inside the non-activating panel: digits, ↑/↓ on the focused part, Tab From → To →
  Apply, ↩ applies.
- VoiceOver reads the pill as "Date, any time" / "Date, last 7 days", the ✕ as "Clear date", and announces "Date
  cleared", "Filters cleared" and "Search cleared".
