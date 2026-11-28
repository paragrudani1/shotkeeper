# 08: Analyze Again from the search window (destination already allowed)

**What to build:** with the local model, or a cloud destination the user already allowed, ⇧⌘E or ✦ on the selected
screenshot sends it to the current backend again, ahead of any Process Existing run. The status line and the result
row show "Waiting to analyze…", "Analyzing…" or held (offline, needs attention); on success the old title turns over
into the status line, struck through, and the description, tags, type and source update. A typed name is kept with
"Use This Name"; refusals and failures say why and change nothing. If the panel was hidden, a toast reports the
result. When the destination is *not* allowed, this ticket shows an interim "not available" line; 09 replaces it with
the consent question.

**Blocked by:** 03 (queue kinds and front placement), 06 (`reanalyze`), 07 (title row, status line, ⇧⌘E binding,
`FileActions+Retitle`). Wave 1 panel work is merged via 07.

**Status:** ready-for-agent

**Sources:** spec "Analyse Again: queue", "Consent" (readiness and "the request is issued only if the target is
allowed at the click"), stories 42–45, 47–63, 65, UI surfaces 5, 7, 9, 10, 11; design §2 "The one bold choice",
§5.1 tooltips, §5.3 (every state except asking-for-consent, unavailable and dropped, which are 09), §5.4, §7 "Analyze
Again finished while the panel was hidden", §8, §9, §12 polish departures 6 and 10.

**Test seam:** seam 3, `SearchWindowState` (the Analyze Again state machine for the selected row: idle → queued →
analyzing → held → result or failed, each outcome's message); `ToastTests` for the hidden-panel toasts. The queue and
processor parts are already covered by 03 and 06.

**Likely touches:** core `Search/SearchWindowState.swift` (per-row Analyze Again state, message builder from
`ReanalysisOutcome` and queue status), `Feedback/Toast.swift` (analyzed-again toasts); app
`Coordinator/FileActions+Retitle.swift` (gets the queue: issue `UserUploadRequest` through `BackendGate` /
`UploadConsent.grant(for:in:)`, enqueue `.reanalyze(rowID)` at the front), `Coordinator/AppCoordinator.swift` (the
`.reanalyze` branch of the queue handler, per-row state from queue status), the status-line and title views from 07,
the result row view, `ToastView` if needed, `SearchSnapshots`, `ToastSnapshots`.

- [ ] Readiness: ✦ is enabled only when `BackendGate` says the backend is ready (UI only; `decide` stays the one
      place that decides). Tooltips per design §5.1 with "Analyze": "Analyze this screenshot again (⇧⌘E)", "…Your name
      is kept.", "…on this Mac (⇧⌘E)"; VoiceOver label "Analyze Again" with the destination hint.
- [ ] Press with the destination allowed (or local): a `UserUploadRequest` issued with the current generation, the job
      enqueued at the front; a second press on a queued or running row does nothing (✦ disabled with "Already waiting
      to analyze this screenshot" / "Analyzing this screenshot").
- [ ] Interim (until 09): destination not allowed → the status line "**Analyze Again needs a model:** <gate or consent
      reason>." with Fix Settings… opening Settings › Model (where the existing consent question lives). Nothing is
      queued or sent. 09 replaces this branch.
- [ ] States and copy from design §5.3, spelled American: **Waiting to analyze…**, **Analyzing…** (title dims to 45%),
      held offline / needs attention (with Fix Settings…), Renamed, Renamed and moved ("Analyzed again, now in
      Receipts"), moved with the name kept by rule, same title as before, kept for low confidence / rename off /
      unusable title, **Kept your name** with the suggestion on a second line and **Use This Name**, kept restored name,
      refused excluded (rule's display text, or "one of your exclude rules"), refused paused (`TimeLabel` time),
      refused missing, failed ("**Could not analyze again:** <readable message>. The screenshot is unchanged." with
      Fix Settings… only when it applies).
- [ ] Use This Name calls `rename` with the suggestion (02's parameter): success is the ordinary "✓ Renamed", a clash
      the clash line; the mark goes back to `model`.
- [ ] The turn-over: on a new title the old one moves into the status line at 12 pt, struck through, while the new one
      fades in (300 ms); description, tags, type and source cross-fade. Reduce Motion → cross-fade only.
- [ ] Result rows: `clock` while queued (warning colour when held), spinner while analyzing; VoiceOver appends
      ", waiting to analyze" / ", analyzing".
- [ ] Panel hidden before the result: the design §7 toasts ("Analyzed again", "Analyzed again, now in Receipts",
      Kept your name with Use This Name, kept by rule, and the error toasts "Could not analyze again: …" /
      "Not analyzed: …"), shown even when "Show a toast after each rename" is off. Edit name in that toast uses the
      toast's own editor. Undo via the toast and menu ("Undo: <title>", or "Undo Move: <title>" from 05 for a
      move-only record).
- [ ] VoiceOver announcements from design §9: "Waiting to analyze", "Analyzing", "Analyzed again. Renamed to …",
      "Analyzed again. Kept your name. Suggested name: …", others = the status line's full text.
- [ ] Record the keyboard deviation in the wiki: Use This Name and Fix Settings… have no key (design §9).
- [ ] New CI snapshots, light and dark: `search-analyze-waiting`, `search-analyze-analyzing`, `search-analyze-held`,
      `search-analyze-renamed`, `search-analyze-kept-your-name`, `search-analyze-kept-restored`,
      `search-analyze-excluded`, `search-analyze-paused`, `search-analyze-failed`, `search-row-indicators`,
      `toast-analyzed-again`, `toast-analyzed-kept-your-name`.
- [ ] Real-Mac checks: a live Analyze Again on Clairic and on the local model; it jumps a running Process Existing
      batch; offline hold then resume; the turn-over animation and Reduce Motion; the hidden-panel toast; ⌘Z undo of an
      Analyze Again rename; VoiceOver announcements.
- [ ] Linux tests and `scripts/lint.sh` green; dated wiki lines.
- [ ] **Done only when `macos-app` CI is green** on the PR.
