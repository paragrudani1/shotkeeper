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
- 2026-11-28: **Auto-update research** ([../research/auto-update.md](../research/auto-update.md), from docs and
  Sparkle 2.10.1 source; not run on a Mac). Sparkle works on an ad-hoc build, but each update is a new code identity.
  That probably means up to 3 keychain dialogs per update (Cloudflare token, OpenRouter key, custom-endpoint key: the
  file-based keychain) and the Desktop privacy prompt again. Quarantine only affects the first install. The EdDSA
  private key can never be replaced without a Developer ID, so losing it ends auto-update for installed copies.
  `CURRENT_PROJECT_VERSION` is fixed at "1" (as of `295df83`) and must increase with every release. Went back to
  Parag: the prompts versus a self-signed certificate versus Developer ID.
- 2026-11-28: **Auto-update decisions (Parag):** use a **self-signed certificate, tested first**. Parag creates one
  certificate in Keychain Access, CI signs with it, and a build N → N+1 update is tested on Parag's Mac, counting the
  keychain and Desktop prompts. If prompts remain, the choice goes back to Parag. Update checks are **manual only**: a
  "Check for Updates…" menu item, no automatic checks. Parag also has to create the Sparkle EdDSA key (see the
  research note's checklist).
- 2026-11-28: **Lesson (process):** `git add docs` in the chief-of-staff's commit `0a5505f` swept in the wave 1 spec
  while its agent was still writing it. While agents write to the shared checkout, stage named paths only.
- 2026-11-28: **Wave 1 spec** written: [../specs/search-filters-and-text-2026-11.md](../specs/search-filters-and-text-2026-11.md)
  (first version in `0a5505f`). Test seams proposed: `ScreenshotIndex` public API, `SearchWindowState`, and a new
  `TextRecognizer` port behind `TextRecognitionRunner`. Went to Parag for confirmation together with the spec's
  judgement calls.
- 2026-11-28: **Prefactor A** opened as PR #9 (`e09b0eb`): `ScreenshotIndex.columns`, frozen-schema migration test,
  settings round-trip test, `changes()` feed, `IndexedScreenshot.testRow`. Details: [prefactor-index](prefactor-index.md)
  (on that branch).
- 2026-11-28: **OpenRouter re-check** ("Re-check 2026-11-28" in [../research/openrouter.md](../research/openrouter.md)):
  the consent text is still accurate and no privacy change is needed. The `provider.only` pin reaches
  `primeintellect/fp4`, `io-net/nvfp4` and the priority tier `primeintellect/fast`, all ZDR. The `fast` tier bills
  2.5× ($0.15/$0.60 per M), and `service_tier: "default"` would keep requests off it. Planned as a small PR together
  with the out-of-date README/wiki prices (Prime Intellect standard is now $0.06/$0.24) and the Clairic promo wording.
- 2026-11-28: Parag **confirmed the wave 1 test seams** and left all of the spec's judgement calls unticked, which
  accepts them: OCR always on with no setting, and Pause does not stop it; ⇧⌘C copies the text; OCR text is in the
  search match, weighted far below the title; Copy Text reads a never-read screenshot on demand; one source at a
  time; type filter = the seven chips; a tag click clears all filters.
- 2026-11-28: **Review of PR #9 (head `e09b0eb`): fix first.** The `macos-app` job failed: a test helper used
  `AsyncSequence.Failure` (macOS 15+) while the package targets 14. The author had reported done on a Linux run
  only, reasoning that no app code was touched. Also, two column PRs could still share migration 3 silently, because
  identical added lines merge cleanly. A fix agent was started the same day.
  - **Lesson → environment:** AGENTS.md gained a line saying Linux green does not prove a macOS build; core-only
    changes need `macos-app` green too (commit on `t3/roadmap-2026-11`).
- 2026-11-28: PR #9 fixes pushed (`bb786fe`; both CI jobs green, runs 46127211459/46127216459); a re-check was started.
  **PR #10** (prefactor B, head `06d1aea`, both jobs green) opened: `CaptureSources`, `FileActions` (+ one file per
  feature), `SearchResultActions`, `WorkspaceActions`, `SearchKeyMap` in core, `scripts/lint.sh` with per-line
  `lint-allow` comments, and per-screen snapshot tests ([prefactor-app](prefactor-app.md) on that branch). Note:
  `CaptureSources` was designed for feature 7, which Parag had dropped by then; the review was asked to judge it.
  **PR #11** (OpenRouter `service_tier: "default"` + README refresh, head `7edf4b0`) opened. Reviews of #10 and #11 were started.
