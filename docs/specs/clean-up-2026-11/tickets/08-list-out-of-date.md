# 08: The list goes out of date: lock changed rows, Check Again

**What to build:** while the Clean Up window is open, files change. When a listed screenshot changes (renamed, moved,
binned elsewhere, re-analyzed, put back) or a run finds a file changed, a warning banner says so, the changed rows are
unticked and locked with "Changed since the list was made" (a changed duplicate group is locked whole), and Check
Again re-lists. Changes that don't touch a listed row (a new screenshot, a settings change) only say "Files changed
since this list was made" and untick nothing.

**Blocked by:** 05 (window, review state), 07 (a failed check during a run sets the flag; the banner sits beside the
run's footer states).

**Status:** ready-for-agent

**Sources:** spec "App side" (the out-of-date flag), story 43, UI surface 2 ("list out of date"); design §6 ("List out
of date", "Out of date, other changes"), §14 spec departure 6.

**Test seam:** seam 2 (`CleanUpReviewState`, driven by index change-feed events and a `TrashReport`), plus one seam 1
case that the feed publishes for every listed-row change the window cares about.

**Likely touches:** core `CleanUpReviewState`; app `FileActions+CleanUp.swift` (subscribes to `changes()` while the
window is open), `CleanUpView` (banner, row note), `CleanUpSnapshots`.

- [ ] A feed event (`.updated`, `.removed`) for a listed row's id marks that row (or its whole duplicate group)
      changed: unticked, checkbox disabled, note "Changed since the list was made"; the footer totals drop it.
- [ ] Other events (new rows, settings changes, unlisted rows) set the "other changes" flag only; nothing unticked.
- [ ] A run's `changedSinceListed` and similar skips mark those rows the same way.
- [ ] Check Again clears the flags and keeps ticks and Keep choices on files still listed and unchanged.
- [ ] Space on a locked row beeps and VoiceOver says why; the banner text is announced.
- [ ] Seam 2 tests for each rule above.
- [ ] New CI snapshot, light and dark: `cleanup-out-of-date`.
- [ ] Real-Mac checks: rename a listed screenshot in Finder and Edit name another in the search panel with the window
      open; the rows lock and the banner shows.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green; dated wiki line.
- [ ] **Done only when `macos-app` CI is green** on the PR.
