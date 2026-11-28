import Foundation

/// The type chips in the search window (spec PR 2, row 2): All · Tweet · Article · Code · Chat · Receipt · Design.
/// `ContentType.other` has no chip; those screenshots show under All.
public enum SearchChip: String, CaseIterable, Equatable, Sendable {
    case all, tweet, article, code, chat, receipt, design

    public var title: String {
        contentType?.displayName ?? "All"
    }

    /// ⌘1…⌘7 select the chips in order (All = 1).
    public var shortcutNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// The chip for ⌘`number`, nil outside 1…7.
    public static func forShortcut(_ number: Int) -> SearchChip? {
        allCases.indices.contains(number - 1) ? allCases[number - 1] : nil
    }

    /// Chip tooltip: "Show only tweet screenshots (⌘2)".
    public var help: String {
        let action = self == .all ? "Show every type" : "Show only \(title.lowercased()) screenshots"
        return "\(action) (⌘\(shortcutNumber))"
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

/// A button in the no-match state (design §5).
public enum SearchNoMatchButton: Hashable, Sendable {
    /// Resets the chip, the date and the source, keeps the words (`clearFilters()`).
    case clearFilters
    /// Resets the words and every filter (`clearSearch()`).
    case clearSearch

    public var title: String {
        switch self {
        case .clearFilters: return "Clear filters"
        case .clearSearch: return "Clear search"
        }
    }
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
        /// An open picker was closed; nothing else changed.
        case closedPicker
        /// The text, chip, date and source were cleared; run the search again.
        case clearedSearch
        /// Nothing to clear: close the window.
        case close
    }

    /// Rows asked for per search (a batch asks for all its files, up to `maxResults`).
    public static let pageSize = 100
    public static let maxResults = 1000
    /// How long "✓ Copied" stays on the image.
    public static let copiedPillDuration: TimeInterval = 1.4
    /// How long a problem message (file gone, copy failed) stays on the image.
    public static let problemPillDuration: TimeInterval = 3
    /// Open, Copy or Reveal on a file that was moved or deleted after it was indexed.
    public static let missingFileMessage = "This file is no longer there. It was moved or deleted after it was indexed."
    /// Copy Image could not read the image data.
    public static let copyFailedMessage = "The image could not be copied."

    /// VoiceOver announcements when something is cleared (design §5). Choosing a value announces nothing: VoiceOver
    /// reads the pill's new value.
    public enum Announcement {
        /// The Date pill's ✕, or ⌫ in the date picker.
        public static let dateCleared = "Date cleared"
        /// The Source pill's ✕, or ⌫ in the source picker's empty narrow field.
        public static let sourceCleared = "Source cleared"
        /// The "Clear filters" button.
        public static let filtersCleared = "Filters cleared"
        /// Esc that clears, or the "Clear search" button.
        public static let searchCleared = "Search cleared"
    }

    public private(set) var text = ""
    public private(set) var chip: SearchChip = .all
    /// The date filter (⌘D, the Date pill); nil = any time.
    public private(set) var date: DateFilter?
    /// The open date picker; nil while closed (`toggleDatePicker()`).
    public internal(set) var datePicker: DatePickerState?
    /// The source filter (⌘S, the Source pill); nil = every source.
    public private(set) var source: SourceKey?
    /// The chosen source's name, kept while the source has no rows left (design §7, "Chosen source gone").
    public private(set) var sourceName: String?
    /// The source list the app loads each time the panel opens (`setSources(_:)`); nil until it has loaded.
    public private(set) var sources: [SourceFacet]?
    /// The open source picker; nil while closed (`toggleSourcePicker()`).
    public internal(set) var sourcePicker: SourcePickerState?
    /// Set by the batch toast's "View in Search"; any edit of the text or a filter leaves the batch.
    public private(set) var batchPaths: [String]?
    public private(set) var items: [SearchResultItem] = []
    public private(set) var selectedIndex: Int?
    public private(set) var matchCount = 0
    public private(set) var totalCount: Int?
    public private(set) var failure: SearchMessage?
    /// True after ↑/↓ or a click on a row, false after typing: Space then opens Quick Look instead of typing.
    public private(set) var isBrowsing = false
    private var lastApplied: ScreenshotQuery?
    /// The clock and calendar for date wording (the Date pill, no-match sentences). The app sets `now` before each
    /// search, the moment the index resolves "today" for that search.
    public var now: Date
    public var time: TimeLabel

    public init(now: Date = Date(), time: TimeLabel = TimeLabel()) {
        self.now = now
        self.time = time
    }

    // MARK: Derived

    public var query: ScreenshotQuery {
        ScreenshotQuery(text: text, contentType: chip.contentType, paths: batchPaths, date: date, source: source)
    }

    public var resultLimit: Int {
        min(Self.maxResults, max(Self.pageSize, batchPaths?.count ?? 0))
    }

    /// Text, a chip, a date or a source narrows the results (the footer then says "6 of 214 screenshots").
    public var hasFilter: Bool {
        ScreenshotIndex.ftsQuery(text) != nil || hasNarrowingFilter
    }

    /// A chip, a date or a source is set (what "Clear filters" resets).
    private var hasNarrowingFilter: Bool {
        chip != .all || hasDateOrSource
    }

    /// The filters that change the no-match wording and buttons (design §5): a chip alone keeps the approved states.
    private var hasDateOrSource: Bool { date != nil || source != nil }

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

    // MARK: Date pill (design §5, "Filter pills")

    /// "Date" when off, else the value: "Last 7 days", "Oct 3 – 17".
    public var datePillTitle: String {
        date?.label(now: now, time: time) ?? "Date"
    }

    /// VoiceOver value: "any time", "last 7 days". The label is "Date".
    public var datePillValue: String {
        date?.spokenValue(now: now, time: time) ?? "any time"
    }

    public var datePillHelp: String {
        date == nil ? "Filter by the day it was taken (⌘D)" : "Change the date (⌘D)"
    }

    // MARK: No match (design §5, "No-match states")

    /// The buttons under the no-match message, in order. A date or a source offers "Clear filters" (it keeps the
    /// words), plus "Clear search" when words are typed. Without either the approved states keep their one button.
    public var noMatchButtons: [SearchNoMatchButton] {
        guard hasDateOrSource else { return [.clearSearch] }
        return hasText ? [.clearFilters, .clearSearch] : [.clearFilters]
    }

    /// Tooltip of a no-match button.
    public func help(for button: SearchNoMatchButton) -> String {
        switch button {
        case .clearFilters: return hasText ? "Show every screenshot that matches the words" : "Show every screenshot"
        case .clearSearch: return "Clear the words and every filter"
        }
    }

    private var hasText: Bool { ScreenshotIndex.ftsQuery(text) != nil }

    /// "Receipt screenshots from Stripe taken in the last 30 days": the screenshots the filters allow. One pattern for
    /// every combination: an optional type, then "from <source>", then "taken …".
    private var filterPhrase: String {
        let kind = chip == .all ? "screenshots" : "\(chip.title) screenshots"
        return [kind, sourceName.map { "from \($0)" }, date?.takenPhrase(now: now, time: time)].compactMap { $0 }
            .joined(separator: " ")
    }

    private var noMatchMessage: SearchMessage {
        let hint = "Try other words from the title, from the text in the image, or a tag."
        if hasText {
            let terms = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = hasDateOrSource ? "Your filters limit this search to \(filterPhrase)." : hint
            return SearchMessage(title: "No screenshots match “\(terms)”", message: message)
        }
        if hasDateOrSource {
            return SearchMessage(title: "No \(filterPhrase)", message: "Clear filters to see every screenshot.")
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

    /// The date filter (picker, the pill's ✕, ⌫ in the picker); nil clears it. Any change leaves a batch view.
    @discardableResult
    public mutating func setDateFilter(_ newDate: DateFilter?) -> Bool {
        guard newDate != date || batchPaths != nil else { return false }
        date = newDate
        batchPaths = nil
        return true
    }

    /// The source filter (picker, the pill's ✕, ⌫ in the picker); nil clears it. Any change leaves a batch view.
    /// The same key with another spelling is no change, but its name is kept for the pill.
    @discardableResult
    public mutating func setSource(_ newSource: SourceFacet?) -> Bool {
        let changed = newSource?.key != source || batchPaths != nil
        source = newSource?.key
        sourceName = newSource?.displayName
        batchPaths = nil
        return changed
    }

    /// The source list loaded for this opening of the panel. When it still has the chosen source, its name follows
    /// the list (the most common spelling can change); when it doesn't, the source stays chosen under its old name.
    public mutating func setSources(_ list: [SourceFacet]) {
        sources = list
        if let source, let current = list.first(where: { $0.key == source }) { sourceName = current.displayName }
        refreshSourcePicker()
    }

    /// The "Clear filters" button: resets the chip, the date and the source, keeps the typed words, leaves a batch
    /// view.
    @discardableResult
    public mutating func clearFilters() -> Bool {
        let changed = hasNarrowingFilter || batchPaths != nil
        chip = .all
        date = nil
        clearSourceValue()
        batchPaths = nil
        return changed
    }

    private mutating func clearSourceValue() {
        source = nil
        sourceName = nil
    }

    /// A tag chip in the preview: the tag goes into the field, and the chip, the date and the source are reset, so the
    /// tag is searched across all screenshots (story 20).
    @discardableResult
    public mutating func clickTag(_ tag: String) -> Bool {
        let plain = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        let changed = plain != text || hasNarrowingFilter || batchPaths != nil
        resetSearch()
        text = plain
        return changed
    }

    /// The "Clear search" button: clears the text, every filter and a batch.
    @discardableResult
    public mutating func clearSearch() -> Bool {
        let changed = !text.isEmpty || hasNarrowingFilter || batchPaths != nil
        resetSearch()
        return changed
    }

    /// Esc closes an open picker first, then clears the search (text, chip, date and source), and closes the window
    /// only when there is nothing to clear (design §6).
    public mutating func escape() -> EscapeOutcome {
        if isPickerOpen {
            closePickers()
            return .closedPicker
        }
        guard !text.isEmpty || hasNarrowingFilter else { return .close }
        resetSearch()
        return .clearedSearch
    }

    private mutating func resetSearch() {
        text = ""
        chip = .all
        date = nil
        clearSourceValue()
        batchPaths = nil
        isBrowsing = false
    }

    /// "View in Search" on a batch toast: show those files (newest first), with an empty text and no filter.
    @discardableResult
    public mutating func showBatch(_ paths: [String]) -> Bool {
        resetSearch()
        batchPaths = paths
        return true
    }

    /// The window was hidden: a batch view does not survive it (the next open shows recent screenshots). The text
    /// and the filters stay (story 18). Returns true when the query changed.
    @discardableResult
    public mutating func windowHidden() -> Bool {
        isBrowsing = false
        closePickers()
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
