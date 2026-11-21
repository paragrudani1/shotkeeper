import Foundation

/// The type chips in the search window (spec PR 2, row 2): All · Tweet · Article · Code · Chat · Receipt · Design.
/// `ContentType.other` has no chip; those screenshots show under All.
public enum SearchChip: String, CaseIterable, Equatable, Sendable {
    case all, tweet, article, code, chat, receipt, design

    public var title: String {
        contentType?.displayName ?? "All"
    }

    /// The content_type filter; nil for All.
    public var contentType: ContentType? {
        switch self {
        case .all: return nil
        case .tweet: return .tweet
        case .article: return .article
        case .code: return .code
        case .chat: return .chat
        case .receipt: return .receipt
        case .design: return .design
        }
    }
}

extension ContentType {
    /// "Tweet", "Article", …, "Other".
    public var displayName: String {
        switch self {
        case .tweet: return "Tweet"
        case .article: return "Article"
        case .code: return "Code"
        case .chat: return "Chat"
        case .receipt: return "Receipt"
        case .design: return "Design"
        case .other: return "Other"
        }
    }
}

/// One label/value pair in the preview's metadata grid (Source / Type / Taken / Folder).
public struct SearchMetadataRow: Equatable, Sendable {
    public var label: String
    public var value: String
}

/// One search result as the window shows it. Built from an index row; all wording is here so it is tested on Linux.
public struct SearchResultItem: Equatable, Sendable, Identifiable {
    public var id: Int64
    /// Current absolute path (open, copy, reveal, drag, Quick Look).
    public var path: String
    /// The file's current name without extension: what the user sees in Finder (like the menu's recent rows).
    public var title: String
    public var description: String?
    public var tags: [String]
    /// Trimmed; nil when the model reported none.
    public var source: String?
    public var contentType: ContentType?
    public var capturedAt: Date?
    public var processedAt: Date?

    public init(_ row: IndexedScreenshot) {
        id = row.id
        path = row.path
        title = URL(fileURLWithPath: row.path).deletingPathExtension().lastPathComponent
        let description = row.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description?.isEmpty == false ? description : nil
        tags = row.tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let source = row.sourceAppOrSite?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source?.isEmpty == false ? source : nil
        contentType = row.contentType
        capturedAt = row.capturedAt
        processedAt = row.processedAt
    }

    /// The time shown in the row: when it was taken, else when it was processed.
    public var date: Date? { capturedAt ?? processedAt }

    /// What the row names as the source: the app or site, else the content type ("Receipt"), else nothing.
    public var sourceLabel: String? {
        if let source { return source }
        if let contentType, contentType != .other { return contentType.displayName }
        return nil
    }

    /// The row's second line: "x.com · 5 min ago".
    public func subtitle(now: Date, time: TimeLabel = TimeLabel()) -> String {
        [sourceLabel, date.map { time.relative($0, now: now) }].compactMap { $0 }.joined(separator: " · ")
    }

    /// VoiceOver name of the row: "Tweet semiconductor flashcards, x.com, today 4:24 PM".
    public func accessibilityLabel(now: Date, time: TimeLabel = TimeLabel()) -> String {
        ([title, source] + [date.map { time.spoken($0, now: now) }]).compactMap { $0 }.joined(separator: ", ")
    }

    /// Tag chips: "#receipt".
    public var hashtags: [String] { tags.map { "#\($0)" } }

    /// The preview's metadata grid.
    public func metadata(time: TimeLabel = TimeLabel()) -> [SearchMetadataRow] {
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        return [
            SearchMetadataRow(label: "Source", value: source ?? "Unknown"),
            SearchMetadataRow(label: "Type", value: contentType?.displayName ?? "Unknown"),
            SearchMetadataRow(label: "Taken", value: date.map { time.dateTime($0) } ?? "Unknown"),
            SearchMetadataRow(label: "Folder", value: folder.isEmpty ? "/" : folder),
        ]
    }
}

/// Thrown by the app's search function when the index never opened; the window shows its error state.
public struct IndexUnavailableError: Error, Equatable, Sendable {
    public var problem: UserFacingProblem
    public init(problem: UserFacingProblem) { self.problem = problem }
}

