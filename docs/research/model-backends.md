# Model backends: research notes (gathered 2026-11-21)

Raw sources saved beside this file: `clairic/schema-input.json`, `clairic/schema-output.json`,
`clairic/model-page-2026-11-21.md`, `clairic/workers-ai-rest-api-2026-11-21.md`. Read those for exact fields; this page is a digest.

## Cloudflare Clairic (primary backend since 2026-11-21)
Source: https://developers.cloudflare.com/workers-ai/models/clairic/ (+ `schema-input.json`, `schema-output.json`).
- Endpoint: `POST https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/@cf/cloudflare/clairic`,
  header `Authorization: Bearer {API_TOKEN}`. Token needs `Workers AI - Read` and `Workers AI - Edit` (REST API get-started page).
- REST responses are wrapped: `{"result": {...model output...}, "success": true, "errors": [], "messages": []}`.
  The model page sample shows only the inner `result` object.
- Body: `model` ("clairic" or "@cf/cloudflare/clairic", required), `state` (string; may be empty when images are sent),
  `fields` (required map name → spec; names match `^[A-Za-z_][A-Za-z0-9_.\-]{0,63}$`), `images` (≤4; each a `data:` URL string
  OR `{content_type, base64, rotation?}`; PNG/JPEG/WebP; 4 MiB each, 8 MiB total; body ≤16 MiB; no remote URLs),
  `reference_date` (ISO date), `options` (`include_quantiles`, `return_state_text`).
- Field `type` enum: text, number, compute, date, time, datetime, duration, boolean, enum, object, list, estimate, forecast.
  Per-type keys (unknown keys are rejected): `instructions`, `nullable` (default true), text: `minLength`/`maxLength`/`pattern`/`enum`/`knowledge`;
  enum: `enum` (required); list: `items` ("text"|"number"|"date"|object spec), `max_items`; date: `source_only`, `null_threshold`.
  `knowledge: true` (text/number only) allows answers not present in the input — likely needed for a synthesized title/description. Unverified live.
- Answers (`result.answers[name]`): always `type`, `value` (null when undetermined). Generated answers (text, number, boolean, enum, object,
  lists): `valid`, `complete`, `confidence` (0 when invalid), `p_null`, `span`, `raw`, `failure_reason`. Typed answers (date…): `guess`, `confidence`
  (probability of guess), `p_null`. Lists: `value[]`, `confidences[]`, `spans[]`, `p_nulls[]`.
- `truncated`: true when any generated answer is invalid/incomplete. `usage`: `input_tokens` (incl. retries), `output_tokens`, `image_tokens`,
  `state_tokens`, `schema_tokens`, `passes`.
- Billing: input tokens only. $0.10/M until 2026-12-01 (promo), then $0.24/M. **Each `text` field gets its own pass; every pass re-bills the full
  state and all images.** Non-text fields share a pass. So cost ≈ passes × (image_tokens + schema share).
- Image tokens: sides rounded to multiples of 32; images under ~65k px² upscaled to ~256×256; larger NOT downscaled by Clairic;
  tokens = (w/32)·(h/32) + 2. E.g. 1024×640 → 642 tokens. Downscaling on the Mac is the main cost lever.
- Context: 65,536 tokens; each prompt must fit in 65,273.
- Preview model; the docs page gives no release date (user brief says 2026-10-19).

## Inkling 2 Mini (optional local backend)
Sources: https://huggingface.co/thinkingmachines/Inkling-2-Mini, https://huggingface.co/blog/inkling2mini (2026-11-20),
https://huggingface.co/mlx-community/Inkling-2-Mini-4bit, https://github.com/ml-explore/mlx-lm/pull/2086.
- Apache-2.0, image-text-to-text, `model_type` `inkling2_loop`. MoE ~26B total / ~3B active; 24 layers, middle 12 looped 3×.
- Chat template takes `reasoning_effort`: none(0.0)|minimal|low|medium|high(0.9, default)|xhigh|max, or a number 0–0.99.
  Use "none" for Shotkeeper. Servers usually pass template vars via `chat_template_kwargs`.
- MLX: support is in mlx-lm PR #2086, **not merged and not in a release as of 2026-11-21** (latest mlx-lm 0.32.2, 2026-10-16).
  PR head commit `0c4c99192230f1943dd468d297f0b8a64ae7b7c2` (branch `jundot:inkling2-mini`). mlx-community 4-bit README installs
  `git+https://github.com/ml-explore/mlx-lm.git@refs/pull/2086/head` and says: for images run `mlx_lm.server` and send `image_url` parts.
- Quants: `mlx-community/Inkling-2-Mini-4bit` (4 safetensors shards, ~17 GB); `VisualInference/Inkling-2-Mini-MLX-2bit` (mlx-vlm tag,
  ships a patch for mlx-vlm tool calls; check its README before relying on mlx-lm). 3-bit MLX repo: not yet verified.
- llama.cpp: GGUFs exist (`ggml-org/Inkling-2-Mini-GGUF` IQ4_NL 17.6 GB, Q8_0 27.8 GB, mmproj Q8_0 0.35 GB; unsloth UD quants 7.8–22.9 GB),
  llama.cpp Inkling PRs (#32187, #32695) still open on 2026-11-21. Live llama.cpp test on the Linux box was cancelled by the user on 2026-11-21 (disk).
