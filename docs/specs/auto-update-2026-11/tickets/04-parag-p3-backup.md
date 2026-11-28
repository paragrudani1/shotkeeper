# 04: Parag backs up both keys offline (spec P3)

**Type:** needs-human (Parag).

**What to do:** follow spec checklist **P3.1–P3.5**: an encrypted USB drive with `~/ShotkeeperSecrets`, both files
attached to a password-manager note, the drive stored away from the Mac.

**Blocked by:** 02 (certificate), 03 (Sparkle key).

**Status:** needs-human

- [ ] Both files on the encrypted drive and in the password-manager note.
- [ ] Parag tells the agent "backups done" (P3.5).

**Notes for the agent:** the spec orders this before anything uses the keys, so the secrets step (05) waits for it.
GitHub secrets can't be read back; GitHub is not a backup.

**Test seam, real-Mac checks, CI:** no code, so no test seam and no `macos-app` gate for this ticket itself. The acceptance boxes above are the check. The real-Mac part *is* the work.
