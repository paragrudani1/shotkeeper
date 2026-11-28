# Shotkeeper wiki

Historical record of decisions and lessons. Every claim is dated; claims about code cite a commit.
Lives at `docs/wiki/`, following the convention the user agreed for team-pulse on 2026-10-27 (adopted here 2026-11-21).

## Decisions
- [model-backend](model-backend.md): which model backend is primary, and how it changed during 2026-11-21.
- [architecture](architecture.md): core/app split, seams, and why (2026-11-21).
- [clairic-field-schema](clairic-field-schema.md): Clairic fields, pass/cost trade-offs, per-screenshot cost, `maxImageLongSide` (2026-11-21); live-call measurements and the switch to scalar fields (2026-11-21).
- [core-implementation](core-implementation.md): files/index/queue/pipeline/runtime choices, 3-bit catalog, open mlx-vlm question (2026-11-21).
- [app-implementation](app-implementation.md): macOS app phase 2: coordinator, settings file, analyzer selection, local runtime, pause, search; what needs a real Mac (2026-11-21).
- [openrouter-backend](openrouter-backend.md): Inkling 2 Mini through OpenRouter: shared OpenAI-compatible client,
  request options (reasoning off, json_schema, logprobs, zdr + data_collection deny), title confidence and rules,
  errors, consent as its own destination, setup checkbox, price hidden until measured (2026-11-22); review fixes:
  consent per model + `provider.only`, "Agree and Continue", account states hold the queue (2026-11-22).
- [prefactor-index](prefactor-index.md): index column table (one place per column, explicit migration versions, frozen
  295df83 schema test), `changes()` feed, settings every-property round-trip, `IndexedScreenshot.testRow` (2026-11-28).
- [search-filters-and-text](search-filters-and-text.md): wave 1 (search filters, recognized text): ticket 01's one
  index migration (3) for the text columns, FTS rebuild and filter indexes, a deviation from the spec's two;
  `ftsColumns` and weights; the conditional text write. Ticket 02's date filter: core `DateFilter`, picker state in
  core, Esc order, newest-taken order with a date, no-match buttons, the `screenshots_taken_at` query plan, one clock
  and calendar for index and panel, real-Mac checks (2026-11-28).
- [subfolders-and-retitle](subfolders-and-retitle.md): wave 2 (subfolders, Edit name, Analyze Again): consent
  generalized as `UserUploadAuthorization`, CODING_STANDARDS #2 reworded; index migration 4 `title_source` with the
  note backfill, `rename(_:to:asSuggestedTitle:)` (2026-11-28).
- [ui-polish](ui-polish.md): UI polish PRs (spec `../specs/ui-polish-2026-11.md`): toast batching, restored-by-undo rule, status item menu, focus, deviations; PR 2 search window rules, Quick Look, batch view; PR 3 setup steps, consent and watch gate, computed Clairic cost, icon geometry (2026-11-21); the consent choke point `UploadConsent.decide` (2026-11-22); PR 4 Settings scene, shortcut recorder, filename style, contrast; app icon: one geometry source, SVG + asset catalog + Icon Composer `.icon` (shipped on every macOS, Parag's decision), glyph stays code-drawn (2026-11-22).

- [prefactor-app](prefactor-app.md): app prefactor before the eight features: `AppCoordinator` parts (`FolderCapture`, `FileActions`), search-panel action set, search key table in core (`SearchKeyMap`), shared app test harness and row builder, snapshots per screen, `scripts/lint.sh` in CI (2026-11-28).

## Standards
- [../../CODING_STANDARDS.md](../../CODING_STANDARDS.md): review checklist (2026-11-21).

## Process
- [roadmap-survey](roadmap-survey.md): code state at `295df83` for the eight approved features, hotspots, prefactors, waves (2026-11-28).
- [workflow](workflow.md): specs stay in `docs/specs/` (2026-11-28); weekly wiki lint on Gemini 4 Hydrogen (2026-11-28).

## Environment
- [environment](environment.md): Linux build box, Docker Swift image, disk limits, credentials (2026-11-21).
- [macos-ci](macos-ci.md): GitHub Actions for the macOS app: Xcode selection, signing, artifact, UI snapshot PNGs, gotchas (2026-11-21).
- [appkit-gotchas](appkit-gotchas.md): panel, keyboard, Quick Look, pasteboard and drag bugs CI cannot catch; read before AppKit UI work (2026-11-21).

## Research
- [../research/model-backends.md](../research/model-backends.md): Clairic REST schema and Inkling 2 Mini facts with sources.
- [../research/icon-composer.md](../research/icon-composer.md): Icon Composer `.icon` layout, `icon.json` keys (from Apple's Landmarks sample), which icon wins, actool facts (2026-11-22).
- [../research/openai-compatible-chat.md](../research/openai-compatible-chat.md): local server request shape (llama-server, mlx_lm.server, structured outputs).
- [../research/spotlight-shortcuts-ocr.md](../research/spotlight-shortcuts-ocr.md): App Intents by OS version, Core Spotlight and signing, Live Text in plain Spotlight, Vision OCR (2026-11-28).
- [../research/capture-types.md](../research/capture-types.md): screen recordings (naming, finishing, frames, cost) and clipboard screenshots (pasteboard, privacy alert from macOS 27.2) (2026-11-28).
- [../research/auto-update.md](../research/auto-update.md): Sparkle 2 on an ad-hoc build: EdDSA-only trust, keychain and privacy prompts after each update, quarantine, self-signed option, release flow (2026-11-28).
- [../research/openrouter.md](../research/openrouter.md): OpenRouter + Inkling 2 Mini: parameters per provider, reasoning switch, logprobs, headers, usage/cost, privacy routing, errors (2026-11-22).
- [../research/vision-ocr-settings.md](../research/vision-ocr-settings.md): Vision OCR settings sweep for ticket 04: `scripts/measure-vision.swift` (macOS only, type-checked and sample-run in `macos-app` CI), how Parag runs it; results pending (2026-11-28).

## Code map
- [../core-api.md](../core-api.md): public core types and how the macOS app wires them.
