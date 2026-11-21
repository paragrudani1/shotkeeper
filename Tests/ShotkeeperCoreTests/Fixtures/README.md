# Test fixtures

All `clairic-response-*.json` files are **synthesized from docs**, not captured from the live API. Their shapes follow:
- the REST envelope `{result, success, errors, messages}` in `docs/research/clairic/workers-ai-rest-api-2026-11-21.md`;
- the inner object (`model`, `answers`, `truncated`, `usage`) and per-answer members (`type`, `value`, `valid`, `complete`,
  `confidence`, `p_null`, `span`, `guess`, lists' `confidences`/`spans`/`p_nulls`, `failure_reason`) in
  `docs/research/clairic/schema-output.json` and the sample response in `docs/research/clairic/model-page-2026-11-21.md`.
- The element shape of `errors[]` (`{code, message}`) in `clairic-response-failure.json` is **not** in the saved docs; the parser
  accepts strings or objects with `message`.

Values (titles, token counts) are invented for tests; token counts follow the image-token formula on the model page.

A file named `clairic-live-<date>.json` would be a sanitized real response; none exists yet (no Cloudflare credentials on the
build box as of 2026-11-21).

Local (OpenAI-compatible) responses are built inline in `LocalOpenAICompatibleAnalyzerTests` from model-output strings, wrapped in
the chat-completion shape documented in `docs/research/openai-compatible-chat.md`.
