# 10: README install, update and privacy text for releases

**What to build:** a new user can install from the Releases page and get past Gatekeeper the first time, an existing
user knows how to update and what a check contacts, and testers still find the CI-build steps.

**Blocked by:** 07 (the menu row exists), 09 (releases exist as described). Must merge before 11, so the 0.2.0 release
page links to accurate instructions.

**Status:** ready-for-agent

**Sources:** spec "README: install and update section (proposed text)" and "Also", stories 1–3, 19–21.

**Test seam:** none (docs). Reviewed against the spec text.

- [ ] "Install" and "Update" sections replace "Install the CI build", using the spec's proposed text. The bracketed
      line about dialogs after an update stays a visible placeholder ("measured in the first two releases") until
      ticket 13 fills it in.
- [ ] "Install a CI build (testers)" keeps today's steps and adds: a CI build counts as older than every release, so
      Check for Updates… moves it to the latest release.
- [ ] Privacy bullet: a check downloads `appcast.xml`, and on install the zip, from github.com; nothing else is
      sent; nothing happens without the click; system profiling stays at Sparkle's default (cite [S3]).
- [ ] Known limits: "signed with a self-signed certificate, not notarized; the first open needs Open Anyway".
- [ ] Build from source: source builds include the updater and count as build 1.
- [ ] **Done only when `macos-app` CI is green** on the PR.

**Real-Mac checks:** real-Mac check 9 (first install with Open Anyway on macOS 15+, as written) is done in P5.1
(ticket 12); fix the text in 13 if it differs.
