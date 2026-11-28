# 03: Queue: job kinds, front placement, per-kind dedupe

**What to build:** the processing queue can hold two kinds of job, "process this new file" and "analyze this indexed
row again", so Analyze Again gets the same rate limit, retries and offline / "Needs attention" holds as everything
else. A re-analysis job goes ahead of waiting jobs without pre-empting the running one, and pressing twice queues it
once. Nothing issues a re-analysis job yet (08 does); new screenshots and Process Existing behave as before.

**Blocked by:** 01 (it renames `enqueue(_:processExisting:)` to `userRequest:`; doing both in one file at once would
conflict).

**Status:** ready-for-agent

**Sources:** spec "Analyse Again: queue" (all bullets), story 52, 63; `docs/wiki/ui-polish.md` "review 4" (the user
request lives for the job's whole life).

**Test seam:** `ProcessingQueueTests` (existing; the spec lists this as one more case in an existing test, not a new
seam).

**Likely touches:** core `Queue/ProcessingQueue.swift`, `Queue/QueuePrimitives.swift`, `ProcessingQueueTests`; app
`Coordinator/AppCoordinator.swift` (the handler dispatches on the kind; until 08 wires it, the `.reanalyze` branch
does nothing and says so in a comment, since nothing enqueues that kind yet).

- [ ] A job carries a kind: `.process(URL)` or `.reanalyze(rowID)`, and its optional `UserUploadRequest`.
- [ ] Duplicates are ignored per kind and key: a second `.reanalyze` of a queued or running row does nothing; a
      `.process` of a URL and a `.reanalyze` of the row at that URL are different jobs.
- [ ] `enqueue(_:atFront:)`: a front job goes before waiting jobs, never pre-empts a running job, still takes a
      rate-limit token. Tests with a fake clock: a `.reanalyze` added behind 50 waiting `.process` jobs runs next.
- [ ] The user request stays with the job through retries (429/5xx), offline and "Needs attention" holds, and is
      dropped when the job ends. Tests for each.
- [ ] Queue status still reports per job, so the app can map a row id to queued / running / held (08 reads it).
- [ ] Existing queue, processor and coordinator tests pass unchanged apart from the enqueue call shape.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green; `docs/core-api.md` updated;
      dated wiki line in `docs/wiki/subfolders-and-retitle.md`.
- [ ] **Done only when `macos-app` CI is green** on the PR.
- CI snapshots: none.
- Real-Mac checks: none beyond a smoke test that new screenshots and Process Existing still run.
