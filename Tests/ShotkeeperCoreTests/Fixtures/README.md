# Test fixtures

`clairic-live-2026-11-21-*.json` are **real responses** (the `result` object of the REST envelope), saved by
`shotkeeper-cli analyze <png> --raw <file>` with the account ID and token scrubbed. Inputs are the PNGs in `live-samples/`
(synthetic screenshots drawn with Pillow, long side 1280). `tweet-list-schema` used the first, list-based schema; `tweet`,
`code` and `receipt` use the current all-scalar schema. See `docs/wiki/clairic-field-schema.md`.

All `clairic-response-*.json` files are **synthesized from docs**, not captured from the live API. Their shapes follow:
- the REST envelope `{result, success, errors, messages}` in `docs/research/clairic/workers-ai-rest-api-2026-11-21.md`;
- the inner object (`model`, `answers`, `truncated`, `usage`) and per-answer members (`type`, `value`, `valid`, `complete`,
  `confidence`, `p_null`, `span`, `guess`, lists' `confidences`/`spans`/`p_nulls`, `failure_reason`) in
  `docs/research/clairic/schema-output.json` and the sample response in `docs/research/clairic/model-page-2026-11-21.md`.
- The element shape of `errors[]` (`{code, message}`) in `clairic-response-failure.json` is **not** in the saved docs; the parser
  accepts strings or objects with `message`.

Values (titles, token counts) are invented for tests; token counts follow the image-token formula on the model page.

The synthesized files still use list-shaped `tags`/`source_app_or_site`; the parser keeps accepting that shape.

Local (OpenAI-compatible) responses are built inline in `OpenAICompatibleAnalyzerTests` (renamed from
`LocalOpenAICompatibleAnalyzerTests` on 2026-11-22) from model-output strings, wrapped in the chat-completion shape
documented in `docs/research/openai-compatible-chat.md`.

## OpenRouter (`OpenRouterAnalyzerTests`)

All `openrouter-*.json` files are **synthesized from OpenRouter's docs** (read 2026-11-22), not captured live (no key
yet). Sources are summarized with URLs in `docs/research/openrouter.md`.

| File | Shape | Source |
|---|---|---|
| `openrouter-response-success.json` | chat completion with `choices[0].logprobs.content[]` whose tokens concatenate to exactly `content`; the title is 4 tokens with logprobs −0.02, −0.15, −0.30, −0.05; `usage` with `cost` | API reference `ChatResult`, `ChatChoice`, `ChatTokenLogprobs`, `ChatUsage` |
| `openrouter-response-reasoning-off.json` | `reasoning_tokens: 0`, `logprobs: null`, `message.reasoning: null` | same, plus the reasoning-tokens page |
| `openrouter-response-malformed.json` | prose instead of JSON in `content` | same |
| `openrouter-error-402.json` | 402, the docs' wording for code 402, `metadata.limit_source: openrouter_credits` + `remedy_hint` (hint text invented) | Errors page ("Error codes"), Limits page ("Handling 402 errors") |
| `openrouter-error-402-in-flight.json` | the docs' in-flight budget example, verbatim | Limits page ("In-flight spending budget") |
| `openrouter-error-429.json` | the docs' 429 example, verbatim | Limits page ("Handling 429 errors") |
| `openrouter-response-error-in-200.json` | a 200 whose body is only `error` (502, `provider_unavailable`), no `choices` | Errors page ("Non-streaming requests") |

Token counts, costs, ids and titles are invented; the costs follow Prime Intellect's listed prices
($0.075 / M input, $0.30 / M output). Other error bodies (401, 403, 404, 503) are inline in the tests.
Live responses, once a key exists, go in `openrouter-live-<date>-<sample>.json`.
