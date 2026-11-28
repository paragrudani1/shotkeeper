# 07: Read one screenshot on demand (copy from a never-read row, "Read text again")

**What to build:** Copy Text on a screenshot indexed before this feature reads that one screenshot right away, ahead
of the queue, and copies when ready (story 36), so the user is never sent to a menu first. On a failed row the
**Read text again** badge re-queues it ahead of the queue; when the read succeeds the badge becomes Copy Text without
copying by itself.

**Blocked by:** 04 (runner), 06 (badge, copy outcome, late-copy rule).

**Status:** ready-for-agent

**Sources:** spec "Existing rows on request" (Copy Text on one such row), decision 2; design §5 Copy Text table rows
"never read (NULL)" and "failed", and the note on re-reads.

**Test seams:** seam 3 (`TextRecognitionRunner` with a stub recognizer: reading one row ahead of the queue) and
seam 2 (the outcome after a re-read).

**Likely touches:** core `TextRecognitionRunner` (a "read this row now" request that sets `pending` and jumps the
queue), `SearchWindowState`; app `SearchResultActions`, the badge view.

- [ ] Runner: a request for one row (NULL or `failed`) marks it `pending` and reads it before older queued rows.
      Tests with a stub recognizer and several pending rows.
- [ ] App: a NULL row shows the same badge as a ready one; ⇧⌘C or a click starts the read, announces "Reading text",
      then copies under 06's late-copy rule. Replaces 06's interim beep.
- [ ] Failed row: the badge re-queues ahead of the queue and switches to reading; ⇧⌘C still only shows the error pill;
      after success the badge reads Copy Text and nothing is copied.
- [ ] CI snapshots: none new (states covered by 06's names); existing ones unchanged.
- [ ] Real-Mac checks: copying from an old screenshot copies after a short wait; switching rows during the wait
      leaves the clipboard alone; "Read text again" on a file that is back in place succeeds.
- [ ] Linux tests and `scripts/lint.sh` green; dated wiki line removing the interim behaviour.
- [ ] **Done only when `macos-app` CI is green** on the PR.
