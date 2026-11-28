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
