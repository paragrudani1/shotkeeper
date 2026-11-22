# OpenRouter backend (Inkling 2 Mini through OpenRouter)

Branch `t3/openrouter-inkling`. Commits: `1ca0d2a` (research), `71a97b5` (core, CLI, fixtures, tests), `8bbabe5`
(app, snapshots, README). Facts and sources: [../research/openrouter.md](../research/openrouter.md) (read 2026-11-22).

## Decisions
- 2026-11-22 (`71a97b5`): **one shared client.** `LocalOpenAICompatibleAnalyzer` became `OpenAICompatibleAnalyzer`
  with an `OpenAICompatibleProfile` per backend. `.localServer` is the old behaviour unchanged (image first,
  `reasoning_effort` + `chat_template_kwargs`, drop the extras once after a 400 that names them, fixed 1.0 / 0.6
  confidence, no billed tokens). `OpenRouterBackend.profile` sets headers, extras, text-first order, accepted image
  types, logprob confidence, title rules, billed tokens and the OpenRouter error dialect. No copy of the request,
  parse or repair code. `HTTPErrorMapping.send` gained a `refine` hook for statuses a backend's docs redefine.
- 2026-11-22 (`71a97b5`): **request.** `POST https://openrouter.ai/api/v1/chat/completions`, model
  `thinkingmachines/inkling-2-mini` (Settings → Model → Advanced can change it; empty = default), `temperature: 0`,
  `max_tokens: 800`, `stream: false`, `response_format` json_schema (the same strict schema as the local backend),
  `reasoning: {"effort": "none"}`, `logprobs: true`, and
  `provider: {"data_collection": "deny", "zdr": true, "require_parameters": true}`. Headers: `HTTP-Referer:
  https://github.com/paragrudani1/shotkeeper`, `X-Title: Shotkeeper` and `X-OpenRouter-Title: Shotkeeper` (the
  current name of `X-Title`; the brief asked for `X-Title`, both are sent). User content is text first, then the image
  (OpenRouter's advice). Images keep the app's downscale (1280 px long side); PNG/JPEG/WebP/GIF only, else refused
  before sending.
  - `max_tokens`, not `max_completion_tokens`: io.net does not list the latter, and `require_parameters` would then
    route everything to Prime Intellect.
  - `require_parameters: true` keeps a provider that would silently ignore `reasoning` (and think at the default
    "high" effort, billed) or `response_format` from serving the request. Both providers list every parameter sent.
  - **Privacy options turned on: `zdr: true` and `data_collection: "deny"`.** Both Inkling 2 Mini endpoints are in
    the public ZDR list with `safety_retention: false`, and the model page's data policy for both says no training,
    no prompt retention, so both stay eligible. If none qualified, OpenRouter returns an error rather than routing
    elsewhere (documented).
  - No 400 fallback for OpenRouter: its parameters are documented, so a 400 is a real error.
- 2026-11-22 (`71a97b5`): **title confidence.** Both providers list `logprobs`, so the title's confidence is
  `exp(mean logprob)` over the tokens that carry the top-level `title` string value (`TitleTokenConfidence`), the same
  per-token scale as Clairic's `exp(log_probability / tokens)`. Without logprobs in the reply it falls back to 1.0
  (parsed) / 0.6 (truncated or repaired), like the local backend. On top, `TitleRules` (core, tested): 3+ letters or
  digits, at most 12 words / 120 characters, usable after `FilenameSanitizer`, not generic (`genericWords`), not only
  digits or a date (incl. month/weekday names: "Nov 22, 2026"), not mostly the app/site name (more than half the
  words are the `source_app_or_site` words, site noise like "com" or generic words). A failure drops the title
  ("kept name: no title"); the other fields are still indexed. Only the OpenRouter profile applies the rules.
  *Revised by the review fixes below (S5 and nits): fallback 0.7, app-name rule, CJK/Cyrillic, UI nouns, bytes.*
- 2026-11-22 (`71a97b5`): **errors** (`OpenRouterBackend.refineError`, documented codes): 402 with
  `limit_source: openrouter_in_flight_budget` → `rateLimited(Retry-After)`; any other 402 → `badRequest(402)`,
  not retried, text "the model backend is out of credits (HTTP 402). Add credits, then try again" (Test Connection:
  "OpenRouter is out of credits. Add credits at openrouter.ai/settings/credits, then try again."); 403 with
  `error_type` `content_policy_violation`/`refusal` → `badRequest(403)` (one file fails, the queue is not held);
  other 401/403 → `unauthorized` (holds the queue); 429 → `rateLimited`; 408/5xx → `serverError`. An error inside a
  200 body (top-level `error` without `choices`, or `choices[0].error`) is mapped by its `code` the same way.
  Messages come from `error.message` (+ `error_type`); `UserFacingError` never shows them.
  - Consequence: running out of credits fails each new screenshot (toast each time) instead of holding the queue.
    *Superseded by S4 below: it holds the queue.*
- 2026-11-22 (`71a97b5`): **consent.** OpenRouter is its own `UploadDestination` and `UploadTarget` (`.openRouter`,
  host `openrouter.ai`). `UploadConsent.decide` and `grant(for:in:)` gained one case each; there is no other copy of
  the rule. *S1 below adds the model to the identity.* Cloudflare or a custom endpoint grant does not cover it, nor does an OpenRouter grant cover a custom
  endpoint at openrouter.ai. Migration: `migrateLegacyConsent` only ever creates a Cloudflare grant, so old settings
  never grant OpenRouter (tested). `BackendGate.readiness` takes `hasOpenRouterKey` (default false: a caller that does
  not pass it never makes OpenRouter ready). Settings prompt: "Screenshots will be sent to OpenRouter, then to Prime
  Intellect or io.net".
  - Downgrade note: an older build cannot decode a grant list that contains `openRouter`, so it falls back to no
    grants (fails closed; a Clairic user is asked again after downgrading).
- 2026-11-22 (`71a97b5`): **price.** `OpenRouterPricing.measuredUSDPerThousandScreenshots` is nil: the docs give
  token prices ($0.075 / $0.30 per M at Prime Intellect, $0.08 / $0.35 at io.net) but not the image's token cost, so
  no estimate is shown anywhere. While nil, the setup card and Settings show no price line. The live test sets it
  from `usage.cost`. `PriceText.perThousandScreenshots` is now the one wording for Clairic and OpenRouter.
- 2026-11-22 (`8bbabe5`): **setup.** Third card "OpenRouter · Inkling 2 Mini" (no badge; never recommended), order
  Clairic, OpenRouter, Local (+ Custom on a re-run; four cards wrap into two rows of two, card titles may wrap). The
  section has the key field, the privacy text naming Prime Intellect and io.net with links to OpenRouter's privacy
  policy and provider data policies, a checkbox and Test Connection. Continue saves the key to the Keychain, selects
  OpenRouter and grants `.openRouter` only when step 2's "I Agree" was pressed in this run, like Clairic.
  - **Deviation from "granted the same way Cloudflare is":** Continue also needs step 3's checkbox "I understand that
    my screenshots are sent to OpenRouter and then to Prime Intellect or io.net." Step 2's wording is the spec's and
    names Cloudflare only, so it is not informed consent for a third party. Step 2 is unchanged.
    *Superseded by S2/S3 below: one "Agree and Continue" button, no checkbox, no dependence on step 2.*
- 2026-11-22 (`8bbabe5`): **Settings → Model.** Segments "Clairic / OpenRouter / Local / Custom". The key field is the
  same `SecretField` as the Clairic token (saved 1 s after typing, used only on commit; B1 in
  [ui-polish](ui-polish.md)), with "Get a key" / "Add credits" links, the price line only once measured, an
  "Advanced" disclosure with the model ID, Test Connection, and a Privacy section with the three policy links. The
  consent row and dialog are the existing ones.
- 2026-11-22 (`71a97b5`): **CLI.** `shotkeeper-cli analyze <image> --backend openrouter [--model …] [--raw <path>]`
  reads `OPENROUTER_API_KEY`, prints latency, per-call and total prompt/completion/reasoning tokens and `usage.cost`,
  `finish_reason`, the number of logprob tokens, the title rules' verdict, the fields, and the filename the app would
  give with default settings (0.5 threshold, sentence case). `--raw` saves the completion (all completions when a
  repair call was made) with every configured secret scrubbed. `scripts/test-linux.sh` passes `OPENROUTER_API_KEY`.

## Snapshot review (run 44996255459, head `c4da140`: green, linux-core + macos-app)
- 2026-11-22: checked light and dark: `setup-3-openrouter`, `-ready` (checkbox ticked, "Connected", Continue is the
  default), `-out-of-credits` (red 402 text), `-8gb`, `setup-3-custom-rerun` (four cards in two rows),
  `settings-model-openrouter-consent` (orange row "Screenshots will be sent to OpenRouter, then to Prime Intellect or
  io.net" + Allow…, Advanced closed), `settings-model-openrouter` (Advanced open with the model placeholder). The four
  segments fit. No price line anywhere. With three cards in a row (every first run now), the card titles and
  subtitles wrap ("Inkling 2 Mini, on / this Mac"); this changes the look of the existing Clairic and local step 3
  snapshots too. Commit `c4da140` only fixed an argument order in the snapshot catalog (run 44996008629 failed to
  compile the test target).

## Review fixes (review of `6ac2a57`, no blockers; Parag's orchestrator picked the options)
- 2026-11-22 (S1): **consent matches where screenshots go.**
  - For the default model the request carries `provider.only: ["primeintellect", "io-net"]` (base slugs from the
    live endpoints API tags `primeintellect/fp4`, `io-net/nvfp4`; research note, "Pinning the providers"), so the
    two providers the consent names are the only ones allowed. Another model gets no `only`.
  - The grant identity includes the model: `UploadTarget.openRouter(model:)`, `UploadGrant.openRouterModel`,
    `OpenRouterBackend.effectiveModel` (trimmed, empty = default). The rule stays in `UploadConsent.decide` /
    `grant(for:in:)` only. Another model needs its own "Allow…", worded "Screenshots will be sent to OpenRouter,
    then to the provider that serves <model>". `BackendGate.granting(.openRouter, expectedOpenRouterModel:)` grants
    only the model the dialog named.
  - OpenRouter keeps **one grant per model** (other destinations keep one), so switching back to the default model
    reuses its original grant time. A model change counts as a destination change (Process Existing requests are
    invalidated).
  - Tests: `UploadConsentTests.testAnOpenRouterGrantCoversOnlyItsModel` (model change, every typed prefix, back to
    the default), app `testAModelNameIsUsedOnlyOnCommit`.
- 2026-11-22 (S2, S3): **setup grants OpenRouter from its own action.** Step 3's checkbox is gone; with a key the
  footer's default button reads **"Agree and Continue"** (Return presses it). The section above it says
  "“Agree and Continue” allows Shotkeeper to send each new screenshot to OpenRouter, then to Prime Intellect or
  io.net." (or "…the provider that serves <model>"), and the button's tooltip and VoiceOver hint say the same.
  `saveOpenRouterSetup(key:)` grants for the configured model from this action alone; step 2's "I Agree" plays no
  part for OpenRouter.
  - **Deviation:** step 2 stays as the spec wrote it ("Your screenshots go to your Cloudflare account", Cloudflare
    checkbox), although a user who then picks OpenRouter has read Cloudflare wording there. The OpenRouter consent is
    step 3's button, whose own text names OpenRouter and the providers.
- 2026-11-22 (S4): **account states hold the queue.** New `AnalyzerError.accountState(String)` (not retryable; the
  queue holds in "Needs attention" like `unauthorized` until Resume; the text is Shotkeeper's own):
  - 402 without `Retry-After` → "OpenRouter is out of credits. Add credits, then choose Resume." 402 with
    `Retry-After` (in-flight budget) stays `rateLimited`.
  - 403 with `metadata.limit_source` → "Your OpenRouter key reached its spending limit. Raise the limit on
    openrouter.ai or wait until it resets, then choose Resume."
  - 404 (not `image_not_found`) → "OpenRouter has no provider for this model that Shotkeeper may use. Check the model
    in Settings → Model, then choose Resume." 503 without `provider_overloaded` → "No OpenRouter provider for this
    model meets Shotkeeper's privacy settings right now. Choose Resume to try again." (The exact 404 message is
    unverified; the research note says so.)
  - The toast and Test Connection show the same sentence. Tests: `ProcessingQueueTests.testAccountStateHoldsUntilResume`,
    `OpenRouterAnalyzerTests` (402 both ways, 403 budget, 404, 503 both ways).
- 2026-11-22 (S5): **app-name rule** rejects only a title with no informative word besides the app/site name (and
  site noise or generic words): "Google Chrome" fails; "Google Chrome settings", "Visual Studio Code build error",
  "App Store listing" pass.
- 2026-11-22 (nits):
  - With the logprobs profile and no logprobs in the reply, a parsed title is 0.7 (`unmeasuredConfidence`); repaired
    stays 0.6.
  - Title rules: CJK/Korean (年月日, 년월일, weekday characters) and Russian (month/weekday names, "г.") date-only titles
    fail; CJK ideographs, kana and Hangul count 2 toward the 3-character minimum ("設定" passes, "設" does not); a
    single UI noun as the whole title ("Settings", "Error", "Dashboard", "Page", "Login"…) is generic.
  - Logprob matching rebuilds the text from each token's `bytes` when present and weights a token that straddles the
    value's edge by the share of its bytes inside it.
  - Arrow keys on the cards follow core's grid (`SetupCards.columns`, `SetupFlow.choose(moving:)`): in two rows of
    two, ←/→ move within the row and ↑/↓ between rows, wrapping and skipping unavailable cards; in one row all four
    step through it.
  - The OpenRouter model field and the custom endpoint's model name field (`ModelNameField`) are used only on commit
    (Return, focus leaving, the field going away; closing Settings and quitting via `commitAllSecretDrafts`), like
    secrets: no rebuild per keystroke (`AppCoordinator.commitModelNameDraft`). Before, the custom model name saved
    on every keystroke.
  - CLI: the failure line goes through `scrub`. Test renamed to `testErrorMessageIsTheErrorMessageOrElseTheBodyPrefix`.
    Fixtures README lists the `openrouter-*.json` files (the earlier edit had not applied) and the new test name.
- 2026-11-22: **what changed for the local / custom backend** with the shared client (`71a97b5`), recorded here:
  the missing-model error reads "No model name configured" (was "No local model name configured"); `invalidResponse`
  texts say "Local server …"; a 2xx body carrying an `error` object (top level without `choices`, or
  `choices[0].error`) is now mapped by its `code` like an HTTP status instead of "no choices[0].message"; request,
  parse, repair and the 400 fallback are unchanged (all `OpenAICompatibleAnalyzerTests` pass unchanged).
- 2026-11-22: **re-review fixes** (review of `36b6667`, no blockers):
  - 404/503 hold the queue only for OpenRouter's own routing answer: the HTTP status itself, an OpenRouter `error`
    body, no `Retry-After`. An HTML edge page, a 503 with `Retry-After` and a 404/503 embedded in a 200 (a provider
    failing mid-generation) are retried again, as before S4 (`refineError(embedded:)`).
  - A 402 without `Retry-After` always holds, including `openrouter_in_flight_budget` (the docs: "not a wait-and-retry
    case"); `openrouter_key_limit` shows the spending-limit text instead of "out of credits".
  - The privacy text in setup and Settings names the providers of the configured model (`destinationPhrase`): Prime
    Intellect or io.net only for the default model, "the provider that serves <model>" otherwise.
  - Setup's "Agree and Continue" grants the model step 3 named (`saveOpenRouterSetup(key:model:)`); if the
    configured model changed in between, nothing is granted and Settings asks.
  - A model name field that only loaded its text is not a draft, so closing Settings never writes an old name back.
    Test Connection tests the model name on screen (draft or setting); it still saves and grants nothing.

## Live test
- 2026-11-22: **skipped**: `OPENROUTER_API_KEY` is not in `.env.local` (names checked only) nor in the environment.
  Fixtures are doc-based (`Tests/ShotkeeperCoreTests/Fixtures/README.md`). To run it: add the key to `.env.local`,
  then for each of `live-samples/{tweet,code,receipt}.png`:
  `SHOTKEEPER_DOCKER_NETWORK=bridge scripts/test-linux.sh run shotkeeper-cli analyze <png> --backend openrouter --raw
  Tests/ShotkeeperCoreTests/Fixtures/openrouter-live-<date>-<sample>.json` (with the key exported from `.env.local`),
  grep the saved files for the key, and set `OpenRouterPricing.measuredUSDPerThousandScreenshots` from the measured
  cost of the 1280×800 tweet × 1,000. Check `reasoning_tokens` is 0 and `logprob_tokens` is not "none".

## Open questions
- 2026-11-22: does `effort: "none"` really skip reasoning at both providers, and do they return logprobs? (Live test.)
- 2026-11-22: hold the queue on "out of credits" instead of failing each file? Answered by the review: it holds (S4).
- 2026-11-22: make OpenRouter the default or recommended backend? (Parag, after the live test.)
