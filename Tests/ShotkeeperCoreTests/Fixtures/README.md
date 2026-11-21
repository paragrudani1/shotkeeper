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

Local (OpenAI-compatible) responses are built inline in `LocalOpenAICompatibleAnalyzerTests` from model-output strings, wrapped in
the chat-completion shape documented in `docs/research/openai-compatible-chat.md`.
