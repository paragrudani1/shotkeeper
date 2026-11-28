# Auto-update spec (feature 8, 2026-11-28)

Parag's requirements are copied verbatim below. Do not edit them. Everything after them is synthesis by the design
sub-agent (2026-11-28) and must not contradict them. Add dated implementation notes and deviations to the wiki
(`docs/wiki/auto-update.md`, once it exists), not here.

## Requirements (Parag, 2026-11-28)

> 2026-11-28: "Signed, notarized builds with auto-update." (approved: "let's do all of it")

Parag's later decisions on the same day. The wiki records these in its own words, not Parag's exact wording. Source:
`docs/wiki/workflow.md`, 2026-11-28 entries "Parag's decisions on scope", "More decisions from Parag" and
"Auto-update decisions (Parag)".

> 2026-11-28 (decision): auto-update only. There is no Apple Developer Program membership, so builds are not
> notarized and have no Developer ID.

> 2026-11-28 (decision): Sparkle is allowed as the one third-party dependency, with a pinned version.

> 2026-11-28 (decision): a self-signed certificate, tested first on Parag's Mac by updating build N → N+1 and counting
> the prompts. If prompts remain, the decision goes back to Parag.

> 2026-11-28 (decision): update checks are manual only: a "Check for Updates…" menu item, and no automatic checks.

---

## Basis

- Code state: `d8e5b17` (branch `t3/roadmap-2026-11`; `main` at `b5c2984`). App layout: prefactor B, PR #10, branch
  `origin/t3/prefactor-app` (head `06d1aea`, review verdict "fix first", not merged yet), described in
  `docs/wiki/prefactor-app.md` on that branch. **This spec assumes PR #10's shape. If it merges with a different shape,
  follow the merged code, not this text.**
- Facts: `docs/research/auto-update.md`. This spec cites its labels: [S1]–[S9] (Sparkle), [A1]–[A17] (Apple), [G1]–[G6]
  (GitHub) and [R1]–[R3] (repo). A claim the research marks *inferred* or *must test* keeps that status here.
- CI today: `.github/workflows/ci.yml`, job `macos-app`. It builds the Release app with `CODE_SIGNING_ALLOWED=NO` and
  then runs `codesign --force --deep --sign -`. The artifact is `Shotkeeper-unsigned`. See `docs/wiki/macos-ci.md`.
- Project: `App/project.yml` sets `CODE_SIGN_IDENTITY "-"`, `ENABLE_HARDENED_RUNTIME: NO`, no sandbox,
  `MARKETING_VERSION 0.1.0`, `CURRENT_PROJECT_VERSION "1"` (fixed) and bundle ID `dev.shotkeeper.Shotkeeper` [R2].
- Survey: `docs/wiki/roadmap-survey.md`, feature 8 and hotspots (`ci.yml` and `project.yml` are shared with feature 3;
  `AppCoordinator` and the menu are shared with 3–6).

## Problem Statement

Today the only way to get Shotkeeper is a CI artifact. It expires after 14 days, it lives in the Actions tab behind
a GitHub login, it is wrapped in a zip inside a zip, and the user has to strip quarantine by hand. Nothing tells
the user that a newer build exists. Getting a fix means repeating the whole manual install, and nobody knows
whether the user's saved keys, the Desktop permission and launch at login survive the swap. Ad-hoc signing ties
the app's identity to one exact binary [A1], so every new build probably looks like a different app to macOS: up to
three keychain dialogs and a new Desktop prompt per update ([A5], [A6], [R1]; inferred in the research).

## Solution

Every tagged version becomes a normal GitHub Release. It contains a zip of the app, signed with Parag's one
self-signed certificate, and an `appcast.xml` feed signed with Sparkle's EdDSA key. The user installs once from the
Releases page, then chooses **Check for Updates…** in the Shotkeeper menu whenever they want to. Sparkle shows the
new version and its release notes, then downloads, verifies, installs and relaunches. The app never checks on its
own. Because every release is signed with the same certificate, macOS should see one stable app across updates
([A3]: "Self-signed identities … work by default" for the keychain). Whether TCC and the keychain partition agree is
not documented ([A8]), so the first two releases double as Parag's N → N+1 test. If prompts remain, the
choice goes back to Parag.

## User Stories

1. As a new user, I want to download Shotkeeper from the repository's Releases page, so that I don't need a GitHub
   login, the Actions tab or an artifact that expires.
2. As a new user, I want one zip that contains only `Shotkeeper.app`, so that installing is "unzip, move to
   Applications, open".
3. As a new user on macOS 15 or later, I want the README to tell me exactly how to get past Gatekeeper the first
   time (Privacy & Security → Open Anyway, or the `xattr` command), so that the one-time block doesn't look like a
   broken app.
4. As a user, I want a "Check for Updates…" item in the Shotkeeper menu, so that I can look for a newer version
   whenever I choose.
5. As a user, I want Shotkeeper never to check for updates by itself, so that it makes no network request I didn't
   ask for.
6. As a user, I want no "Check for updates automatically?" question on the second launch, so that the app doesn't
   ask me about a feature it doesn't have.
7. As a user, I want the update window to come to the front when I choose the menu item, even though Shotkeeper
   has no Dock icon, so that I can see the result.
8. As a user who is up to date, I want a clear "You're up to date" answer, so that I know the check ran.
9. As a user with an update available, I want to see the new version number and what changed before installing,
   so that I can decide whether to update now.
10. As a user, I want to install the update and have Shotkeeper relaunch itself, so that I don't have to download,
    unzip or drag anything again.
11. As a user, I want the updated app to open without another Gatekeeper block, so that updating is less work than
    the first install (Sparkle removes quarantine itself; source code [S8]; must test).
12. As a user, I want my saved Cloudflare token, OpenRouter key and custom-endpoint key to keep working after an
    update without dialogs, so that updating doesn't feel like reinstalling.
13. As a user, I want Desktop access and launch at login to survive an update, so that screenshots keep being
    processed and Shotkeeper still starts when I log in.
14. As a user, I want screenshots taken just before I clicked "Install and Relaunch" to be finished after the
    relaunch, with no file lost or half-renamed, so that updating is safe at any moment.
15. As a user offline or with GitHub down, I want "Check for Updates…" to show an error and leave everything else
    working, so that a failed check costs nothing.
16. As a user, I want the menu item disabled while a check or an install is already running, so that I can't start
    two at once.
