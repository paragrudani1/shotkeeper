import XCTest
@testable import ShotkeeperCore

/// Formatters may use U+202F (narrow no-break space) before AM/PM depending on the ICU/CLDR version.
private func plain(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-11-21 16:24:00 UTC, a Saturday.
private let now = Date(timeIntervalSince1970: 1_795_278_240)
private let us = TimeLabel(calendar: utc, locale: Locale(identifier: "en_US"))

final class TimeLabelTests: XCTestCase {
    func testShortLabels() {
        XCTAssertEqual(plain(us.short(now, now: now)), "4:24 PM")
        XCTAssertEqual(plain(us.short(now.addingTimeInterval(-16 * 3600), now: now)), "12:24 AM")
        XCTAssertEqual(us.short(now.addingTimeInterval(-86_400), now: now), "Yesterday")
        XCTAssertEqual(us.short(now.addingTimeInterval(-17 * 3600), now: now), "Yesterday", "23:24 the day before")
        XCTAssertEqual(us.short(now.addingTimeInterval(-5 * 86_400), now: now), "Mon")
        XCTAssertEqual(us.short(now.addingTimeInterval(-7 * 86_400), now: now), "Nov 14")
        XCTAssertEqual(us.short(now.addingTimeInterval(-365 * 86_400), now: now), "Nov 21, 2025")
    }

    func testSpokenLabelsAlwaysIncludeTheTime() {
        XCTAssertEqual(plain(us.spoken(now, now: now)), "today 4:24 PM")
        XCTAssertEqual(plain(us.spoken(now.addingTimeInterval(-86_400), now: now)), "yesterday 4:24 PM")
        XCTAssertEqual(plain(us.spoken(now.addingTimeInterval(-5 * 86_400), now: now)), "Monday 4:24 PM")
        XCTAssertEqual(plain(us.spoken(now.addingTimeInterval(-7 * 86_400), now: now)), "November 14 4:24 PM")
    }

    func testLocaleAndCalendarAreInjected() {
        let german = TimeLabel(calendar: utc, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(german.short(now, now: now), "16:24")
        var tokyo = utc
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 16:24 UTC is 01:24 the next day in Tokyo; "now" there is the same instant, so still today.
        XCTAssertEqual(plain(TimeLabel(calendar: tokyo, locale: Locale(identifier: "en_US")).short(now, now: now)), "1:24 AM")
    }

    func testTimeOrDateTime() {
        XCTAssertEqual(plain(us.timeOrDateTime(now.addingTimeInterval(600), now: now)), "4:34 PM")
        XCTAssertTrue(plain(us.timeOrDateTime(now.addingTimeInterval(86_400), now: now)).contains("Nov 22"))
    }
}

final class RecentItemsTests: XCTestCase {
    private func row(_ id: Int64, _ path: String, minutesAgo: Double, status: ProcessingStatus = .done,
                     source: String? = "x.com") -> IndexedScreenshot {
        IndexedScreenshot(id: id, path: path, originalFilename: "Screenshot.png", contentHash: "h\(id)",
                          processedAt: now.addingTimeInterval(-minutesAgo * 60), title: "model title \(id)",
                          sourceAppOrSite: source, status: status)
    }

    func testLastFiveDoneNewestFirstWithFileNames() {
        var rows = (1...7).map { row(Int64($0), "/d/Shot \($0).png", minutesAgo: Double(10 - $0)) }
        rows.append(row(8, "/d/failed.png", minutesAgo: 0, status: .failed))
        rows.append(row(9, "/d/pending.png", minutesAgo: 0, status: .pending))
        let items = RecentItems.make(from: rows.shuffled())
        XCTAssertEqual(items.map(\.id), [7, 6, 5, 4, 3])
        XCTAssertEqual(items.first?.title, "Shot 7", "the file name the user sees, not the raw model title")
        XCTAssertEqual(RecentItems.limit, 5)
    }

    func testAccessibilityLabel() {
        let item = RecentItem(id: 1, path: "/d/Tweet semiconductor flashcards.png", title: "Tweet semiconductor flashcards",
                              source: "x.com", date: now)
        XCTAssertEqual(plain(item.accessibilityLabel(now: now, time: us)), "Tweet semiconductor flashcards, x.com, today 4:24 PM")
        var noSource = item
        noSource.source = nil
        XCTAssertEqual(plain(noSource.accessibilityLabel(now: now.addingTimeInterval(86_400), time: us)),
                       "Tweet semiconductor flashcards, yesterday 4:24 PM")
    }
}

final class MenuTextTests: XCTestCase {
    private func status(_ queue: QueueStatus, count: Int? = 214, failure: String? = nil) -> MenuStatusSummary {
        let summary = MenuText.status(queue: queue, watchedFolderName: "Desktop", indexedCount: count, failure: failure,
                                      now: now, time: us)
        return MenuStatusSummary(dot: summary.dot, headline: summary.headline, detail: plain(summary.detail))
    }

    func testStatusDotAndLines() {
        XCTAssertEqual(status(.idle), MenuStatusSummary(dot: .green, headline: "Watching Desktop",
                                                        detail: "Idle · 214 screenshots in the index"))
        XCTAssertEqual(status(.idle, count: 1).detail, "Idle · 1 screenshot in the index")
        XCTAssertEqual(status(.idle, count: nil).detail, "Idle")
        XCTAssertEqual(status(.processing(current: URL(fileURLWithPath: "/a"), remaining: 2)),
                       MenuStatusSummary(dot: .green, headline: "Watching Desktop", detail: "Processing: 3 left"))
        XCTAssertEqual(status(.paused(until: now.addingTimeInterval(18 * 60))),
                       MenuStatusSummary(dot: .gray, headline: "Watching Desktop", detail: "Paused until 4:42 PM"))
        XCTAssertEqual(status(.paused(until: now)).detail, "Resuming…")
        XCTAssertEqual(status(.paused(until: nil)).detail, "Paused")
        XCTAssertEqual(status(.offline), MenuStatusSummary(dot: .orange, headline: "Watching Desktop",
                                                           detail: "Offline: waiting for the model backend"))
        XCTAssertEqual(status(.error("Cloudflare API token is not set")),
                       MenuStatusSummary(dot: .orange, headline: "Watching Desktop",
                                         detail: "Needs attention: Cloudflare API token is not set"))
        XCTAssertEqual(status(.idle, failure: "Could not open the index."),
                       MenuStatusSummary(dot: .red, headline: "Not working", detail: "Could not open the index."))
        XCTAssertEqual(MenuText.status(queue: .idle, watchedFolderName: nil, indexedCount: 0, now: now).headline,
                       "Watching for screenshots")
    }

    func testDownloadLine() {
        XCTAssertEqual(MenuText.download(fraction: 0.45, totalGB: 9.1), "Downloading Inkling 2 Mini · 4.1 of 9.1 GB")
        XCTAssertEqual(MenuText.download(fraction: 2, totalGB: 9.1), "Downloading Inkling 2 Mini · 9.1 of 9.1 GB")
        XCTAssertEqual(MenuText.download(fraction: -1, totalGB: 12), "Downloading Inkling 2 Mini · 0.0 of 12.0 GB")
    }

    func testUndoItem() {
        XCTAssertEqual(MenuText.undoItem(for: nil), "Undo")
        let record = UndoRecord(timestamp: now, from: "/d/Screenshot 1.png", to: "/d/Tweet semiconductor flashcards.png")
        XCTAssertEqual(MenuText.undoItem(for: record), "Undo: Tweet semiconductor flashcards")
    }
}

final class ExpiringMessageTests: XCTestCase {
    func testExpiresAfterThirtySeconds() {
        var message = ExpiringMessage()
        message.set("Queued 3 screenshots", at: now)
        XCTAssertEqual(message.visibleText(at: now.addingTimeInterval(29)), "Queued 3 screenshots")
        XCTAssertNil(message.visibleText(at: now.addingTimeInterval(30)), "never shows stale text")
        XCTAssertFalse(message.expire(at: now.addingTimeInterval(10)))
        XCTAssertTrue(message.expire(at: now.addingTimeInterval(31)))
        XCTAssertNil(message.text)
    }

    func testNextSuccessClearsIt() {
        var message = ExpiringMessage()
        message.set("Could not save settings", at: now)
        message.clearAfterSuccess()
        XCTAssertNil(message.visibleText(at: now))
        message.set("again", at: now)
        message.set(nil, at: now)
        XCTAssertNil(message.expiresAt)
    }
}

final class UserFacingErrorTests: XCTestCase {
    func testShortMessagesNeverDumpTheErrorValue() {
        let cases: [(any Error, String, Bool)] = [
            (AnalyzerError.notConfigured("Cloudflare API token is not set"), "Cloudflare API token is not set", true),
            (AnalyzerError.unauthorized("Authentication error 10000 secret-ish detail"), "the model backend rejected the token", true),
            (AnalyzerError.invalidResponse("{json}"), "the model's answer could not be read", false),
            (AnalyzerError.badRequest(status: 413, message: "too big"), "the model backend rejected the image (HTTP 413)", false),
            (FileOrganizerError.sourceMissing("/Users/me/Desktop/x.png"), "the file is no longer there", false),
            (UndoError.originalPathOccupied("/Users/me/x.png"), "another file now has the original name", false),
            (UndoError.fileNotAtDestination("/x"), "the file was moved or renamed since", false),
            (ManualRenameError.unusableName("..."), "that name cannot be used as a file name", false),
            (CocoaLikeError(), "something went wrong", false),
        ]
        for (error, message, needsSettings) in cases {
            let problem = UserFacingError.problem(for: error)
            XCTAssertEqual(problem.message, message)
            XCTAssertEqual(problem.needsSettings, needsSettings, message)
            XCTAssertFalse(problem.message.contains("/"), "no paths")
        }
        XCTAssertEqual(UserFacingProblem(message: "the file is no longer there").sentence, "The file is no longer there.")
    }

    func testOnlyNonRetryableErrorsNotify() {
        XCTAssertFalse(UserFacingError.shouldNotify(AnalyzerError.unreachable("x")))
        XCTAssertFalse(UserFacingError.shouldNotify(AnalyzerError.rateLimited(retryAfter: 3)))
        XCTAssertFalse(UserFacingError.shouldNotify(AnalyzerError.serverError(status: 502, message: "")))
        XCTAssertTrue(UserFacingError.shouldNotify(AnalyzerError.notConfigured("x")))
        XCTAssertTrue(UserFacingError.shouldNotify(ImagePreparerError.unreadable("x")))
    }

    private struct CocoaLikeError: Error {}
}
