# Search filters and Copy Text (wave 1, 2026-11-28)

Implementation notes and departures for the [wave 1 spec](../specs/search-filters-and-text-2026-11.md) and the
approved [design](../design/search-filters-and-text.md). The spec's requirements are not edited; deviations go here.

## Ticket 02: date filter (2026-11-28, branch `t3/w1-02-date-filter`)

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
  `COALESCE(captured_at, processed_at)` expression index. The filter is correct without it.

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
