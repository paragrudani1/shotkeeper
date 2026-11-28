# 08: Parag's public EdDSA key in the app; CI requires it

**What to build:** the app carries `SUPublicEDKey` (Parag's public key from P2.6), so it accepts only updates signed
with the project's key and refuses any other (story 17). From this ticket on, CI and the release build fail if the
built app lacks the key.

**Blocked by:** 07 (Sparkle and the plist check exist); 03 (Parag's public key, P2.6).

**Status:** blocked (waits for Parag's P2)

**Sources:** spec "Info.plist keys" (`SUPublicEDKey`), stories 17, 35.

**Test seam:** seam 3, the plist check in `macos-app`.

- [ ] `SUPublicEDKey` in `App/project.yml` `info.properties`, exactly as Parag pasted it (it is public; commit it).
- [ ] The plist check requires `SUPublicEDKey` present and non-empty, in `macos-app` and (once 09 exists) the release
      build job.
- [ ] Dated wiki line: key added, date, where it came from (never anything about the private key).
- [ ] **Done only when `macos-app` CI is green** on the PR.

**Real-Mac checks:** the CI artifact still launches and "Check for Updates…" behaves as in 07 (no start-up error).
