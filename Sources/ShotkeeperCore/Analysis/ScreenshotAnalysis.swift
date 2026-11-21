import Foundation

/// What a backend extracted from one screenshot. Backend-neutral: every `ScreenshotAnalyzer` returns this.
public struct ScreenshotAnalysis: Codable, Equatable, Sendable {
    /// 3–6 words, already validated for use as a filename stem (see `FilenameSanitizer`). Nil when the backend
    /// produced nothing usable; the pipeline then keeps the original filename.
    public var title: String?
    /// 0...1. Clairic: the field's `confidence` (0 when `valid == false`). Local LLM: 1 when the JSON validated,
    /// lower when the title had to be repaired. The pipeline renames only when `titleConfidence >= threshold`.
    public var titleConfidence: Double
    public var sourceAppOrSite: String?
    public var contentType: ContentType
    public var description: String?
    public var tags: [String]
    public var keyText: String?
    /// ISO-8601 calendar date (yyyy-MM-dd) mentioned in the screenshot, if any.
    public var dateMentioned: String?
    /// Which backend and model produced this, e.g. "clairic@cf/cloudflare/clairic" or "local:mlx-community/Inkling-2-Mini-4bit".
    public var producedBy: String
    /// Input tokens billed (Clairic `usage.input_tokens`); nil for local backends.
    public var billedInputTokens: Int?

    public init(title: String?, titleConfidence: Double, sourceAppOrSite: String?, contentType: ContentType,
                description: String?, tags: [String], keyText: String?, dateMentioned: String?,
                producedBy: String, billedInputTokens: Int? = nil) {
        self.title = title
        self.titleConfidence = titleConfidence
        self.sourceAppOrSite = sourceAppOrSite
        self.contentType = contentType
        self.description = description
        self.tags = tags
        self.keyText = keyText
        self.dateMentioned = dateMentioned
        self.producedBy = producedBy
        self.billedInputTokens = billedInputTokens
    }
}

public enum ContentType: String, Codable, CaseIterable, Sendable {
    case tweet, article, code, chat, receipt, design, other
}
