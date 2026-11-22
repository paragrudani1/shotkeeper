import Foundation

/// The single place that says what Shotkeeper asks a model for. Both backends derive their schema from here:
/// `ClairicFieldSchema` (Clairic field specs) and `OpenAICompatibleAnalyzer` (JSON schema + system prompt).
/// Tune wording here; tune Clairic types/cost in `ClairicFieldSchema`. Rationale: docs/wiki/clairic-field-schema.md.
public enum AnalysisFields {
    public static let title = "title"
    public static let sourceAppOrSite = "source_app_or_site"
    public static let contentType = "content_type"
    public static let description = "description"
    public static let tags = "tags"
    public static let keyText = "key_text"
    public static let dateMentioned = "date_mentioned"

    public static let all = [title, sourceAppOrSite, contentType, description, tags, keyText, dateMentioned]

    public static let titleMaxLength = 60
    public static let descriptionMaxLength = 240
    public static let keyTextMaxLength = 500
    public static let maxTags = 8
    /// Clairic sends tags as one comma-separated `text` answer (see `ClairicFieldSchema`): 8 tags × ~20 characters.
    public static let tagsTextMaxLength = 160
    /// Clairic `source_app_or_site` cap; app names and domains are short.
    public static let sourceAppOrSiteMaxLength = 40

    public enum Instructions {
        public static let title = """
            A 3-6 word descriptive filename for this screenshot in sentence case, naming the subject, e.g. \
            "Tweet semiconductor flashcards" or "Stripe invoice for October". No dates, no file extension, \
            never just "Screenshot".
            """
        public static let sourceAppOrSite = """
            The app or website shown, as its common name (e.g. "X", "Slack", "GitHub", "Figma", "Terminal", \
            "nytimes.com"). Null if it cannot be told.
            """
        public static let contentType = "The kind of content shown in the screenshot."
        public static let description = "One or two sentences describing what the screenshot shows and why it might matter."
        public static let tags = "Up to 8 short lowercase keywords (1-2 words each) for finding this screenshot later."
        /// Clairic only: tags as one text answer. "different" because the live list answer repeated one tag 7 times.
        public static let tagsCommaSeparated = """
            Up to 8 different short lowercase keywords (1-2 words each) for finding this screenshot later, \
            separated by commas.
            """
        public static let keyText = "The main visible text of the screenshot (headline, message or code), verbatim, without UI chrome."
        public static let dateMentioned = """
            The most prominent calendar date printed in the screenshot content (post date, due date, event date). \
            Null if none.
            """
    }
}
