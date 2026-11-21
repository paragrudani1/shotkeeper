import Foundation

/// Reads/writes extended attributes. The macOS app implements this with `getxattr`/`setxattr`; core only builds payloads.
public protocol FileMetadataWriter: Sendable {
    /// Current value of the attribute, or nil when it is not set.
    func readExtendedAttribute(_ name: String, of url: URL) throws -> Data?
    func writeExtendedAttribute(_ name: String, data: Data, to url: URL) throws
}

/// Does nothing (Linux, tests, or when the user turned Finder metadata off).
public struct NoopFileMetadataWriter: FileMetadataWriter {
    public init() {}
    public func readExtendedAttribute(_ name: String, of url: URL) throws -> Data? { nil }
    public func writeExtendedAttribute(_ name: String, data: Data, to url: URL) throws {}
}

/// Binary-plist payloads for the Finder/Spotlight xattrs.
/// - Tags: `com.apple.metadata:_kMDItemUserTags` is a binary plist array of strings; a colored tag is "Name\n<color index>".
/// - Comment: `com.apple.metadata:kMDItemFinderComment` is a binary plist string. Spotlight indexes it; Finder's Get Info
///   panel reads comments from `.DS_Store`, so a comment set this way may not show there (known macOS behaviour).
public enum FinderMetadata {
    public static let tagsAttribute = "com.apple.metadata:_kMDItemUserTags"
    public static let commentAttribute = "com.apple.metadata:kMDItemFinderComment"
    /// Comments are kept short; Spotlight does not need the whole description.
    public static let maxCommentLength = 1000

    public static func tagsPayload(_ tags: [String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
    }

    public static func commentPayload(_ comment: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: String(comment.prefix(maxCommentLength)), format: .binary, options: 0)
    }

    public static func decodeTags(_ data: Data) -> [String]? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String]
    }

    public static func decodeComment(_ data: Data) -> String? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? String
    }

    /// Existing tags first (keeping their colors), then new ones whose name is not already present (case-insensitive).
    public static func mergedTags(existing: [String], adding new: [String]) -> [String] {
        func name(_ tag: String) -> String { String(tag.split(separator: "\n", maxSplits: 1).first ?? "").lowercased() }
        var seen = Set(existing.map(name))
        var result = existing
        for tag in new {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    /// Adds `tags` to the file's Finder tags (keeping the user's) and sets the comment when non-empty.
    public static func apply(tags: [String], comment: String?, to url: URL, using writer: FileMetadataWriter) throws {
        if !tags.isEmpty {
            let existing = try writer.readExtendedAttribute(tagsAttribute, of: url).flatMap(decodeTags) ?? []
            let merged = mergedTags(existing: existing, adding: tags)
            if merged != existing { try writer.writeExtendedAttribute(tagsAttribute, data: try tagsPayload(merged), to: url) }
        }
        if let comment = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            try writer.writeExtendedAttribute(commentAttribute, data: try commentPayload(comment), to: url)
        }
    }
}
