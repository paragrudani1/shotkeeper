import Foundation

/// One row of the menu's "Recent" section.
public struct RecentItem: Equatable, Sendable, Identifiable {
    public var id: Int64
    /// Current absolute path (what a click opens).
    public var path: String
    /// The file's current name without extension: what the user sees in Finder.
    public var title: String
    /// "x.com", "Slack", … when the model reported it.
    public var source: String?
    /// When it was processed (falls back to the capture time).
    public var date: Date

    public init(id: Int64, path: String, title: String, source: String?, date: Date) {
        self.id = id
        self.path = path
        self.title = title
        self.source = source
        self.date = date
    }

    /// VoiceOver name: "Tweet semiconductor flashcards, x.com, today 4:24 PM".
    public func accessibilityLabel(now: Date, time: TimeLabel = TimeLabel()) -> String {
        ([title, source].compactMap { $0?.isEmpty == false ? $0 : nil } + [time.spoken(date, now: now)])
            .joined(separator: ", ")
    }
}

public enum RecentItems {
    /// The menu shows the last 5 processed screenshots.
    public static let limit = 5

    /// Newest first, `done` rows only, at most `limit`. Input order does not matter.
    public static func make(from rows: [IndexedScreenshot], limit: Int = RecentItems.limit) -> [RecentItem] {
        rows.filter { $0.status == .done }
            .compactMap { row -> RecentItem? in
                guard let date = row.processedAt ?? row.capturedAt else { return nil }
                let stem = URL(fileURLWithPath: row.path).deletingPathExtension().lastPathComponent
                return RecentItem(id: row.id, path: row.path, title: stem, source: row.sourceAppOrSite, date: date)
            }
            .sorted { ($0.date, $0.id) > ($1.date, $1.id) }
            .prefix(max(0, limit))
            .map { $0 }
    }
}

/// The colored dot next to the menu's status line.
public enum StatusDot: String, Equatable, Sendable {
    /// Watching, idle or processing.
    case green
    /// Paused.
    case gray
    /// Offline, or held until the user fixes something ("Needs attention").
    case orange
    /// Broken: the index could not be opened, or the local model server gave up.
    case red
}

/// The two status lines at the top of the menu.
public struct MenuStatusSummary: Equatable, Sendable {
    public var dot: StatusDot
    /// "Watching Desktop"
    public var headline: String
    /// "Idle · 214 screenshots in the index", "Processing: 3 left", "Paused until 3:42 PM", …
    public var detail: String

    public init(dot: StatusDot, headline: String, detail: String) {
        self.dot = dot
        self.headline = headline
        self.detail = detail
    }
}

/// Menu wording. Pure; the app passes in its state.
public enum MenuText {
    /// - Parameters:
    ///   - watchedFolderName: last path component of the watched folder, nil while unknown.
    ///   - indexedCount: screenshots in the index (`IndexStats.done`), nil when unknown.
    ///   - failure: a hard failure (index not opened, local server gave up); wins over the queue status.
    public static func status(queue: QueueStatus, watchedFolderName: String?, indexedCount: Int?, failure: String? = nil,
                              now: Date, time: TimeLabel = TimeLabel()) -> MenuStatusSummary {
        let headline = watchedFolderName.map { "Watching \($0)" } ?? "Watching for screenshots"
        if let failure { return MenuStatusSummary(dot: .red, headline: "Not working", detail: failure) }
        switch queue {
        case .idle:
            let detail = indexedCount.map { "Idle · \(screenshots($0)) in the index" } ?? "Idle"
            return MenuStatusSummary(dot: .green, headline: headline, detail: detail)
        case .processing(_, let remaining):
            return MenuStatusSummary(dot: .green, headline: headline, detail: "Processing: \(remaining + 1) left")
        case .paused(let until?):
            let detail = until <= now ? "Resuming…" : "Paused until \(time.timeOrDateTime(until, now: now))"
            return MenuStatusSummary(dot: .gray, headline: headline, detail: detail)
        case .paused(nil):
            return MenuStatusSummary(dot: .gray, headline: headline, detail: "Paused")
        case .offline:
            return MenuStatusSummary(dot: .orange, headline: headline, detail: "Offline: waiting for the model backend")
        case .error(let message):
            return MenuStatusSummary(dot: .orange, headline: headline, detail: "Needs attention: \(message)")
        }
    }

    /// "Downloading Inkling 2 Mini · 4.1 of 9.1 GB". `fraction` is clamped to 0...1.
    public static func download(fraction: Double, totalGB: Double, modelName: String = "Inkling 2 Mini") -> String {
        let done = min(max(fraction, 0), 1) * totalGB
        return "Downloading \(modelName) · \(oneDecimal(done)) of \(oneDecimal(totalGB)) GB"
    }

    /// "Undo: Tweet semiconductor flashcards" for the latest undoable rename, or "Undo" (shown disabled) when
    /// there is nothing to undo.
    public static func undoItem(for record: UndoRecord?) -> String {
        guard let record else { return "Undo" }
        return "Undo: \(URL(fileURLWithPath: record.to).deletingPathExtension().lastPathComponent)"
    }

    /// "1 screenshot", "214 screenshots".
    public static func screenshots(_ count: Int) -> String {
        count == 1 ? "1 screenshot" : "\(count) screenshots"
    }

    private static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }
}

/// The last user-facing message in the menu. It disappears after `lifetime` or as soon as the next action
/// succeeds, so the menu never shows stale text.
public struct ExpiringMessage: Equatable, Sendable {
    public static let lifetime: TimeInterval = 30

    public private(set) var text: String?
    public private(set) var expiresAt: Date?

    public init() {}

    public mutating func set(_ text: String?, at now: Date) {
        self.text = text
        expiresAt = text == nil ? nil : now.addingTimeInterval(Self.lifetime)
    }

    /// The text if it has not expired at `now`.
    public func visibleText(at now: Date) -> String? {
        guard let text, let expiresAt, now < expiresAt else { return nil }
        return text
    }

    /// Drops the text once it has expired. Returns true when something was cleared.
    @discardableResult
    public mutating func expire(at now: Date) -> Bool {
        guard text != nil, visibleText(at: now) == nil else { return false }
        set(nil, at: now)
        return true
    }

    /// A later action succeeded: the old message no longer describes the current state.
    public mutating func clearAfterSuccess() {
        text = nil
        expiresAt = nil
    }
}
