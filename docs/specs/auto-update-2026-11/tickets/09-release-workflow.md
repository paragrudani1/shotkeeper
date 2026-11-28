# 09: Release workflow (tag `v*` → signed zip + appcast, published atomically)

**What to build:** pushing a tag such as `v0.2.0` runs a separate workflow that builds the app without secrets, signs
it with `Shotkeeper Release` in a temporary keychain, makes the zip and a one-item `appcast.xml`, and publishes the
GitHub Release only once both assets are uploaded. Any failure before publishing leaves at most a draft. **No
required approval:** the `publish` job uses `environment: release` for its tag rule and secrets, and runs without
waiting for a click (Parag's decision 2026-11-28, wiki `workflow.md`).

**Blocked by:** 01 (`release-plan`), 06 (shared Xcode and signing scripts), 07 (Sparkle tools from the SwiftPM
artifacts folder; plist check script). It can be written, reviewed and merged before Parag's P4: it only runs on a
tag. Its first real run is ticket 11, which needs 05 (secrets) and 08 (public key).

**Status:** ready-for-agent

**Sources:** spec "Release flow (one new workflow, two jobs)" steps 1–5 and 1–8, "The GitHub `release` environment and
its secrets" (minus the required reviewer), "Where the appcast is hosted", stories 22, 24–26, 29, 31–32.

**Test seam:** seam 3. Every step that can run without secrets is a script already exercised on every push by
`macos-app` (Xcode selection, signing with `-`, verification, plist check) or by Linux tests (`ReleasePlan`). The
workflow file adds only wiring, the keychain steps, `generate_appcast` and `gh release`.

- [ ] Trigger: `push` of tags `v*` only; no `pull_request` / `pull_request_target`. Concurrency group, no cancelling.
      Workflow permissions `contents: read`.
- [ ] Job `build` (no environment, no secrets, no `actions/cache`): shared Xcode script; previous tag from
      `gh release view --json tagName` ("none" if there is no release); `shotkeeper-cli release-plan`; `xcodegen
      generate`; Release build with `CODE_SIGNING_ALLOWED=NO` and the plan's `MARKETING_VERSION` /
      `CURRENT_PROJECT_VERSION` overrides; plist check with the expected versions and `SUPublicEDKey`; one artifact
      (`ditto`-archived app, Sparkle `bin/`, plan output).
- [ ] Job `publish` (`environment: release`, `contents: write`, needs `build`; only system tools and
      `generate_appcast`): random keychain password masked with `::add-mask::`; `.p12` decoded to `$RUNNER_TEMP`,
      keychain commands in the spec's order ([G1]), `.p12` deleted right after import; signing script with
      `Shotkeeper Release` and `--keychain`; verify plus the DR-shape check (`certificate leaf`, no `cdhash`); `ditto
      -c -k --sequesterRsrc --keepParent`; `generate_appcast --ed-key-file -` with the key on stdin from an `env:`
      variable (never an argument, never `-s`), `--embed-release-notes`, the release download prefix, a fresh folder
      holding only the new zip and its notes.
- [ ] Publish: `gh release create --draft` with both assets and `notes.md`; check both assets are listed with
      non-zero sizes; then `gh release edit --draft=false --latest`.
- [ ] Post-publish: `curl -fsSL` the `latest/download/appcast.xml` URL and compare byte-for-byte with the uploaded
      file; a mismatch fails loudly (fix by a follow-up release, never a deletion).
- [ ] `if: always()` cleanup: `security delete-keychain` and remove everything written to `$RUNNER_TEMP`.
- [ ] `actions/checkout`, `upload-artifact`, `download-artifact` pinned to full commit SHAs. No `set -x`, no echo of
      a secret or anything derived from one. No artifact or cache from `publish`.
- [ ] The release-notes file name `generate_appcast` matches to the archive is cited from Sparkle 2.10.1 source (or
      confirmed here if 01 couldn't).
- [ ] Proposed, not in the spec (the reviewer decides): `macos-app` also runs `release-plan` for the newest
      `CHANGELOG.md` section with `--previous none`, so a malformed changelog fails on push rather than on the tag.
- [ ] The workflow file parses (GitHub shows no "invalid workflow" error on the branch push).
- [ ] Dated wiki lines (`auto-update.md`): no required reviewer (Parag, 2026-11-28), two-job split, feed URL.
- [ ] **Done only when `macos-app` CI is green** on the PR. The release workflow's own first green run is ticket 11's
      acceptance, not this one's.

**Real-Mac checks:** none here; see 11–13.
