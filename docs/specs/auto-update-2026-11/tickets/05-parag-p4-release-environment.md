# 05: Parag creates the GitHub `release` environment and its secrets (spec P4, changed)

**Type:** needs-human (Parag, in the GitHub web UI).

**What to do:** follow spec checklist **P4.1 and P4.3–P4.10**. **Skip P4.2 (Required reviewers).** Parag decided on
2026-11-28 that there is no required approval per release (`docs/wiki/workflow.md`, "Auto-update spec"). The
environment keeps its tag rule (`v*`) and its three environment secrets.

**Blocked by:** 04 (backups first).

**Status:** needs-human

- [ ] Environment `release` exists with deployment rule: ref type **Tag**, pattern `v*`, and **no** required reviewer.
- [ ] Three **environment** secrets (not repository secrets): `SIGNING_CERT_P12_BASE64`, `SPARKLE_ED_PRIVATE_KEY`,
      `SIGNING_CERT_P12_PASSWORD`.
- [ ] P4.8 tag ruleset (`v*`: restrict creations, updates, deletions; Repository admin bypass). The spec marks it
      *recommended*. With no required reviewer it is the main guard against a stray or moved tag, so the agent
      asks Parag to do it and records the answer in the wiki if they skip it.
- [ ] Clipboard cleared (P4.7); `~/ShotkeeperSecrets` removed only after the backup is checked (P4.9).
- [ ] Parag tells the agent "environment ready" (P4.10).

**Agent check afterwards (read-only):** `gh api repos/{owner}/{repo}/environments/release` shows the tag policy and
no `required_reviewers` rule; `gh secret list --env release` lists the three names. Never print values.

**Test seam, real-Mac checks, CI:** no code, so no test seam and no `macos-app` gate for this ticket itself. The acceptance boxes above are the check. The real-Mac part *is* the work.
