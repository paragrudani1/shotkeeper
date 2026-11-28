# Auto-update tickets (2026-11-28)

Tickets for the [auto-update spec](../../auto-update-2026-11.md), made with the to-tickets skill, local layout: one file
per ticket, blocking edges as text. The spec's requirements are not edited here. Parag's later decisions live in
[workflow](../../../wiki/workflow.md) ("Auto-update spec", 2026-11-28) and win over the spec's synthesis (below).

Builds on **PR #10** (`origin/t3/prefactor-app`, not merged yet; wiki `docs/wiki/prefactor-app.md` on that branch):
`Coordinator/` one part per file (it names `UpdateChecks` as feature 8's file), per-screen `MenuSnapshots`,
`scripts/lint.sh`, the lint step in `ci.yml`. Tickets 07 onward depend on it; 06 rebases over its `ci.yml` change.

Every code ticket counts as done only when `macos-app` CI is green on its PR (AGENTS.md), with the Linux tests and
`scripts/lint.sh`. **needs-human** tickets are Parag's checklist steps; an agent can't do them.

## Tickets

| # | Ticket | Blocked by | Who |
|---|---|---|---|
| 01 | [Release plan in core and `release-plan` CLI](01-release-plan-core-cli.md) | none | agent (core + CLI) |
| 02 | [P1: `Shotkeeper Release` certificate](02-parag-p1-certificate.md) | none | **needs-human** |
| 03 | [P2: Sparkle EdDSA key, public key to the agent](03-parag-p2-sparkle-key.md) | none | **needs-human** |
| 04 | [P3: offline backup](04-parag-p3-backup.md) | 02, 03 | **needs-human** |
| 05 | [P4: `release` environment + secrets, no reviewer](05-parag-p4-release-environment.md) | 04 | **needs-human** |
| 06 | [Shared Xcode + inside-out signing scripts, ad-hoc in `macos-app`](06-ci-signing-script-adhoc.md) | none (rebase over PR #10's `ci.yml`) | agent (CI) |
| 07 | [Sparkle 2.10.1 + "Check for Updates…" row](07-sparkle-check-for-updates.md) | PR #10, 06 | agent (app + CI) |
| 08 | [Public EdDSA key in the app; CI requires it](08-public-key-and-strict-plist-check.md) | 07, 03 | agent |
| 09 | [Release workflow](09-release-workflow.md) | 01, 06, 07 | agent (CI) |
| 10 | [README install/update/privacy](10-readme-install-update.md) | 07, 09 | agent (docs) |
| 11 | [Publish 0.2.0](11-first-release-0-2-0.md) | 05, 08, 09, 10 | agent, Parag confirms the tag |
| 12 | [P5: N → N+1 test, 0.2.0 → 0.2.1](12-parag-p5-n-to-n1-test.md) | 11 | **needs-human** (+ agent publishes 0.2.1) |
| 13 | [Record result, real-Mac checks, finish README](13-record-test-and-real-mac-checks.md) | 12 | agent (docs) |

```
01 ───────────────────────────┐
06 ──┬──> 07 ──┬──> 09 ──> 10 ─┼──> 11 ──> 12 ──> 13
PR#10┘         └──> 08 ────────┤
02 ─┐               ^          │
03 ─┼──> 04 ──> 05 ─┼──────────┘
    └───────────────┘ (03 → 08: public key)
```

## What can run in parallel

- **Now (before PR #10):** 01 (core only), 06 (CI scripts; rebase after PR #10), and Parag's 02 and 03, then 04 → 05.
  Nothing an agent builds waits for Parag until 08; the signing script runs ad-hoc on every push from 06 on.
- **Once PR #10 merges:** 07 (if 06 is in), plus 01/06 if still open.
- **Once 07 merges:** 09, and 08 as soon as Parag's public key (03) arrives.
- **Gate to the first release (11):** 05 + 08 + 09 + 10. 12 and 13 are sequential.
- At most four agents at once (workflow, 2026-11-28).

## Hotspots

- `.github/workflows/ci.yml`: 06 (signing/Xcode steps), 07 (plist check step), PR #10 (lint step). 06 before 07 keeps
  them sequential; 09 adds a new workflow file and doesn't edit `ci.yml` unless it takes the proposed `release-plan`
  step.
- `App/project.yml`: 07 (package, plist keys), 08 (one key). Feature 3 (Spotlight) also edits it; one-line conflicts.
- Menu (`MenuRowID`, `MenuContentView`, `MenuSnapshots`): only 07 here; wave 1 ticket 08 also adds menu rows.
- `docs/wiki/auto-update.md`: created by whichever of 01/06 merges first; the others append dated lines.

## Spec spots superseded by Parag's decisions (follow the wiki, not these lines)

Parag decided on 2026-11-28: **no required approval per release** (the `release` environment keeps its `v*` tag rule
and secrets, no required reviewer), and **the first two real releases are the N → N+1 test**. The spec's
requirements are untouched; its synthesis still says "approval" in these places:

- Story 22 ("one command plus one approval click") → one command (push the tag).
- Story 23 (release waits for approval) → superseded; the tag rule and secrets-only-in-`publish` remain.
- "The GitHub `release` environment" → "**required reviewer: Parag**" → none.
- "Why none of them can leak" → "Only a `v*` tag can enter the environment, and only with Parag's click … would still
  wait for Parag's approval, and the approval page shows the commit" → the click is gone. The tag ruleset (the spec
  calls it P4.6 there; it is **P4.8** in the checklist) is now the main guard against a stray or moved tag, which is
  why ticket 05 asks Parag to do it rather than leaving it optional.
- Checklist **P4.2** (Required reviewers) → skipped (ticket 05).
- **P5 intro** ("You approve each one in the repository's Actions tab …") → no approval; the release publishes when
  the tag is pushed (ticket 12).
- "Decisions Parag might disagree with" **#4** → reversed by Parag.
- The N → N+1 test on real releases matches the spec text already (Solution, Slicing 3, decision 8); nothing to
  supersede there, only confirmed.

The spec says to record dated deviations and implementation notes in `docs/wiki/auto-update.md`, not in the spec.
The first ticket that creates that page copies these two decisions into it with a link to `workflow.md`.
