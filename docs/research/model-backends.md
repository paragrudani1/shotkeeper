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
  `knowledge: true` (text/number only) allows answers not present in the input. Accepted live on 2026-11-21 (title, description, tags, source).
- Answers (`result.answers[name]`): always `type`, `value` (null when undetermined). Generated answers (text, number, boolean, enum, object,
  lists): `valid`, `complete`, `confidence` (0 when invalid), `p_null`, `span`, `raw`, `failure_reason`. Typed answers (date…): `guess`, `confidence`
  (probability of guess), `p_null`. Lists: `value[]`, `confidences[]`, `spans[]`, `p_nulls[]`.
- `truncated`: true when any generated answer is invalid/incomplete. `usage`: `input_tokens` (incl. retries), `output_tokens`, `image_tokens`,
  `state_tokens`, `schema_tokens`, `passes`.
- Billing: input tokens only. $0.10/M until 2026-12-01 (promo), then $0.24/M. Docs: **each `text` field gets its own pass; every pass re-bills the full
  state and all images.** Non-text fields share a pass.
  **Live, 2026-11-21 (differs from the docs):** `input_tokens = schema_tokens + k × image_tokens` exactly, with k = one copy per
  answer. 7 scalar fields (text, enum, date) → k = 7, and a text list of 8+1 items took k = 16. Non-text fields did not share a pass.
  `usage.passes` (schema-output: "sequential decode steps") was 33–125 and does not track cost. Source: the saved responses in
  `Tests/ShotkeeperCoreTests/Fixtures/clairic-live-2026-11-21-*.json`; analysis in `docs/wiki/clairic-field-schema.md`.
- Image tokens: sides rounded to multiples of 32; images under ~65k px² upscaled to ~256×256; larger NOT downscaled by Clairic;
  docs: tokens = (w/32)·(h/32) + 2. **Live `usage.image_tokens` has no +2** (1280×800 → 1000, 591×1280 → 720). Downscaling on
  the Mac is the main cost lever.
- Live answer details (2026-11-21): `confidence` comes with `confidence_method: ar_sequence_probability` (whole sequence, so
  multi-word text scores low), plus `log_probability` and `tokens`. A `source_only` date answers as a generated answer with
  `printed_value`/`normalization_method`, not with `guess`; `11/08/2026` failed with `invalid_printed_temporal`.
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
  ships a patch for mlx-vlm tool calls; check its README before relying on mlx-lm). 3-bit MLX repo: see the catalog section below.
- llama.cpp: GGUFs exist (`ggml-org/Inkling-2-Mini-GGUF` IQ4_NL 17.6 GB, Q8_0 27.8 GB, mmproj Q8_0 0.35 GB; unsloth UD quants 7.8–22.9 GB),
  llama.cpp Inkling PRs (#32187, #32695) still open on 2026-11-21. Live llama.cpp test on the Linux box was cancelled by the user on 2026-11-21 (disk).

## MLX quant catalog (checked 2026-11-21, ~11:00 UTC)
Source: `https://huggingface.co/api/models?search=Inkling-2-Mini%20mlx` (26 hits), then `/api/models/<repo>?blobs=true`
for sizes/revisions and each model card (`/raw/main/README.md`). Sizes = sum of repo files, GB = 10^9 bytes.

| Repo | Revision (sha) | Download | Card says | Format |
|---|---|---|---|---|
| `mlx-community/Inkling-2-Mini-4bit` | `9856dc53edead71405f8348930937c3638ff21a2` | 17.33 GB | serve with `mlx_lm.server` (PR #2086 install) | mlx-lm |
| `VisualInference/Inkling-2-Mini-MLX-3bit` | `ab80e9d5290b3e0c5af093bfd89d2f534c3ffb5b` | 13.46 GB | "for Macs with 24 GB"; 11.9 GiB weights, peak 12.7–14.1 GiB, +1.4% perplexity | mlx-vlm |
| `VisualInference/Inkling-2-Mini-MLX-2bit` | `66cf4fbfecdd3198202dc8918e2ba6e22561519d` | 10.40 GB | "16 GB (tight) or 18 GB"; 9.1 GiB weights, peak 9.8–11.2 GiB, +10% perplexity, weaker image recognition | mlx-vlm |

- **A real 3-bit MLX build for 24 GB Macs exists**: `VisualInference/Inkling-2-Mini-MLX-3bit` (created 2026-11-21 05:27 UTC).
  Same publisher and method as the 2-bit build the user chose, so it is the catalog's 3-bit entry.
  Other 3-bit builds seen: `netprojects/Inkling-2-Mini-MLX-3bit` (14.73 GB, "for 24 GB Macs", mlx-vlm, weights renamed on
  2026-11-21 so early downloads break) and `mlx-community/Inkling-2-Mini-oQ3e-mtp` (13.70 GB, needs oMLX ≥ 0.8.1, not mlx-lm).
- **Open risk:** both VisualInference cards say to use **mlx-vlm** (`git+https://github.com/Neywa-Labs/mlx-vlm`, PR 2778,
  merged 2026-11-20, unreleased) and `mlx_vlm.generate`, not `mlx_lm.server`. Whether the pinned mlx-lm commit loads their
  weights is unverified (no Mac here). mlx-lm's loader (`mlx_lm/models/inkling2/checkpoint.py` at the pinned commit) remaps
  the original checkpoint's key names; mlx-vlm-format keys may differ. `ModelVariant.verifiedWithMLXLM` is false for these
  and setup shows "Experimental build". First Mac run must check this; fallback is serving them with `mlx_vlm.server`.
- Revisions are pinned in `ModelCatalog` and passed as `hf download --revision`.

## mlx_lm.server at the pinned commit
Source: `https://raw.githubusercontent.com/ml-explore/mlx-lm/0c4c99192230f1943dd468d297f0b8a64ae7b7c2/mlx_lm/server.py`
(`main()` argparse) and `pyproject.toml` at the same commit.
- Flags used: `--model`, `--host` (default `127.0.0.1`), `--port` (default 8080), `--chat-template-args` (JSON passed to
  `apply_chat_template`, e.g. `{"reasoning_effort":"none"}`). Others available: `--max-tokens` (default 512), `--temp`,
  `--draft-model`, `--trust-remote-code`, `--log-level`, `--prompt-cache-size`, `--kv-bits`, `--decode-concurrency`.
- Per-request `chat_template_kwargs` is accepted. Images: message parts of type `image_url`/`input_image`/`image`; data URLs work.
- Endpoints: `GET /health`, `GET /v1/models`, `POST /v1/chat/completions`.
- Console script `mlx_lm.server` (pyproject `[project.scripts]`); `python -m mlx_lm.server` is deprecated.
- `requires-python = ">=3.11"`; deps include `transformers>=5.7.0`, `pillow`, `mlx>=0.32.3` on Darwin. macOS's bundled
  python3 is 3.9, so the plan prefers `uv venv --python 3.12`.
