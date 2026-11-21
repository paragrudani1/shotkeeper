import Foundation

/// The Clairic `fields` map Shotkeeper sends, in one place.
///
/// Source for every key used below: docs/research/clairic/schema-input.json (`fields.additionalProperties.properties`)
/// and docs/research/clairic/model-page-2026-11-21.md ("Unknown keys for a field's type are rejected").
/// `ClairicFieldSchemaTests` checks each spec against that saved schema.
///
/// Cost model, measured on the first live calls (2026-11-21, `Tests/ShotkeeperCoreTests/Fixtures/clairic-live-2026-11-21-*.json`):
/// `usage.input_tokens = schema_tokens + k × image_tokens`, where k is one image copy per scalar answer and, for a
/// `list`, one per item (+1 for the list). The model page's "other fields share a pass" did not hold: the list-based
/// schema (8 tags + 1 source item) billed the image 16 times. So every field here is a scalar (no lists) and
/// k = number of fields. Decision record: docs/wiki/clairic-field-schema.md.
public enum ClairicFieldSchema {
    public static func fields() -> [String: AnalysisJSON] {
        [
            // The whole point of the app. Needs `maxLength` (text-only key) to keep stems short and
            // `knowledge: true` because the title is synthesized, not printed in the screenshot.
            AnalysisFields.title: [
                "type": "text",
                "instructions": .string(AnalysisFields.Instructions.title),
                "maxLength": .number(Double(AnalysisFields.titleMaxLength)),
                "knowledge": true,
            ],
            // Search/Spotlight summary. Synthesized (`knowledge`), and needs `maxLength` to stay 1–2
            // sentences; a list item cannot carry `maxLength`.
            AnalysisFields.description: [
                "type": "text",
                "instructions": .string(AnalysisFields.Instructions.description),
                "maxLength": .number(Double(AnalysisFields.descriptionMaxLength)),
                "knowledge": true,
            ],
            // Full-text index payload: verbatim, so no `knowledge`; capped with `maxLength`.
            AnalysisFields.keyText: [
                "type": "text",
                "instructions": .string(AnalysisFields.Instructions.keyText),
                "maxLength": .number(Double(AnalysisFields.keyTextMaxLength)),
            ],
            // Was a one-item text list to "share a pass"; live, lists cost an image copy per item and give no
            // `maxLength`, so it is plain text now. `knowledge` lets it recognise an app from its UI.
            AnalysisFields.sourceAppOrSite: [
                "type": "text",
                "instructions": .string(AnalysisFields.Instructions.sourceAppOrSite),
                "maxLength": .number(Double(AnalysisFields.sourceAppOrSiteMaxLength)),
                "knowledge": true,
            ],
            // Closed set mirrors `ContentType`; never null so the pipeline always has a bucket.
            AnalysisFields.contentType: [
                "type": "enum",
                "enum": .array(ContentType.allCases.map { .string($0.rawValue) }),
                "nullable": false,
                "instructions": .string(AnalysisFields.Instructions.contentType),
            ],
            // Keywords are synthesized, hence `knowledge`. One comma-separated text answer: the live `list` of 8
            // billed 8+ image copies and repeated one keyword (clairic-live-2026-11-21-tweet.json).
            AnalysisFields.tags: [
                "type": "text",
                "instructions": .string(AnalysisFields.Instructions.tagsCommaSeparated),
                "maxLength": .number(Double(AnalysisFields.tagsTextMaxLength)),
                "knowledge": true,
            ],
            // `source_only`: the date must be printed, so Clairic does not invent one from context.
            AnalysisFields.dateMentioned: [
                "type": "date",
                "source_only": true,
                "instructions": .string(AnalysisFields.Instructions.dateMentioned),
            ],
        ]
    }

    /// How many times one call bills the image: one copy per scalar field (measured 2026-11-21; see the type comment).
    /// Not `usage.passes`, which counts sequential decode steps (schema-output.json) and was 38 on the first call.
    public static var imageCopiesPerCall: Int {
        fields().values.filter { $0["type"] != "list" }.count
    }

    /// Image tokens as `usage.image_tokens` reports them. Model page ("Clairic tokenizes images as follows"): sides
    /// rounded to multiples of 32, images under ~65,000 px² scaled up to reach that area (never down), one token per
    /// 32×32 patch. The page adds 2 start/end markers, but live usage (2026-11-21) shows none: 1280×800 → 1000,
    /// 1280×831 → 1040, 591×1280 → 720, and `input_tokens` = `schema_tokens` + copies × `image_tokens` exactly.
    public static func estimatedImageTokens(width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return 0 }
        var w = Double(width), h = Double(height)
        let minArea = 65_536.0 // "about 65,000 pixels (256x256)"
        if w * h < minArea {
            let scale = (minArea / (w * h)).squareRoot()
            w *= scale
            h *= scale
        }
        let pw = max(1, Int((w / 32).rounded()))
        let ph = max(1, Int((h / 32).rounded()))
        return pw * ph
    }

    /// Schema tokens billed for `fields()` once per call (live `usage.schema_tokens`, 2026-11-21; the list-based
    /// schema it replaced cost 3,448).
    public static let measuredSchemaTokens = 1242

    /// Expected `usage.input_tokens` for one call with an image of this size: schema + one image copy per field.
    public static func estimatedInputTokens(width: Int, height: Int) -> Int {
        measuredSchemaTokens + imageCopiesPerCall * estimatedImageTokens(width: width, height: height)
    }

    /// Recommended `maxImageLongSide` for the Mac's ImageIO downscale. See docs/wiki/clairic-field-schema.md.
    public static let recommendedMaxImageLongSide = 1280
}
