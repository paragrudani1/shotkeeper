# 03: Source filter, end to end

**What to build:** the user presses ⌘S (or clicks the **Source** pill), types a few letters in the picker's narrow
field, presses ↩, and the results narrow to screenshots from that app or site. "X" and "x.com" are one source; the
list is ordered by count and shows each count; a chosen source that no longer exists stays selected with count 0.
Source combines with date, type and text.

**Blocked by:** 02 (reuses its picker, `clearFilters()`, the no-match sentence builder and the row 2 layout). PR #10
merged (via 02).

**Status:** ready-for-agent

**Sources:** spec "Filter model" (Sources, Filtering by source), "Source list states", stories 6–9, 11, 14–22, 23;
design §4 (Source picker, long values, disabled pill), §5 (Source rows, no-match with source), §6 (⌘S, ⌘S ⌫),
§7 (Many sources, Long source names, Chosen source gone, Empty index).

**Test seams:** seam 1 (`ScreenshotIndex.sources()` and the source filter) and seam 2 (`SearchWindowState`);
key binding in `SearchKeyMapTests`.

**Likely touches:** core `SourceKey` and its normalizer (new), `SourceFacet` (new), `ScreenshotIndex.sources()`,
`ScreenshotQuery.source`, `ScreenshotIndex.search`, `SearchWindowState` (source list, `setSource(_:)`), `SearchKeyMap`;
app source pill and picker (own files), `SearchViewModel` (load the list each time the panel opens),
`SearchSnapshots`. Shared hotspots with 06: `SearchWindowState`, `SearchKeyMap.bindings`, `SearchView`,
`SearchSnapshots`; the second to merge rebases.

- [ ] Normalizer: trim, fold case and diacritics, drop a leading `www.`, drop a lone top-level domain (`x.com` → x,
      `github.com` → github), leave `bbc.co.uk` and `docs.google.com` as they are; no alias table. Tests through
      `sources()`.
- [ ] `sources()` returns `[SourceFacet]` (key, display name = most common raw spelling with alphabetical tie-break,
      count over all `done` rows), sorted by count then name, rows without a source left out.
- [ ] Source filter resolves the key to its raw spellings and filters with `IN (SELECT value FROM json_each(?))`.
      Tests: combined with text, type, date and batch; `matchCount`/`totalCount`; a key with no rows left returns no
      results.
- [ ] `SearchWindowState`: `setSource(_:)` ends a batch view; Esc, Clear search, Clear filters and a tag click reset
      it; `windowHidden()` keeps it; `hasFilter` counts it; the state holds the loaded source list; no-match wording
      with a source ("No screenshots from Slack taken in the last 7 days"), including a source that is gone.
- [ ] ⌘S (`s`, key code 1) in `SearchKeyMap`, collision test passes; beep when the pill is disabled; ⌘S ⌫ clears it.
- [ ] App: Source pill (off / on / disabled with the design's tooltip, max 180 pt with tail truncation, full name in
      tooltip and VoiceOver); picker 280 pt, narrow field with folded substring match and the first match highlighted,
      "No source matches “zz”", counts right-aligned with tabular figures, 8 rows then scroll, a gone source pinned
      under "Any source" with count 0.
- [ ] New CI snapshots, light and dark: `search-filters-on` (date + source + chip), `search-source-picker` (many
      sources, one long name); `search-empty-index` updated to show the disabled Source pill.
- [ ] Real-Mac checks: the narrow field takes the focus and gives it back; Japanese IME in the narrow field (↩ in the
      candidate list doesn't pick a source); ⌘S on QWERTY, Dvorak and Russian; VoiceOver picker rows ("Slack, 64
      screenshots").
- [ ] Linux tests and `scripts/lint.sh` green; dated wiki line for the normalization rule.
- [ ] **Done only when `macos-app` CI is green** on the PR.
