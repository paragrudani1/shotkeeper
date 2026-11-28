# 02: Date filter, end to end

**What to build:** the user presses ⌘D (or clicks the **Date** pill at the right end of the chip row), picks Today,
Yesterday, Last 7 days, Last 30 days or a custom range in the in-panel picker, and the results narrow to screenshots
taken on those days. It combines with text and the type chip, the footer reads "N of M screenshots", the pill shows
the value with an ✕ to clear it, and the no-match states name the filter. This ticket also builds the shared filter
pieces that 03 reuses: the in-panel picker, `clearFilters()`, the "Clear filters" button and the no-match sentence
builder.

**Blocked by:** PR #10 (app prefactor) merged. Builds on its `SearchKeyMap` (core key table and collision tests),
`SearchResultActions` and the one-file-per-screen snapshot files (`SearchSnapshots`).

**Status:** ready-for-agent

**Sources:** spec "Filter model", "How filters show in the panel", stories 1–5, 10–19, 21–22; design §2 (layout A,
picker A2), §4 (Row 2, Picker, Date picker), §5 (Filter pills, Pickers, No-match states), §6 (⌘D, Esc order, focus
while a picker is open), §7, §8.

**Test seams:** seam 1 (`ScreenshotIndex.search(_:limit:now:calendar:)` with a pinned clock and calendar) and seam 2
(`SearchWindowState`, prior art `SearchWindowTests`); key binding in `SearchKeyMapTests`.

**Likely touches:** core `DateFilter` (new), `ScreenshotQuery`, `ScreenshotIndex.search`, `SearchWindowState`,
`SearchKeyMap`; app `SearchView` (row 2 pills, picker overlay; put the picker and pills in their own files to keep
`SearchView.swift` from growing), `SearchViewModel`, `SearchPanel` key dispatch, `SearchSnapshots`.
Shared hotspots with 03 and 06: `SearchWindowState`, `SearchKeyMap.bindings`, `SearchView`, `SearchSnapshots`.
03 waits for this ticket; 06 may run in parallel and the second to merge rebases (expect one-line conflicts only).

- [ ] `DateFilter` (`.today`, `.yesterday`, `.last7Days`, `.last30Days`, `.days(from:through:)` with calendar days)
      resolves to a half-open `[start, end)` of whole local days for a given `now` and `Calendar`. Tests: day edges,
      midnight rollover, a non-UTC time zone, a DST change day, a swapped custom range, a one-day range.
- [ ] `ScreenshotQuery.date`; `search` filters on `COALESCE(captured_at, processed_at)` and resolves "today" on each
      call. Tests: rows with only `processed_at`; date + text + type + batch paths combine with AND; `matchCount` and
      `totalCount`; no text → newest first (story 12).
- [ ] `SearchWindowState`: `setDateFilter(_:)`, `clearFilters()` (keeps the text), each returns whether to search and
      ends a batch view; `escape()` and `clearSearch()` reset text, chip and date, and Esc closes only when all are
      empty; `clickTag(_:)` resets the date; `windowHidden()` keeps it; `hasFilter` counts it.
- [ ] No-match wording from design §5 for date with and without chip and text ("No screenshots taken in the last 7
      days", "No Receipt screenshots taken on Oct 3", "Your filters limit this search to …"), with buttons Clear
      filters / Clear search as in the table. Custom range labels per design ("Oct 3 – 17", year dropped in the
      current year). Tests per combination.
- [ ] ⌘D in `SearchKeyMap` (character `d`, physical key code 2); the collision test passes. Esc order: close the
      picker, then clear everything, then close the panel. ⌫ in the date list clears the date and closes.
- [ ] App: Date pill (off / on / open states), in-panel picker (not a popover, not a window; the panel stays key),
      custom range with two `DatePicker(.field)` and Apply; focus goes to the picker and back to the field; VoiceOver
      name and value ("Date", "last 7 days") and "Date cleared" / "Filters cleared" / "Search cleared" announcements.
- [ ] New CI snapshots, light and dark: `search-date-custom`, `search-no-match-filters-only`, `search-no-match-filters`.
- [ ] Real-Mac checks (CI can't see them; list them in the PR and the wiki): the picker opens without activating
      Shotkeeper or taking key status; a click outside it closes it; ⌘D on QWERTY, Dvorak and Russian; `DatePicker(.field)`
      editing inside the non-activating panel; VoiceOver reads the pill and the announcements.
- [ ] Linux tests and `scripts/lint.sh` green; dated wiki lines (design departures adopted, Esc order).
- [ ] **Done only when `macos-app` CI is green** on the PR.