/// Title and body of a centered message in the result area (no match, error).
public struct SearchMessage: Equatable, Sendable {
    public var title: String
    public var message: String
}

/// Everything the search window shows and how it reacts to input, without AppKit. The app renders it and runs the
/// searches it asks for: when a mutating call returns true, run `query` with `resultLimit` and hand the outcome to
/// `apply(_:for:)` or `fail(_:for:)`.
public struct SearchWindowState: Equatable, Sendable {
    /// What the result area shows.
    public enum Phase: Equatable, Sendable {
        /// Before the first answer arrives.
        case loading
        case results
        /// The query (text, chip or batch) matches nothing, but the index has screenshots.
        case noMatch(SearchMessage)
        /// The index holds no analyzed screenshots.
        case emptyIndex
        /// The index did not open, or the search failed. Never shown as the empty state.
        case error(SearchMessage)
    }

    public enum EscapeOutcome: Equatable, Sendable {
        /// The text and chip were cleared; run the search again.
        case clearedSearch
        /// Nothing to clear: close the window.
        case close
    }

    /// Rows asked for per search (a batch asks for all its files, up to `maxResults`).
    public static let pageSize = 100
    public static let maxResults = 1000
    /// How long "✓ Copied" stays on the image.
    public static let copiedPillDuration: TimeInterval = 1.4

    public private(set) var text = ""
    public private(set) var chip: SearchChip = .all
    /// Set by the batch toast's "View in Search"; any edit of the text or chip leaves the batch.
    public private(set) var batchPaths: [String]?
    public private(set) var items: [SearchResultItem] = []
    public private(set) var selectedIndex: Int?
    public private(set) var matchCount = 0
    public private(set) var totalCount: Int?
    public private(set) var failure: SearchMessage?
    /// True after ↑/↓ or a click on a row, false after typing: Space then opens Quick Look instead of typing.
    public private(set) var isBrowsing = false
    private var lastApplied: ScreenshotQuery?

    public init() {}

    // MARK: Derived

    public var query: ScreenshotQuery {
        ScreenshotQuery(text: text, contentType: chip.contentType, paths: batchPaths)
    }

    public var resultLimit: Int {
        min(Self.maxResults, max(Self.pageSize, batchPaths?.count ?? 0))
    }

    /// Text or a chip narrows the results (the footer then says "6 of 214 screenshots").
    public var hasFilter: Bool {
        ScreenshotIndex.ftsQuery(text) != nil || chip != .all
    }

    /// The clear (x) button in the field.
    public var showsClearButton: Bool { !text.isEmpty }

    public var selected: SearchResultItem? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    public var phase: Phase {
        if let failure { return .error(failure) }
        guard let totalCount, lastApplied != nil else { return .loading }
        if totalCount == 0 { return .emptyIndex }
        if items.isEmpty { return .noMatch(noMatchMessage) }
        return .results
    }

    /// Left side of the footer: "Recent · 214 screenshots", "6 of 214 screenshots", "This batch · 37 screenshots".
    public var footerText: String {
        guard failure == nil, let totalCount, lastApplied != nil else { return "" }
        if hasFilter { return "\(matchCount) of \(MenuText.screenshots(totalCount))" }
        if batchPaths != nil { return "This batch · \(MenuText.screenshots(matchCount))" }
        return "Recent · \(MenuText.screenshots(totalCount))"
    }

    /// Space opens Quick Look when there is a selection and the user is not typing a query (the field is empty, or
    /// the last thing they did was move the selection). Otherwise Space types a space. ⌘Y always opens it.
    public var spaceOpensQuickLook: Bool {
        selected != nil && (text.isEmpty || isBrowsing)
    }

    private var noMatchMessage: SearchMessage {
        let hint = "Try other words from the title, from the text in the image, or a tag."
        if ScreenshotIndex.ftsQuery(text) != nil {
            let terms = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return SearchMessage(title: "No screenshots match “\(terms)”", message: hint)
        }
        if chip != .all {
            return SearchMessage(title: "No \(chip.title) screenshots", message: "Choose All to see every screenshot.")
        }
        if batchPaths != nil {
            return SearchMessage(title: "These screenshots are no longer in the index",
                                 message: "They were moved, renamed or restored since. Clear the search to see recent screenshots.")
        }
        return SearchMessage(title: "No screenshots", message: hint)
    }

