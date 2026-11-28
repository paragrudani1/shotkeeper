# 03: Parag creates Sparkle's EdDSA key (spec P2)

**Type:** needs-human (Parag, on their Mac).

**What to do:** follow spec checklist **P2.1–P2.7**: download Sparkle **2.10.1** (the pinned version), run
`generate_keys` once, paste the **public** key to the agent (P2.6), and export the private key to
`~/ShotkeeperSecrets/sparkle-private-key.txt` (P2.7).

**Blocked by:** None (can start immediately). Can run at the same time as 02.

**Status:** needs-human

- [ ] Exactly one key exists. If `generate_keys` says a key already exists, stop and tell the agent (P2.4).
- [ ] The public key is pasted to the agent (P2.6). It is public; it goes into `App/project.yml` in ticket 08.
- [ ] The private key file exists and has not been opened or pasted anywhere.

**Notes for the agent:** the private key is the one irreversible thing in this feature (spec "Further Notes").
Never ask for it. Blocks 04 (backup) and 08 (public key in the app).

**Test seam, real-Mac checks, CI:** no code, so no test seam and no `macos-app` gate for this ticket itself. The acceptance boxes above are the check. The real-Mac part *is* the work.
