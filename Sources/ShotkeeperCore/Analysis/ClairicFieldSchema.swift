import Foundation

/// The Clairic `fields` map Shotkeeper sends, in one place.
///
/// Source for every key used below: docs/research/clairic/schema-input.json (`fields.additionalProperties.properties`)
/// and docs/research/clairic/model-page-2026-11-21.md ("Unknown keys for a field's type are rejected").
/// `ClairicFieldSchemaTests` checks each spec against that saved schema.
///
/// Cost model (model page, "How media inputs are billed"): each `text` field gets its own pass; all other fields
/// share one pass; every pass re-bills the full image. So passes = (#text fields) + 1, and the image dominates cost.
/// Current choice: 3 text fields + 1 shared pass = 4 passes. Decision record: docs/wiki/clairic-field-schema.md.
public enum ClairicFieldSchema {
    public static func fields() -> [String: AnalysisJSON] {
        [
            // TEXT pass 1. The whole point of the app. Needs `maxLength` (text-only key) to keep stems short and
            // `knowledge: true` because the title is synthesized, not printed in the screenshot.
            AnalysisFields.title: [
                "type": "text",
                "instructions": .string(AnalysisFields.Instructions.title),
                "maxLength": .number(Double(AnalysisFields.titleMaxLength)),
                "knowledge": true,
            ],
            // TEXT pass 2. Search/Spotlight summary. Synthesized (`knowledge`), and needs `maxLength` to stay 1–2
            // sentences; a list item cannot carry `maxLength`.
            AnalysisFields.description: [
                "type": "text",
                "instructions": .string(AnalysisFields.Instructions.description),
                "maxLength": .number(Double(AnalysisFields.descriptionMaxLength)),
                "knowledge": true,
            ],
            // TEXT pass 3. Full-text index payload: verbatim, so no `knowledge`; capped with `maxLength`.
            AnalysisFields.keyText: [
                "type": "text",
                "instructions": .string(AnalysisFields.Instructions.keyText),
                "maxLength": .number(Double(AnalysisFields.keyTextMaxLength)),
            ],
            // SHARED pass. Folded out of `text` to save a full image pass: a one-item text list. An `enum` would also
            // share the pass but cannot name the long tail of sites. `knowledge` lets it recognise an app from its UI.
            AnalysisFields.sourceAppOrSite: [
                "type": "list",
                "items": "text",
                "max_items": 1,
                "knowledge": true,
                "instructions": .string(AnalysisFields.Instructions.sourceAppOrSite),
            ],
            // SHARED pass. Closed set mirrors `ContentType`; never null so the pipeline always has a bucket.
            AnalysisFields.contentType: [
                "type": "enum",
                "enum": .array(ContentType.allCases.map { .string($0.rawValue) }),
                "nullable": false,
                "instructions": .string(AnalysisFields.Instructions.contentType),
            ],
            // SHARED pass. Keywords are synthesized, hence `knowledge`.
            AnalysisFields.tags: [
                "type": "list",
                "items": "text",
                "max_items": .number(Double(AnalysisFields.maxTags)),
                "knowledge": true,
                "instructions": .string(AnalysisFields.Instructions.tags),
            ],
            // SHARED pass. `source_only`: the date must be printed, so Clairic does not invent one from context.
            AnalysisFields.dateMentioned: [
                "type": "date",
                "source_only": true,
                "instructions": .string(AnalysisFields.Instructions.dateMentioned),
            ],
        ]
    }

    /// Number of passes the schema should cost (each text field + one shared pass), before any context-window merging.
    public static var expectedPasses: Int {
        fields().values.filter { $0["type"] == "text" }.count + 1
    }

    /// Image tokens per the model page ("Clairic tokenizes images as follows"): sides rounded to multiples of 32,
    /// images under ~65,000 px² scaled up to reach that area (never down), one token per 32×32 patch, +2 markers.
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
        return pw * ph + 2
    }

    /// Recommended `maxImageLongSide` for the Mac's ImageIO downscale. See docs/wiki/clairic-field-schema.md.
    public static let recommendedMaxImageLongSide = 1280
}