    // MARK: Input (each returns true when the query changed and a search must run)

    @discardableResult
    public mutating func setText(_ newText: String) -> Bool {
        guard newText != text else { return false }
        text = newText
        batchPaths = nil
        isBrowsing = false
        return true
    }

    @discardableResult
    public mutating func selectChip(_ newChip: SearchChip) -> Bool {
        guard newChip != chip || batchPaths != nil else { return false }
        chip = newChip
        batchPaths = nil
        return true
    }

    /// A tag chip in the preview: the tag goes into the field and the type chip goes back to All.
    @discardableResult
    public mutating func clickTag(_ tag: String) -> Bool {
        let plain = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        let changed = plain != text || chip != .all || batchPaths != nil
        text = plain
        chip = .all
        batchPaths = nil
        isBrowsing = false
        return changed
    }

    /// The "Clear search" button: clears the text, the chip and a batch.
    @discardableResult
    public mutating func clearSearch() -> Bool {
        let changed = !text.isEmpty || chip != .all || batchPaths != nil
        text = ""
        chip = .all
        batchPaths = nil
        isBrowsing = false
        return changed
    }

    /// Esc clears the search first (text and chip), and closes only when there is nothing to clear.
    public mutating func escape() -> EscapeOutcome {
        guard !text.isEmpty || chip != .all else { return .close }
        text = ""
        chip = .all
        batchPaths = nil
        isBrowsing = false
        return .clearedSearch
    }

    /// "View in Search" on a batch toast: show those files (newest first), with an empty text and the All chip.
    @discardableResult
    public mutating func showBatch(_ paths: [String]) -> Bool {
        text = ""
        chip = .all
        batchPaths = paths
        isBrowsing = false
        return true
    }

    /// The window was hidden: a batch view does not survive it (the next open shows recent screenshots).
    /// Returns true when the query changed.
    @discardableResult
    public mutating func windowHidden() -> Bool {
        isBrowsing = false
        guard batchPaths != nil else { return false }
        batchPaths = nil
        return true
    }

    // MARK: Selection

    /// ↑/↓: moves and clamps to the list; with no selection, ↓ picks the first row and ↑ the last.
    public mutating func moveSelection(by delta: Int) {
        guard !items.isEmpty else { selectedIndex = nil; return }
        let current = selectedIndex ?? (delta > 0 ? -1 : items.count)
        selectedIndex = min(max(current + delta, 0), items.count - 1)
        isBrowsing = true
    }

    /// A click on a row.
    public mutating func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        isBrowsing = true
    }

    // MARK: Results

    /// A search finished. Ignored (returns false) when `query` is no longer the current one. A new query selects
    /// the best match; the same query run again (window reopened) keeps the selected file if it is still there.
    @discardableResult
    public mutating func apply(_ result: ScreenshotSearchResult, for query: ScreenshotQuery) -> Bool {
        guard query == self.query else { return false }
        let previousPath = lastApplied == query ? selected?.path : nil
        items = result.rows.map(SearchResultItem.init)
        matchCount = result.matchCount
        totalCount = result.totalCount
        failure = nil
        lastApplied = query
        if items.isEmpty {
            selectedIndex = nil
        } else {
            selectedIndex = previousPath.flatMap { path in items.firstIndex { $0.path == path } } ?? 0
        }
        return true
    }

    /// A search threw. `IndexUnavailableError` (the index never opened) and other errors get readable text.
    @discardableResult
    public mutating func fail(_ error: any Error, for query: ScreenshotQuery) -> Bool {
        guard query == self.query else { return false }
        items = []
        selectedIndex = nil
        matchCount = 0
        lastApplied = query
        if let unavailable = error as? IndexUnavailableError {
            failure = SearchMessage(
                title: "The screenshot index could not be opened",
                message: "\(unavailable.problem.sentence) Your screenshots are not affected. Quit and reopen Shotkeeper to try again.")
        } else {
            failure = SearchMessage(
                title: "Search failed",
                message: "\(UserFacingError.problem(for: error).sentence) Try again, or quit and reopen Shotkeeper.")
        }
        return true
    }
}