17. As a user, I want Shotkeeper to refuse an update that wasn't signed with the project's key, so that nobody can
    push me a fake build through a hijacked download.
18. As a user, I want Shotkeeper never to install an older version over a newer one, so that a mistake in the feed
    can't roll me back.
19. As a user with a CI build installed, I want "Check for Updates…" to move me to the latest release, so that
    testers end up on the normal path.
20. As a privacy-minded user, I want the README's Privacy section to say what a check contacts (github.com and its
    download host) and that nothing is sent automatically, so that I can trust the app's network behaviour.
21. As a user, I want About to show the version I'm running, so that I can tell whether an update worked.
22. As Parag, I want to cut a release by pushing a tag such as `v0.2.0`, so that releasing is one command plus one
    approval click.
23. As Parag, I want a release to wait for my approval in GitHub before it can use the signing secrets, so that a
    stray tag can't publish a build.
24. As Parag, I want the release to fail before publishing anything when the version isn't higher than the last
    release, when the changelog has no entry for it, or when signing fails, so that a broken release never reaches
    users.
25. As Parag, I want the release published only once every asset is uploaded, so that no user ever sees a release
    without its zip or feed.
26. As Parag, I want the release notes written once, in the changelog, and used for both the GitHub Release page
    and Sparkle's update window, so that the two never disagree.
27. As Parag, I want a step-by-step checklist for the certificate, the Sparkle key, the GitHub secrets and the
    backups, so that I can do my part without knowing code signing.
28. As Parag, I want an exact procedure and report form for the N → N+1 test, so that the prompt count is
    measured, not guessed.
29. As Parag, I want the private keys to stay out of the public repo, its logs, its artifacts and its caches, so
    that publishing the source never exposes them.
30. As Parag, I want an offline backup of the EdDSA key and the certificate, so that losing a laptop doesn't end
    auto-update for every installed copy.
31. As a maintainer, I want the build number to be computed from the tag, so that it always rises and two
    releases can never share one.
32. As a maintainer, I want the release's signing script to run on every CI push with an ad-hoc identity, so that
    the first real release isn't the first time it runs.
33. As a maintainer, I want Sparkle pinned to one exact version and imported in one app file only, so that the
    dependency stays contained and every upgrade is a reviewed change.
34. As a maintainer, I want the version and release-notes rules in core with Linux unit tests, so that they are
    tested without a Mac.
35. As a maintainer, I want CI to fail if the built app lacks the feed URL or the public key, or has automatic
    checks on, so that a broken configuration can't ship.
36. As a maintainer, I want the exception to "no third-party dependencies" written into the docs with its date, so
    that later agents don't remove Sparkle or add a second dependency by analogy.
37. As a future agent, I want the decision path back to Parag documented (prompts remain → Developer ID, accept the
    prompts, or something else), so that I don't quietly change the signing approach.

## Implementation Decisions

### Release flow (one new workflow, two jobs)

A new workflow, separate from CI, is triggered only by `push` of tags matching `v*`. It has no `pull_request` and no
`pull_request_target` trigger [G3]. It runs one release at a time (a concurrency group with no cancelling).
Workflow-level permissions are `contents: read`.

**Job 1, `build` (no environment, no secrets, `contents: read`).** It runs everything that downloads or runs
third-party tooling: Homebrew's XcodeGen, SwiftPM's Sparkle package and Xcode. No secret is present while that code
runs.
1. Select Xcode exactly as `macos-app` does. Move that step into a shared script so the two jobs can't drift.
2. **Release plan.** Read the previous release's tag (`gh release view --json tagName`; the repo is public, so the
   read-only token works; "none" for the first release). Then run `shotkeeper-cli release-plan --tag <tag>
   --previous <tag|none> --changelog CHANGELOG.md --out <dir>`. It prints the marketing version, the build number
   and the zip name, and writes the release-notes HTML and Markdown files. Any error fails the release here,
   before anything is built (see "Core seam").
3. `xcodegen generate`, then `xcodebuild build` (Release) with `CODE_SIGNING_ALLOWED=NO`,
   `MARKETING_VERSION=<plan>` and `CURRENT_PROJECT_VERSION=<plan>` as command-line overrides. There is no
   `xcodebuild test` here: CI already ran the tests on that commit.
4. Check the built Info.plist: `CFBundleVersion` and `CFBundleShortVersionString` equal the plan,
   `SUEnableAutomaticChecks` is false, and `SUFeedURL` and `SUPublicEDKey` are present and non-empty.
5. Upload one short-lived artifact: the unsigned `Shotkeeper.app` (archived with `ditto`, so symlinks survive),
   Sparkle's `bin/` tools from the SwiftPM artifacts folder [S1], and the plan output. Nothing in it is secret.
   It is public like every artifact of a public repo.

The build job uses **no `actions/cache`**. This closes off cache poisoning into a release, and a clean build costs
only a few minutes.

**Job 2, `publish` (`environment: release`, `contents: write`, needs `build`).** No checkout of build tooling, no
Homebrew, no SwiftPM. It uses only the macOS runner's own `security`, `codesign`, `ditto` and `gh`, plus Sparkle's
`generate_appcast` from job 1.
1. **Temporary keychain** [G1]: generate a random keychain password inside the job and register it with
   `::add-mask::`. It is not a stored secret, because [G1] says it "can be any new random string". Decode
   `SIGNING_CERT_P12_BASE64` into `$RUNNER_TEMP`, then run `create-keychain`, `set-keychain-settings -lut 21600`,
   `unlock-keychain`, `import … -P "$SIGNING_CERT_P12_PASSWORD" -A -t cert -f pkcs12 -k`,
   `set-key-partition-list -S apple-tool:,apple: -k`, and `list-keychains -d user -s`, in that order. Delete the
   decoded `.p12` right after the import.
