# 01: Release plan in core and `shotkeeper-cli release-plan`

**What to build:** given a tag, the previous release's tag and `CHANGELOG.md`, one command tells the release job the
marketing version, the build number, the zip name and the title, and writes the release notes as Markdown (GitHub
Release body) and as escaped HTML (Sparkle's update window). A bad tag, a version that isn't higher than the last
release, or a missing or empty changelog section fails with one readable line before anything is built. This
ticket also adds `CHANGELOG.md` with its first section (`0.2.0`).

**Blocked by:** None (can start immediately). Core and CLI only; it does not touch app files, so it does not wait
for PR #10.

**Status:** ready-for-agent

**Sources:** spec "Core seam: `ReleasePlan`", "Build number", stories 24, 26, 31, 34; Testing Decisions, seam 1.

**Test seam:** seam 1, `ReleasePlan.make(tag:previousTag:changelog:)`, a pure function in `ShotkeeperCore` (a
`Release/` folder), tested under `Tests/ShotkeeperCoreTests` with changelog samples in `Fixtures`. Prior art:
`FilenameSanitizerTests`, `MenuTextTests`. No network, no Mac, no Sparkle.

- [ ] Tag parsing: `vMAJOR.MINOR.PATCH` only. Rejected, each with its own `ReleasePlanError` line: no `v`, two
      parts, pre-release or build suffixes, leading zeros, minor or patch over 99, below 0.1.0.
- [ ] Build number `MAJOR×10000 + MINOR×100 + PATCH` (`v0.2.0` → 200, `v1.0.0` → 10000); a test shows it rises with
      every version step.
- [ ] Previous tag: equal or lower is rejected; `0.10.0` > `0.9.0` (numeric); `none` / `nil` for the first release.
- [ ] Changelog: `## <version> (<date>)` sections, newest first. The right section among several; the last section
      in the file; missing section and empty section are errors; `0.2.1` does not match `0.2.10`.
- [ ] HTML: paragraphs, `- ` bullets, inline `` `code` `` only; everything else escaped (`<script>`, `&`, quotes).
- [ ] Archive name `Shotkeeper-<version>.zip`, title `Shotkeeper <version>`.
- [ ] CLI `release-plan --tag … --previous …|none --changelog … --out <dir>`: writes `notes.md` and the HTML notes
      under the name `generate_appcast` expects (read it in `generate_appcast` at Sparkle 2.10.1 and cite the source
      line in a comment; if it can't be settled from source, name it in the PR and let ticket 09 confirm it),
      prints `key=value` lines for `$GITHUB_OUTPUT`, exits non-zero with the error line on failure.
- [ ] `CHANGELOG.md` at the repo root with a `0.2.0` section (the first release, ticket 11; it may be reworded there).
- [ ] AGENTS.md layout line for the CLI: "live analyzer calls and release tooling".
- [ ] Dated wiki line (new page `docs/wiki/auto-update.md`, linked from `index.md`): seam, error lines, file names.
- [ ] Linux tests green (`scripts/test-linux.sh`, own `SCRATCH`).
- [ ] **Done only when `macos-app` CI is green** on the PR (core must also build for macOS 14).

**Real-Mac checks:** none. Release-time behaviour is checked by ticket 11's first run.
