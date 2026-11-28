# Wave 2 tickets: subfolders, Edit name and Analyze Again (2026-11-28)

Tickets for the [spec](../../subfolders-and-retitle-2026-11.md) (all 15 decisions accepted by Parag) and the approved
[design](../../../design/subfolders-and-retitle.md) (Parag, 2026-11-28, all departures accepted). Made with the
to-tickets skill, local layout: one file per ticket, blocking edges as text. The spec's requirements are not edited
here.

Builds on main with PR #9 (index prefactor: column table, `changes()`, `testRow`) and PR #10 (app prefactor:
`FileActions` + one `FileActions+<Feature>.swift` per feature, `SearchResultActions`, `SearchKeyMap`, per-screen
snapshot files, `scripts/lint.sh`; see [prefactor-app](../../../wiki/prefactor-app.md) on main). Wave 2 gets its own
integration branch, cut from main after wave 1 (`t3/wave1-search`) merges.

Every ticket counts as done only when `macos-app` CI is green on its PR (AGENTS.md: Linux green does not prove the
macOS build), along with the Linux tests and `scripts/lint.sh`.

## Tickets

| # | Ticket | Blocked by | Area |
|---|---|---|---|
| 01 | [Consent: `UserUploadAuthorization` and CODING_STANDARDS #2](01-consent-user-upload-authorization.md) | none | core + app call sites + standards |
| 02 | [Index migration: `title_source`](02-title-source-migration.md) | none | core |
| 03 | [Queue: job kinds, front placement, per-kind dedupe](03-queue-job-kinds.md) | 01 | core + coordinator |
| 04 | [Sort new screenshots into subfolders](04-subfolders-new-screenshots.md) | wave 1 03 (`SourceKey`) | core + Settings + toast |
| 05 | [Sort Existing Screenshots… (plan, run, Stop, Undo All)](05-sort-existing-screenshots.md) | 04 | core + Settings + menu + toast |
| 06 | [Analyze Again in core: `reanalyze`](06-reanalyze-core.md) | 01, 02, wave 1 01 (`text_status`) | core |
| 07 | [Edit name from the search window (⌘E)](07-edit-name-in-search.md) | 02, wave 1 panel work merged | core + search panel |
| 08 | [Analyze Again from the search window (allowed destination)](08-analyze-again-in-search.md) | 03, 06, 07 | core + search panel + toast |
| 09 | [Analyze Again asks first (consent card)](09-analyze-again-asks-first.md) | 08 | core + search panel |
| 10 | [Integrate wave 2 and verify on a real Mac](10-integrate-and-verify.md) | 01–09 | integration |

```
01 ──> 03 ──────────────┐
01 ─┬─> 06 ─────────────┼──> 08 ──> 09 ──> 10
02 ─┘                   │
02 ──> 07 ──────────────┘
wave 1 01 ──> 06
wave 1 03 ──> 04 ──> 05 ──────────────────> 10
wave 1 panel work (02, 03, 06, 07) ──> 07
```

## What can run when

- **Now, before wave 1 merges (core only, branch from main):** 01 and 02, in parallel. Then 03 once 01 merges.
  These touch no search-panel file (01 renames call sites in `FolderCapture`/`AppCoordinator`, not the panel).
  Until the wave 2 integration branch exists, open them as PRs into a short-lived `t3/wave2-core` branch from main
  (or straight into main if Parag prefers; both are core-only and keep main green).
- **Before wave 1 merges, from `t3/wave1-search`:** 06 needs wave 1 01's `text_status` (already merged into
  `t3/wave1-search`), and 04 needs wave 1 03's `SourceKey`. They can start on a branch from `t3/wave1-search` with
  01/02 merged in, and retarget to the wave 2 integration branch once it exists. 04 and 05 touch Settings, the toast
  and the menu, not the search panel, so they don't collide with wave 1's panel tickets. If juggling two bases is
  not worth it, wait for wave 2's integration branch.
- **Must wait for wave 1's panel work to merge (wave 2 integration branch):** 07, then 08, then 09. They change
  `SearchWindowState`, `SearchKeyMap`, `SearchView`, `SearchPanel` and `SearchSnapshots`, which wave 1 02, 03, 06 and
  07 change first, and they extend wave 1's Esc order, focus order and ⇧⌘ trigger.
- **Parallel lanes once the integration branch exists:** subfolders (04 → 05) beside retitle (07 → 08 → 09).
- At most four agents at once (workflow, 2026-11-28).

## Ownership rules

- **Migration:** only 02 adds an index migration version. Wave 1 takes 3, so 02 writes 4 and re-checks the highest
  version on its target branch at merge time, claiming the next free one (`shippedColumns` versions must run 1, 2,
  3…). No other wave 2 ticket adds a column: subfolders need none (the path says where the file is).
- **Consent:** only 01 changes `UploadConsent.decide`, the request types and CODING_STANDARDS #2, in one PR. 08 and 09
  only issue a `UserUploadRequest`; `decide` is still the one place that decides.
