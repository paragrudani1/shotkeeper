# 10: Integrate wave 2 and verify on a real Mac

**What to build:** the wave 2 integration branch merges into main as one checked whole: every spec requirement met
or recorded as a dated deviation (CODING_STANDARDS #7), the real-Mac checks run together on Parag's Mac, and the
wiki and code map current.

**Blocked by:** 01–09.

**Status:** ready-for-agent (the real-Mac part needs Parag)

**Sources:** spec (all), design §11, CODING_STANDARDS #7, `docs/wiki/appkit-gotchas.md`.

**Test seam:** none new; the full suites and the CI snapshot artifact.

- [ ] Integration branch rebased or merged on current main; migration version re-checked against main (02's number is
      still the next free one, `shippedColumns` versions run 1, 2, 3…).
- [ ] `git grep -n -i "analyse"` over `Sources App Tests CODING_STANDARDS.md docs/core-api.md` finds nothing
      (American spelling; main at `0e755e8` has three doc comments saying "re-analyse" in `AppCoordinator.swift`,
      `FileActions.swift` and `SearchResultActions.swift`, which whichever ticket touches them fixes);
      `ProcessExisting` type names gone (01).
- [ ] Every story in the spec ticked against the code or given a dated deviation in
      `docs/wiki/subfolders-and-retitle.md`; the design departures (§12) recorded as implemented.
- [ ] Every snapshot name listed in tickets 04, 05, 07, 08, 09 present in the CI artifact, light and dark, and looked at.
- [ ] Real-Mac pass (Parag): the checks listed in 04, 05, 07, 08 and 09, plus the migration on the real index (rows kept,
      names fixed in the toast earlier now count as "your name").
- [ ] `docs/core-api.md` and `docs/wiki/index.md` current.
- [ ] **Done only when `macos-app` CI is green** on the integration PR into main.
