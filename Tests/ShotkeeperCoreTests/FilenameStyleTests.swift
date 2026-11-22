import XCTest
@testable import ShotkeeperCore

final class FilenameStyleTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-11-21 16:24 UTC.
    private let date = Date(timeIntervalSince1970: 1_795_278_240)

    private func stem(_ title: String, _ casing: FilenameStyle.Casing, date datePrefix: Bool = false,
                      capturedAt: Date? = nil, timeZone: TimeZone? = nil) -> String? {
        FilenameStyle(casing: casing, datePrefix: datePrefix)
            .stem(from: title, capturedAt: capturedAt ?? date, timeZone: timeZone ?? utc)
    }

    func testDefaultIsSentenceCaseWithoutDate() {
        XCTAssertEqual(FilenameStyle(), FilenameStyle(casing: .sentence, datePrefix: false))
        XCTAssertEqual(AppSettings().filenameStyle, FilenameStyle())
        XCTAssertEqual(FilenameStyle.example(.sentence), "Tweet semiconductor flashcards")
        XCTAssertEqual(FilenameStyle.example(.title), "Tweet Semiconductor Flashcards")
        XCTAssertEqual(FilenameStyle.example(.kebab), "tweet-semiconductor-flashcards")
    }

    func testSentenceCaseRaisesOnlyTheFirstLetterAndKeepsProperNounsAndAcronyms() {
        XCTAssertEqual(stem("tweet semiconductor flashcards", .sentence), "Tweet semiconductor flashcards")
        XCTAssertEqual(stem("Invoice from Acme Cloud for November", .sentence), "Invoice from Acme Cloud for November")
        XCTAssertEqual(stem("iPhone 15 battery settings", .sentence), "iPhone 15 battery settings")
        XCTAssertEqual(stem("macOS update notes", .sentence), "macOS update notes")
        XCTAssertEqual(stem("PDF export dialog", .sentence), "PDF export dialog")
        XCTAssertEqual(stem("42 unread emails in Gmail", .sentence), "42 unread emails in Gmail")
        XCTAssertEqual(stem("éclair recipe card", .sentence), "Éclair recipe card")
    }

    func testTitleCaseKeepsMinorWordsAcronymsAndMixedCase() {
        XCTAssertEqual(stem("invoice from acme for the month of november", .title),
                       "Invoice from Acme for the Month of November")
        XCTAssertEqual(stem("the state of AI in 2026", .title), "The State of AI in 2026")
        XCTAssertEqual(stem("iPhone settings for wi-fi", .title), "iPhone Settings for Wi-Fi")
        XCTAssertEqual(stem("notes to sign up for", .title), "Notes to Sign up For", "the last word is raised")
        XCTAssertEqual(stem("Acme/the march invoice", .title), "Acme - The March Invoice", "a phrase after \" - \" starts raised")
        XCTAssertEqual(stem("GitHub PR review for v1.2", .title), "GitHub PR Review for v1.2")
        XCTAssertEqual(stem("Mission Control in macOS", .title), "Mission Control in macOS")
    }

    func testKebabCaseLowercasesJoinsAndDropsPunctuation() {
        XCTAssertEqual(stem("Tweet semiconductor flashcards", .kebab), "tweet-semiconductor-flashcards")
        XCTAssertEqual(stem("PDF export in macOS", .kebab), "pdf-export-in-macos")
        XCTAssertEqual(stem("Invoice #42 (Acme) – paid!", .kebab), "invoice-42-acme-paid")
        XCTAssertEqual(stem("Parag's notes, v1.2 release", .kebab), "parags-notes-v1.2-release")
        XCTAssertEqual(stem("Acme/March invoice", .kebab), "acme-march-invoice", "the sanitizer's \" - \" is one dash")
        XCTAssertEqual(stem("COVID-19 dashboard", .kebab), "covid-19-dashboard")
    }

    func testNonLatinTextIsKept() {
        // Caseless scripts are unchanged; Cyrillic and Greek follow the casing rules; combining marks stay.
        XCTAssertEqual(stem("東京タワー 夜景", .sentence), "東京タワー 夜景")
        XCTAssertEqual(stem("東京タワー 夜景", .title), "東京タワー 夜景")
        XCTAssertEqual(stem("東京タワー 夜景", .kebab), "東京タワー-夜景")
        XCTAssertEqual(stem("счёт за ноябрь", .sentence), "Счёт за ноябрь")
        XCTAssertEqual(stem("счёт за ноябрь", .title), "Счёт За Ноябрь")
        XCTAssertEqual(stem("Счёт за ноябрь", .kebab), "счёт-за-ноябрь")
        XCTAssertEqual(stem("हिंदी नोट्स सूची", .kebab), "हिंदी-नोट्स-सूची")
        XCTAssertEqual(stem("فاتورة شهر نوفمبر", .kebab), "فاتورة-شهر-نوفمبر")
        XCTAssertEqual(stem("Launch plan 🚀 notes", .kebab), "launch-plan-🚀-notes")
    }

    func testDatePrefixUsesTheCaptureDayInTheTimeZone() {
        XCTAssertEqual(stem("Tweet semiconductor flashcards", .sentence, date: true),
                       "2026-11-21 Tweet semiconductor flashcards")
        XCTAssertEqual(stem("Tweet semiconductor flashcards", .title, date: true),
                       "2026-11-21 Tweet Semiconductor Flashcards")
        XCTAssertEqual(stem("Tweet semiconductor flashcards", .kebab, date: true),
                       "2026-11-21-tweet-semiconductor-flashcards")
        // 16:24 UTC is already the next day in Tokyo.
        XCTAssertEqual(stem("Receipt", .sentence, date: true, timeZone: TimeZone(identifier: "Asia/Tokyo")),
                       "2026-11-22 Receipt")
        XCTAssertEqual(FilenameStyle(casing: .sentence, datePrefix: true).stem(from: "Receipt", capturedAt: nil, timeZone: utc),
                       "Receipt", "no known date, no prefix")
    }

    func testADateAlreadyAtTheStartIsKeptAndNotDoubled() {
        XCTAssertEqual(stem("2026-11-21 Tweet flashcards", .sentence, date: true), "2026-11-21 Tweet flashcards")
        XCTAssertEqual(stem("2026-11-20 tweet flashcards", .sentence, date: true), "2026-11-20 Tweet flashcards",
                       "the user's own date wins, and the words after it are styled")
        XCTAssertEqual(stem("2026-11-21 Tweet flashcards", .kebab, date: true), "2026-11-21-tweet-flashcards")
        XCTAssertEqual(stem("2026-11-21-tweet-flashcards", .title), "2026-11-21 Tweet-Flashcards")
        XCTAssertEqual(stem("2026-11-21", .sentence, date: true), "2026-11-21")
        XCTAssertEqual(stem("2026-11-210 units", .sentence, date: true), "2026-11-21 2026-11-210 units",
                       "not a date followed by a word")
        XCTAssertEqual(stem("2026-11-2 foo", .sentence, date: true), "2026-11-2 Foo", "a one-digit day is a date too")
        XCTAssertEqual(stem("2026-1-5-notes", .kebab, date: true), "2026-1-5-notes")
    }

    /// "Edit name" passes no capture date: a typed date is kept, a removed one stays removed.
    func testATypedNameKeepsOrDropsTheDateAsTyped() {
        let style = FilenameStyle(casing: .sentence, datePrefix: true)
        XCTAssertEqual(style.stem(from: "acme invoice", capturedAt: nil, timeZone: utc), "Acme invoice")
        XCTAssertEqual(style.stem(from: "2026-11-21 acme invoice", capturedAt: nil, timeZone: utc), "2026-11-21 Acme invoice")
    }

    func testSentenceCaseLeavesDomainsAndVersionsFirst() {
        XCTAssertEqual(stem("x.com thread about chips", .sentence), "x.com thread about chips")
        XCTAssertEqual(stem("v1.2 release notes", .sentence), "v1.2 release notes")
        XCTAssertEqual(stem("3d printer settings", .sentence), "3d printer settings")
    }

    /// Styling a styled name again (the pipeline on a renamed file, or "Edit name" + Save without changes) changes
    /// nothing, also at the length cap and with the date.
    func testStylingIsIdempotentAtTheCap() throws {
        let titles = [String(repeating: "word ", count: 40), String(repeating: "Acme invoice for November ", count: 6),
                      "a" + String(repeating: "b", count: 120), String(repeating: "東京タワー ", count: 30)]
        for title in titles {
            for casing in FilenameStyle.Casing.allCases {
                for withDate in [false, true] {
                    let style = FilenameStyle(casing: casing, datePrefix: withDate)
                    let first = try XCTUnwrap(style.stem(from: title, capturedAt: date, timeZone: utc))
                    XCTAssertLessThanOrEqual(first.utf16.count, 80)
                    XCTAssertEqual(style.stem(from: first, capturedAt: date, timeZone: utc), first, "\(casing) \(withDate) pipeline")
                    XCTAssertEqual(style.stem(from: first, capturedAt: nil, timeZone: utc), first, "\(casing) \(withDate) edit name")
                    if casing == .kebab { XCTAssertFalse(first.hasSuffix("-"), first) }
                }
            }
        }
        // Kebab-case backs off to the last "-" at the cap.
        let kebab = try XCTUnwrap(FilenameStyle(casing: .kebab).stem(from: String(repeating: "sentence ", count: 12),
                                                                     capturedAt: nil, timeZone: utc))
        XCTAssertTrue(kebab.hasSuffix("sentence"), kebab)
    }

    func testKebabCaseNeverReturnsAnEmptyName() {
        for title in ["©️", "™", "®", "‼️", "#️⃣", "—", "« »"] {
            let result = FilenameStyle(casing: .kebab).stem(from: title, capturedAt: nil, timeZone: utc)
            XCTAssertTrue(result == nil || !(result ?? "").isEmpty, "\(title) → \(String(describing: result))")
            if let result { XCTAssertFalse(result.hasPrefix("-") || result.hasSuffix("-"), result) }
        }
        XCTAssertEqual(FilenameStyle.cap("abc-def", maxLength: 5, separator: "-"), "abc")
    }

    func testSanitizerRulesStillApply() {
        XCTAssertNil(stem("Screenshot 2026-01-13 at 10.22.11", .kebab, date: true), "generic names are still refused")
        XCTAssertNil(stem("...", .title))
        XCTAssertEqual(stem("a/b: notes", .sentence), "A - b - notes")
    }

    func testLengthStaysWithinTheLimitIncludingTheDate() throws {
        let long = String(repeating: "word ", count: 40)
        for casing in FilenameStyle.Casing.allCases {
            for withDate in [false, true] {
                let result = try XCTUnwrap(stem(long, casing, date: withDate))
                XCTAssertLessThanOrEqual(result.utf16.count, FilenameSanitizer.defaultMaxLength, "\(casing) \(withDate)")
                XCTAssertFalse(result.hasSuffix(" ") || result.hasSuffix("-"), result)
                if withDate { XCTAssertTrue(result.hasPrefix("2026-11-21"), result) }
            }
        }
        // "ß" becomes "SS" when raised: still capped.
        let sharp = String(repeating: "ß", count: 80)
        XCTAssertLessThanOrEqual(try XCTUnwrap(stem(sharp, .sentence)).utf16.count, 80)
    }
}
