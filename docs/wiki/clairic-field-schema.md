# Clairic field schema and cost

> **2026-11-21 (live):** the first live calls superseded the estimates and the list-based schema below. Read the
> "Live calls" section first; the older sections are kept as history.

Code: `Sources/ShotkeeperCore/Analysis/ClairicFieldSchema.swift` (types and keys), `AnalysisFields.swift` (wording shared
with the local backend). Facts: `docs/research/clairic/model-page-2026-11-21.md`, `schema-input.json`.

## 2026-11-21: live calls; schema changed to all-scalar fields (branch `t3/clairic-live-test-fixes`)

Three synthetic screenshots, long side 1280 (`Tests/ShotkeeperCoreTests/Fixtures/live-samples/`), one call each, plus
one re-run of the tweet after the fix. Raw `result` objects (secrets scrubbed) saved as
`Fixtures/clairic-live-2026-11-21-{tweet-list-schema,tweet,code,receipt}.json` with `shotkeeper-cli analyze --raw`.

| Call | Schema | image_tokens | schema_tokens | input_tokens | passes | Latency |
|---|---|---|---|---|---|---|
| tweet 1280×800 | lists (as shipped) | 1,000 | 3,448 | **19,448** | 38 | 6.1 s |
| tweet 1280×800 | scalar | 1,000 | 1,242 | **8,242** | 38 | 2.7 s |
| code 1280×831 | scalar | 1,040 | 1,242 | 8,522 | 125 | 5.6 s |
| receipt 591×1280 | scalar | 720 | 1,242 | 6,282 | 33 | 2.3 s |

What the real API showed (each backed by a test in `CloudflareClairicAnalyzerTests`):
- **Billing is one image copy per answer, not per text field.** Every call fits
  `input_tokens = schema_tokens + k × image_tokens` exactly. Scalar schema: k = 7 = number of fields. List schema:
  k = 16. Inferred split: 5 scalars + 9 list items (8 tags + 1 source) + 2. The model page's "other fields share a pass"
  did not hold for these fields. `usage.passes` is "sequential decode steps" (schema-output.json) and does not track cost.
- **The 8-item tags list repeated itself:** `semiconductor` ×7 + `pdf`. As one comma-separated text field: 8
  distinct tags. So `tags` and `source_app_or_site` are now `text` (`maxLength` 160 / 40, `knowledge`), and
  `tagsCommaSeparated` asks for "different" keywords. The parser still accepts lists (old fixtures).
- **Title `confidence` is a whole-sequence probability** (`confidence_method: ar_sequence_probability`): 0.38 / 0.04 /
  0.20 for three good titles, all below the 0.50 rename threshold. `titleConfidence` is now
  `exp(log_probability / tokens)`, the average per-token probability: 0.87 / 0.71 / 0.82. Falls back to `confidence`.
- **Image tokens have no +2 markers** in `usage.image_tokens`; `estimatedImageTokens` now matches usage.
- `knowledge: true` on text fields was accepted. Titles came back in sentence case and never "Screenshot". The tweet
  title equals the instruction's own example ("Tweet semiconductor flashcards"), but the sample was a semiconductor
  tweet, so this proves nothing either way.
- A `source_only` date is a *generated* answer (`valid`, `decoder`, `printed_value`, `normalization_method`), not a
  typed one with `guess`. A US-style `11/08/2026` came back `valid: false`, `failure_reason: invalid_printed_temporal`
  (→ no date); `Mar 14, 2026` normalized to `2026-03-14`.
- An absent source comes back as `value: null` with `p_null` ≈ 1, as documented. The envelope was wrapped (`result`).
- `description` confidence is ~1e-5 on every call (long sequence), so it is not used anywhere.

Cost per full-screen screenshot (1280×800): 1,242 + 7 × 1,000 = **8,242 tokens → $0.82 promo / $1.98 standard per 1,000**
(the estimate below said $0.46 / $1.11). `ClairicFieldSchema.estimatedInputTokens` encodes this. 1024 px long side:
5,722 tokens ($0.57 / $1.37). `maxImageLongSide` stays 1280: the code screenshot's ~22 px text was read correctly at 1280 except `\(stem)`, which came back as `1( stem)`.
Next lever if cost matters: each field costs one image copy (~12%), so drop or merge a field (e.g. `description`).

## 2026-11-21: schema chosen (analyzers commit `ea83cff`). *Superseded above.*

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

## Per-screenshot cost estimate (from docs, superseded by live data above)

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

## Open questions
- 2026-11-21 (answered by the live calls above): live behaviour, `schema_tokens`, title case.
- 2026-11-21: three samples only. Tag count varies (1 for code, 5 for the receipt, 8 for the tweet). Revisit
  `date_mentioned` if numeric US dates keep failing.
