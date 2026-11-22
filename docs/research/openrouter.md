# OpenRouter + Inkling 2 Mini: research notes (gathered 2026-11-22)

Used by the `.openRouter` backend (`OpenRouterBackend` + the shared `OpenAICompatibleAnalyzer`). Every fact has a
source and an access date. All URLs were read on **2026-11-22 (06:20–07:40 UTC)** unless a line says otherwise.
Docs pages were read as Markdown (`<page>.md`, the form OpenRouter's `llms.txt` index links to).

Raw API snapshots saved beside this file (trimmed to this model), read without a key:
- `openrouter/model-inkling-2-mini-2026-11-22.json`: the model's entry in `GET https://openrouter.ai/api/v1/models`.
- `openrouter/endpoints-inkling-2-mini-2026-11-22.json`: `GET https://openrouter.ai/api/v1/models/thinkingmachines/inkling-2-mini/endpoints`.
- `openrouter/zdr-endpoints-inkling-2-mini-2026-11-22.json`: this model's entries in `GET https://openrouter.ai/api/v1/endpoints/zdr`.
- `openrouter/providers-2026-11-22.json`: the two providers in `GET https://openrouter.ai/api/v1/providers`.
- `openrouter/model-page-data-policy-2026-11-22.json`: the `dataPolicy` objects embedded in the model page
  https://openrouter.ai/thinkingmachines/inkling-2-mini.

## The orchestrator's unverified facts, checked

| Claim | Verdict | Source |
|---|---|---|
| Model ID `thinkingmachines/inkling-2-mini`, canonical `thinkingmachines/inkling-2-mini-20261120` | **True** (`id`, `canonical_slug`) | models snapshot |
| Text and image input | **True**: `input_modalities: ["text","image"]`, output text only | models snapshot |
| Served by Prime Intellect and io.net | **True**: two endpoints, `PrimeIntellect` (tag `primeintellect/fp4`, fp4) and `Io Net` (tag `io-net/nvfp4`, nvfp4) | endpoints snapshot |
| ~$0.08–0.10 /M input, ~$0.35–0.40 /M output | **Partly wrong.** Prime Intellect **$0.075 /M input, $0.30 /M output** (cache read $0.015 /M); io.net **$0.08 /M input, $0.35 /M output** (cache read $0.016 /M). The model-level `pricing` is the cheaper one (Prime Intellect). No image or per-request price is listed. | endpoints snapshot (`pricing.prompt` / `completion` are USD per token) |
| Reasoning ON by default | **True**: `reasoning.default_enabled: true`, `default_effort: "high"`, `mandatory: false`, `supported_efforts: [max, high, medium, low, minimal, none]` | models snapshot |
| Endpoint `https://openrouter.ai/api/v1/chat/completions` | **True** (server `https://openrouter.ai/api/v1` + `POST /chat/completions`; the model lists `/api/v1/chat/completions` among its `endpoints`) | https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion.md, models snapshot |

Credits are US dollars: "OpenRouter uses a credit system where the base currency is US dollars. All of the pricing on
our site and API is denoted in dollars." (https://openrouter.ai/docs/faq.md).

Other model facts (models + endpoints snapshots): context 1,048,576 tokens at Prime Intellect and 262,144 at io.net;
`max_completion_tokens` 65,536 at both; both `status: 0`, uptime last day 99.6% / 99.8%.

## Supported parameters per provider

From the endpoints snapshot (`supported_parameters`):

| Parameter | Prime Intellect | io.net |
|---|---|---|
| `response_format`, `structured_outputs` | yes | yes |
| `reasoning`, `reasoning_effort`, `include_reasoning` | yes | yes |
| `logprobs`, `top_logprobs` | yes | yes |
| `temperature`, `seed`, `stop`, `top_p`, `top_k` | yes | yes |
| `max_tokens` | yes | yes |
| `max_completion_tokens` | yes | **no** |
| `min_p` | yes | no |
| `tools` / `tool_choice` | yes (all modes) | yes (`required`/`function` no) |

Consequence for Shotkeeper: send `max_tokens`, not `max_completion_tokens`. The API reference marks `max_tokens` as
"deprecated, use max_completion_tokens", but with `provider.require_parameters: true` (below) a request carrying
`max_completion_tokens` would exclude io.net.

**Image input format and size limits.** Chat Completions takes an image as a content part
`{"type": "image_url", "image_url": {"url": ..., "detail": ...}}`; `url` is a "URL of the image (data: URLs
supported)" (API reference, `ChatContentImage`). Supported types: `image/png`, `image/jpeg`, `image/webp`,
`image/gif` (https://openrouter.ai/docs/guides/overview/multimodal/image-understanding.md). That page also says: "we
recommend sending the text prompt first, then the images", and "system messages should contain text only". **Size
limits: the docs are silent.** "The number of images you can send in a single request varies per provider and per
model"; the error list has `image_too_large` ("exceeds the provider's maximum file size or pixel dimensions") without
numbers (https://openrouter.ai/docs/api_reference/errors-and-debugging.md). Neither endpoint lists an image limit.
How many prompt tokens one image costs for this model is not documented either; only a live call can tell.

## Disabling reasoning

https://openrouter.ai/docs/guides/best-practices/reasoning-tokens.md:
- The `reasoning` object takes "one of the following (not both)": `effort` ("max", "xhigh", "high", "medium",
  "low", "minimal" or "none") or `max_tokens`; or `enabled: true` for defaults. "`"effort": "none"` - Disables
  reasoning entirely."
- `exclude: true`: "The model will still use reasoning, but it won't be returned in the response. The tokens are
  still billed". So `exclude` does **not** turn reasoning off.
- Per-model options come from `GET /api/v1/models` → `reasoning`: "`mandatory`: When `true`, hide disable controls
  and do not send `effort: "none"` — the model rejects it." For this model `mandatory` is false and `none` is in
  `supported_efforts` (models snapshot), so **`reasoning: {"effort": "none"}` is the documented switch this model
  honours.**
- `reasoning: {enabled: false}` appears only as the unified equivalent of Anthropic's `thinking: {type: "disabled"}`
  (same page, "Reasoning with the Anthropic Messages API"); the API reference describes `enabled` only as "Enables
  reasoning with default settings. Defaults to being inferred from `effort` or `max_tokens`". Not used.
- The top-level `reasoning_effort` is a shorthand that "Cannot be used simultaneously with reasoning.effort if they
  differ" (API reference). Not sent.
- Reasoning tokens are output tokens, billed, and count against `max_tokens`; when the budget goes to reasoning the
  response is `finish_reason: "length"` with empty `content` (reasoning-tokens page). Detect via
  `usage.completion_tokens_details.reasoning_tokens`.
- Unverified until a live call: that both providers really skip thinking with `effort: "none"`. Check
  `reasoning_tokens` = 0 (or absent) in the live usage.

## Structured output

https://openrouter.ai/docs/guides/features/structured-outputs.md: Chat Completions takes
`response_format: {"type": "json_schema", "json_schema": {"name", "strict", "schema"}}` (the OpenAI shape, same as
`openai-compatible-chat.md`). "Support is determined per endpoint"; to route only to supporting endpoints, "Set
`require_parameters: true` in your provider preferences". "Use strict mode … Enforcement varies by provider: some
guarantee schema-conforming output, while others … treat it as a strong hint, so exact compliance is not guaranteed
on every endpoint." Both endpoints list `structured_outputs` and `response_format`. `json_schema.name`: "a-z, A-Z,
0-9, underscores, dashes, max 64 chars" (API reference, `ChatJsonSchemaConfig`). Shotkeeper keeps its tolerant parse
and one repair round because compliance is not guaranteed.

Provider routing (https://openrouter.ai/docs/guides/routing/provider-selection.md, "Default parameter preferences"):
even without `require_parameters`, `response_format` is a soft preference; other parameters are silently dropped by
providers that do not support them. With `require_parameters: true` "the request won't even be routed to that
provider".

## Logprobs

- Request: `logprobs` ("Whether to return log probabilities of the output tokens or not") and `top_logprobs` (0–20,
  needs `logprobs: true`) (https://openrouter.ai/docs/api_reference/parameters.md). Both providers list both.
- Response (API reference schemas `ChatChoice`, `ChatTokenLogprobs`, `ChatTokenLogprob`):
  `choices[].logprobs.content[]` = `{token, logprob, bytes, top_logprobs[]}`; `content` may be null.
- Unverified until a live call: that the providers fill `logprobs` when asked. The code treats them as optional.

## App attribution headers

https://openrouter.ai/docs/app-attribution.md:
- `HTTP-Referer`: "identifies your app's URL and is used as the primary identifier for rankings. **This header is
  required for app attribution.**"
- `X-OpenRouter-Title`: "sets or modifies your app's display name … `X-Title` is still supported for backwards
  compatibility. This header alone does not create an app page."
- Optional: `X-OpenRouter-Categories`, `X-OpenRouter-App-Visibility: hidden`. Not sent.

Shotkeeper sends `HTTP-Referer: https://github.com/paragrudani1/shotkeeper`, `X-OpenRouter-Title: Shotkeeper` and
`X-Title: Shotkeeper` (the brief asked for `X-Title`; the current name is added so the title survives if the legacy
header is retired).

## Authentication

`Authorization: Bearer <key>`; keys start with `sk-or-v1-`; "Send the credential exactly as issued, with no extra
whitespace or quotes" (https://openrouter.ai/docs/api_reference/authentication.md). Keys are created at
https://openrouter.ai/keys with an optional credit limit (same page).

## Usage and cost in the response

https://openrouter.ai/docs/cookbook/administration/usage-accounting.md:
- "OpenRouter automatically returns detailed usage information with every response". "On Chat Completions, the
  `usage: { include: true }` and `stream_options: { include_usage: true }` parameters are deprecated and have no
  effect." So nothing is sent to get usage.
- Chat Completions `usage`: `prompt_tokens`, `completion_tokens`, `total_tokens`,
  `completion_tokens_details.reasoning_tokens`, `prompt_tokens_details.cached_tokens`, `cost`, `cost_details`
  (`upstream_inference_cost`, `upstream_inference_prompt_cost`, `upstream_inference_completions_cost`), `is_byok`.
  "`cost`: The total amount charged to your account" (credits = USD, FAQ above).
- API reference `ChatUsage` agrees (`cost`: "Cost of the completion", number or null).

## Privacy routing

`provider` object (provider-selection page and API reference `ProviderPreferences`, `additionalProperties: false`):
- `data_collection`: `"allow"` (default: "allow providers which store user data non-transiently and may train on it")
  or `"deny"` ("use only providers which do not collect user data"). "If no available model provider meets the
  requirement, your request will return an error."
- `zdr: true`: "Restrict routing to only ZDR (Zero Data Retention) endpoints." Safety Retention endpoints "are also
  eligible unless your privacy settings or guardrail are set to ZDR only". The per-request flag "operates as an 'OR'
  with your account-wide and guardrail ZDR settings" (https://openrouter.ai/docs/guides/features/zdr.md).
- ZDR "means no routine storage of prompts or responses after processing", apart from in-flight CSAM screening
  (planned 2026-10-27: flagged content "may be retained for human review, reporting, and preservation where required
  by law") (zdr page). "Providers that do not retain your data are also unable to train on your data" (zdr page).

**Both providers stay eligible with both options on:**
- Both Inkling 2 Mini endpoints are in the public ZDR list `GET /api/v1/endpoints/zdr` with
  `safety_retention: false` (zdr snapshot), so `zdr: true` keeps both, whatever the account's Safety Retention choice.
- The model page's per-endpoint `dataPolicy` for both: `training: false`, `retainsPrompts: false`,
  `safetyRetention: false` (model-page snapshot). `data_collection: "deny"` therefore excludes neither. (The docs do
  not spell out the exact filter behind `deny`; this is the published per-endpoint policy it is based on.)

**Turned on in Shotkeeper:** `provider: {"data_collection": "deny", "zdr": true, "require_parameters": true}`.
`require_parameters` is not a privacy option: it keeps a provider that would ignore `reasoning`, `response_format` or
`logprobs` from serving the request; both providers support every parameter Shotkeeper sends (table above).
Not sent: `order`/`only` (pinning a provider would lose the fallback), `allow_fallbacks` (default true).

Within OpenRouter itself: "OpenRouter does not store your prompts or responses, *unless* you opt in" to private
logging or to "OpenRouter Use of Inputs/Outputs" (both off by default), or content is flagged as potential CSAM. It
stores request metadata (token counts, latency) (https://openrouter.ai/docs/guides/privacy/data-collection.md).

Policy links (all returned HTTP 200 on 2026-11-22):
- OpenRouter privacy policy: https://openrouter.ai/privacy (linked from the data-collection page); terms
  https://openrouter.ai/terms.
- Provider data policies: https://openrouter.ai/docs/guides/privacy/provider-logging and ZDR:
  https://openrouter.ai/docs/guides/features/zdr.
- Prime Intellect: privacy https://www.primeintellect.ai/privacy-policy, terms https://www.primeintellect.ai/terms-of-service;
  io.net: privacy https://io.net/privacy, terms https://io.net/terms (providers snapshot). io.net headquarters: US;
  Prime Intellect: not listed.

## Errors and status codes

https://openrouter.ai/docs/api_reference/errors-and-debugging.md:
- Body: `{"error": {"code": number, "message": string, "metadata"?: {...}}}`; "The HTTP Response will have the same
  status code as `error.code`" when the request is invalid or out of credits. "Otherwise, the returned HTTP response
  status will be `200` and any error occurred while the LLM is producing the output will be emitted in the response
  body". A non-streaming request whose provider fails after the headers gets "a `200 OK` whose JSON body holds only an
  `error` object and no `choices`", or `choices[0].error` with `finish_reason: "error"` next to partial content.
- Codes: 400 bad request; 401 invalid credentials; **402 "Your account or API key has insufficient credits. Add more
  credits and retry the request."**; 403 forbidden (permissions, guardrail block, moderation; budget limits also come
  as 403 with `metadata.limit_source`); 408 timeout; 429 rate limited; 502 model down or invalid response; 503 "no
  available model provider that meets your routing requirements".
- Typed `error.metadata.error_type`: e.g. `payment_required` 402, `rate_limit_exceeded` 429, `provider_overloaded`
  503, `provider_unavailable` 502, `content_policy_violation` / `refusal` 403, `invalid_image` / `image_too_large` /
  `unsupported_image_format` 400, `timeout` 504, `server` 500 (message masked).
- `Retry-After` (seconds) may come on 429 and 503, and on a 402 whose `metadata.limit_source` is
  `openrouter_in_flight_budget`. "A `402` without the header is not a wait-and-retry case."

https://openrouter.ai/docs/api_reference/limits.md:
- 402 `limit_source`: `openrouter_in_flight_budget` ("transient … wait for [Retry-After] and retry"),
  `openrouter_credits` (balance cannot cover the request), `openrouter_key_limit` (the key's credit limit).
- Rate limits: the platform request caps apply to `:free` variants (20/min, 50 or 1000/day), key management and
  per-IP bursts on key endpoints. **For paid inference the docs give no request-per-minute number**; 429s then come
  from the upstream provider, and "fallback routing retries other providers for the same model automatically before
  the error reaches you". "Successful inference responses do not include `X-RateLimit-*` headers."

Shotkeeper's mapping (`OpenRouterBackend.refineError`, `HTTPErrorMapping`): 401/403 → `unauthorized` (holds the queue),
except a 403 with `error_type` `content_policy_violation` or `refusal` → `badRequest(403)` (that one file fails);
402 with `limit_source == openrouter_in_flight_budget` → `rateLimited(Retry-After)` (retried); other 402 →
`badRequest(402)` ("out of credits", not retried); 429 → `rateLimited`; 408/5xx → `serverError` (retried).

## Where the docs are silent (2026-11-22)
- Image size limits per request or per image, and how many prompt tokens an image costs for this model.
- Whether `effort: "none"` is honoured by both providers in practice (documented, model lists `none`).
- A paid-model request-per-minute limit.
- The exact filter `data_collection: "deny"` applies (the per-endpoint `dataPolicy` is the published basis).