- 2026-11-28: **Wave 1 design pass** done: [../design/search-filters-and-text.md](../design/search-filters-and-text.md) +
  mockup. Date/Source pills at the end of the chip row (⌘D/⌘S open in-panel pickers); Copy Text as a Live-Text-style
  badge on the preview image (the one bold choice). Departures from the polish spec: picker fields take focus while
  open, Esc order picker → clear → close, "Clear filters" button. Sent to Parag for approval. Practical note: the
  mockup's 880 px panel overflows the 728 px render frame; it was shown through a `body{zoom:.8}` copy in /tmp.
- 2026-11-28: Parag **approved the wave 1 design** and left all four polish-spec departures unticked, which accepts
  them: picker focus, Esc order, "Clear filters", menu bar items.
- 2026-11-28: **PR #9 merged** (`b5c2984`, head `bb786fe`) after a re-check verdict of "merge". That re-check
  simulated two column PRs merged with "keep both": the suite fails. Follow-up: `shippedColumns` is a dictionary
  literal, so a duplicate key crashes the run (signal 4) instead of failing the test. It should become ordered pairs
  with a uniqueness assert.
- 2026-11-28: **PR #10 review: fix first**, no blockers. Behaviour is preserved. The lint misses Swift 6 access-level
  imports (`public import AppKit`), `NSWorkspace.recycle` and POSIX deletes, and accepts a `lint-allow` marker with
  no reason or one inside a string. The `CaptureSources` docs still describe dropped feature 7; the reviewer advised
  keeping the type and rewording it. **PR #11 review: fix first**: README overstates shortcut-conflict detection;
  the research it cites must reach main first (this docs branch); it lacked a wiki line (added to
  [openrouter-backend](openrouter-backend.md)); `macos-app` failed once in the actool step, probably a flake.
- 2026-11-28: **Wave 2 spec** ([../specs/subfolders-and-retitle-2026-11.md](../specs/subfolders-and-retitle-2026-11.md),
  `d82de8d`). Parag **accepted all 15 recommended decisions**: sort modes Off / By type / By app or site / By type then
  app or site; fixed type folder names; unknown app → "Other" (or the type folder in two-level mode); subfolders only
  inside the organized folder; "Sort Existing" only touches files still where Shotkeeper put them, asks with counts
  first and uploads nothing; ⌘E edits the name, ⇧⌘E runs Analyse Again; when the destination isn't allowed, the
  existing Settings question (a lasting grant); a hand-typed name is kept (the model's title is offered as "Use This
  Name"); restored-by-undo files keep their name; Analyse Again applies current rename/move/sort settings; undo
  restores name and place only; exclusions and Pause refuse; Analyse Again jumps the queue; leaving the panel cancels
  a name edit; a failed Analyse Again leaves the row as it was. Consent: `ProcessExistingAuthorization` becomes
  `UserUploadAuthorization`, and CODING_STANDARDS #2 is reworded in the same PR.
- 2026-11-28: **PR #10 re-check: merge once `macos-app` is green.** Every fix was proven with planted files and a
  simulated "keep both" merge. The chief of staff fixed the remaining doc-comment nit directly (`903b3fc`).
- 2026-11-28: **Auto-update spec** ([../specs/auto-update-2026-11.md](../specs/auto-update-2026-11.md), `b87c047`).
  Parag's answers:
  - The N → N+1 prompt test uses **the first two real releases** (0.2.0 → 0.2.1). Recommended was private test
    releases; Parag chose real ones. They are public before the prompt count is known.
  - **No required approval per release**: Parag ticked "You approve each release" to change it. The `release`
    environment keeps its tag restriction (`v*`) and secrets, but has no required reviewer.
  - Accepted: feed on GitHub Releases (`releases/latest/download/appcast.xml`, redirect checked in the first
    release); `CHANGELOG.md` section required per release; tag `vMAJOR.MINOR.PATCH` with build number
    MAJOR×10000+MINOR×100+PATCH (no betas).
  - The spec's other calls stand (two jobs, build without secrets / sign without build tools; Sparkle pinned
    2.10.1; `SUAllowsAutomaticUpdates = false`; no design pass, since the UI is one menu row).
  - Before the app work: Parag must create the self-signed certificate and Sparkle's EdDSA keys (spec checklist P1/P2).
