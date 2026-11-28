# 02: Parag creates the `Shotkeeper Release` certificate (spec P1)

**Type:** needs-human (Parag, on their Mac). No agent can do this.

**What to do:** follow spec checklist **P1.1–P1.9** exactly: a self-signed **Code Signing** identity named
**`Shotkeeper Release`**, valid 7300 days, in the login keychain, exported as `~/ShotkeeperSecrets/shotkeeper-release.p12`
with a generated password saved in your password manager.

**Blocked by:** None (can start immediately).

**Status:** needs-human

- [ ] P1.7 passes: "Shotkeeper Release" under My Certificates has a private key under it. Trust settings unchanged.
- [ ] The `.p12` exists and its password is in the password manager.
- [ ] Parag tells the agent "certificate done". Nothing secret goes to the agent; the certificate name is fixed and
      public.

**Notes for the agent:** the certificate must never be rotated (spec "Further Notes"). Blocks 04 (backup) and,
through 05, the first release.

**Test seam, real-Mac checks, CI:** no code, so no test seam and no `macos-app` gate for this ticket itself. The acceptance boxes above are the check. The real-Mac part *is* the work.
