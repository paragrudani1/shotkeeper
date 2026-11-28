# Workflow

How feature work and wiki upkeep are organised. Related: [index](index.md), [environment](environment.md).

## Specs and tickets
- 2026-11-28: Parag decided that specs stay as files in `docs/specs/` (requirements verbatim from Parag, never
  edited), not GitHub issues. Reason given in the question: the repo is public since 2026-11-22, so issues would be
  public. Prior art: `docs/specs/ui-polish-2026-11.md`.

## Wiki lint
- 2026-11-28: Parag approved a weekly wiki lint on **Gemini 4 Hydrogen** (T3 provider `antigravity`, model
  `gemini-4-hydrogen`, `thought_level: high`). T3 scheduled task `scheduled-task:dfd40791-3543-42be-9121-768973dc7f2d`,
  Mondays 09:00 (first run 2026-11-30 08:00 UTC). The task runs read-only and posts its report to a separate thread.
  It checks index coverage, contradictions, claims that have been overtaken but not marked superseded, undated code
  claims, answered open questions and broken links, all against `origin/main`. The scheduled run only hands the work
  to the Hydrogen delegate. If that model is unavailable, the run reports it and does not fall back to another model.
  The chief of staff turns the findings into wiki edits.

## Agent concurrency
- 2026-11-28: Parag set a cap of **at most 4 subagents at a time**. Five research agents had been started; the
  distribution research (signing, notarization, Sparkle) was cancelled and is re-run when a slot frees.

## Roadmap
- 2026-11-28: Parag approved all eight candidate features ("let's do all of it"): search filters, copying a
  screenshot's text, Shortcuts and Spotlight, sorting into subfolders, fixing or re-running a title, clean-up help
  (duplicates, old screenshots), more capture types (screen recordings, clipboard), and signed, notarized builds with
  auto-update. Plus a fix for the Clairic price before the promo ends on 2026-12-01. The research notes and the code
  survey come first ([roadmap-survey](roadmap-survey.md) once it is written), then specs in `docs/specs/`.
- 2026-11-28: disk had 14 GB free, below the 15 GB floor (see [environment](environment.md)). Most of the space is in
  other projects' T3 worktrees, which are not this project's to delete. Docker builds are on hold until Parag frees space.
  *Resolved the same day:* Parag chose to delete only stale worktrees. Of the 47 clean easysocial worktrees, 44 had a
  commit on 2026-11-27 or 2026-11-28, so they were probably in use. Only the 3 clean ones older than 3 days were removed
  (`git worktree remove`, which keeps their branches): easysocial-api `research/template-volume-by-source`,
  `research/meta-template-ttl-api` and `t3/triage-issue-1994`. Afterwards there was 19 GB free; the free space moves
  with other projects' activity, so check `df -h /` before starting parallel Docker builds.
- 2026-11-28: **Parag's decisions on scope.**
  - Feature 8 becomes **auto-update only**: there is no Apple Developer Program membership, so the build stays
    ad-hoc signed and is not notarized. Research: `../research/auto-update.md` (once written).
  - Clean-up: **move to Trash** after the user confirms a list they ticked, with Undo. This needs a written exception
    to the AGENTS.md rule "never delete or overwrite a user file"; the clean-up spec adds it. Moving to the Trash
    still never replaces a file.
- 2026-11-28: **Clairic price after the promo:** no code change is needed. At `295df83`, `SetupCopy.swift` already
  uses the standard $0.24 per M input tokens ($1.98 per 1,000 screenshots, shown as "About $2"). Only README and wiki
  wording that calls the promo current needs updating after 2026-12-01. Source:
  [../research/clairic/pricing-2026-11-28.md](../research/clairic/pricing-2026-11-28.md). The pricing page also lists
  `@cf/cloudflare/clairic-flash`, which stays at $0.10 per M; it is untested.
