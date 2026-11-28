# Auto-update: decisions and implementation notes (2026-11-28)

Dated deviations and implementation notes for the [auto-update spec](../specs/auto-update-2026-11.md) and its tickets
(`docs/specs/auto-update-2026-11/tickets/`). The spec's requirements are not edited; notes go here.

## Parag's decisions that win over the spec (2026-11-28)

Recorded in [workflow](workflow.md) ("Auto-update spec", 2026-11-28); copied here as the tickets README asks.
- **No required approval per release.** The `release` environment keeps its `v*` tag rule and its secrets, but has
  no required reviewer. Pushing the tag publishes the release. The tag ruleset (checklist P4.8) is now the main guard
  against a stray or moved tag. Spec lines that still say "approval" (story 22, story 23, "required reviewer: Parag",
  "Why none of them can leak", P4.2, the P5 intro, "Decisions Parag might disagree with" #4) are superseded.
- **The N → N+1 test uses the first two real releases** (0.2.0 → 0.2.1), not private test releases.

## Ticket 01: release plan in core and `shotkeeper-cli release-plan` (2026-11-28, `cadb9ef`)

- **Seam**: `ReleasePlan.make(tag:previousTag:changelog:)` in `Sources/ShotkeeperCore/Release/`, a pure function,
  tested in `Tests/ShotkeeperCoreTests/ReleasePlanTests.swift` with changelog fixtures `changelog-several.md` and
  `changelog-empty-section.md`. It returns `marketingVersion`, `buildNumber`, `tag`, `archiveName`, `title`,
  `notesMarkdown` and `notesHTML`, plus `outputFiles` and `githubOutput(directory:)` for the CLI.
- **Checks run in this order**, and the first failure is the only line: the tag, then the previous tag, then
  "higher than previous", then the changelog. So a bad tag never reports a changelog problem.
- **Error lines** (`ReleasePlanError.message`), as the release log shows them:
  - `Tag 0.2.0 does not start with v (expected vMAJOR.MINOR.PATCH)` (also `V0.2.0`)
  - `Tag v0.2 is not vMAJOR.MINOR.PATCH` (wrong number of parts, empty part, non-digits)
  - `Tag v0.2.0-beta.1 has a pre-release or build suffix; releases are vMAJOR.MINOR.PATCH only` (any `-` or `+`)
  - `Tag v0.02.0 has a leading zero`
  - `Tag v0.100.0: minor and patch must be 0-99 (build number MAJOR×10000+MINOR×100+PATCH)`
  - `Tag v0.0.9 is below v0.1.0, the first version a release may have`
  - `Tag v1000000000000000.0.0: major version is too large`
  - `Previous release: <one of the tag lines above>`
  - `v0.2.0 is not higher than the previous release v0.2.1`
  - `CHANGELOG.md has no section for 0.2.1`
  - `CHANGELOG.md section 0.2.1 is empty`
  - CLI only: `Cannot read the changelog at <path>`, `Cannot write the release notes into <dir>: <reason>`.
- **Changelog rules**: a section starts at a line `## <version> …` whose first word after `## ` is exactly the
  version (so `0.2.1` never matches `0.2.10`), and ends at the next `## ` line or the end of the file. `###`
  subheadings stay inside the section. The body is trimmed; whitespace only counts as empty. Windows line endings are
  accepted. The date in the heading is not checked. Section order is not checked either: the plan takes the
  section for the tag's version wherever it is.
- **HTML subset**: blank lines separate blocks; `- ` at the start of a line is a bullet, and an indented line under
  a bullet continues it; other lines form paragraphs (wrapped lines joined with a space). Backtick pairs become
  `<code>`, and an unpaired last backtick stays literal. `& < > " '` are escaped everywhere, inside code too.
  Everything else (`**`, `###`, links) shows as typed. The output has no DOCTYPE and no `<body>`, so
  `generate_appcast` embeds it as a fragment (Sparkle 2.10.1 `generate_appcast/ArchiveItem.swift:475-477`). The
  release job also passes `--embed-release-notes`, which embeds it either way.
- **File names** (CLI `--out <dir>`): `notes.md` (the section, for `gh release create --notes-file`) and
  `Shotkeeper-<version>.html`. The HTML name is settled from source: `generate_appcast` looks for the archive's name
  with its extension swapped, trying `.html`, `.txt`, `.md` and `.markdown` in that order (Sparkle 2.10.1
  [`generate_appcast/ArchiveItem.swift:419-446`](https://github.com/sparkle-project/Sparkle/blob/2.10.1/generate_appcast/ArchiveItem.swift#L419-L446),
  `releaseNotesPath`; the help text in `generate_appcast/main.swift:192` says the same). Ticket 09 puts that
  file next to `Shotkeeper-<version>.zip` in the appcast folder. `notes.md` doesn't match the zip's name, so it is
  never picked up as the notes, even if it ends up in that folder too. `SPUExtractReleaseNotesContent`
  (`Sparkle/SPUExtractSignedFeed.m:62`) only strips a leading `sparkle-sign-warning` comment, so the fragment
  passes through unchanged.
- **`$GITHUB_OUTPUT` keys**: `version`, `build_number`, `tag`, `archive_name`, `title`, `notes_markdown_file`,
  `notes_html_file` (the paths are under `--out` as given).
- **CLI** `release-plan --tag … --previous …|none --changelog … --out <dir>`: `none` → no previous release (core
  `nil`). The plan is made before anything is written, so a failed plan leaves no `--out` folder. Writes never
  replace a file (`.withoutOverwriting`), so a re-run into the same folder fails rather than mixing two plans.
  Errors go to stderr with exit 1; a usage error exits 2.
- `CHANGELOG.md` has its first section, `## 0.2.0 (2026-11-28)`. Ticket 11 sets the real date and may reword it.
- **Additions beyond the spec** (none change a requirement): `major version is too large` stops an `Int` overflow in
  the build number; it is not a version policy. A malformed previous tag fails with the `Previous release:` prefix.
  `outputFiles` and `githubOutput` live in core rather than the CLI, so the file names and keys are unit-tested.
- 2026-11-28 (review fix): release-notes HTML escapes per Unicode scalar, not per `Character`. The review showed
  `<`/`>`/`&` followed by a ZWJ or combining mark slipped through, and an unescaped `]]>` would end the appcast's
  CDATA (`generate_appcast` 2.10.1 `ArchiveItem.swift:475-477`). A duplicate `## <version>` section now fails the
  release ("CHANGELOG.md has more than one section for …") instead of silently using the first.

## Ticket 06: shared Xcode and inside-out signing scripts, ad-hoc in `macos-app` (2026-11-28)

- **Scripts**: `scripts/select-xcode.sh` (no arguments; the old "Select newest stable Xcode" step body, plus a
  "Selected Xcode: <path>" line; appends `version=` to `$GITHUB_OUTPUT` when set) and `scripts/sign-app.sh
  [--keychain <file>] <identity> <app>`. Both are `#!/bin/bash`, use only BSD-compatible `grep`/`sed`, and CI runs
  them with `/bin/bash` (3.2) on macOS. Ticket 09's release job calls both: `scripts/sign-app.sh --keychain
  "$KEYCHAIN" "Shotkeeper Release" <app>` after it has created and unlocked the temp keychain.
- **Identity**: only `-` or `Shotkeeper Release` is accepted (anything else exits 2 without echoing it). `--keychain`
  is refused with `-` (exit 2); a missing keychain file or a path that is not an app exits 1. The script never
  echoes the identity, the keychain path or the app path ("identity: ad-hoc" / "identity: release certificate");
  `codesign`'s own output names the app path, which is not secret. It never takes a password.
- **Order and flags** (from Sparkle's "Sandboxing" > "Code Signing" example,
  https://sparkle-project.org/documentation/sandboxing/ , cited in the script): `Installer.xpc` `-f -s ID -o runtime`,
  `Downloader.xpc` `-f -s ID -o runtime --preserve-metadata=entitlements` ("For Sparkle versions >= 2.6"),
  `Autoupdate`, `Updater.app`, `Sparkle.framework` each `-f -s ID -o runtime`, then the app with `-f -s ID` only
  (Hardened Runtime off, [S1] Library Validation; `ENABLE_HARDENED_RUNTIME: NO`). `--keychain <file>` goes right after
  the identity (codesign(1): "During signing, only search for the signing identity in the keychain file
  specified"). Inside-out and no `--deep` for signing: Sparkle's page ("please do not add --deep … when signing your
  application") and Apple's "Creating distribution-signed code for macOS"
  (https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac: "Sign code from the
  inside out", "Don't pass the --deep option to codesign when you sign code", which it calls helpful "in verifying a
  code signature").
- **Skips and failures**: no `Contents/Frameworks/Sparkle.framework` → "skip: Sparkle.framework is not in the
  bundle", only the app is signed (today, until ticket 07). An XPC service that is missing is skipped with a line
  (Sparkle allows removing them). Sparkle present without `Versions/B`, `Autoupdate` or `Updater.app` fails before
  anything is signed: a new Sparkle layout must be a reviewed script change, not a silent skip.
- **Verification**: `codesign --verify --deep --strict --verbose=2`, then for each signed Sparkle item "Hardened
  Runtime on" and for the app "off" (from the `CodeDirectory … flags=…(…)` line of `codesign --display
  --verbose=1`; only the flags are printed), then `codesign --display -r -` to the log. With `-` the script prints
  "DR shape check skipped: an ad-hoc signature's DR is a cdhash by nature"; with the release identity the DR must
  contain `certificate leaf` and must not contain `cdhash` ("DR shape: ok"), else exit 1.
- **Self-test** (`scripts/sign-app.sh --self-test`, seam 3): everywhere, a fake `codesign` on `PATH` logs calls and
  the test compares the exact call list (order, flags, `--keychain` placement), the skip/fail layouts, the DR rules,
  the Hardened Runtime check (fake drops the flag / adds it to the app), a failing verify, usage errors and that
  neither the identity nor the keychain path is echoed. On macOS it then builds `Throwaway.app` with a Sparkle-shaped
  framework (`Versions/B` with `Sparkle` dylib, `Autoupdate`, `Updater.app`, `XPCServices/{Installer,Downloader}.xpc`,
  top-level symlinks) from tiny `cc` binaries, pre-signs `Downloader.xpc` with an entitlement, runs the script with
  `-` and the real `codesign`, and checks the entitlement survived `--preserve-metadata=entitlements`. Also passes
  under `bash:3.2` (Docker, busybox tools) on the Linux box.
- **Guard**: `scripts/lint.sh` rule `deep-sign` (see its header) fails on a `codesign` line in `scripts/*.sh` or
  `.github/workflows/*.y*ml` that has `--deep` and no `--verify`. One line at a time: continuation lines and
  `codesign` through a variable are blind spots. On adding it, it flagged the old `ci.yml` line, as intended.
- **Artifact**: still `Shotkeeper-unsigned`, ad-hoc, build 1 (the zip step now also prints `CFBundleVersion`). After
  the upload, `macos-app` downloads the artifact back, unzips it with `ditto -x -k` and verifies it with
  `codesign --verify --deep --strict --verbose=2`.
- **Not done here**: the Info.plist key check (feed URL, public key, automatic checks off) needs Sparkle's keys, so it
  lands with ticket 07/08, as the spec's seam 3 lists it next to the signing script.
