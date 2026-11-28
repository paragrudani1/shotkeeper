# 10: Integrate clean-up and verify on a real Mac

**What to build:** the clean-up integration branch merges as one checked whole: every spec requirement met or
recorded as a dated deviation (CODING_STANDARDS #7), the research's nine real-Mac checks and the design's real-Mac
list run together on Parag's Mac, and the wiki and code map current.

**Blocked by:** 01–09.

**Status:** ready-for-agent (the real-Mac part needs Parag)

**Sources:** spec (all), design §13 and §14, research "Must test on a real Mac", CODING_STANDARDS #1 and #7,
`docs/wiki/appkit-gotchas.md`.

**Test seam:** none new; the full suites, `scripts/lint.sh --self-test` and the CI snapshot artifact.

- [ ] Branch merged or rebased on its base; migration version re-checked (01's number is still the next free one;
      `shippedColumns` versions run 1, 2, 3… with no gap).
- [ ] `git grep -n "trashItem\|recycle("` over `Sources App scripts` finds only `FileOrganizer.swift` and the lint
      rule; no `lint-allow: trash` anywhere; AGENTS.md and CODING_STANDARDS #1 carry only the new wording.
- [ ] `git grep -n -i "analyse\|colour\|behaviour"` over the new code, strings and snapshot names finds nothing
      (American spelling).
- [ ] Every story in the spec ticked against the code or given a dated deviation in `docs/wiki/clean-up.md`; the
      design departures (§14) and each "research wins" point (README) recorded as implemented.
- [ ] Every snapshot name listed in tickets 03 and 05–09 present in the CI artifact, light and dark, and looked at.
- [ ] Real-Mac pass (Parag; macOS 14, 15 and 26 where available; ad-hoc build without Full Disk Access): research
      checks 1–9 as assigned in 06, 07 and 09, the real-Mac checks in 03–09, and the migration on the real index
      (rows kept). **Check 4 (SMB: throws, file stays) is a ship gate.** Results go into the wiki and, for Apple
      facts, a dated follow-up in `docs/research/trash-and-last-used.md`; these feed the consolidated per-release Mac
      checklist (workflow, 2026-11-28).
- [ ] `docs/core-api.md` and `docs/wiki/index.md` current (clean-up page listed).
- [ ] **Done only when `macos-app` CI is green** on the integration PR.
