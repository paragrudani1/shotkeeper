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
- 2026-11-28: **More decisions from Parag**, answering the survey's open questions
  ([roadmap-survey](roadmap-survey.md)):
  - Re-analyse (#5): an explicit "Analyse Again" on one screenshot is the user's request to upload it, **but only if
    the current backend's destination is allowed at that moment**. Otherwise it asks first. CODING_STANDARDS #2 is
    reworded once, in the consent prefactor PR (survey prefactor 6), before #5 and #7.
  - Auto-update (#8): **Sparkle is allowed** as the one exception to "no third-party dependencies" (2026-11-21), with a
    pinned version and the exception written into the docs.
  - Clipboard capture (#7): **on by default** (Parag chose this over the recommended opt-in). Folder and filename
    exclusions cannot match these screenshots. Open: whether the pasteboard privacy prompt on newer macOS makes on by
    default unworkable; see `../research/capture-types.md` once it is written.
  - Copy text (#2): **full on-device OCR with Apple Vision**. The text goes in the index, where it can be searched and
    copied, and can be added to existing screenshots on request. The model's `key_text` stays as it is.
  - Prefactor A (named index columns, settings round-trip test, index change feed, row builder) started 2026-11-28 on
    branch `t3/prefactor-index`.
- 2026-11-28: **Spotlight/Shortcuts/OCR research** ([../research/spotlight-shortcuts-ocr.md](../research/spotlight-shortcuts-ocr.md)).
  - The note worries that the CI artifact may be fully unsigned (`CODE_SIGNING_ALLOWED=NO`). It is not: as of
    `295df83`, `ci.yml:180-187` ad-hoc signs the Release app (`codesign --force --deep --sign -`) and verifies it.
    Whether Core Spotlight accepts an *ad-hoc* signature is still undocumented and needs a real-Mac check before the
    Spotlight spec is final.
  - OCR timing follows from Parag's choice that the text is searchable: OCR runs when a screenshot is indexed. The
    default minimum text height (1/32 of image height) and the speed per image need measuring on real screenshots.
  - Left for the Spotlight spec (wave 3), to ask Parag then: keep macOS 14 as the minimum (macOS 15+ for
    `IndexedEntity`/`FileEntity`)? A Shotkeeper section in Spotlight, given that plain Spotlight already finds the
    text, tags and comment (possible duplicate results)? What should opening a Spotlight result do?

## UI design step
- 2026-11-28: Parag asked that new UI be designed with the **frontend-design** skill
  (`/root/.claude/plugins/cache/anthropic-plugin-directory/frontend-design/1.1.1-0fbfda5a91f4/skills/frontend-design/SKILL.md`).
  How it fits:
  - Every spec with UI gets a design pass after the spec and before the tickets. A design agent reads the skill, the
    spec, `../specs/ui-polish-2026-11.md`, [appkit-gotchas](appkit-gotchas.md) and the latest CI snapshot PNGs, and writes
    `docs/design/<feature>.md`: layout as ASCII wireframes, hierarchy, every piece of copy, the states (empty, error,
    loading, many results) and keyboard behaviour. It also produces an HTML mockup, which I render for Parag to approve.
    Tickets cite the approved design note.
  - The skill's rule "where the brief pins down a visual direction, follow it exactly" applies: the ui-polish spec
    already fixes the identity (SF system font, semantic colours, indigo #5856D6/#5E5CE6 only for brand moments, light
    and dark). So the design pass makes choices about layout, hierarchy, copy and interaction within native macOS
    conventions. It does not invent a new palette or typeface. Its "spend boldness in one place" and writing rules
    (sentence case, plain verbs, an action keeps its name through the flow, errors say how to fix them) apply in full.
  - The HTML mockup is for review only. CI snapshot PNGs of the real SwiftUI views stay the acceptance check.
- 2026-11-28: **Capture research** ([../research/capture-types.md](../research/capture-types.md)). No backend accepts
  video, so recordings become still frames on the Mac (AVFoundation, app side, behind a seam). Four frames cost about
  3.5× a screenshot on Clairic; one tiled image costs the same as a screenshot. Clipboard: Apple documents no way to
  tell a screenshot from any other copied image, and from macOS 27.2 reading a copied image in the background
  probably shows a privacy alert until the user chooses "Always Allow". That conflicts with Parag's "on by default"
  decision (above), so it went back to Parag.
  - Side finding: OpenRouter's endpoint list for Inkling 2 Mini changed after 2026-11-22: six endpoints and $0.06/M
    input. `../research/openrouter.md`, the `provider.only` pin and the ZDR checks need re-checking.
- 2026-11-28: **Feature 7 dropped.** After the capture research, Parag dropped **both clipboard capture and screen
  recordings**: "Drop clipboard capture", "drop screen recording feature too". This supersedes the clipboard
  "on by default" decision above. `../research/capture-types.md` stays as the record of why. With only #5 left
  needing the consent change, it moves into the #5 (fix or re-run a title) work instead of a separate prefactor PR.
  The remaining roadmap is features 1–6 and 8 (auto-update only).
