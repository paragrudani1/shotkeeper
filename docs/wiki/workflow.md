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
