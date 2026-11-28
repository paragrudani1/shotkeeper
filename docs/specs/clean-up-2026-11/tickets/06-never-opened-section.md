# 06: Never opened: old screenshots the user never opened

**What to build:** the Clean Up window gains its second section, **Never opened**: screenshots taken more than 3
months ago (1 month, 3 months, 6 months or 1 year, remembered) that the user never opened in Shotkeeper and that macOS
has no open record for. Nothing is pre-ticked. A file listed as a duplicate isn't listed here. The section note says
since when Shotkeeper has counted opens and that macOS records opens from Finder but not from every app.

**Blocked by:** 01 (`last_opened_at`), 04 (opens recorded, `opensRecordedSince`), 05 (window, plan, review state).

**Status:** ready-for-agent

**Sources:** spec "\"Never opened\"", "\"Old\"", stories 12–20; design §5.3, §5.5, §6 (nothing in Never opened,
nothing in either); research §2 ("How the app reads it", "Answer to spec question 2"), "What this changes in the
spec" (`LastUsedDates` bullet). The research wins over the spec here (README).

**Test seam:** seam 1 (`cleanUpPlan`, never-opened half, with a fake `LastUsedDates` and an injected clock), seam 2
(`CleanUpReviewState`), `SettingsTests` round-trip for `cleanUpAge`.

**Likely touches:** core `ScreenshotProcessor+CleanUp.swift`, new `CleanUp/LastUsedDates.swift` (port),
`CleanUpReviewState`, `AppSettings` (`cleanUpAge`, one `CodingKeys` line); app new
`Platform/MetadataLastUsedDates.swift`, `CleanUpView` (section, picker), `CleanUpSnapshots`.

- [ ] `LastUsedDates` port: URL → `.date(Date)` / `.noRecord`. The research shows the API can't tell "never opened"
      from "not tracked" (`MDItemCopyAttribute` returns NULL for both, [D6]), so the spec's `.never`/`.unknown` split
      collapses to one case unless real-Mac check 8 finds a clean split by disk; then add `.unknown` per volume and
      the §5.5 row note. Read only at listing time, never stored.
- [ ] App implementation reads `NSMetadataItem(url:)` + `NSMetadataItemLastUsedDateKey` (DTS's choice), with a comment
      citing the research note. It never reads `com.apple.lastuseddate#PS` and never uses the access time.
- [ ] Candidates: `done`, not `restored_by_undo`, file present at the indexed path, in scope, older than the age, no
      `last_opened_at`, no macOS date, not listed as a duplicate. Age = now − `captured_at` (fallback: file creation
      date, then modification date). Oldest first. Files without a row are not listed.
- [ ] Seam 1 tests: age boundaries with the injected clock; `captured_at` vs file dates; `recordOpened` hides a row;
      a macOS date hides it, no record doesn't; restored rows excluded; duplicates not listed twice; the plan still
      writes nothing.
- [ ] `CleanUpReviewState`: nothing pre-ticked; Select All/None for this section; changing the age re-lists this
      section only and keeps ticks on files still listed; totals include both sections. Seam 2 tests.
- [ ] UI per design §5.3: pinned header with the inline age `Picker` (default 3 months, `AppSettings.cleanUpAge`),
      the note with `opensRecordedSince` (and the "started counting opens today" variant), rows with thumbnail,
      title, folder, date taken and size. The "no record" note is said **once** in the section note, not per row
      (design spec departure 2). Empty states for this section and for both.
- [ ] New CI snapshots, light and dark: `cleanup-empty-never-opened`, `cleanup-empty-both`; `cleanup-list` updated to
      show both sections (design §13: "both sections, one group with a rowless copy, selection").
- [ ] Real-Mac checks: research **check 8** (the last-used date after nothing, Quick Look in Finder, double-click in
      Finder, `open`, Shotkeeper's Open, Preview's File > Open, a Shotkeeper Quick Look; then an external disk with
      indexing off and one in Spotlight's Privacy list) and **check 9** (`xattr -l` on system screenshots for
      `com.apple.quarantine`). Record the results in the research note's follow-up and the wiki; they decide the
      per-row note.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green; `docs/core-api.md`; dated
      wiki line.
- [ ] **Done only when `macos-app` CI is green** on the PR.
