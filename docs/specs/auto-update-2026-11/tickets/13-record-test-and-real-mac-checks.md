# 13: Record the N → N+1 result, real-Mac checks, finish the README

**What to build:** the wiki holds the measured prompt counts and the real-Mac check results, and the README says what
a user sees after an update. If any prompt remained, the decision goes back to Parag and nothing about signing changes.

**Blocked by:** 12 (Parag's report).

**Status:** blocked (waits for Parag's P5)

**Sources:** spec P5 "Decision rule", "Real-Mac checks" 1–9, "README" bracketed parts, story 37.

**Test seam:** none (docs); the evidence is Parag's report.

- [ ] Wiki `auto-update.md`: the full report, dated, plus real-Mac checks 1–9 with pass/fail each (1: "You're up to
      date" proves Sparkle follows the `latest/download` redirect; 6: three screenshots during Install and Relaunch
      all renamed, indexed and undoable; 7: no `mlx` process left after an update; 8: no App Management notice).
- [ ] Decision rule applied exactly: 0 keychain dialogs, no Desktop prompt, no Gatekeeper dialog, one Login Items and
      one Files & Folders entry → the self-signed plan stands and the README says "no dialogs". **Otherwise** record
      the numbers and send the choice back to Parag (accept the prompts, Developer ID, or something else they name).
      No agent changes the signing approach; the EdDSA key stays either way.
- [ ] README: fill in the dialogs line and the "never run on a real Mac" known-limit bullet; correct the install
      text if P5.1 differed.
- [ ] Any failed real-Mac check becomes a new ticket (a fix ships as a later release, never by deleting one).
- [ ] Note for feature 3 (Spotlight): test against a release build, not a CI artifact (spec "Further Notes").
- [ ] **Done only when `macos-app` CI is green** on the docs PR.
