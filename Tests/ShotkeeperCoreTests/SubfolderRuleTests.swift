import XCTest
@testable import ShotkeeperCore

/// The pure router (`SubfolderRule.relativeFolder`): which folders below the organized folder a screenshot goes to.
/// The pipeline's own tests (`ScreenshotProcessorTests`, "Subfolders") check the same rules on disk.
final class SubfolderRuleTests: XCTestCase {
    /// No existing folders anywhere.
    private let none: ([String]) -> [String] = { _ in [] }

    func testByTypeUsesFixedPluralFolderNames() {
        let expected: [ContentType: String] = [.tweet: "Tweets", .article: "Articles", .code: "Code", .chat: "Chats",
                                               .receipt: "Receipts", .design: "Designs", .other: "Other"]
        for type in ContentType.allCases {
            XCTAssertEqual(SubfolderRule.byType.relativeFolder(contentType: type, source: "Slack", existing: none),
                           [expected[type]!], "\(type)")
        }
    }

    func testOffIsTheOrganizedFolderItself() {
        XCTAssertEqual(SubfolderRule.off.relativeFolder(contentType: .receipt, source: "Mail", existing: none), [])
    }

    func testBySourceNamesANewFolderFromTheSpelling() {
        XCTAssertEqual(SubfolderRule.bySource.relativeFolder(contentType: .chat, source: "Slack", existing: none), ["Slack"])
        XCTAssertEqual(SubfolderRule.byTypeThenSource.relativeFolder(contentType: .chat, source: "Slack", existing: none),
                       ["Chats", "Slack"])
    }

    func testAnExistingFolderWithTheSameSourceKeyIsReused() {
        let existing: ([String]) -> [String] = { parent in
            switch parent {
            case []: return ["slack", "x.com", "Receipts"]
            case ["Chats"]: return ["github.com", "GitHub"]
            default: return []
            }
        }
        XCTAssertEqual(SubfolderRule.bySource.relativeFolder(contentType: .tweet, source: "X", existing: existing), ["x.com"])
        XCTAssertEqual(SubfolderRule.bySource.relativeFolder(contentType: .chat, source: "Slack", existing: existing), ["slack"])
        // Several matches: the first alphabetically wins ("GitHub" < "github.com").
        XCTAssertEqual(SubfolderRule.byTypeThenSource.relativeFolder(contentType: .chat, source: "www.github.com",
                                                                     existing: existing), ["Chats", "GitHub"])
    }

    func testATypeFolderIsReusedInAnyLetterCase() {
        let existing: ([String]) -> [String] = { $0 == [] ? ["receipts"] : [] }
        XCTAssertEqual(SubfolderRule.byType.relativeFolder(contentType: .receipt, source: nil, existing: existing),
                       ["receipts"])
        XCTAssertEqual(SubfolderRule.byTypeThenSource.relativeFolder(contentType: .receipt, source: "Mail", existing: existing),
                       ["receipts", "Mail"])
    }

    func testTheNonAnswerListIsFixed() {
        XCTAssertEqual(SubfolderRule.unknownSources, ["unknown", "n/a", "none", "screenshot", "image", "desktop"])
    }

    func testAnUnknownSourceGoesToOtherOrStaysInTheTypeFolder() {
        for source in [nil, "", "  ", "Unknown", "N/A", "none", "Screenshot", "IMAGE", "Desktop", ".", "..", "...", " . "] {
            XCTAssertEqual(SubfolderRule.bySource.relativeFolder(contentType: .chat, source: source, existing: none),
                           ["Other"], "\(String(describing: source))")
            XCTAssertEqual(SubfolderRule.byTypeThenSource.relativeFolder(contentType: .chat, source: source, existing: none),
                           ["Chats"], "\(String(describing: source))")
        }
    }

    func testASourceNamedLikeATypeFolderIsNotSpecial() {
        let existing: ([String]) -> [String] = { $0 == [] ? ["Code"] : [] }
        XCTAssertEqual(SubfolderRule.bySource.relativeFolder(contentType: .chat, source: "code", existing: existing), ["Code"])
    }

    // MARK: Folder names from hostile sources

    func testSlashesAndColonsBecomeADash() {
        XCTAssertEqual(SubfolderRule.folderName(forSource: "x/y"), "x - y")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Notes: Work"), "Notes - Work")
        // A run of separators counts once.
        XCTAssertEqual(SubfolderRule.folderName(forSource: "https://github.com/me"), "https - github.com - me")
    }

