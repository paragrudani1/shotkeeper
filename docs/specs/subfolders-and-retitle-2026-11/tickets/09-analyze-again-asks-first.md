# 09: Analyze Again asks first (consent card, unavailable and dropped states)

**What to build:** when the current destination isn't allowed, ⇧⌘E or ✦ opens a card over the preview with the same
question Settings asks ("Screenshots will be sent to your Cloudflare account.") and what happens to this screenshot.
**Allow** grants the destination for good through the existing path and the analysis starts; **Cancel** sends
nothing. The panel never activates Shotkeeper. If the settings change while the card is open or while the job waits,
nothing is sent and the line says "The destination changed. Analyze again." A backend that isn't ready, or an
unidentified custom endpoint, gives a disabled ✦ that still explains itself on click or ⇧⌘E.

**Blocked by:** 08 (replaces its interim "not allowed" branch; same status line and Analyze Again state machine).

**Status:** ready-for-agent

**Sources:** Parag's consent decision (top of the spec); spec "Consent" ("Otherwise it asks first", readiness,
`unidentifiedEndpoint`), stories 46–48, UI surface 6; design §5.3 rows "Asking for consent", "Request dropped", "Not
available", "Not available, unidentified endpoint"; §6 (choice, layout, copy, closing rules); §9 (consent card column,
Esc order, focus); §12 spec departures 1–2.

**Test seam:** seam 3, `SearchWindowState` (asking state; Esc order card → editor → picker → clear → close; ↩ = Allow
while the card is open; typing ignored; selection change or hide closes as Cancel; Allow after a settings change grants
nothing and yields "dropped"); seam 2 via 01/06's tests (an invalidated request counts as none) — add a case only if
a new path appears.

**Likely touches:** core `Search/SearchWindowState.swift`; app `Coordinator/FileActions+Retitle.swift` (capture the
`ConsentRequest` at the press via `BackendGate.consentPrompt`; grant through the existing granting path; then issue
the request with the new generation), a new consent card view file, `Platform/SearchPanel.swift` (route ↩ / Esc to
the card without moving focus), `SearchSnapshots`.

- [ ] Destination has no grant at the press → the card, showing the `ConsentRequest` captured then. Title: the exact
      `ConsentRequest.prompt` plus a period, as in Settings. Message (American spelling): "Allow it to analyze this
      screenshot now. Shotkeeper then also sends each new screenshot there to name it. Older screenshots are sent only
      when you ask." Buttons Cancel and **Allow** (brand primary). `hand.raised.fill` in orange.
- [ ] Allow → grant (grant time now, so it also covers future screenshots, exactly as Settings) → request issued →
      status line goes straight to Waiting / Analyzing. Cancel, Esc, a click outside, a selection change or hiding the
      panel → nothing sent and no status line.
- [ ] Settings change while the card is open → Allow grants nothing; status line "**The destination changed. Analyze
      again.**" Same line when a queued job's request is invalidated (`invalidateAll()`) and `decide` skips it.
- [ ] Unavailable: backend not ready → ✦ disabled, tooltip with the gate reason; click or ⇧⌘E beeps (⇧⌘E) and shows
      "**Analyze Again needs a model:** <gate reason>." with Fix Settings…. Unidentified endpoint → "**Analyze Again is
      off:** the custom endpoint's address is incomplete, so it can't be allowed. Check the URL in Settings › Model."
      No index → disabled with its reason.
- [ ] Focus: the card never takes key status; the search field keeps focus; ↩ / Esc reach the card; typing goes
      nowhere while it is open. Full Keyboard Access: Cancel → Allow.
- [ ] VoiceOver: "Screenshots will be sent to <destination>. Allow or Cancel." when the card opens.
- [ ] Remove 08's interim branch; no path sends without `decide` (CODING_STANDARDS #2 as reworded by 01).
- [ ] New CI snapshots, light and dark: `search-consent` (one per destination kind is not required; Cloudflare plus a
      custom endpoint is enough), `search-analyze-dropped`, `search-analyze-unavailable`.
- [ ] Real-Mac checks: the card never activates Shotkeeper (the frontmost app stays frontmost) and the panel doesn't
      hide; ↩ and Esc reach it; Allow then a live analysis on a fresh Cloudflare grant; switching backend in Settings
      while a job waits gives "The destination changed"; VoiceOver.
- [ ] Linux tests and `scripts/lint.sh` green; dated wiki line (including spec departures 1–2 as implemented).
- [ ] **Done only when `macos-app` CI is green** on the PR.
