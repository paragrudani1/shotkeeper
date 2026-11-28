# 04: Record opens in Shotkeeper

**What to build:** every explicit action the user takes on one screenshot in Shotkeeper counts as opening it, so a
screenshot they used is never offered as "never opened". Opening a search result or a Recent row, Quick Look in the
search panel, Reveal in Finder, Copy image, Copy Text, dragging a result out, Edit name and Analyze Again set
`last_opened_at`. Appearing in results, being selected, a toast, an Undo, and anything in the Clean Up window don't.
Shotkeeper remembers when it started counting.

**Blocked by:** 01 (`last_opened_at`, `recordOpened(id:at:)`). Wave 1's Copy Text and wave 2's Edit name / Analyze
Again are on the integration branch already.

**Status:** ready-for-agent

**Sources:** spec "\"Never opened\"" (recorded by Shotkeeper, which actions count, `opensRecordedSince`), stories
15, 17, 22; design §5.3 line 3 (the note's wording, rendered by 06).

**Test seam:** seam 1 (`ScreenshotProcessor.recordOpened(rowID:)`), `SearchKeyMapTests` (or the core action enum's
test) for which actions count, `SettingsTests` round-trip for `opensRecordedSince`.

**Likely touches:** core `ScreenshotProcessor` (`recordOpened(rowID:)`, injected clock), `SearchKeyMap` action enum
(`countsAsOpen`), `AppSettings` (`opensRecordedSince`, one `CodingKeys` line); app `SearchResultActions`, the menu's
Recent rows, `FileActions` and its retitle extension, the first-launch hook in the coordinator. Hotspot: search panel
files (one call per action, after it succeeds).

- [ ] Core rule: each search action says whether it counts as an open (open, Quick Look, reveal, copy image, copy
      text, drag out, edit name, Analyze Again: yes; select, preview, scroll, filter: no). Tested per action.
- [ ] One core entry point `recordOpened(rowID:)`, called by the app **after** the action succeeds; it ignores
      non-`done` rows (01). The menu's Recent rows and `FileActions` (Edit name, Analyze Again) call it too.
- [ ] Not counted (tests): an Undo, a toast, being shown in results or the preview; anything from the Clean Up window
      (05/06 never call it; Quick Look there is for deciding, story 22).
- [ ] `AppSettings.opensRecordedSince`: set at the first launch with this feature and never moved later; the
      every-property round-trip test picks it up.
- [ ] A stale save after an open keeps the open (01's merge rule), tested through seam 1 with `process` and
      `reanalyze` racing a `recordOpened`.
- [ ] If search results flicker on a Quick Look `.updated` event, the search refresh coalesces events; the feed
      contract doesn't change (spec "Index schema…", last bullet).
- [ ] CI snapshots: none new (no visible change); existing search snapshots unchanged.
- [ ] Real-Mac checks: research check 8, Shotkeeper rows only: after Shotkeeper's Open and a Shotkeeper Quick Look,
      read `last_opened_at` (set) and `kMDItemLastUsedDate` (record what macOS does; the result goes to 06's note).
      Search results don't flicker on Quick Look.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green; `docs/core-api.md`; dated
      wiki line.
- [ ] **Done only when `macos-app` CI is green** on the PR.
