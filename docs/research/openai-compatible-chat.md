# OpenAI-compatible `/v1/chat/completions` (local backends): research notes (gathered 2026-11-21)

Used by `OpenAICompatibleAnalyzer` (profile `.localServer`; renamed from `LocalOpenAICompatibleAnalyzer` on 2026-11-22). Servers differ; the analyzer sends the common subset plus optional extras and
drops the extras once if a server rejects them with HTTP 400.

## llama.cpp `llama-server`
Source: https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md (fetched 2026-11-21).
- `response_format`: plain `{"type": "json_object"}`, schema-constrained `{"type": "json_object", "schema": {...}}`, and the
  OpenAI wrapper `{"type": "json_schema", "json_schema": {"name": ..., "strict": ..., "schema": {...}}}` are all accepted.
- `chat_template_kwargs`: "Allows sending additional parameters to the json templating system", e.g. `{"enable_thinking": false}`.
- `reasoning_effort`: "If `none`, reasoning/thinking is disabled. Otherwise, the value is made available to the jinja template."
- Reasoning is returned separately in `message.reasoning_content` (deepseek format) unless `reasoning_format` is `none`,
  in which case it stays in the raw text (hence `<think>` stripping in the parser).
- `image_url.url` may be "base64 (raw or URI-encoded via `data:image/...;base64`)"; formats supported by `stb_image` (jpeg, png, …).
- `max_tokens`: the endpoint defers to OpenAI's docs; native equivalent `n_predict` defaults to -1 (unbounded), so always send a cap.

## mlx-lm `mlx_lm.server`
Source: https://raw.githubusercontent.com/ml-explore/mlx-lm/main/mlx_lm/SERVER.md (fetched 2026-11-21).
- Default `localhost:8080`. Fields: `messages`, `max_tokens` (default 512), `temperature` (default 0.0), `top_p`, `stop`, `model`, …
- `response_format` and `chat_template_kwargs` are **not documented** for mlx-lm (main branch). The Inkling PR (#2086, see
  `model-backends.md`) is what makes images work; whether it honours `chat_template_kwargs` is unverified. Hence the 400-retry.
- Response: `choices[].message`, `finish_reason` is `"stop"` or `"length"`; `usage.prompt_tokens/completion_tokens/total_tokens`.

## OpenAI structured outputs (reference shape)
Source: https://developers.openai.com/api/docs/guides/structured-outputs (fetched 2026-11-21; page now documents the Responses API).
- Chat Completions uses `response_format: {type: "json_schema", ...}` (shape as quoted in the llama.cpp README above).
- Strict-mode examples list every property in `required`, set `"additionalProperties": false`, and express nullable fields as
  `"type": ["string", "null"]`. Shotkeeper's local schema follows those rules.

## Content parts
- User content is an array of parts: `{"type": "image_url", "image_url": {"url": "data:<mime>;base64,<b64>"}}` and
  `{"type": "text", "text": "..."}` (llama.cpp README; mlx-community Inkling README says to send `image_url` parts to `mlx_lm.server`).
- Some servers return `message.content` as a string, others as an array of `{type: "text", text}` parts; the parser accepts both.