    func testPathTraversalNeverLeavesTheFolder() {
        XCTAssertNil(SubfolderRule.folderName(forSource: ".."))
        XCTAssertNil(SubfolderRule.folderName(forSource: "."))
        // What is left of path syntax alone ("-") is unknown too.
        XCTAssertNil(SubfolderRule.folderName(forSource: "../.."))
        XCTAssertNil(SubfolderRule.folderName(forSource: "/"))
        // Dashes, dots and spaces are trimmed at both ends.
        XCTAssertEqual(SubfolderRule.folderName(forSource: "../../etc"), "etc")
        for name in ["../..", "../../etc", "/", "a/../b", "/tmp"] {
            let folder = SubfolderRule.folderName(forSource: name)
            XCTAssertFalse(folder?.contains("/") ?? false, name)
            XCTAssertNotEqual(folder, "..", name)
            XCTAssertFalse(folder?.hasPrefix(".") ?? false, name)
        }
    }

    func testLeadingDotsAndWwwAreDropped() {
        XCTAssertEqual(SubfolderRule.folderName(forSource: ".hidden"), "hidden")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "...Slack.."), "Slack")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "www.nytimes.com"), "nytimes.com")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "  Google   Chrome  "), "Google Chrome")
    }

    func testControlAndBidiCharactersAreDropped() {
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Sl\u{0}ack\u{7}\n"), "Slack")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "evil\u{202E}gnp.exe"), "evilgnp.exe")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Sl\u{2028}ack"), "Sl ack")  // line separator is whitespace
        XCTAssertNil(SubfolderRule.folderName(forSource: "\u{1}\u{2}"))
    }

    func testInvisibleFormatCharactersAreDropped() {
        // Unicode category Cf: invisible, and bidi ones can reorder or disguise a name.
        let cases: [(String, String)] = [
            ("Sla\u{200F}ck", "U+200F right-to-left mark"),
            ("\u{FEFF}Slack", "U+FEFF byte order mark"),
            ("Sl\u{00AD}ack", "U+00AD soft hyphen"),
            ("Sla\u{2060}ck", "U+2060 word joiner"),
            ("Slack\u{061C}", "U+061C Arabic letter mark"),
            ("\u{200E}Slack", "U+200E left-to-right mark"),
            ("Sl\u{200B}ack", "U+200B zero-width space"),
            ("\u{2066}Slack\u{2069}", "U+2066/2069 isolates"),
        ]
        for (source, what) in cases {
            XCTAssertEqual(SubfolderRule.folderName(forSource: source), "Slack", what)
        }
        XCTAssertNil(SubfolderRule.folderName(forSource: "\u{200E}\u{FEFF}\u{00AD}"))
    }

    func testAnLtrMarkBeforeSlackReusesTheSlackFolder() {
        let existing: ([String]) -> [String] = { $0 == [] ? ["Slack"] : [] }
        XCTAssertEqual(SubfolderRule.bySource.relativeFolder(contentType: .chat, source: "\u{200E}Slack",
                                                             existing: existing), ["Slack"])
        XCTAssertEqual(SubfolderRule.bySource.relativeFolder(contentType: .chat, source: "\u{200E}Slack", existing: none),
                       ["Slack"])
    }

    func testAnEmojiZwjSequenceIsKept() {
        // U+200D joins the family emoji; U+200C/U+200D are the format characters that stay.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        XCTAssertEqual(SubfolderRule.folderName(forSource: family), family)
        XCTAssertEqual(SubfolderRule.folderName(forSource: "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308} Pride"),
                       "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308} Pride")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "\u{0645}\u{06CC}\u{200C}\u{062E}"),
                       "\u{0645}\u{06CC}\u{200C}\u{062E}")  // Persian needs ZWNJ
    }

    func testWhitespaceCollapsesBeforeControlCharactersAreDropped() {
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Google\nChrome"), "Google Chrome")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Google\tChrome"), "Google Chrome")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Google\r\nChrome"), "Google Chrome")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Google \u{0} Chrome"), "Google Chrome")
    }

    func testDashesSpacesAndDotsAreTrimmedAtBothEnds() {
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Mail:"), "Mail")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "/Mail/"), "Mail")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "-- Mail --"), "Mail")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Notes: Work"), "Notes - Work")
        // After the 60-character cut too: the cut lands just after a " -" from a colon.
        XCTAssertEqual(SubfolderRule.folderName(forSource: String(repeating: "a", count: 58) + ":b"),
                       String(repeating: "a", count: 58))
    }

    func testEmojiAndAccentsAreKept() {
        XCTAssertEqual(SubfolderRule.folderName(forSource: "Café 🍕"), "Café 🍕")
        XCTAssertEqual(SubfolderRule.folderName(forSource: "👨‍👩‍👧‍👦 Family"), "👨‍👩‍👧‍👦 Family")
    }

    func testLongNamesAreCutAtACharacterBoundary() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(SubfolderRule.folderName(forSource: long), String(repeating: "a", count: 60))
        // 60 family emoji are 1500 bytes: the 255-byte limit cuts first, never inside an emoji.
        let family = "👨‍👩‍👧‍👦"
        let emoji = SubfolderRule.folderName(forSource: String(repeating: family, count: 300))
        XCTAssertEqual(emoji, String(repeating: family, count: 255 / family.utf8.count))
        // A cut that ends on a space or dot is trimmed again.
        XCTAssertEqual(SubfolderRule.folderName(forSource: String(repeating: "a", count: 59) + " b"),
                       String(repeating: "a", count: 59))
    }

    func testHostileSourcesRouteInsideTheOrganizedFolder() {
        for source in ["../..", "x/y", ".hidden", "🍕", String(repeating: "z", count: 300), "..", "/"] {
            let path = SubfolderRule.byTypeThenSource.relativeFolder(contentType: .code, source: source, existing: none)
            XCTAssertEqual(path.first, "Code", source)
            for component in path {
                XCTAssertFalse(component.isEmpty || component.contains("/") || component.hasPrefix("."), source)
                XCTAssertLessThanOrEqual(component.count, 60, source)
                XCTAssertLessThanOrEqual(component.utf8.count, 255, source)
            }
        }
    }
}

