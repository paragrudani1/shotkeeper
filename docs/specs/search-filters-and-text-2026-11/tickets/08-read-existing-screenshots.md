# 08: Read Text in Existing Screenshots (backfill from the menu)

**What to build:** "Read Text in Existing Screenshots…" in the menu bar menu asks "Read the text in 180 screenshots?",
then reads them newest first. The status line shows "Reading text: 142 left", "Stop Reading Text" stops it and puts
unread rows back as they were, a quit and relaunch continues it, and the last message reports how many were read or
could not be read. Failed rows from earlier runs are included.

**Blocked by:** 04 (runner). PR #10 merged (coordinator parts). Independent of 06 and 07.

**Status:** ready-for-agent

**Sources:** spec "Existing rows on request" ("Read text in existing screenshots"), stories 38–44; design §5 "Read
text in existing screenshots (menu bar menu)", §11 polish departure 6.

**Test seams:** seam 3 (runner with a stub recognizer over a real in-memory index); menu wording through the existing
`MenuText` tests.

**Likely touches:** core `TextRecognitionRunner` / index (count NULL + `failed` `done` rows, queue them, stop with the
previous state restored, progress), `MenuText`; app `MenuContentView`, `StatusText`, the coordinator part that owns
the runner, `MenuSnapshots`. Hotspot: menu files (no other wave 1 ticket edits them).

- [ ] Core: "read existing" counts `done` rows with status NULL or `failed`, marks them `pending`, and reports the
      count; stop sets still-`pending` rows from this request back to their previous state (NULL or `failed`); rows
      queued by new screenshots stay `pending`. Pending rows survive a reopen of the index (story 41). Tests for each.
- [ ] Progress (rows left, read, failed) is available to the menu; failures never stop the run (stories 43–44).
- [ ] Menu: item hidden when nothing needs reading; confirm alert title/message/buttons as in the design (Read Text is
      default); status line "Reading text: N left"; "Stop Reading Text" while running; the three final messages.
      Wording in core `MenuText` with tests.
- [ ] New CI snapshots, light and dark: `menu-reading-text` (status line + Stop item) and `menu-read-text-done`
      (final message). These names are proposed here; the design lists no menu snapshot.
- [ ] Real-Mac checks: the confirm alert from an `LSUIElement` app comes to the front; quitting mid-run and relaunching
      continues; a large backfill keeps the Mac responsive.
- [ ] Linux tests and `scripts/lint.sh` green; dated wiki line.
- [ ] **Done only when `macos-app` CI is green** on the PR.
