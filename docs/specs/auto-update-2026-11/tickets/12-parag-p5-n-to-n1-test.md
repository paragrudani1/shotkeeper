# 12: Parag's N → N+1 test on 0.2.0 → 0.2.1 (spec P5, changed)

**Type:** needs-human (Parag, on their Mac), with one agent step in the middle.

**What to do:** follow spec checklist **P5.1–P5.13** and send the report form. Changes from the spec text (Parag,
2026-11-28): there is **no approval click**: ignore "You approve each one in the Actions tab" in the P5 intro; each
release publishes by itself once its tag is pushed. The test uses **the first two real releases**, 0.2.0 and 0.2.1,
which are public before the prompt count is known.

**Blocked by:** 11 (0.2.0 published).

**Status:** needs-human

- [ ] Parag: P5.1–P5.6 on 0.2.0, then says "N ready" (P5.7).
- [ ] **Agent step:** on "N ready", add a `0.2.1` `CHANGELOG.md` section in a PR (a real change if one is ready,
      otherwise a notes-only release, which still exercises the update), merge it once `macos-app` is green, and push
      tag `v0.2.1` after Parag confirms. Check that its run is green and the feed shows 0.2.1.
- [ ] Parag: P5.7–P5.12 on the update; P5.13 (0.2.2) only if P5.8 counted a keychain or Desktop prompt. The agent
      publishes 0.2.2 the same way.
- [ ] Parag sends the filled report form. Spec real-Mac checks 1–9 can be done in the same session; the agent lists
      them for Parag alongside the form (ticket 13 records them).

**Test seam, CI:** the 0.2.1 (and 0.2.2) changelog PR counts only when `macos-app` is green on it, and the release runs must be green. **Real-Mac checks:** this ticket *is* the real-Mac test (P5 plus checks 1–9).