- 2026-11-28: **Wave 1 ticket 01** opened as draft PR #13 into `t3/wave1-search` (`3e6fb13`): migration 3
  (four text columns, FTS rebuilt with `recognized_text`, weights 10/6/3/1/2/0.5, three indexes),
  `setRecognizedText(…ifContentHash:)`, `newestPendingTextRow()`. Review started.
  - The worktree came from the parent's docs branch, not the integration branch; the brief's `git switch` step
    caught it. Keep that step in every implementer brief.
- 2026-11-28: **Bottleneck: macOS CI.** PRs #10, #12 and #13 all waited on `macos-app` at once, and every docs push
  to #12 restarted its run. Rule from now on: batch docs pushes to an open docs PR. Candidate improvement (after
  #10 merges, since it edits `ci.yml`): skip `macos-app` for docs-only changes (`paths-ignore` for `docs/**`, `*.md`).
- 2026-11-28: **PR #10 merged** (`000310c`, head `903b3fc`); `t3/wave1-search` fast-forwarded to it.
- 2026-11-28: **PR #13 review: merge into integration once `macos-app` is green**, no blockers or should-fix. Proven
  with a throwaway test: a 3,000-row v2 database with an injected failure after the FTS drop rolls back to v2 intact,
  and the retry migrates cleanly (FTS `integrity-check` passes after insert, update, delete and upsert). Query plans
  use the new indexes. Nits left for the wave 1 final review: migration 3 builds SQL from the live `ftsColumns` list
  (freeze a copy); a partial index on the pending sort; a note in ticket 08 that a failed re-read drops old text.
- 2026-11-28: **Auto-update tickets** (13, `docs/specs/auto-update-2026-11/tickets/`): 01 release plan + CLI +
  CHANGELOG and 06 signing scripts have no blockers; 02–05 are Parag's P1–P4; 07 Sparkle + menu row; 08 public key;
  09 release workflow; 10 README; 11 publish 0.2.0; 12 the P5 test with 0.2.1; 13 record the results. Ticket 05 asks
  Parag for a tag ruleset, which replaces the dropped reviewer as the guard against a wrong tag.
- 2026-11-28: **PR #12 merged** (`74a641f`, head `5eaac60`; docs), then **PR #11 merged** (`0e755e8`, head `92aa001`;
  OpenRouter `service_tier: "default"` + README). PR #13 conflicted with `t3/wave1-search` after the fast-forward to
  #10 (`shippedColumns` changed to pairs). The chief of staff resolved it (`49aef72`: pairs plus `(3, […])`; lint ok,
  429 Linux tests pass). Docs commits made after `5eaac60` stay on `t3/roadmap-2026-11` for the next docs PR.
- 2026-11-28: Parag **approved the wave 2 design** ([../design/subfolders-and-retitle.md](../design/subfolders-and-retitle.md))
  and left all departures unticked, which accepts them. **Spelling: American everywhere**, so the action is
  **"Analyze Again"**. The spec and design text say "Analyse"; Parag's quoted requirement stays verbatim, and
  everything else (synthesis, design strings, code) uses "Analyze".
