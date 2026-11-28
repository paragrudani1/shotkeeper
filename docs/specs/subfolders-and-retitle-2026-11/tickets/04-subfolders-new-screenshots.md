# 04: Sort new screenshots into subfolders

**What to build:** in Settings › General, under "Move into the organized folder", the user picks **Sort into
subfolders**: Off, By type, By app or site, or By type, then app or site. An example path under the picker shows
what will happen. The next screenshot lands in the right subfolder inside the organized folder (created if missing,
reused in any letter case, never replacing a file), the toast says "Sorted into Receipts", and Undo puts it back.
Screenshots already there stay put (sorting them is 05).

**Blocked by:** wave 1 ticket 03 (it adds core `SourceKey`, which the router must reuse: a second normalizer would
be a second copy of the rule). It touches Settings and the toast, not the search panel.
Before wave 1 merges to main, this can start on a branch from `t3/wave1-search` once wave 1 03 is merged there; its
PR targets the wave 2 integration branch once that exists.

**Status:** ready-for-agent

**Sources:** spec "Subfolder rule (core, Linux-tested)", "Subfolders in the pipeline", stories 1–19, UI surfaces 1
and 3 (single toast); design §4 "Layout" and "Organized folder missing or unreadable", §7 "Single screenshot, sorted
into a subfolder", §10, §12 polish departures 5 and 9.

**Test seam:** seam 1, `ScreenshotProcessor` through `process` (`StubAnalyzer`, `TempDir`, in-memory index, real
`UndoLog`); `SettingsTests` round-trip picks up `subfolderRule`; the `Feedback` toast tests for the label.

**Likely touches:** core `Settings/AppSettings.swift` (`subfolderRule`, one `CodingKeys` line), a new
`Files/SubfolderRule.swift` (enum, `relativeFolder(contentType:source:existing:)`, type folder names, the
non-answer list, folder-name cleaning), `Pipeline/ScreenshotProcessor.swift` (destination folder; list existing
names read-only), `Feedback/Toast.swift` (label); app `UI/SettingsView.swift` (or a new
`SettingsSubfolderSection.swift` to keep the file small), `UI/ToastView.swift` if the label needs layout,
`SettingsSnapshots.swift`, `ToastSnapshots.swift`. Tests: new `SubfolderRuleTests`, `ScreenshotProcessorTests`,
`ToastTests`, `SettingsTests`.

- [ ] `SubfolderRule` `.off` (default) / `.byType` / `.bySource` / `.byTypeThenSource`, stored as
      `AppSettings.subfolderRule`; an unknown stored value decodes as `.off`. Applies only when `moveEnabled` is on and
      `organizedFolder` is set; never creates folders anywhere else.
- [ ] Pure router returns path components below the organized folder (`[]` = the folder itself). Fixed type folder
      names: Tweets, Articles, Code, Chats, Receipts, Designs, Other.
- [ ] Source folders: `SourceKey` match against existing folder names at that level (first alphabetically wins), so
      "X" reuses "x.com" and "slack" reuses "Slack"; else a new name from the raw spelling (drop `www.`, `/` and `:` →
      " - ", drop control characters, trim spaces and dots, cap 60 characters at a grapheme boundary). Empty, `.` or
      `..` count as unknown. The first spelling seen keeps the folder's name.
- [ ] Unknown source (nil, empty after cleaning, or the constant non-answer list "unknown", "n/a", "none",
      "screenshot", "image", "desktop", with a test): `.bySource` → Other; `.byTypeThenSource` → the type folder itself.
- [ ] Pipeline: destination = organized folder + router result; order unchanged (analyze → stem → organize → undo
      record → Finder metadata → index). A kept name (low confidence, no title, rename off) is still sorted. One undo
      record per move; undo restores the original path and name, sets `restored_by_undo`, and leaves the empty
      subfolder alone. The move goes through `index.updatePath`, so the change feed publishes `.updated`.
- [ ] Fallback: when the subfolder can't be made (a *file* named "Receipts", or permission denied), the screenshot
      goes to the organized folder root and the row's `note` gets "subfolder not created (…)"; if that fails too,
      today's rule (kept in place, with a note).
- [ ] Watching invariant: a test or a documented assertion that subfolders are never watched or re-processed (the
      watcher and Process Existing see direct children only); a doc comment says a later recursive watch must exclude
      the organized folder.
- [ ] Seam 1 tests: routing for each rule and type; unknown sources; reuse by `SourceKey`; name cleaning; the "file
      named Receipts" fallback; a no-replace clash in a subfolder gives "Name 2"; undo of a sorted file; the change
      feed event for the move.
- [ ] Settings: the "Sort into subfolders" menu `Picker` and, when not Off, the **Example** row (real organized folder
      name, current filename style and date prefix, " › " separators, middle truncation) with the per-rule note from
      design §4, and the line "Screenshots already there stay where they are." Hidden when moving is off or no
      organized folder. Missing / unreadable folder replaces the example with the design's warning row. (The **Sort
      Existing Screenshots…** button is 05; leave its spot.)
- [ ] Toast: when a subfolder was used, the label is "Sorted into Receipts" / "Sorted into Chats › Slack" (middle
      truncation) instead of "Renamed" / "Moved"; not when the fallback put the file at the root. VoiceOver: "Renamed
      and sorted into Receipts: <name>." Pure wording in `Feedback/`, with tests.
- [ ] New CI snapshots, light and dark: `settings-general-subfolders-off`, `settings-general-subfolders-by-type`,
      `settings-general-subfolders-by-app`, `settings-general-subfolders-two-level`,
      `settings-general-subfolders-folder-missing`, `toast-sorted`. `UISnapshotCatalogTests` stays unique.
- [ ] Real-Mac checks: Finder shows the subfolders after a few real screenshots (by type, then two-level); an existing
      "slack" folder is reused for "Slack" on APFS; Undo from the toast and from the menu puts the file back and leaves
      the empty folder; the Settings page doesn't jump when the picker changes.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green (the listing of existing folder
      names is read-only, so no `file-op` marker is needed); `docs/core-api.md` and a dated wiki line.
- [ ] **Done only when `macos-app` CI is green** on the PR.
- Interplay with 06: Analyze Again reuses the pipeline's destination helper. If 06 merges first, this ticket adds the
  seam 1 test "Analyze Again moves to the new type's folder"; if this merges first, 06 adds it.
