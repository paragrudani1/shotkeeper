# 06: Analyze Again in core: `ScreenshotProcessor.reanalyze`

**What to build:** the core entry point that analyzes one already-indexed screenshot again, with every rule the spec
sets, testable on Linux. Given a row id and an optional `UserUploadRequest`, it refuses (missing, excluded, paused),
skips (awaiting consent), or updates the row's analysis and renames and moves the file the way a new screenshot would,
keeping a name the user typed and a file restored with Undo. A failure leaves the row exactly as it was. No UI yet
(08 wires it to the panel and the queue); the CLI is out of scope (spec, Out of Scope).

**Blocked by:** 01 (`userRequest:` on `decide`), 02 (`title_source`). It also reads and resets wave 1's
`text_status`, so it needs wave 1 ticket 01 (migration 3, merged into `t3/wave1-search`): before wave 1 merges to
main, branch from `t3/wave1-search` with 01 and 02 merged in, or wait for the wave 2 integration branch.

**Status:** ready-for-agent

**Sources:** spec "Analyse Again (core)" (steps 1–9, failure rule, `ReanalysisOutcome`, "Use suggested name", lint),
stories 42–64 (core parts), Testing Decisions seam 1 and seam 2 (the snapshot-switch test).

**Test seam:** seam 1, `ScreenshotProcessor` (`StubAnalyzer`, `TempDir`, in-memory index, real `UndoLog`); seam 2 for
the consent snapshot switch.

**Likely touches:** core `Pipeline/ScreenshotProcessor.swift` (or a `ScreenshotProcessor+Reanalyze.swift` extension,
which keeps `analyze` inside the type for `lint.sh`), a `ReanalysisOutcome` / `TitleKeptReason` type,
`ScreenshotProcessorTests` (or a new `ReanalyzeTests`), `UploadConsentTests`, `docs/core-api.md`.

- [ ] `reanalyze(rowID:request:) -> ReanalysisOutcome` keys on the row id and reads the row's current path at each
      attempt. It is the only way past `.alreadyIndexed`.
- [ ] Steps in order: look up the row (file missing → `.refused(.missing)`); exclusion check with
      `ExcludeRules.exclusion(for:capturedAt:now:)` (`.refused(.excluded(rule))`) and Pause (`.refused(.paused(until:))`),
      no upload in either case; fingerprint and prepare; `UploadConsent.decide` on the snapshot read once right before
      `analyze`, with the request (refusal → `.skipped(.awaitingConsent)`, nothing written); `analyze` with the
      pipeline's `AnalysisContext`, never containing recognized text.
- [ ] Apply to a copy of the row: title, confidence, type, source, description, tags, `key_text`, `date_mentioned`,
      `produced_by`, billed tokens; `processed_at = now`; `status` stays `done`; note gains "analyzed again". Content
      hash changed → update it and set `text_status = pending`; unchanged → leave `text_status` alone.
- [ ] Name: `restored_by_undo` → index only, no rename or move; `title_source == user` → title and name kept,
      `suggestedTitle` returned, not stored; else the pipeline's rule (`renameEnabled`, `minTitleConfidence`, filename
      style, capture date for the prefix); below threshold or unusable → current name and old title kept.
- [ ] Place: the pipeline's move rule with today's settings, including the subfolder rule if 04 has merged (reuse one
      destination helper; see 04's interplay note). Skipped for restored rows. Then organize → undo record right after
      the move → Finder tags and comment → `updatePath` → `save`, with `process`'s failure handling.
- [ ] Failure never makes the row worse: if preparing or analyzing throws, the row is byte-for-byte as before (still
      `done`, still in search) and the error is rethrown for the queue's retry rules. Not saved as `failed`.
- [ ] `ReanalysisOutcome`: `.updated(finalURL:renamed:moved:titleKept:suggestedTitle:)`, `.refused(…)`,
      `.skipped(.awaitingConsent)`; `TitleKeptReason` `.yourName`, `.restoredByUndo`, `.lowConfidence`, `.renameOff`,
      `.unusable`. A "same title as before" result is distinguishable (design §5.3 needs it).
- [ ] Seam 1 tests: `title_source` kept with `suggestedTitle`; "Use This Name" (`rename` with the suggestion, 02's
      parameter) clears the mark; restored rows updated in the index only; low confidence keeps the current name;
      moves to the new type's folder when sorting is on (if 04 merged); failed analysis leaves the row identical;
      missing, excluded and paused refusals with no upload (the stub records nothing); `text_status` reset only on
      content change; the analyzer request carries no recognized text; change feed `.updated` for a re-analysis; the
      rename and move are undoable.
- [ ] Seam 2: `testSwitchingToACloudBackendWhilePreparingDoesNotSendTheFile` repeated for `reanalyze`; a file taken
      before the grant is analyzed only with a request for that target.
- [ ] `scripts/lint.sh` green with no new `lint-allow` (`analyze` stays in `ScreenshotProcessor`, moves in
      `FileOrganizer`); `SCRATCH=.build/linux-<you> scripts/test-linux.sh` green; `docs/core-api.md` and dated wiki line.
- [ ] **Done only when `macos-app` CI is green** on the PR.
- CI snapshots: none. Real-Mac checks: none (core only; 08 covers the live path).
