import XCTest
@testable import ShotkeeperCore

final class FilenameSanitizerTests: XCTestCase {
    private func stem(_ s: String, _ max: Int = 80) -> String? { FilenameSanitizer.stem(from: s, maxLength: max) }

    func testKeepsGoodTitleAndCasing() {
        XCTAssertEqual(stem("Tweet semiconductor flashcards"), "Tweet semiconductor flashcards")
        XCTAssertEqual(stem("iOS 18 release notes"), "iOS 18 release notes")
        XCTAssertEqual(stem("ALL CAPS stays"), "ALL CAPS stays")
    }

    func testPathAndReservedCharacters() {
        XCTAssertEqual(stem("Tweet: semiconductor flashcards"), "Tweet - semiconductor flashcards")
        XCTAssertEqual(stem("Q3/Q4 revenue chart"), "Q3 - Q4 revenue chart")
        XCTAssertEqual(stem(#"C:\Users\path"#), "C - Users - path")
        XCTAssertEqual(stem("a | b"), "a - b")
        XCTAssertEqual(stem(#"What is "this"? <b>*bold*</b>"#), "What is this b bold - b")
        XCTAssertNil(stem("/ : \\ * ? \" < > |"))
    }

    func testControlCharactersAndWhitespace() {
        XCTAssertEqual(stem("Line one\nline\ttwo\r\n"), "Line one line two")
        XCTAssertEqual(stem("  lots   of\u{00A0}\u{00A0}space  "), "lots of space")
        XCTAssertEqual(stem("bell\u{07}char"), "bell char")
        XCTAssertEqual(stem("para\u{2029}sep\u{2028}line"), "para sep line")
        XCTAssertEqual(stem("nul\u{0}byte"), "nul byte")
    }

    func testZeroWidthAndBidiCharactersAreStripped() {
        XCTAssertEqual(stem("zero\u{200B}width"), "zerowidth")
        XCTAssertEqual(stem("\u{FEFF}BOM title"), "BOM title")
        XCTAssertEqual(stem("joi\u{200D}ner and non\u{200C}joiner"), "joiner and nonjoiner")
        XCTAssertEqual(stem("rtl\u{202E}override\u{2066}isolate"), "rtloverrideisolate")
        XCTAssertEqual(stem("soft\u{00AD}hyphen"), "softhyphen")
    }

    func testEmojiAreKeptIncludingZWJSequences() {
        XCTAssertEqual(stem("Party plans 🎉"), "Party plans 🎉")
        XCTAssertEqual(stem("Family 👨‍👩‍👧 photo plan"), "Family 👨‍👩‍👧 photo plan")
        XCTAssertEqual(stem("Flag 🏳️‍🌈 parade"), "Flag 🏳️‍🌈 parade")
        XCTAssertEqual(stem("🎉"), "🎉")
    }

    func testUnicodeLettersAndNFC() {
        XCTAssertEqual(stem("Café menu"), "Café menu")
        let decomposed = "Cafe\u{0301} menu"
        let result = stem(decomposed)
        XCTAssertEqual(result, "Caf\u{00E9} menu")
        XCTAssertEqual(result?.unicodeScalars.count, 9, "must be NFC (precomposed é)")
        XCTAssertEqual(stem("東京の天気予報"), "東京の天気予報")
        XCTAssertEqual(stem("Привет мир заметки"), "Привет мир заметки")
    }

    func testLeadingAndTrailingTrim() {
        XCTAssertEqual(stem("...hidden file"), "hidden file")
        XCTAssertEqual(stem("--rm -rf notes"), "rm -rf notes")
        XCTAssertEqual(stem("- bullet title"), "bullet title")
        XCTAssertEqual(stem("Release notes v2.0."), "Release notes v2.0")
        XCTAssertEqual(stem("Notes ... "), "Notes")
        XCTAssertEqual(stem("Notes -"), "Notes")
        XCTAssertEqual(stem("COVID-19 dashboard"), "COVID-19 dashboard")
        XCTAssertEqual(stem("Pre- and post-"), "Pre- and post-")
    }

    func testReservedNames() {
        XCTAssertNil(stem("."))
        XCTAssertNil(stem(".."))
        XCTAssertNil(stem(""))
        XCTAssertNil(stem("   "))
        XCTAssertNil(stem("\u{200B}\u{200B}"))
        XCTAssertNil(stem("---"))
    }

    func testGenericTitles() {
        for generic in ["Screenshot", "screenshot", "Screen Shot", "Image", "Untitled", "untitled image", "A screenshot",
                        "The image", "No title", "Screenshot 2026-01-13 at 10.22.11", "Screen Shot 2026-01-13 at 10.22.11 PM",
                        "Copy of screenshot", "screen capture", "N/A", "unknown", "Picture.", "snapshot"] {
            XCTAssertNil(stem(generic), generic)
        }
        // Not generic: carries content words.
        XCTAssertEqual(stem("Screenshot of Xcode build error"), "Screenshot of Xcode build error")
        XCTAssertEqual(stem("Image editing tips"), "Image editing tips")
    }

    func testDigitsOnlyIsKeptButEmptyIsNot() {
        XCTAssertEqual(stem("404"), "404")
        XCTAssertNil(stem("?!"))
    }

    func testLengthCapPrefersWordBoundary() {
        let title = "Quarterly revenue dashboard showing regional breakdown for enterprise customers in Europe"
        let r = stem(title, 40)!
        XCTAssertLessThanOrEqual(r.utf16.count, 40)
        XCTAssertEqual(r, "Quarterly revenue dashboard showing")
        XCTAssertFalse(r.hasSuffix(" "))
    }

    func testLengthCapCutsLongWordWhenNoBoundary() {
        let r = stem(String(repeating: "a", count: 100), 80)!
        XCTAssertEqual(r.utf16.count, 80)
    }

    func testLengthCapNeverSplitsGraphemeClusters() {
        // Each family emoji is 8 UTF-16 units; 10 of them do not fit in 20.
        let families = String(repeating: "👨‍👩‍👧", count: 10)
        let r = stem(families, 20)!
        XCTAssertEqual(r, "👨‍👩‍👧👨‍👩‍👧")
        XCTAssertEqual(r.utf16.count, 16)
        // A flag (4 units) at the boundary.
        let flags = "ab" + String(repeating: "🇯🇵", count: 5)
        XCTAssertEqual(stem(flags, 8), "ab🇯🇵")
    }

    func testLengthCapDoesNotLeaveTrailingSpaceOrDot() {
        XCTAssertEqual(stem("Hello world. Next sentence", 12), "Hello world")
        XCTAssertEqual(stem("abcdef ghijkl", 7), "abcdef")
    }

    func testZeroOrNegativeMaxLength() {
        XCTAssertNil(stem("Anything", 0))
        XCTAssertNil(stem("Anything", -5))
    }

    func testDefaultMaxLengthIs80() {
        let r = FilenameSanitizer.stem(from: String(repeating: "word ", count: 40))!
        XCTAssertLessThanOrEqual(r.utf16.count, 80)
    }
}

final class TagNormalizerTests: XCTestCase {
    func testLowercasesTrimsDedupesAndStripsHash() {
        XCTAssertEqual(TagNormalizer.normalize(["Swift", "#swift", " SwiftUI ", "swift_ui", "ios"]),
                       ["swift", "swiftui", "swift ui", "ios"])
    }

    func testDropsLongGenericAndEmpty() {
        XCTAssertEqual(TagNormalizer.normalize(["", "  ", "screenshot", "image", "a very long tag with many words",
                                                String(repeating: "x", count: 40), "ok"]), ["ok"])
    }

    func testLimit() {
        let many = (1...20).map { "tag\($0)" }
        XCTAssertEqual(TagNormalizer.normalize(many).count, 8)
        XCTAssertEqual(TagNormalizer.normalize(many, limit: 3), ["tag1", "tag2", "tag3"])
    }

    func testKeepsNumbersAndUnicode() {
        XCTAssertEqual(TagNormalizer.normalize(["2026", "Café", "東京"]), ["2026", "café", "東京"])
    }
}
