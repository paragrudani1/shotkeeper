# Clairic field schema and cost

Code: `Sources/ShotkeeperCore/Analysis/ClairicFieldSchema.swift` (types and keys), `AnalysisFields.swift` (wording shared
with the local backend). Facts: `docs/research/clairic/model-page-2026-11-21.md`, `schema-input.json`.

## 2026-11-21: schema chosen (analyzers commit `ea83cff`)

Billing rule from the model page: each `text` field gets its own pass, all other fields share one pass, and every pass
re-bills the full image. So **passes = text fields + 1**, and image tokens × passes is nearly the whole bill.

| Field | Type | Pass | Why |
|---|---|---|---|
| `title` | text, `maxLength` 60, `knowledge` | own | The product. Needs `maxLength` (text-only key) and `knowledge` (synthesized, not printed). |
| `description` | text, `maxLength` 240, `knowledge` | own | Search summary; needs a length cap, which list items cannot carry. |
| `key_text` | text, `maxLength` 500 | own | Verbatim text for the FTS index; needs a length cap. |
| `source_app_or_site` | list of text, `max_items` 1, `knowledge` | shared | **Folded out of `text`**: saves one full image pass (~1,000 tokens at 1280 px). |
| `content_type` | enum (7 values), `nullable: false` | shared | Closed set mirrors `ContentType`. |
| `tags` | list of text, `max_items` 8, `knowledge` | shared | Items with confidence < 0.3 are dropped. |
| `date_mentioned` | date, `source_only` | shared | Must be printed in the screenshot; stops Clairic inferring a date. |

`source_app_or_site` options considered:
- `text`: best fidelity, costs a fifth pass (+25% per screenshot).
- `enum` of known apps: shares the pass but cannot name the long tail (any website domain); rejected.
- **one-item text `list`** (chosen): shares the pass, open vocabulary, `knowledge` lets it recognise an app from its chrome.
  Trade-off: no `maxLength` on list items; the parser takes the first item and drops it below 0.3 confidence.
  Unverified live: that a text list really rides the shared pass. Check `usage.passes == 4` on the first live call; if it is 5,
  lists get their own pass too and the fold buys nothing.

A test (`ClairicFieldSchemaTests`) checks every key of every spec against the saved `schema-input.json`, including that a key's
description names the field's type (the API rejects unknown keys for a type).

## Per-screenshot cost estimate

Image tokens from the model page formula: `(w/32)·(h/32) + 2`, sides rounded to multiples of 32. A 16:10 Retina screenshot
(2880×1800) downscaled on the Mac:

| Long side | Size | Image tokens/pass | 4 passes (chosen) | 5 passes (source as text) |
|---|---|---|---|---|
| 1280 | 1280×800 | 1,002 | ~4,600 tokens: **$0.0011** ($0.00046 promo) | ~5,600: $0.0013 |
| 1024 | 1024×640 | 642 | ~3,200 tokens: **$0.00076** ($0.00032 promo) | ~3,800: $0.00091 |

Totals add ~600 schema tokens (a guess, scaled from the doc sample's 472 for six short fields; `state` is empty). Prices:
$0.24/M input tokens, $0.10/M promo until 2026-12-01. Retries count toward `usage.input_tokens`.
Per 1,000 full-screen screenshots: ~$1.10 at 1280 vs ~$0.76 at 1024. Region captures under 1280 px cost less either way.

**Recommendation: `maxImageLongSide` = 1280** (`ClairicFieldSchema.recommendedMaxImageLongSide`). The 1024 saving is
~$0.34 per 1,000 screenshots, while 1024 shrinks a Retina capture ~2.8× and small UI text (which `key_text`, `title` and `tags` rely
on) starts to blur. Revisit with live data. Keep the long side a multiple of 32 so Clairic's rounding adds nothing.

## Open questions (2026-11-21)
- No live call yet (no Cloudflare credentials on the build box). Fixtures are synthesized from the docs.
- `usage.schema_tokens` for this schema, and whether `knowledge` titles stay in sentence case: check on the first live call.