2. **Sign inside-out, never `--deep`** ([S5]; `SUInstallerLauncher.m` warns about `--deep`), with the identity
   **`Shotkeeper Release`** (the fixed certificate name in Parag's checklist) and `--keychain <temp>`:
   1. Sparkle's XPC services, if present;
   2. `Autoupdate`;
   3. `Updater.app`;
   4. `Sparkle.framework`;
   5. `Shotkeeper.app`.

   The implementer copies the exact per-item flags from [S5]'s example and cites it next to the script. Sparkle's
   helpers ship with Hardened Runtime on; keep it on for them. The **app itself keeps Hardened Runtime off**: with
   Library Validation on, a non-Team-ID signature may stop Sparkle from loading ([S1]; [R2] has it off).
3. Verify with `codesign --verify --deep --strict --verbose=2`. `--deep` is banned only for *signing*.
   `codesign --display -r -` must show `certificate leaf` and must not show `cdhash` (the DR shape from [A8]).
   The DR goes to the log; it is public by nature.
4. **Zip**: `ditto -c -k --sequesterRsrc --keepParent Shotkeeper.app Shotkeeper-<version>.zip`, containing only
   the app [S1][S2].
5. **Appcast**: in a fresh folder, put only the new zip and its release-notes file. Then run
   `generate_appcast --ed-key-file - --embed-release-notes --download-url-prefix
   https://github.com/paragrudani1/shotkeeper/releases/download/v<version>/ -o appcast.xml <folder>`. The private
   key goes in through an `env:` variable piped to stdin, never as an argument ([S8] `generate_appcast/main.swift`;
   [G2]). The `-s` option is deprecated as "insecure" [S7].
   - **The appcast holds only the newest release.** Updates are full zips, never deltas (out of scope), so Sparkle
     only needs the newest item. This avoids merging an older feed, whose behaviour the research marks "must be
     checked in a dry run". The cost: a user who skips versions sees only the newest notes.
   - The research does not cover how `generate_appcast` matches a release-notes file to its archive (file name
     and extension). The implementer reads that in `generate_appcast` at 2.10.1 and cites it.
   - The "mismatch code signing identity" warning [S8] should not appear between two self-signed releases. It
     does appear once, harmlessly, when the update source is an ad-hoc CI build.
6. **Publish atomically**: `gh release create v<version> --draft --title "Shotkeeper <version>" --notes-file
   <plan notes .md> Shotkeeper-<version>.zip appcast.xml`. Then check that the draft lists both assets with
   non-zero sizes. Only then run `gh release edit v<version> --draft=false --latest`. If any earlier step fails,
   at most a draft is left behind, and users never see a draft [G5].
7. **Post-publish check**: `curl -fsSL` the stable feed URL (below) and confirm it is byte-identical to the uploaded
   `appcast.xml`. This also settles whether the `latest/download` redirect works ([G4]; not verified in the
   research). A mismatch fails the job loudly. The release is already public by then, so the fix is a follow-up
   release, never a deletion.
8. An `if: always()` step runs `security delete-keychain` and removes everything the job wrote to `$RUNNER_TEMP`
   [G1].

Third-party actions (`actions/checkout`, `actions/upload-artifact`, `actions/download-artifact`) are pinned to
full commit SHAs in this workflow [G3]. No step uses `set -x`, and no step echoes a secret or anything derived
from one.

### The existing CI job uses the same signing script

`macos-app` stops calling `codesign --force --deep --sign -`. It calls the same inside-out signing script with
the ad-hoc identity `-`. It then runs the same verification and the same Info.plist key check as `build` step 4.
So every push exercises the script and the plist check, and the first release is not their first run. The CI
artifact stays ad-hoc signed (`Shotkeeper-unsigned`, build number 1). The CI job never sees a secret.

### Where the appcast is hosted

`SUFeedURL` = `https://github.com/paragrudani1/shotkeeper/releases/latest/download/appcast.xml`.
- Why: GitHub serves "your latest release asset" at `/releases/latest/download/<asset>` [G4]. "Latest" is the
  newest non-draft, non-pre-release [G5], so drafts and pre-releases never reach users. Publishing the release
  and the feed is one action, and nothing else needs hosting.
- Rejected:
  - **GitHub Pages** (Pages setup, a deploy step with `pages: write`, a second place that can drift from
    Releases);
  - **`appcast.xml` committed to `main`** (the release job would need to push to `main`; raw URLs are cached).
- Risks: Sparkle following the redirect is *inferred* (URLSession follows redirects by default). Release step 7
  checks the URL, and real-Mac check 1 checks it in Sparkle itself. "Latest" is sorted by `created_at` [G5];
  passing `--latest` explicitly guards against an older tag being released later. If the redirect turns out to
  break Sparkle, GitHub Pages is the fallback. That would change `SUFeedURL`, which only a release can do, so
  the fallback must be decided before the first release ships.

### The GitHub `release` environment and its secrets

Environment **`release`**:
- deployment rule "Selected branches and tags", **tag pattern `v*`**;
- **required reviewer: Parag**;
- three environment secrets (not repository secrets):

| Secret | Contents | Used by |
| --- | --- | --- |
| `SPARKLE_ED_PRIVATE_KEY` | the one-line file from `generate_keys -x` (base64 of a 32-byte ed25519 seed [S8]) | `generate_appcast --ed-key-file -` via stdin |
| `SIGNING_CERT_P12_BASE64` | `base64 -i shotkeeper-release.p12` | temp keychain import |
| `SIGNING_CERT_P12_PASSWORD` | the `.p12` export password | temp keychain import |

The keychain password is generated per run, so it is not a secret Parag stores. The certificate name
`Shotkeeper Release` is fixed in the workflow; it is not a secret. `SUPublicEDKey` is public and committed in
`App/project.yml`.

**Why none of them can leak, even though the repo, its logs and its artifacts are public:**
- **Forks and PRs never run with them.** The release workflow has no PR trigger. GitHub doesn't pass secrets to
  workflows triggered from a fork [G2]. Environment secrets are "only available to workflow jobs that use the
  environment", and only after its protection rules pass [G6]. CI's PR jobs reference no environment.
- **Only a `v*` tag can enter the environment, and only with Parag's click.** Pushing a tag needs write access,
  which only Parag has. A tag ruleset restricting who may create, update or delete `v*` tags is recommended (step
  P4.6). Even someone with write access who edited the workflow at a tag would still wait for Parag's approval,
  and the approval page shows the commit.
- **Secrets are only present where no third-party code runs.** The `build` job, which runs Homebrew, XcodeGen,
  SwiftPM and Xcode, gets no secret. The `publish` job runs only system tools plus Sparkle's `generate_appcast`.
  That is the pinned dependency we already trust to verify our updates, and the key reaches it on stdin.
- **Logs**: no `echo`, no `set -x`. GitHub masks registered secrets. The generated keychain password is masked
  with `::add-mask::`. Nothing derived from a secret (decoded bytes, file contents) is printed. "Base64 … is not a
  substitute for actual encryption" [G2], so the `.p12` base64 is handled as the secret it is.
- **Command lines**: no secret appears as an argument ("Command-line processes may be visible to other users"
  [G2]). The key goes through stdin. The `.p12` password goes through an `env:` variable into `security import -P`.
  That is an argument, but on a single-tenant, ephemeral GitHub-hosted VM, and it is the form [G1] documents.
  The temp keychain is deleted at the end.
- **Artifacts and caches**: the publish job uploads no artifacts and uses no cache. The only things it publishes
  are the signed zip and the appcast. The app's signature contains the certificate's public part, which is meant
  to be public; the private key is never in the bundle.
- **Releases**: assets are the zip and `appcast.xml`. Release notes come from the reviewed `CHANGELOG.md`.

### Build number

`CFBundleVersion` "must increase with each release" [S1], and Sparkle refuses downgrades ([S8]
`SUPlainInstaller.m`). Today it is fixed at `"1"` [R2].
- **The tag is the single source of truth.** Tag `vMAJOR.MINOR.PATCH` gives marketing version `MAJOR.MINOR.PATCH`
  and **build number `MAJOR×10000 + MINOR×100 + PATCH`**. For example, `v0.2.0` → `200` and `v1.0.0` → `10000`.
  - It is deterministic. Re-running a failed release gives the same number, and a tag gives the same number
    forever.
  - It needs no state (unlike `github.run_number`).
  - It rises exactly when the version rises.
- Constraints, enforced by the release plan:
  - `MINOR` and `PATCH` are 0–99;
  - no pre-release or build suffixes;
  - the version is ≥ 0.1.0, so every release number is ≥ 100 and above the dev and CI build's `1`;
  - the version is strictly greater than the previous release's.
- `App/project.yml` keeps `MARKETING_VERSION 0.1.0` and `CURRENT_PROJECT_VERSION 1` as **dev defaults**. Releases
  override both on the `xcodebuild` command line. So a CI or source build always counts as older than any release,
  and "Check for Updates…" moves it to the latest release (story 19).
- If the formula ever changes, the new numbers must stay above every number already published. Record that in
  the wiki at the time.

### Info.plist keys (all in `App/project.yml` `info.properties`) [S3]

| Key | Value | Why |
| --- | --- | --- |
| `SUFeedURL` | `https://github.com/paragrudani1/shotkeeper/releases/latest/download/appcast.xml` | HTTPS feed [S1] |
| `SUPublicEDKey` | Parag's public key from `generate_keys` (step P2) | mandatory for an app without a Team ID (research §1) |
| `SUEnableAutomaticChecks` | `false` | **no automatic checks.** Setting it also stops Sparkle's permission question on the second launch, which it asks only when the key is unset [S3] |
| `SUAutomaticallyUpdate` | `false` | explicit; it is already the default [S3] |
| `SUAllowsAutomaticUpdates` | `false` | hides the "Automatically download and install updates" choice in the update window, so the user can't switch on what the requirement rules out. **Not in the research note**: the implementer confirms the key and its effect in [S3] and cites it |
| `SUVerifyUpdateBeforeExtraction` | `true` | checks the EdDSA signature before unzipping. [S3] advises it if "you aren't likely to lose access to your private EdDSA key", and the offline backup (P3) is part of this spec |

- Not set: `SUScheduledCheckInterval` (no scheduled checks), `SUEnableInstallerLauncherService` and
  `SUEnableDownloaderService` (non-sandboxed apps don't use them [S5]), and system profiling (left at Sparkle's
  default; the implementer cites [S3] for that default in the README privacy line).
- `SURequireSignedFeed` (2.9+, needs `SUVerifyUpdateBeforeExtraction` [S1]) is left out of this spec. The feed is
  served over HTTPS from GitHub, and the research doesn't cover how feed signing works with `generate_appcast`.
  It can be added later: older apps simply don't require it.
- Hardened Runtime stays **off** for the app ([S1] Library Validation; [R2]).

### Dependency

- Sparkle **2.10.1** ([S9], latest stable on 2026-11-28; it needs macOS 12, and we target 14 [S8]), added to
  `App/project.yml` `packages:` with **`exactVersion: 2.10.1`**, not `from:`. It is a binary target with a
  checksum in its `Package.swift` [S8]. The research says the XcodeGen declaration is inferred, not tested, so
  the first CI run is the test.
- It is linked by the **app target only**. The root `Package.swift` (core, CLI, Linux) never depends on Sparkle.
- Docs: add a dated line to `docs/wiki/architecture.md` next to "No third-party dependencies": Sparkle 2.10.1,
  pinned, app target only, approved by Parag 2026-11-28, the only exception. Add a matching line to the AGENTS.md
  layout section. Upgrading Sparkle is its own PR that re-runs the real-Mac checks.
- `scripts/lint.sh` (from PR #10) gains a rule **`sparkle-import`**: `import Sparkle` is allowed only in the
  update-checks file. Mechanical rules belong in CI, as CODING_STANDARDS says.

### The menu item and where update code lives (prefactor B's conventions)

- **`UpdateChecks`**, its own file under the app's `Coordinator/` folder, as `prefactor-app.md` asks. It is the
  only file that imports Sparkle.
  - It owns one `SPUStandardUpdaterController` [S4], created with `startingUpdater: false` and started from
    `AppCoordinator.startServices()`. It is not started while `RuntimeEnvironment.isRunningUnitTests` is true;
    tests run hosted in the app.
  - It exposes `canCheckForUpdates` (observable, mirrored from the updater's KVO property [S4]) and
    `checkForUpdates()`.
  - The coordinator owns it as `coordinator.updates`, like `capture` and `fileActions`. A small host protocol is
    added only if it ever needs coordinator state; today it needs none.
- **Menu**: `MenuRowID` gains `.checkForUpdates`. The row "Check for Updates…" sits **between "About Shotkeeper"
  and "Quit Shotkeeper"**, after the existing divider. That follows the macOS app-menu convention of About, then
  Check for Updates. It has no shortcut. It is **disabled** while `canCheckForUpdates` is false; a disabled row
  is skipped by ↑/↓, like the other rows. It is always shown, including before setup: updating doesn't depend on
  a backend.
- **Action**: `AppDelegate.perform(.checkForUpdates)` closes the menu panel, then calls `NSApp.activate()` the way
  `.about` does, then `coordinator.updates.checkForUpdates()`. Sparkle's standard windows do the rest. A
  Dock-less app needs the activation so the window comes to the front (story 7; real-Mac check 2). Sparkle's
  gentle-reminder API [S6] is for scheduled checks only, so it is not needed.
- **Quit during install**: Sparkle quits the app normally, so `applicationWillTerminate` runs as it does today.
  It commits secret drafts, stops services and terminates the managed processes (CODING_STANDARDS #5). Rows still
  pending are re-queued at the next launch by `CaptureSources`, so nothing is lost (real-Mac check 6).
- **UI design pass**: the only new UI is one menu row with fixed copy. The update windows are Sparkle's standard
  ones. **This spec proposes skipping the separate design pass** (see "Decisions Parag might disagree with").
  The row gets menu snapshot states (enabled, disabled).

### Core seam: `ReleasePlan` (the one new seam, Linux-tested)

No feed parsing and no in-app version comparison are ours: Sparkle parses the appcast and compares versions, and
`generate_appcast` writes the feed. The rules that are ours are the release job's, so they go in one core
function, called by a new CLI subcommand:

```swift
// Shape only; names may change in review.
public struct ReleasePlan: Equatable, Sendable {
    public var marketingVersion: String   // "0.2.0"
    public var buildNumber: Int           // 200
    public var tag: String                // "v0.2.0"
    public var archiveName: String        // "Shotkeeper-0.2.0.zip"
    public var title: String              // "Shotkeeper 0.2.0"
    public var notesMarkdown: String      // the CHANGELOG section body, for the GitHub Release
    public var notesHTML: String          // the same, rendered and escaped, for Sparkle's window
    public static func make(tag: String, previousTag: String?, changelog: String) throws(ReleasePlanError) -> ReleasePlan
}
```

- **Version rules**: parsing `vMAJOR.MINOR.PATCH`, the build-number formula, the constraints above, and "strictly
  greater than `previousTag`" (compared numerically, so `0.10.0` > `0.9.0`).
- **Release notes**: `CHANGELOG.md` at the repo root (new file) has one `## <version> (<date>)` section per release,
  newest first. The plan takes that version's section body. A missing or empty section is an error.
  - HTML rendering covers a deliberately small subset: paragraphs, `- ` bullet lists, and inline `` `code` ``.
    Everything else is escaped as text, so a stray `<` can never become markup in Sparkle's window.
  - The first `CHANGELOG.md` entry is written in the implementation PR.
- **Errors** (`ReleasePlanError`) each carry the one line the release log shows, for example "Tag v0.2 is not
  vMAJOR.MINOR.PATCH" or "CHANGELOG.md has no section for 0.2.1".
- **CLI**: `shotkeeper-cli release-plan --tag … --previous …|none --changelog … --out <dir>`. It writes
  `notes.md` and the release-notes HTML under the name `generate_appcast` expects, then prints `key=value` lines
  for `$GITHUB_OUTPUT`. The AGENTS.md layout line for the CLI changes from "live analyzer calls" to "live analyzer
  calls and release tooling".

### README: install and update section (proposed text)

This replaces "Install the CI build". The implementer fills in the bracketed parts after Parag's N → N+1 test.

> ## Install
>
> 1. Download `Shotkeeper-<version>.zip` from the [latest release](https://github.com/paragrudani1/shotkeeper/releases/latest)
>    and double-click it to unzip.
> 2. Move `Shotkeeper.app` to `/Applications` **before you open it**. Launch at login only works from there, and
>    updates replace the app where it is.
> 3. Open it. Shotkeeper is signed with its own certificate but not notarized by Apple, so macOS blocks it the
>    first time. Open **System Settings → Privacy & Security**, scroll to the message about Shotkeeper, choose
>    **Open Anyway** and confirm. Or, in Terminal, run `xattr -dr com.apple.quarantine /Applications/Shotkeeper.app`
>    and open it again. You only do this once.
> 4. It has no Dock icon; look for its icon in the menu bar.
>
> ## Update
>
> Shotkeeper never checks for updates by itself. To check, open the Shotkeeper menu and choose **Check for
> Updates…**. If a newer version exists, you see what changed. Choose **Install Update**, and Shotkeeper
> replaces itself and relaunches. Updates are verified with the project's signing key before they are installed.
> [After an update, macOS may ask … — fill in from the N → N+1 result, or "no dialogs" if there were none.]
>
> ### Install a CI build (testers)
>
> [The current "Install the CI build" steps, unchanged. Add: a CI build counts as older than every release, so
> Check for Updates… moves it to the latest release.]

Also:
- **Privacy**: a bullet saying that "Check for Updates…" downloads `appcast.xml`, and if you install, the zip, from
  github.com (GitHub sees an ordinary HTTPS request from your Mac); nothing else is sent, and nothing happens
  without the click.
- **Known limits**: "The build is unsigned and not notarized" becomes "signed with a self-signed certificate, not
  notarized; the first open needs Open Anyway". The "never run on a real Mac" bullet is updated after the test.
- **Build from source**: one line saying that source builds include the updater and count as build 1.

### Slicing

1. **Core + CLI**: `ReleasePlan`, its tests, the `release-plan` subcommand and the first `CHANGELOG.md`. It is
   Linux-testable, and it still needs `macos-app` green (AGENTS.md).
2. **App + CI + release workflow**: the Sparkle package, `UpdateChecks`, the menu row and snapshots, the Info.plist
   keys (needs Parag's public key from P2), the shared signing and Xcode scripts, the `macos-app` change, the
   release workflow, the lint rule, README, the wiki page `docs/wiki/auto-update.md`, and the architecture and
   AGENTS lines. It depends on PR #10 and on slice 1.
3. **The first two releases are Parag's test** (P5). There is no separate dry-run mechanism. A failed publish
   leaves at most a draft (release step 6).

## Testing Decisions

- **Good tests** check what a person sees: the version and build number a tag produces, the notes text a user
  reads, the error line Parag reads in the log, the menu rows a user can reach. They don't check private
  helpers, regexes or call counts. No test needs the network, Sparkle or a Mac.
- **Seam 1 (new, the only new one): `ReleasePlan.make`**, in core, under `Tests/ShotkeeperCoreTests`. Prior art:
  the pure-function tests `FilenameSanitizerTests` and `MenuTextTests`. Changelog samples go in `Fixtures`. It
  covers:
  - tag parsing, including rejections: no `v`, two parts, suffixes, leading zeros, minor or patch over 99, below
    0.1.0;
  - the build-number formula and that it rises with every version step;
  - previous-tag ordering: equal, lower, `0.10.0` vs `0.9.0`, and none for the first release;
  - changelog section selection: the right version among several, the last section in the file, a missing
    section, an empty section, a version that is a prefix of another (`0.2.1` vs `0.2.10`);
  - HTML rendering: bullets, paragraphs, inline code, and escaping of `<script>`, `&` and quotes;
  - the archive name and title.
- **Seam 2 (existing): the menu's `MenuViewState.rows`** plus the menu snapshot catalog. Prior art:
  `ToastAndMenuTests` (row order) and `MenuSnapshots`. It covers "Check for Updates…" between About and Quit,
  and that the disabled state drops it from the ↑/↓ order. App side, so CI only.
- **Seam 3 (existing): the CI workflow itself.** On every push, `macos-app` runs:
  - the shared signing script with `-`;
  - `codesign --verify --deep --strict`;
  - the Info.plist key check (feed URL and key present, automatic checks false).

  The release workflow re-runs the same checks with the real identity, plus the DR shape and the post-publish
  feed comparison.
- **Not unit-tested, on purpose**: `UpdateChecks` is a thin pass-through to Sparkle, and faking Sparkle would test
  the fake. It is covered by real-Mac checks 1–5.

### Real-Mac checks (a person on a Mac; CI can't do these)

The N → N+1 test (P5) covers the prompt count and the identity questions from the research's "Open items". Beyond
it, the implementation is only done when these pass on Parag's Mac, with the results in the wiki:
1. "Check for Updates…" on the latest version shows "You're up to date". This also proves Sparkle follows the
   `latest/download` redirect.
2. The update window comes to the front over other apps, from the Dock-less menu bar app.
3. The row is disabled while a check runs, and enabled again afterwards.
4. **No automatic checks**: across launches, no update window appears unprompted. The command
   `defaults read dev.shotkeeper.Shotkeeper SULastCheckTime` reports no value until the first manual check [S1][S6].
   The update window offers no "automatically download and install" choice.
5. Offline (Wi-Fi off), "Check for Updates…" shows an error; screenshots still queue and process when back online.
6. **Update mid-work**: take three screenshots and choose Install and Relaunch at once. After the relaunch, all
   three are renamed and indexed, no file is missing or duplicated, and Undo still works on them.
7. With the local backend running, no `mlx`/Python server process is left over after an update (`pgrep -fl mlx`).
8. No "Shotkeeper was prevented from modifying apps" (App Management) notification appears during an update
   ([A11]; research open item 5).
9. First install from the release zip on macOS 15+ works with Open Anyway, as the README describes.

## What Parag must do

A step-by-step checklist for someone who has never signed code. Every step says what to do, what you should see,
and what to keep secret. It is written so that it can later become an interactive wizard. Each step has an ID, one
action, one check and one "if it goes wrong".

You need: a Mac signed in to your usual user account, a browser logged in to GitHub as `paragrudani1`, a password
manager, and one USB drive you can wipe (for the backup). Allow about 45 minutes, plus the test in P5.

**Never paste these anywhere except the GitHub secret boxes in P4:** the `.p12` file, its password, the Sparkle
private key file. The *public* key in P2.6 is safe to share.

### P1. Create the self-signed code-signing certificate

| # | Do | You should see | If it goes wrong |
| --- | --- | --- | --- |
| P1.1 | In Finder, create a folder `ShotkeeperSecrets` in your home folder. | An empty folder `~/ShotkeeperSecrets`. | — |
| P1.2 | Open **Keychain Access**: press ⌘Space, type `Keychain Access`, press Return. | The Keychain Access window. | If Spotlight opens the Passwords app instead, look in `/System/Library/CoreServices/Applications/`. |
| P1.3 | In the menu bar choose **Keychain Access → Certificate Assistant → Create a Certificate…** | A window "Create Your Certificate". | — |
| P1.4 | Name: **`Shotkeeper Release`** (exactly this; the release workflow looks for this name). Identity Type: **Self Signed Root**. Certificate Type: **Code Signing**. Tick **Let me override defaults**. Click Continue. | A note that you are about to create a self-signed certificate. Click Continue. | If the name is different, signing fails in the release. Delete the certificate and start again at P1.3. |
| P1.5 | Validity Period (days): **7300** (20 years). Click Continue. | The certificate information page. | If 7300 is refused, use the largest number it accepts and note it. Expired self-signed certificates still verify [A3], but never replace this one: a new certificate changes the app's identity. |
| P1.6 | On every following page (Certificate Information, Key Pair Information, Key Usage Extension, Extended Key Usage, Basic Constraints, Subject Alternate Name, Location), **keep the defaults** and click Continue. Fill in an email only if it insists. Location: keychain **login**. Click Create, then Done. | — | — |
| P1.7 | In Keychain Access, select **login** on the left and the **My Certificates** tab at the top. Find **Shotkeeper Release**. | It has a ▸ triangle. Opening it shows a private key under it. It says "This root certificate is not trusted"; **that is expected, so don't change trust settings.** | No triangle or no key means the identity wasn't created. Repeat P1.3–P1.6. |
| P1.8 | Right-click **Shotkeeper Release** → **Export "Shotkeeper Release"…**. File Format: **Personal Information Exchange (.p12)**. Save as **`shotkeeper-release.p12`** in `~/ShotkeeperSecrets`. | A password prompt for the export. | Export greyed out means you selected only the key or only the certificate. Select the certificate row itself (the one with the triangle). |
| P1.9 | Let your password manager **generate a strong password** (20+ characters) and save it there as "Shotkeeper .p12 password". Type it twice in the export prompt. If macOS then asks for your **Mac login password** to allow the export, enter it. | `~/ShotkeeperSecrets/shotkeeper-release.p12` exists. | — |

### P2. Create Sparkle's EdDSA update key

| # | Do | You should see | If it goes wrong |
| --- | --- | --- | --- |
| P2.1 | Open https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1 and download **`Sparkle-2.10.1.tar.xz`**. | The file in Downloads. | Use exactly 2.10.1, the version the app pins. |
| P2.2 | Double-click it to unpack. | A folder (e.g. `Sparkle-2.10.1`) with a `bin` folder inside. | — |
| P2.3 | Open **Terminal** (⌘Space, `Terminal`). Type `cd ` (with a space), drag the unpacked folder into the Terminal window, press Return. | The prompt now ends in that folder's name. | — |
| P2.4 | Run `./bin/generate_keys` | It says it generated a key and saved it in your keychain, and prints the public key. | If macOS says it can't be opened, allow it in System Settings → Privacy & Security → Open Anyway and run it again. **If it says a key already exists, stop and tell the agent.** Don't create a second key. |
| P2.5 | If a keychain dialog asks to allow access, click **Allow**. | — | — |
| P2.6 | **Copy the public key** it printed (the long text inside `<string>…</string>`, or after "public key"). Paste it to the agent. | — | This one is public and safe to share. It goes into the app. |
| P2.7 | Run `./bin/generate_keys -x ~/ShotkeeperSecrets/sparkle-private-key.txt` | A new file `sparkle-private-key.txt` in `~/ShotkeeperSecrets`. **Don't open it or paste it anywhere except P4.5.** | — |

### P3. Back up both keys offline (do this before anything else uses them)

Why: **if the Sparkle private key is lost or leaked, every installed copy of Shotkeeper can never auto-update again.**
Without a Developer ID it can't be replaced [S1]; users would have to reinstall by hand. If the certificate is
lost, the next build has a new identity, and the prompts this plan avoids come back. GitHub secrets can't be read
back, so GitHub is not a backup.

| # | Do | You should see | If it goes wrong |
| --- | --- | --- | --- |
| P3.1 | Plug in the USB drive. In **Disk Utility**, erase it as **APFS (Encrypted)**, name it `ShotkeeperBackup`, and save its password in your password manager. | An encrypted drive on the desktop. | This erases everything on that drive. Use an empty one. |
| P3.2 | Copy the whole `~/ShotkeeperSecrets` folder to the drive. | Both files on the drive. | — |
| P3.3 | In your password manager, make a secure note "Shotkeeper release keys" and **attach both files**. The `.p12` password is already there from P1.9. | Two attachments in the note. | — |
| P3.4 | Eject the drive and store it somewhere other than next to your Mac. | — | — |
| P3.5 | Tell the agent "backups done". (Keep `~/ShotkeeperSecrets` until P4 is finished.) | — | — |

### P4. Create the GitHub `release` environment and its secrets

| # | Do | You should see | If it goes wrong |
| --- | --- | --- | --- |
| P4.1 | Open https://github.com/paragrudani1/shotkeeper/settings/environments and click **New environment**. Name: **`release`** (lower case). Click **Configure environment**. | The environment's settings page. | — |
| P4.2 | Tick **Required reviewers**, add **paragrudani1**, click **Save protection rules**. | "Required reviewers: 1". | Every release then waits for your Approve click in the Actions tab. That is intended. |
| P4.3 | Under **Deployment branches and tags**, choose **Selected branches and tags** → **Add deployment branch or tag rule** → Ref type **Tag** → pattern **`v*`** → **Add rule**. | One rule: tag `v*`. | If you pick "Branch" instead of "Tag", releases fail with "not allowed to deploy". Fix the rule type. |
| P4.4 | Under **Environment secrets**, click **Add environment secret**. Name **`SIGNING_CERT_P12_BASE64`**. In Terminal run `base64 -i ~/ShotkeeperSecrets/shotkeeper-release.p12 \| pbcopy` and paste into Value. Click **Add secret**. | The secret listed (its value is never shown again). | Use **environment** secrets on this page, not repository secrets. |
| P4.5 | Add **`SPARKLE_ED_PRIVATE_KEY`**: run `pbcopy < ~/ShotkeeperSecrets/sparkle-private-key.txt` and paste. | Listed. | — |
| P4.6 | Add **`SIGNING_CERT_P12_PASSWORD`**: paste the password from your password manager (P1.9). | Three secrets listed. | — |
| P4.7 | Copy some harmless text so the clipboard no longer holds a secret. | — | — |
| P4.8 | *(Recommended)* https://github.com/paragrudani1/shotkeeper/settings/rules → **New ruleset → New tag ruleset**. Name `release tags`, Enforcement **Active**, Target tags **Include by pattern `v*`**. Tick **Restrict creations**, **Restrict updates** and **Restrict deletions**. Add **Repository admin** to the bypass list. **Create**. | The ruleset is active. | This stops anyone but an admin (you) from making or moving a release tag. |
| P4.9 | After the backup (P3) is checked, move `~/ShotkeeperSecrets` to the Trash and empty it. The Sparkle key also stays in your login keychain from P2.4. | — | — |
| P4.10 | Tell the agent "environment ready". | — | — |

### P5. The N → N+1 test on your Mac

The agent publishes **0.2.0** (build N) and later **0.2.1** (build N+1). You approve each one in the repository's
**Actions** tab (the run waits at "publish" → Review deployments → Approve). Each number below is something you
count or read; the report form is at the end.

**Before:** if an older Shotkeeper (a CI build) is in `/Applications`, quit it from its menu and move it to the
Trash. Your settings and index stay. A keychain dialog when 0.2.0 first reads keys that a CI build saved is
expected once; count it under "first launch", not as an update prompt.

| # | Do | Count or note |
| --- | --- | --- |
| P5.1 | From the 0.2.0 release page, download `Shotkeeper-0.2.0.zip`, unzip, drag `Shotkeeper.app` to **Applications**. Open it: when macOS blocks it, use **System Settings → Privacy & Security → Open Anyway**. | Did Open Anyway work? (yes/no) |
| P5.2 | Finish setup with a cloud backend so a key is saved (Clairic token or OpenRouter key). If you have them, also save the other two (OpenRouter key, custom-endpoint key) in Settings → Model. | Which of the 3 secrets are saved. |
| P5.3 | Allow Desktop access when asked. Turn on **Launch at login** (Settings → General). Take a screenshot (⇧⌘4) and wait until it is renamed. | Dialogs during first launch (number and what they said). |
| P5.4 | **Baseline**: quit Shotkeeper from its menu and open it again. Take a screenshot. | Dialogs on relaunch of the *same* build (expect 0). Screenshot renamed? |
| P5.5 | In Terminal run `codesign --display -r - /Applications/Shotkeeper.app` and copy the line starting `designated =>`. | DR before. Safe to share; it contains no secret. |
| P5.6 | Did any "check for updates" window or question ever appear by itself during P5.1–P5.4? | yes/no |
| P5.7 | Tell the agent "N ready". When 0.2.1 is published, choose **Shotkeeper menu → Check for Updates…** | Did a window appear in front, showing 0.2.1 and its notes? |
| P5.8 | Click **Install Update**, then **Install and Relaunch**. From that click until Shotkeeper is back in the menu bar and has renamed one new screenshot, **count every dialog**. Answer each keychain dialog with **Always Allow** and type your Mac login password if asked. Never type a backend key into a dialog. | • Gatekeeper / "can't be opened" dialogs: n<br>• Keychain dialogs: n, and which item each named<br>• Desktop folder access prompt: yes/no<br>• Any other dialog or notification: exact text |
| P5.9 | Open About: the version. Take a screenshot: was it renamed **without re-entering any key**? | Version shown; renamed yes/no |
| P5.10 | **System Settings → General → Login Items**: how many Shotkeeper entries, and is it on? Then **Privacy & Security → Files & Folders**: how many Shotkeeper entries, and is Desktop on? | Login items: 0/1/2, on/off. Files & Folders: 0/1/2, Desktop on/off |
| P5.11 | Log out and back in. | Did Shotkeeper start by itself? |
| P5.12 | Run P5.5's command again. | DR after; the same as before? |
| P5.13 | *Only if P5.8 counted any keychain or Desktop prompt:* tell the agent, who publishes **0.2.2**. Repeat P5.7–P5.12. | Same counts for N+1 → N+2: did "Always Allow" carry over? |

**Report (copy, fill in, send to the agent):**

```
Mac model / macOS version:
Update tested: 0.2.0 (200) -> 0.2.1 (201)        [and 0.2.1 -> 0.2.2 if P5.13 ran]
Secrets saved before the update: Clairic yes/no, OpenRouter yes/no, custom endpoint yes/no
First launch of 0.2.0: Open Anyway worked yes/no; dialogs: n (text)
Baseline relaunch, same build: dialogs n
Update window appeared by itself at any time: yes/no
Check for Updates window in front, showed 0.2.1 + notes: yes/no
After the update:
  Gatekeeper dialogs: n
  Keychain dialogs: n  (items: ...)
  Desktop access prompt: yes/no
  Other dialogs/notifications: ...
  About shows: ...
  New screenshot renamed without re-entering keys: yes/no
  Login Items entries: n, on/off; started after log-out/in: yes/no
  Files & Folders entries: n, Desktop on/off
  Designated requirement identical before/after: yes/no
N+1 -> N+2 (only if run): keychain n, Desktop yes/no
```

**Decision rule:** if P5.8 shows **0 keychain dialogs, no Desktop prompt and no Gatekeeper dialog**, and login items
and Files & Folders show one entry each, the self-signed plan stands and the README says "no dialogs". **If any
prompt remains, the agent records the numbers in the wiki and the choice goes back to Parag.** The options then
include accepting the prompts, Apple's Developer ID (which brings back notarization), or something else Parag
names. No agent changes the signing approach on its own. Whatever is chosen, the EdDSA key stays, so already
installed copies keep updating [S8 `SUUpdateValidator.m`: a matching EdDSA key "allows change of Code Signing
identity"].

## Out of Scope

- Notarization, Developer ID and the Apple Developer Program, unless Parag reverses that decision after P5.
- Automatic or scheduled update checks, background downloads, silent installs and gentle reminders [S6].
- Delta updates (`generate_appcast` makes them by default [S2]; the one-item appcast and full zips avoid them).
- Pre-release or beta channels, and a Settings switch for them.
- A signed feed (`SURequireSignedFeed`), until the research covers it.
- Moving keychain items to the data protection keychain. It needs a provisioning profile [A2][A7].
- A DMG installer, Homebrew cask, or any distribution channel other than GitHub Releases.
- Spotlight and App Intents signing questions (feature 3), though P5's result feeds into them.
- Removing Sparkle's unused XPC services from the bundle ([S5] says they "may" be removed; not worth the risk
  now).

## Further Notes

- **The one irreversible thing is the EdDSA key.** Everything else (certificate, hosting, build-number scheme
  going upwards, even switching to Developer ID) can change in a later release. Losing or leaking the key cannot be
  undone [S1].
- **The certificate must never be rotated.** The DR pins its leaf hash ([A8] shape). Expiry doesn't matter for
  verification [A3].
- The research's open items 1–5 map to P5.8 (Gatekeeper), P5.8 and P5.13 (keychain, "Always Allow"), P5.10
  (Desktop, login item), P5.11 (login item after login) and real-Mac check 8 (App Management).
- Feature 3 (Spotlight, Shortcuts) noted that nobody knows whether Core Spotlight accepts an ad-hoc signature.
  Releases from this spec are self-signed, so wave 3 should test against a release build, not a CI artifact.
- The survey's original feature 8 bullet about Hardened Runtime and `ManagedProcess` no longer applies. The app
  keeps Hardened Runtime off.

## Decisions Parag might disagree with

1. **Feed on GitHub Releases** (`/releases/latest/download/appcast.xml`) rather than GitHub Pages. It is simpler,
   but it relies on a redirect that is only verified in the first release.
2. **Build number from the tag** (`MAJOR×10000 + MINOR×100 + PATCH`), so minor and patch versions stop at 99,
   and there are no `-beta` tags.
3. **`CHANGELOG.md` is required.** A release fails without a section for its version. The same text is the GitHub
   Release body and Sparkle's notes.
4. **A required reviewer on the `release` environment.** Each release waits for your Approve click.
5. **Two jobs**: the build runs without secrets and signing runs without build tools. That costs one more
   artifact hop and about a minute.
6. **The appcast lists only the newest version.** Someone skipping from 0.2.0 to 0.4.0 sees only 0.4.0's notes.
7. **No separate UI design pass**: the only UI is one menu row ("Check for Updates…", between About and Quit) and
   Sparkle's stock windows.
8. **The first two real releases are the test.** 0.2.0 and 0.2.1 are public before the prompt count is known.
   (They're harmless if prompts remain: a later release can change signing, and the EdDSA key carries trust
   across.)
9. **Release tooling lives in `ShotkeeperCore`** (a `Release/` folder) and in the existing CLI, rather than in a
   separate package target. It ships unused inside the app binary.
10. **`SUAllowsAutomaticUpdates = false`** hides Sparkle's "install automatically" choice, so users can't opt into
    automatic updates either.
11. **Sparkle `exactVersion: 2.10.1`**, the current stable release, not the 2.11 beta. Every upgrade is a PR plus
    real-Mac checks.
