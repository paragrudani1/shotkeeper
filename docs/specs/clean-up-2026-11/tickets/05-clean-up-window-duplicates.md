# 05: Clean Up window: find duplicates (read-only)

**What to build:** "Clean Up…" in the status menu opens a Clean Up window that checks the watched folder and the
organized folder and lists exact copies of screenshots Shotkeeper knows, in groups, with one copy marked **Keep** and
the extra copies ticked. The user can keep a different copy, tick and untick, Select All/None, Quick Look and reveal
(neither counts as opened), and Show Only Ticked. The footer counts what is ticked. Nothing moves: Move to Trash… is
present and stays disabled until 07 wires it (on the integration branch only, never on main).

**Blocked by:** None (can start immediately on the integration branch). The plan reads `done` and
`restored_by_undo` rows only, which exist already. 01 is not needed here.

**Status:** ready-for-agent

**Sources:** spec "Where clean-up looks (scope)", "Exact duplicates", "The plan (core, read-only)", `App side`
(`CleanUpReviewState`), stories 1–11, 21, 22, 42, 44, 45, UI surfaces 1–3, 9; design §2 (layout A, Keep pill, the
stack), §3, §4, §5.1, §5.2, §5.4, §5.6 (first two rows), §6 (checking, stopped, no folder, missing, unreadable,
index empty, index error, nothing in Duplicates, many results, skipped while listing), §11, §12; research §4 (never
list the Trash).

**Test seam:** seam 1 (`ScreenshotProcessor.cleanUpPlan`, duplicates half; `TempDir` with watched, organized (with
subfolders) and fake Trash folders; in-memory index; injected clock and digest) and seam 2 (`CleanUpReviewState`,
new, prior art `SearchWindowTests`).

**Likely touches:** core new `Files/ContentDigest.swift` (FNV-1a 64 over every byte, sibling of
`ContentFingerprint`), new `CleanUpScope`, new `Pipeline/ScreenshotProcessor+CleanUp.swift` (`cleanUpPlan`,
`CleanUpPlan`), new `CleanUp/CleanUpReviewState.swift`; app new `Coordinator/FileActions+CleanUp.swift`, new
`UI/CleanUpView.swift` (and row/group views in their own files), `WindowPresenter` (id `clean-up`),
`MenuContentView` ("Clean Up…"), new `CleanUpSnapshots` in `UISnapshotTests`, `docs/core-api.md`.

- [ ] Scope (pure core value from the settings snapshot): watched folder direct children; organized folder any depth;
      symlink-resolved standardized paths compared by components; regular files only, no symlinks, hidden files or
      folders (so `~/.Trash` and `.Trashes` are never walked, research §4), packages or `FileOrganizer` temp files;
      `ScreenshotDetector.imageExtensions`; in the watched folder only files with a row or that `ScreenshotDetector`
      calls screenshots. Symlinked folders not followed.
- [ ] Duplicates: group by size, digest only size collisions, group on equal size and digest; nothing stored. A group
      is listed only with at least one `done` copy; rowless copies included. Default Keep order: restored by Undo,
      `done` row, inside the organized folder, oldest capture date, shortest path then alphabetical. Pending,
      retrying or restored-without-analysis copies are shown with a disabled checkbox ("Still being named") and may
      be Keep (design §5.2, spec departure 8).
- [ ] `cleanUpPlan` writes nothing (no file, row, undo line or setting), runs off the main actor, reports progress
      and can be cancelled; returns groups, skip counts (unreadable, outside scope, still processing) and per
      candidate the URL, row id, size, capture date, listing fingerprint and location.
- [ ] Seam 1 tests: copies with different mtimes found; same size but different bytes not grouped; a forced digest
      collision is listed (the byte comparison that refuses it is 07's); groups without a `done` row not listed;
      default Keep order; one Keep per group; every scope case in the spec's list never listed.
- [ ] `CleanUpReviewState`: duplicate extras pre-ticked; Keep switching swaps states (design §2); exactly one Keep per
      group; Select All/None per section; totals; Show Only Ticked. Seam 2 tests for each.
- [ ] Window and menu as design §4–§6 for the states above: "Clean Up…" under Process Existing Screenshots…, shown
      once setup is finished; 680 × 600, min 560 × 420; the check starts on open; Check Again (⇧⌘R) keeps ticks and
      Keep choices on unchanged files; the footer stack and "12 ticked, 34.2 MB"; Keep pill tooltips; "Not in search"
      and "Search will show this copy" notes; Show Only Ticked (⌘T). No default button (↩ does nothing).
- [ ] Keys and VoiceOver from design §11 that apply here (↑↓, Space, ⌘K, ⌘Y, ⌘R, ⌘A, ⇧⌘A, ⌘T, ⇧⌘R, Esc/⌘. while
      checking, ⌘W); group containers and row labels; "Check finished" announcement. Quick Look and Reveal here never
      call `recordOpened`.
- [ ] New CI snapshots, light and dark: `cleanup-list` (Duplicates only until 06 adds the second section),
      `cleanup-list-keep-rowless`, `cleanup-list-only-ticked`, `cleanup-list-many`, `cleanup-checking`,
      `cleanup-comparing`, `cleanup-check-stopped`, `cleanup-no-folders`, `cleanup-folder-missing`,
      `cleanup-folder-unreadable`, `cleanup-index-empty`, `cleanup-index-error`, `cleanup-empty-duplicates`.
- [ ] Real-Mac checks (design §13): Space ticks in the `List` without Quick Look or scrolling; ⌘Y Quick Look from a
      regular window; pinned section headers; scrolling 1,000 rows; both Keyboard navigation settings; VoiceOver.
      Measure listing on a few thousand files and record it in the wiki (spec "Exact duplicates", "Further Notes").
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green; `docs/core-api.md`; dated
      wiki line.
- [ ] **Done only when `macos-app` CI is green** on the PR.