/// The words of Settings › General's "Sort into subfolders" rows (design §4), tested here so the app only lays them out.
final class SubfolderSettingsTextTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_795_278_240)  // 2026-11-21 16:24 UTC
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func example(_ rule: SubfolderRule, _ style: FilenameStyle = FilenameStyle(casing: .sentence, datePrefix: false),
                         rename: Bool = true) -> String? {
        SubfolderSettingsText.example(rule: rule, folderName: "Screenshots", style: style, renameEnabled: rename,
                                      capturedAt: date, timeZone: utc)
    }

    func testPickerChoices() {
        XCTAssertEqual(SubfolderRule.allCases.map(SubfolderSettingsText.title),
                       ["Off", "By type", "By app or site", "By type, then app or site"])
    }

    func testExamplePerRule() {
        XCTAssertNil(example(.off))
        XCTAssertEqual(example(.byType), "Screenshots › Receipts › Invoice from Acme.png")
        XCTAssertEqual(example(.bySource), "Screenshots › Mail › Invoice from Acme.png")
        XCTAssertEqual(example(.byTypeThenSource), "Screenshots › Receipts › Mail › Invoice from Acme.png")
    }

    func testExampleFollowsTheFilenameStyle() {
        XCTAssertEqual(example(.byType, FilenameStyle(casing: .kebab, datePrefix: false)),
                       "Screenshots › Receipts › invoice-from-acme.png")
        XCTAssertEqual(example(.byType, FilenameStyle(casing: .title, datePrefix: true)),  // title case keeps "from"
                       "Screenshots › Receipts › 2026-11-21 Invoice from Acme.png")
        // Renaming off: the screenshot keeps its macOS name.
        XCTAssertEqual(example(.byType, rename: false), "Screenshots › Receipts › Screenshot 2026-11-21 at 16.24.00.png")
    }

    func testNotePerRule() {
        XCTAssertNil(SubfolderSettingsText.note(for: .off))
        XCTAssertEqual(SubfolderSettingsText.note(for: .byType),
                       "Folders: Tweets, Articles, Code, Chats, Receipts, Designs and Other.")
        XCTAssertEqual(SubfolderSettingsText.note(for: .bySource),
                       "One folder per app or site. Screenshots from an unknown app go to Other.")
        XCTAssertEqual(SubfolderSettingsText.note(for: .byTypeThenSource),
                       "Screenshots from an unknown app stay in the type folder.")
        XCTAssertEqual(SubfolderSettingsText.leftAlone, "Screenshots already there stay where they are.")
    }

    func testFolderProblems() throws {
        XCTAssertEqual(SubfolderSettingsText.warning(.missing, folderName: "Screenshots"),
                       "Can't find “Screenshots”. Choose the organized folder again above.")
        XCTAssertEqual(SubfolderSettingsText.warning(.unreadable, folderName: "Screenshots"),
                       "Shotkeeper can't open “Screenshots”. Allow access in Finder (Get Info › Sharing & Permissions), or choose another folder.")
        XCTAssertNil(SubfolderSettingsText.warning(.ok, folderName: "Screenshots"))

        let dir = try TempDir()
        XCTAssertEqual(OrganizedFolderStatus.check(dir.url), .ok)
        XCTAssertEqual(OrganizedFolderStatus.check(dir.url.appendingPathComponent("gone")), .missing)
        let file = try dir.file("Screenshots", contents: "not a folder")
        XCTAssertEqual(OrganizedFolderStatus.check(file), .missing)
    }
}
