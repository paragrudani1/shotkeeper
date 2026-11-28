# 11: Publish 0.2.0 (build N of the test)

**What to build:** the first real release. Tag `v0.2.0` runs the release workflow end to end and publishes
`Shotkeeper-0.2.0.zip` and `appcast.xml` as the latest release, with no approval click.

**Blocked by:** 05 (environment and secrets), 08 (public key in the app), 09 (workflow), 10 (README). Pushing the tag
is outward-facing and public: confirm with Parag before pushing it.

**Status:** blocked (waits for Parag's P4)

**Sources:** spec "Slicing" 3, release flow steps 6–7, P5 intro.

**Test seam:** seam 3, the release run itself (plan, plist check, DR shape, asset sizes, feed comparison).

- [ ] `CHANGELOG.md` has the final `0.2.0` section on `main`; tag pushed with the push helper from AGENTS.md.
- [ ] Release run green; log shows the DR with `certificate leaf` and no `cdhash`; no secret or derived value in the
      log (read it through once).
- [ ] The release is published as latest; `curl` of `releases/latest/download/appcast.xml` matched the upload
      (step 7), which settles the redirect question [G4] for curl.
- [ ] If the run fails before publishing: at most a draft is left; fix in a PR, delete only the draft, re-tag only
      if the tag never produced a published release (record the decision in the wiki).
- [ ] Dated wiki line with the run ID and the result; then tell Parag "0.2.0 is out" to start ticket 12.
- [ ] `macos-app` CI green on the commit the tag points at.

**Real-Mac checks:** handed to Parag in ticket 12.
