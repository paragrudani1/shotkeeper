import Foundation

/// How new screenshots are sorted into subfolders of the organized folder (wave 2 spec, "Subfolder rule"; decisions
/// 1–4). Subfolders exist only inside the organized folder, so the rule applies only when "Move into the organized
/// folder" is on and an organized folder is set.
public enum SubfolderRule: String, Codable, Sendable, CaseIterable {
    /// Today's behavior: everything in the organized folder itself. The default.
    case off
    /// Tweets, Articles, Code, Chats, Receipts, Designs, Other.
    case byType
    /// One folder per app or site; unknown sources go to Other.
    case bySource
    /// The type folder, then the app or site inside it; unknown sources stay in the type folder.
    case byTypeThenSource
}

extension SubfolderRule {
    /// The type folder names: fixed, plural English (spec decision 2; no setting renames them).
    public static func typeFolderName(_ type: ContentType) -> String {
        switch type {
        case .tweet: return "Tweets"
        case .article: return "Articles"
        case .code: return "Code"
        case .chat: return "Chats"
        case .receipt: return "Receipts"
        case .design: return "Designs"
        case .other: return "Other"
        }
    }

    /// The folders below the organized folder that a screenshot goes to: `[]` is the organized folder itself,
    /// `["Chats", "Slack"]` is `Organized/Chats/Slack`. Pure: `existing` answers which subfolder names already exist
    /// below the given components (`[]` = in the organized folder itself), so an existing folder is reused.
    /// - Parameter source: the spelling a new source folder is named from (the pipeline passes
    ///   `SourceFacet.displayName`, never `SourceKey.rawValue`).
    public func relativeFolder(contentType: ContentType, source: String?,
                               existing: ([String]) -> [String]) -> [String] {
        switch self {
        case .off:
            return []
        case .byType:
            return [Self.typeFolder(contentType, existing: existing([]))]
        case .bySource:
            return [Self.sourceFolder(source, existing: existing([])) ?? Self.typeFolder(.other, existing: existing([]))]
        case .byTypeThenSource:
            let type = Self.typeFolder(contentType, existing: existing([]))
            return [type] + [Self.sourceFolder(source, existing: existing([type]))].compactMap { $0 }
        }
    }

    /// Whether the rule needs a source folder name (so the pipeline only looks up `SourceFacet.displayName` then).
    public var usesSource: Bool { self == .bySource || self == .byTypeThenSource }

    /// Answers from the model that name no app or site: such a source counts as unknown (spec "Unknown source").
    /// Compared after folding case, width and diacritics.
    public static let unknownSources: Set<String> = ["unknown", "n/a", "none", "screenshot", "image", "desktop"]

    /// Longest source folder name, in characters (grapheme clusters).
    public static let maxFolderNameLength = 60
    /// Longest name a macOS volume takes, in UTF-8 bytes (APFS and HFS+ allow 255).
    static let maxFolderNameBytes = 255

    /// A safe folder name for a source, or nil when the source is unknown (nil, a non-answer, or nothing usable left).
    /// The rules (spec "Source folder names"), in order: drop a leading `www.`; `/` and `:` (a run of them counts
    /// once) become " - "; invisible format characters (Unicode category Cf: bidirectional marks and controls such as
    /// U+200E, U+202E, U+2066, zero-width spaces, U+FEFF, soft hyphens) are dropped, so "\u{200E}Slack" is the same
    /// folder as "Slack", but U+200C/U+200D (zero-width non-joiner and joiner) stay, because emoji sequences such as
    /// 👨‍👩‍👧‍👦 and some scripts need them; runs of whitespace, newlines and line separators included, become one space
    /// ("Google\nChrome" → "Google Chrome"); then the remaining control characters are dropped. Dashes, spaces and dots
    /// are trimmed at both ends ("Mail:" → "Mail"; no hidden folder, no `.` or `..`), again after the cut to at most
    /// 60 characters and 255 UTF-8 bytes (at a character boundary). A name with nothing left ("../..") is unknown.
    /// macOS reserves no other names: a name the volume still refuses makes the pipeline fall back to the organized
    /// folder itself.
    public static func folderName(forSource raw: String?) -> String? {
        guard let raw else { return nil }
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasPrefix("www.") { name.removeFirst(4) }
        name = name.replacingOccurrences(of: "[/:]+", with: " - ", options: .regularExpression)
        // Format characters first: some Foundations count U+200B as whitespace, and it must vanish, not become a space.
        name = dropping(name, where: isInvisibleFormat)
        name = collapseWhitespace(name)
        name = dropping(name, where: isControl)
        name = trimEnds(collapseWhitespace(name))  // again: "a \u{0} b" left two spaces
        var capped = ""
        for character in name {
            guard capped.count < maxFolderNameLength,
                  capped.utf8.count + String(character).utf8.count <= maxFolderNameBytes else { break }
            capped.append(character)
        }
        name = trimEnds(capped)
        guard !name.isEmpty, !isNonAnswer(raw), !isNonAnswer(name) else { return nil }
        return name
    }

    /// The type folder below the organized folder: an existing one with that name in any letter case, else the
    /// fixed name.
    private static func typeFolder(_ type: ContentType, existing: [String]) -> String {
        let name = typeFolderName(type)
        return firstAlphabetically(existing) { SourceKey.fold($0) == SourceKey.fold(name) } ?? name
    }

    /// The source folder below a parent with these `existing` names: an existing one with the same `SourceKey`
    /// (first alphabetically), else a new name from `source`. Nil when the source is unknown.
    private static func sourceFolder(_ source: String?, existing: [String]) -> String? {
        guard let name = folderName(forSource: source) else { return nil }
        let wanted = Set([SourceKey(name), source.flatMap(SourceKey.init)].compactMap { $0 })
        return firstAlphabetically(existing) { SourceKey($0).map(wanted.contains) == true } ?? name
    }

    /// Alphabetical ignoring case and diacritics, then by Unicode scalars (`SourceFacet.alphabetical`).
    private static func firstAlphabetically(_ names: [String], where matches: (String) -> Bool) -> String? {
        names.filter(matches).min(by: SourceFacet.alphabetical)
    }

    private static func isNonAnswer(_ text: String) -> Bool { unknownSources.contains(SourceKey.fold(text)) }

    private static func isInvisibleFormat(_ scalar: Unicode.Scalar) -> Bool {
        // ZWNJ/ZWJ stay: emoji sequences and scripts need them.
        scalar.properties.generalCategory == .format && scalar.value != 0x200C && scalar.value != 0x200D
    }

    /// Controls, plus line/paragraph separators should a Foundation not count them as whitespace.
    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    private static func dropping(_ text: String, where unsafe: (Unicode.Scalar) -> Bool) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !unsafe($0) }))
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Dashes (left by a `/` or `:` at an end), spaces and dots off both ends.
    private static func trimEnds(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-")))
    }
}