- **`ScreenshotProcessor`:** 02 (`title_source` writes), 04 (destination folder), 05 (`sortPlan` / `sort`), 06
  (`reanalyze`). Put 05 and 06 in their own extension files to keep conflicts to the call into the shared destination
  helper. 04 and 06 both use that helper; whichever merges second adds the "Analyze Again moves to the new type's
  folder" test.
- **`FileActions`:** 05 adds `FileActions+Subfolders.swift`; 07 adds `FileActions+Retitle.swift`, 08 gives it the
  queue, 09 adds the consent step.
- **Search panel:** 07 → 08 → 09 are chained. New views go in their own files so `SearchView.swift` doesn't become the
  conflict point.
- **Menu and toast wording** (`MenuText`, `Toast`): 04 (sorted label), 05 (batch, moved back, "Undo Move:"), 08
  (analyzed-again toasts). Pure rules in core `Feedback/`, each with tests.

## Spelling: "Analyze", not "Analyse"

Parag chose American spelling on 2026-11-28 (wiki [workflow](../../../wiki/workflow.md)). Parag's quoted requirement
at the top of the spec stays as written. Everywhere else, implementers write **Analyze / Analyzed / Analyzing /
analysis**, in strings, identifiers, snapshot names, comments and docs. Spots where the source documents say
"Analyse" and must be read as "Analyze":

- **Spec** (`docs/specs/subfolders-and-retitle-2026-11.md`, line numbers at `6d93931`):
  - Solution, "**Analyse Again** (⇧⌘E)" (l. 75); user stories 42–65 and their heading (l. 131–155).
  - `SearchKey.analyseAgain` (l. 273) → `SearchKey.analyzeAgain`.
  - Section headings "Analyse Again (core)" and "Analyse Again: queue" (l. 284, 324).
  - The row note "analysed again" (l. 300) → "analyzed again".
  - CODING_STANDARDS #2 draft, "Analyse Again" (l. 380) → "Analyze Again" (ticket 01).
  - UI surfaces: "The destination changed. Analyse again." (l. 443); announcements "Analysing", "Analysed again"
    (l. 458).
  - Decisions 6, 8–10, 12, 13, 15 (l. 541–552).
  - Also British forms in synthesis text: "generalisation", "authorisation" (l. 340), "behaviour" (l. 60),
    "organisation" (story 24), and "colour" in the design (§2, §10). Code and copy use "generalization",
    "authorization", "behavior", "organization", "color".
- Ticket "Sources" lines quote spec headings as written ("Analyse Again (core)", "Analyse Again: queue") so they can
  be found; that is the only "Analyse" in these tickets outside this list.
- **Design** (`docs/design/subfolders-and-retitle.md`):
  - §2 token table, status label "Analysed again"; icon button "Analyse Again: `sparkles`"; the turn-over example.
  - §5.1 tooltips "Analyse this screenshot again (⇧⌘E)", "…on this Mac", VoiceOver label "Analyse Again".
  - §5.3 every state: "Waiting to analyse…", "Analysing…", "Analysed again…", "Could not analyse again:", "Not
    analysed:", "The destination changed. Analyse again.", "Analyse Again needs a model:", "Analyse Again is off:",
    tooltips "Already waiting to analyse this screenshot", "Analysing this screenshot".
  - §5.4 VoiceOver ", waiting to analyse", ", analysing".
  - §6 card message "Allow it to analyse this screenshot now…".
  - §7 hidden-panel toasts: "Analysed again", "Could not analyse again", "Not analysed".
  - §9 VoiceOver table: "Waiting to analyse", "Analysing", "Analysed again…".
  - §11 snapshot names: `search-analyse-*` → `search-analyze-*` (e.g. `search-analyze-waiting`,
    `search-analyze-analyzing`), `toast-analysed-again` → `toast-analyzed-again`, `toast-analysed-kept-your-name` →
    `toast-analyzed-kept-your-name`.
  - §12 departures and the closing "Open point for Parag" (now settled: American everywhere).
- **Mockup** (`docs/design/subfolders-and-retitle-mockup.html`): every "Analyse"/"Analysed"/"Analysing" string. It is
  for review only; the CI snapshots are the check.
- **Code on main** (`0e755e8`): three doc comments say "re-analyse" (`AppCoordinator.swift`, `FileActions.swift`,
  `SearchResultActions.swift`); fix them when touching those files (ticket 10 checks none remain).

## Snapshot names (light and dark)

- 04: `settings-general-subfolders-off`, `-by-type`, `-by-app`, `-two-level`, `-folder-missing`; `toast-sorted`
- 05: `settings-general-subfolders-sorting`, `sort-confirm`, `sort-nothing`, `toast-sort-batch`, `toast-sort-stopped`,
  `toast-moved-back`, `menu-sorting`, `menu-undo-move`
- 07: `search-edit-name`, `search-edit-name-error`, `search-edit-name-clash`; existing preview snapshots updated for
  the two icon buttons
- 08: `search-analyze-waiting`, `-analyzing`, `-held`, `-renamed`, `-kept-your-name`, `-kept-restored`, `-excluded`,
  `-paused`, `-failed`; `search-row-indicators`; `toast-analyzed-again`, `toast-analyzed-kept-your-name`
- 09: `search-consent`, `search-analyze-dropped`, `search-analyze-unavailable`
