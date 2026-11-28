# 01: Consent: `UserUploadAuthorization` and CODING_STANDARDS #2

**What to build:** the one consent change for wave 2, with no visible change for the user. The Process Existing
authorization becomes the general "the user asked to send these particular files while that destination was selected
and allowed" authorization, so Analyze Again (06, 08) can use the same rule instead of a second copy. "Process
Existing Screenshots…" behaves exactly as before. CODING_STANDARDS #2 is reworded in this PR, and the old wording is
left nowhere.

**Blocked by:** None (can start immediately). It does not touch the search panel, so it does not wait for wave 1.

**Status:** ready-for-agent

**Sources:** spec "Consent: one generalisation of the Process Existing authorisation" (all of it, including the
CODING_STANDARDS draft), Testing Decisions seam 2; Parag's consent decision quoted at the top of the spec;
`docs/wiki/ui-polish.md` "Consent choke point" and "review 4" (2026-11-22).

**Owns the consent generalization.** No other wave 2 ticket changes `UploadConsent.decide`, the request types or
CODING_STANDARDS #2. Later tickets only *issue* a `UserUploadRequest`.

**Test seam:** seam 2, `UploadConsent.decide`, pure (prior art `UploadConsentTests`). Process Existing behavior is
also covered by the existing `ScreenshotProcessorTests` and `ProcessingQueueTests`, which must pass after the rename
with no change other than the names.

**Likely touches:** core `Setup/UploadConsent.swift`, `Pipeline/ScreenshotProcessor.swift` (parameter names,
`SkipReason.awaitingConsent` comment), `Queue/ProcessingQueue.swift` (`enqueue(_:processExisting:)` →
`userRequest:`), their tests; app `Coordinator/FolderCapture.swift`, `AppCoordinator.swift`, and any other call site
(`git grep ProcessExisting`); `CODING_STANDARDS.md`; `docs/core-api.md`; `docs/wiki/ui-polish.md`. Hotspot:
`ProcessingQueue` (03 builds on this rename, so 03 waits for it).

- [ ] Rename, don't add: `ProcessExistingAuthorization` → `UserUploadAuthorization(target:)`,
      `ProcessExistingRequest` → `UserUploadRequest`, `ProcessExistingRequests` → `UserUploadRequests`, every
      `processExisting:` parameter → `userRequest:`. The generation stamp, `invalidateAll()` on any backend, endpoint
      or grant change, and `authorization(for:)` keep their behavior. No reason field and no second kind: `decide`
      must not branch on why the user asked.
- [ ] `UploadConsent.decide(target:grants:capturedAt:userRequest:)` keeps the rule: `.thisMac` → allow; no grant
      covers the target → `.skip(.destinationNotAllowed)` (a user request never lifts this); taken at or after the
      grant → allow; else a user request for this very target → allow; else `.skip(.takenBeforeGrant)`.
- [ ] Every existing `UploadConsentTests` case passes under the new names (renamed tests keep their meaning, e.g.
      `testProcessExistingLiftsOnlyTheTimeRuleForItsOwnTarget` → `testAUserRequestLiftsOnlyTheTimeRuleForItsOwnTarget`).
- [ ] New cases: a user request never lifts `destinationNotAllowed`; a request for another target doesn't count; an
      invalidated request counts as none (through `UserUploadRequests`); a file taken before the grant is allowed only
      with the request.
- [ ] The user-facing command keeps its name, "Process Existing Screenshots…". Only type and parameter names change.
- [ ] CODING_STANDARDS #2 replaced with the spec's draft, in American spelling and with "Analyze Again":
      "…or the user asked to send that image while that destination was selected and allowed (a
      `UserUploadAuthorization`: "Process Existing Screenshots…", "Analyze Again")…". `git grep -n ProcessExisting`
      over `Sources App Tests CODING_STANDARDS.md docs/core-api.md` finds nothing afterwards.
- [ ] `UploadConsent`'s doc comments and `docs/core-api.md` updated. A dated line in `docs/wiki/ui-polish.md` under the
      consent sections says the Process Existing entries are superseded by name only; old entries stay as the record.
- [ ] Dated line in `docs/wiki/subfolders-and-retitle.md` (create the page and its `index.md` line if this is the
      first wave 2 ticket to merge).
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` green.
- [ ] **Done only when `macos-app` CI is green** on the PR (the app call sites compile only there).
- CI snapshots: none new; all existing names unchanged.
- Real-Mac checks: "Process Existing Screenshots…" on a cloud backend still asks nothing extra and still sends files
  taken before the grant (smoke test, no new UI).