- 2026-11-28: **Clean-up spec** drafted ([../specs/clean-up-2026-11.md](../specs/clean-up-2026-11.md)). Exact
  duplicates are found by size grouping, then a full hash, then a byte-for-byte compare before each move (size + mtime
  + 64 KiB would miss `cp` copies). A research note must come first: Finder "Put Back" with `trashItem` vs
  `NSWorkspace.recycle`, what updates `kMDItemLastUsedDate`, and the Trash URL `trashItem` returns. 12 decisions went
  to Parag.
- 2026-11-28: Draft PRs **#15** (auto-update 01: `ReleasePlan` + `release-plan` CLI + CHANGELOG, into
  `t3/auto-update`; Sparkle's release-notes naming confirmed at `generate_appcast/ArchiveItem.swift:419-446`) and
  **#16** (wave 1 02: date filter, into `t3/wave1-search`) opened; both wait on `macos-app`.
- 2026-11-28: Parag **accepted all 12 clean-up recommendations**: exact copies only (byte-compared before each
  move); a group needs at least one indexed screenshot; extra copies are pre-ticked, never-opened ones are not;
  "opened" = any Shotkeeper action on it or macOS's last-used date; opened once means never listed; with no macOS
  record it is listed with a note; "old" defaults to 3 months (1/3/6/12, counted from when taken); restored-by-undo
  files are never listed and are the copy kept; a trashed row stays marked trashed until the Trash is emptied;
  menu Undo takes back the whole last batch (also wave 2's Sort Existing); the Trash call follows the research;
  a separate Clean Up window from the menu bar.
- 2026-11-28: **PR #14 merged into `t3/wave1-search`** (`e25049c`; wave 1 ticket 05, the Vision measurement tool).
  `macos-app` type-checked it and ran it on two generated images, both green. Handed to Parag to run (instructions:
  `docs/research/vision-ocr-settings.md` "How to run (Parag)"). Ticket 04 waits for the results.
- 2026-11-28: **PR #13 merged into `t3/wave1-search`** (`be7e4ad`, head `49aef72`; wave 1 ticket 01). Tickets 04 and 06
  are now unblocked (04 still needs Parag's Vision numbers before it merges).
- 2026-11-28: **PR #15 review: fix first** (one should-fix). Release-notes escaping went per `Character`, so `<`+ZWJ and
  `]]>`+ZWJ slipped through and could break the appcast's CDATA. The chief of staff fixed it (`089ef62`: per-scalar
  escaping and a duplicate-section error, two tests, 439 Linux tests pass). Merge into `t3/auto-update` once CI is green.
- 2026-11-28: **PR #16 review: merge into integration**, no blockers. Should-fix: the index search and the panel
  could use different clocks and calendars after a time-zone change (pass `now`/`calendar` into `index.search`, use
  `Calendar.autoupdatingCurrent`). Nits: cross-year VoiceOver range, default calendar in `DatePicker`, picker 2 pt
  too high. All three new snapshots match the design. The merge was blocked by conflicts with tickets 01/05 now on
  the integration branch, so one agent resolves them and applies the review fixes on #16's branch.
  - **Pattern:** parallel tickets that each create the same wiki page (here `search-filters-and-text.md`) always
    conflict. Next time the first ticket creates the page and later tickets only append to it.
- 2026-11-28: **Wave 2 tickets** (10, `docs/specs/subfolders-and-retitle-2026-11/tickets/`): 01 consent
  (`UserUploadAuthorization` + CODING_STANDARDS #2), 02 `title_source` migration (version 4), 03 queue job kinds,
  04 sort new screenshots, 05 Sort Existing, 06 `reanalyze` in core, 07 Edit name, 08 Analyze Again, 09 Analyze
  Again asks first, 10 integration + real-Mac pass. The integration branch **`t3/wave2` is cut from
  `t3/wave1-search`**, not from main: migration 4 must sit on top of wave 1's migration 3, and the versions test
  requires contiguous numbers. `t3/wave2` takes wave 1's tip as it moves.
- 2026-11-28: **Trash research** ([../research/trash-and-last-used.md](../research/trash-and-last-used.md)): keep
  `FileManager.trashItem` in core `FileOrganizer`, behind `#if canImport(Darwin)` (Linux Foundation lacks it). Put
  Back is best-effort for batches (Apple bug r. 23153124 hits `recycle` too), so the confirmation promises Undo, not
  Put Back. Undo uses `renameNoReplace` from the stored Trash URL; "never opened" and "unknown" can't be told apart
  through `MDItemCopyAttribute`. The network-volume behaviour must be tested on a real Mac before clean-up ships.
  - **Environment idea:** real-Mac checks are piling up across specs (Spotlight with ad-hoc signing, Vision
    settings, Trash on network volumes, Sparkle prompts, date-field Return). Plan: one consolidated Mac checklist
    for Parag per release, built from the specs' real-Mac sections.
- 2026-11-28: **PR #15 merged into `t3/auto-update`** (`b59226b`, head `089ef62`; auto-update ticket 01). Next for
  auto-update: ticket 06 (signing scripts, ad-hoc in CI), then 07 (Sparkle + menu row); 08 waits for Parag's
  public key.
- 2026-11-28: **PR #17 review (consent): fix first**, no blockers. The truth table is unchanged and the new
  CODING_STANDARDS #2 is stricter than the old one. Should-fix: the public `UserUploadAuthorization.init` let app code
  bypass the generation check. The chief of staff made it internal (`d6ceef4`; lint ok, 433 Linux tests pass). The
  "issue only if allowed at the click" guard is assigned to ticket 08. Kept app identifiers that name the
  Process Existing command (accepted deviation).
- 2026-11-28: **PR #16 merged into `t3/wave1-search`** (`6841d92`, head `327a7a0`; wave 1 ticket 02). The chief of
  staff checked `search-date-custom-light.png` from run 46138812725: the picker sits below the row-2 divider, as the
  design says. Ticket 03 (source filter) and 06 (Copy Text) are next on the panel.
- 2026-11-28: Parag **approved the Clean Up design** ([../design/clean-up.md](../design/clean-up.md)) and left all
  departures unticked, which accepts them. One list with two sections; a "Keep" pill; a stack of the ticked
  thumbnails in the footer (the one bold element); a sheet alert with Cancel as the default; ⌘⌫ ignored for 0.5 s and
  on key repeat; rows that change are locked until Check Again; "Show Only Ticked" (⌘T); one "no record" note per
  section. The window has no default button, on purpose.
- 2026-11-28: **PR #18** (wave 1 04, reading text; provisional Apple-default Vision settings
  `vision-r3-accurate-h1/32-lc1`) opened. It cannot merge until Parag's measurement. `t3/wave1-search` took main
  (`c72dbdf`: research notes, docs, #11) so code can cite `docs/research/` on the integration branch.
- 2026-11-28: **Clean-up tickets** (10, `docs/specs/clean-up-2026-11/tickets/`). 01 migration (`last_opened_at`,
  `trashed_from`, `trashed`); 02 `FileOrganizer.trash` with the AGENTS.md exception, CODING_STANDARDS #1 and the lint
  `trash` rule in one PR; 03 undo batches; 04 record opens; 05 list duplicates (read-only); 06 never opened; 07 Move
  to Trash; 08 list out of date; 09 failed Undo and Put Back; 10 integration and the real-Mac pass. The SMB
  network-volume check must pass before clean-up ships.
- 2026-11-28: **PR #20** (wave 2 02, `title_source`, migration 4) opened; review started. **PR #21** (CI triggers:
  one run per PR push, docs-only changes skipped) opened; it carries out the macOS-bottleneck improvement noted above.
- 2026-11-28: **PR #17 merged into `t3/wave2`** (`0139f02`, head `d6ceef4`). **Mistake:** one of its four check runs
  had failed (`macos-app`, pull_request run 46139322159, the actool step), and the merge went ahead on T3's "all
  checks passed" without reading the `gh pr checks` output that was already printed. The same commit passed in
  push run 46139318397, and it is the same actool exception seen on PR #11, with a doubled path `App/App/Shotkeeper`.
  So the merged code is the tested code, but the rule was broken. **Rule:** before every merge, refuse if any line of
  `gh pr checks` is not `pass`. A diagnosis agent was started for the actool step (no retries, root cause only).
  - **Guard added:** `/root/local-dev/shotkeeper-llm/bin/merge-if-green <pr> <sha>` refuses unless the head matches
    and every `gh pr checks` line is `pass`, marks a draft ready, then merges with `--match-head-commit`. All merges
    go through it from now on.
- 2026-11-28: **PR #21 merged** (`117e2b2`): CI runs once per PR push, and docs-only changes are skipped. The PR
  itself showed one run per job instead of two. `main` was merged into `t3/wave1-search` (`d63be6a`), `t3/wave2`
  (`fce1069`) and `t3/auto-update` (`cf37f0d`) so their PRs get the new triggers. All were clean merges, done with
  `merge-if-green` for the PR.
- 2026-11-28: **actool flake: root cause found, in our script.** The step passed relative paths, and actool forwards
  the call to a long-lived `ibtoold` server. When the server that xcodebuild started (cwd `App/`) was still alive,
  it resolved the paths from `App/`, giving `App/App/Shotkeeper/AppIcon.icon`. Calls taking 0.03–0.2 s show the
  server was reused in the failing runs; 2–3 s calls show a new server in the passing one. Fix: absolute
  `$GITHUB_WORKSPACE/...` paths, no retries (PR #22, `7e839a2`). Evidence is in `macos-ci.md` on that branch.
- 2026-11-28: **PR #20 review: code ready**, blocked only by base conflicts (wiki add/add with #17). The reviewer
  proved migration 4 on a 20,000-row v3 database, with an injected failure and a mid-transaction crash snapshot.
  The chief of staff merged the base, combined the wiki page, and tightened the backfill to match the note only as
  the whole note or its last `; ` part, so a quoted error can't match. Tests were added and 437 Linux tests pass
  (`93a3dbb`). Recorded for ticket 06: check `restored_by_undo` before `title_source`.
- 2026-11-28: **PR #19 merged into `t3/auto-update`** (`219a902`, head `5ecddaa`; auto-update 06, signing scripts).
  The review found no blockers. Signing order and flags match Sparkle's live sandboxing page. Hardened Runtime is on
  for Sparkle's parts and off for the app, as the spec says. The downloaded artifact's SHA matched the upload. The
  review also found that the "Lint on macOS" step actually runs in the Linux job (from PR #10's fixes), so the bash
  3.2 claim was never true. Follow-ups: PR A (lint on macOS, against main) and PR B (`OTHER_CODE_SIGN_FLAGS --deep`
  check, `select-xcode.sh` message, a ticket 09 note to dry-run the real-identity path with a throwaway certificate).
- 2026-11-28: **PR #22 merged** (`e852070`): the actool step uses absolute paths (root cause of the flake). `main`
  was merged into the three integration branches again.
- 2026-11-28: **PR #20 merged into `t3/wave2`** (`b12dc4d`, head `93a3dbb`; wave 2 02, migration 4 `title_source`).
  Wave 2 ticket 06 (`reanalyze` in core) is unblocked and waits for a free slot.
- 2026-11-28: **PR #23 review (source filter): fix first.** `macos-app` didn't compile (an escaping closure in
  `SearchView`), so CI produced no snapshots. Should-fix before wave 2 relies on `SourceKey`: width folding and
  whitespace collapsing ("ＧｉｔＨｕｂ" ≠ "GitHub"), and documentation that `rawValue` is a matching key, never a folder or
  display name (use `SourceFacet.displayName`). The SQL, keyboard, strings and the author's four decisions were
  approved. A fix agent started.
  - **Pattern:** two implementers (PR #23 here, and PR #9 earlier) handed back with `macos-app` "pending" and it
    then failed. Fix briefs now say waiting for CI is part of the task.
- 2026-11-28: PRs **#24** (lint on macOS, against main), **#25** (wave 2 03, queue job kinds; under review) and
  **#26** (auto-update 06 follow-ups) opened.
- 2026-11-28: **PR #24 merged** (`f19156b`): lint runs in `macos-app` under `/bin/bash`. Job 140968794035 printed
  "GNU bash, version 3.2.57(1)-release", "lint self-test: ok" and "lint: ok". `main` still needs merging into the
  integration branches. For `t3/auto-update`, #26 also edits the `lint.sh` header, so merge #26 first, then main.
- 2026-11-28: **PR #25 review (queue kinds): fix first**, with one should-fix. A paused job whose attempt then got a
  429 kept showing `.running` (the reviewer proved it with a probe test). The chief of staff fixed it (`45f55b1`):
  job states are published when an attempt ends, `waitUntil` now fails loudly on timeout, and a pause-then-429 test
  was added (454 Linux tests pass). Consent carry is clean: the init is still internal, and the request is dropped
  when the job ends.
- 2026-11-28: Auto-update ticket 07 (Sparkle 2.10.1 + "Check for Updates…") started. It stops and reports if Sparkle
  needs `SUPublicEDKey` to start, which would make it wait for Parag's key (ticket 03/P2).
- 2026-11-28: **PR #26 merged into `t3/auto-update`** (`904283b`; the `OTHER_CODE_SIGN_FLAGS --deep` check, the
  `select-xcode.sh` message, and the ticket 09 note). Main (#24) was then merged into all three integration branches.
  `t3/auto-update` needed a hand resolution (`96e720a`): the old misnamed lint step was dropped from `linux-core`, the
  fake-codesign self-test kept, main's macOS lint step placed before Xcode selection, and both `lint.sh` header notes
  kept. YAML parses, and lint and its self-test pass. CI on the push run verifies the result.
- 2026-11-28: **PR #23 merged into `t3/wave1-search`** (`5bf635b`, head `94a055c`; wave 1 03, source filter). The fix
  agent resolved the build error and the `SourceKey` width/whitespace/URL issues, and checked the snapshots. The chief
  of staff read the `SourceKey` diff before merging. **Left open:** the Source pill always fills its 180 pt limit
  (`.frame(maxWidth:)` at `SearchFilterViews.swift:82`) instead of fitting its text, against the design. It is queued
  as a small polish fix before wave 1 merges to main. `t3/wave1-search` was then merged into `t3/wave2`
  (510 Linux tests pass; the wiki index conflict was combined), so wave 2 ticket 04 can use `SourceKey`.
- 2026-11-28: **PR #25 merged into `t3/wave2`** (`2c691eb`, head `45f55b1`; wave 2 03, queue job kinds with the
  pause/429 state fix). Wave 2 tickets 08–09 (panel) still wait for wave 1's panel tickets; 05 (Sort Existing)
  waits for 04.
- 2026-11-28: **PR #28** (wave 1 06, Copy Text) opened. Its app code had not compiled yet at handback; a review
  started in parallel. Notable deviation: the open panel refreshes on the index change feed (needed for "Reading
  text…" and the waiting copy).
  - **Process correction:** delegated agents refuse to wait on CI (T3 rule: children never watch or poll), so the
  "waiting for CI is part of the task" line in briefs does nothing. The chief of staff watches each PR's checks,
  and a red `macos-app` gets its own fix delegate.
