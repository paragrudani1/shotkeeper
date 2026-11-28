import Foundation

/// One source (app or site) as the source filter sees it: the model's free-text `source_app_or_site`, normalized so
/// that spellings of one source compare equal ("X", "x.com"; "GitHub", "github.com", "www.github.com").
///
/// `rawValue` is a matching key only: never show it and never name a folder or file from it (it is lowercased, folded
/// and may have lost its domain). Display and folder names come from `SourceFacet.displayName`.
///
/// The rule (wave 1 spec, "Filter model", Sources; 2026-11-28):
/// - fold case, diacritics and width ("Café" = "cafe", "ＧｉｔＨｕｂ" = "GitHub"), trim whitespace and collapse runs of
///   it to one space ("Google  Chrome" = "Google Chrome");
/// - drop a leading `www.`;
/// - when what is left is one name plus one top-level domain (`x.com`, `github.com`, `nytimes.com`), drop the domain,
///   so the site matches the app name; a name with `:` or `/` is a URL, not a host, and is left alone
///   (`https://github.com`);
/// - leave anything with more labels as it is (`bbc.co.uk`, `docs.google.com`).
///
/// There is no alias table: "Twitter" and "X" are two sources. Without a list of top-level domains, a name like
/// "Node.js" also loses its last label ("node"); that only merges it with a source spelled "Node".
public struct SourceKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The normalized text ("github", "bbc.co.uk"). A matching key, not a display or folder name (see the type).
    public let rawValue: String

    /// The key for a raw source value; nil when nothing is left after trimming (rows without a source).
    public init?(_ raw: String) {
        var folded = Self.fold(raw)
        if folded.hasPrefix("www.") { folded.removeFirst(4) }
        let labels = folded.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count == 2, !labels[0].isEmpty, !folded.contains(where: \.isWhitespace),
           !labels[0].contains(where: { $0 == ":" || $0 == "/" }),
           labels[1].count >= 2, labels[1].allSatisfy({ $0.isASCII && $0.isLetter }) {
            folded = String(labels[0])
        }
        guard !folded.isEmpty else { return nil }
        rawValue = folded
    }

    /// Text with case, diacritics and width folded, whitespace trimmed and each run of it collapsed to one space: what
    /// source keys and the source picker's narrow field compare ("  Café " → "cafe", "Ｇｏｏｇｌｅ　 Chrome" →
    /// "google chrome"). Width folding runs first, so a full-width space counts as whitespace.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public var description: String { rawValue }

    public static func < (lhs: SourceKey, rhs: SourceKey) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One row of the source list (`ScreenshotIndex.sources()`): a source, the name to show for it, and how many analyzed
/// screenshots in the whole index have it.
public struct SourceFacet: Hashable, Sendable, Identifiable {
    public var key: SourceKey
    /// The most common raw spelling (trimmed); ties go to the first alphabetically.
    public var displayName: String
    public var count: Int

    public var id: SourceKey { key }

    public init(key: SourceKey, displayName: String, count: Int) {
        self.key = key
        self.displayName = displayName
        self.count = count
    }

    /// Merges per-spelling counts into one facet per key, sorted by count (highest first), then by name. Spellings
    /// without a key (empty) are left out.
    static func merge(_ spellings: [(raw: String, count: Int)]) -> [SourceFacet] {
        var groups: [SourceKey: [String: Int]] = [:]
        for (raw, count) in spellings {
            guard let key = SourceKey(raw) else { continue }
            let spelling = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            groups[key, default: [:]][spelling, default: 0] += count
        }
        return groups.map { key, spellings in
            let name = spellings.min { a, b in a.value != b.value ? a.value > b.value : alphabetical(a.key, b.key) }!.key
            return SourceFacet(key: key, displayName: name, count: spellings.values.reduce(0, +))
        }
        .sorted { a, b in a.count != b.count ? a.count > b.count : alphabetical(a.displayName, b.displayName) }
    }

    /// Alphabetical, ignoring case and diacritics, then by Unicode scalars so the order never depends on the locale.
    static func alphabetical(_ a: String, _ b: String) -> Bool {
        let (foldedA, foldedB) = (SourceKey.fold(a), SourceKey.fold(b))
        return foldedA != foldedB ? foldedA < foldedB : a < b
    }
}
