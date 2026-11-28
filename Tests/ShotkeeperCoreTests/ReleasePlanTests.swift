import XCTest
@testable import ShotkeeperCore

/// Seam 1 of the auto-update spec: `ReleasePlan.make` turns a tag, the previous release's tag and CHANGELOG.md into
/// what the release job needs, or one error line for the release log.
final class ReleasePlanTests: XCTestCase {
    private func changelog(_ name: String = "changelog-several.md") throws -> String {
        String(decoding: try Fixture.data(name), as: UTF8.self)
    }

    func testPlanForTheFirstRelease() throws {
        let plan = try ReleasePlan.make(tag: "v0.2.0", previousTag: nil, changelog: changelog())
        XCTAssertEqual(plan.marketingVersion, "0.2.0")
        XCTAssertEqual(plan.buildNumber, 200)
        XCTAssertEqual(plan.tag, "v0.2.0")
        XCTAssertEqual(plan.archiveName, "Shotkeeper-0.2.0.zip")
        XCTAssertEqual(plan.title, "Shotkeeper 0.2.0")
        XCTAssertEqual(plan.notesMarkdown, "First release with automatic updates.\n\n- Check for Updates… in the menu.")
    }

    /// The line the release log shows when `make` fails, or nil when it succeeds.
    private func errorLine(tag: String, previous: String? = nil, changelog: String? = nil) throws -> String? {
        let text = try changelog ?? self.changelog()
        do {
            _ = try ReleasePlan.make(tag: tag, previousTag: previous, changelog: text)
            return nil
        } catch {
            return error.message
        }
    }

    /// A changelog with one non-empty section per version, newest first.
    private func changelog(sections versions: [String]) -> String {
        "# Changelog\n\n" + versions.reversed().map { "## \($0) (2026-11-28)\n\n- Notes for \($0).\n" }.joined(separator: "\n")
    }

    private func buildNumber(_ tag: String) throws -> Int {
        try ReleasePlan.make(tag: tag, previousTag: nil, changelog: changelog(sections: [String(tag.dropFirst())])).buildNumber
    }

    func testBuildNumberIsMajorTimes10000PlusMinorTimes100PlusPatch() throws {
        XCTAssertEqual(try buildNumber("v0.1.0"), 100)
        XCTAssertEqual(try buildNumber("v0.2.0"), 200)
        XCTAssertEqual(try buildNumber("v0.2.1"), 201)
        XCTAssertEqual(try buildNumber("v0.10.0"), 1000)
        XCTAssertEqual(try buildNumber("v0.99.99"), 9999)
        XCTAssertEqual(try buildNumber("v1.0.0"), 10000)
        XCTAssertEqual(try buildNumber("v12.3.45"), 120345)
    }

    func testBuildNumberRisesWithEveryVersionStep() throws {
        // Ascending tags, each one patch, minor or major step above the last, including the 99 → next roll-overs.
        let tags = ["v0.1.0", "v0.1.1", "v0.1.99", "v0.2.0", "v0.9.0", "v0.10.0", "v0.99.0", "v0.99.99", "v1.0.0",
                    "v1.0.1", "v1.1.0", "v2.0.0", "v10.0.0"]
        let numbers = try tags.map(buildNumber)
        for (tag, (lower, higher)) in zip(tags.dropFirst(), zip(numbers, numbers.dropFirst())) {
            XCTAssertLessThan(lower, higher, "\(tag) must get a higher build number than the tag before it")
        }
        XCTAssertGreaterThan(numbers[0], 1, "every release is above the dev and CI build number 1")
    }

    func testVersionMustBeHigherThanThePreviousRelease() throws {
        XCTAssertEqual(try errorLine(tag: "v0.2.1", previous: "v0.2.1"),
                       "v0.2.1 is not higher than the previous release v0.2.1")
        XCTAssertEqual(try errorLine(tag: "v0.2.1", previous: "v0.3.0"),
                       "v0.2.1 is not higher than the previous release v0.3.0")
        XCTAssertEqual(try errorLine(tag: "v0.2.0", previous: "v0.2.1"),
                       "v0.2.0 is not higher than the previous release v0.2.1")
        XCTAssertEqual(try errorLine(tag: "v0.9.0", previous: "v0.10.0", changelog: changelog(sections: ["0.9.0"])),
                       "v0.9.0 is not higher than the previous release v0.10.0")
        XCTAssertNil(try errorLine(tag: "v0.2.1", previous: "v0.2.0"))
        XCTAssertNil(try errorLine(tag: "v0.10.0", previous: "v0.9.0", changelog: changelog(sections: ["0.10.0"])),
                     "0.10.0 is above 0.9.0: numbers, not text")
        XCTAssertNil(try errorLine(tag: "v0.2.10", previous: "v0.2.9"))
        XCTAssertNil(try errorLine(tag: "v0.2.0", previous: nil), "no previous release: the first one")
    }

    func testABadPreviousTagIsNamedAsThePreviousRelease() throws {
        XCTAssertEqual(try errorLine(tag: "v0.2.1", previous: "0.2.0"),
                       "Previous release: Tag 0.2.0 does not start with v (expected vMAJOR.MINOR.PATCH)")
        XCTAssertEqual(try errorLine(tag: "v0.2.1", previous: "v0.2.0-beta"),
                       "Previous release: Tag v0.2.0-beta has a pre-release or build suffix; releases are vMAJOR.MINOR.PATCH only")
    }

    private func notes(_ tag: String, _ file: String = "changelog-several.md") throws -> String {
        try ReleasePlan.make(tag: tag, previousTag: nil, changelog: changelog(file)).notesMarkdown
    }

    func testChangelogSectionIsTheOneForTheTagsVersion() throws {
        XCTAssertEqual(try notes("v0.2.1"), "- Fixed the `Undo` row after a rename.\n- Faster startup.", "a middle section")
        XCTAssertEqual(try notes("v0.3.0"), "Search got faster.", "the first section")
        XCTAssertEqual(try notes("v0.2.0"), "First release with automatic updates.\n\n- Check for Updates… in the menu.",
                       "the last section in the file")
        XCTAssertEqual(try notes("v0.2.10"), "- Ten.", "0.2.10, not its prefix 0.2.1")
    }

    func testMissingOrEmptyChangelogSectionFails() throws {
        XCTAssertEqual(try errorLine(tag: "v0.4.0"), "CHANGELOG.md has no section for 0.4.0")
        XCTAssertEqual(try errorLine(tag: "v0.2.2"), "CHANGELOG.md has no section for 0.2.2", "0.2.2 is not a prefix match")
        XCTAssertEqual(try errorLine(tag: "v0.2.1", changelog: changelog(sections: ["0.2.10"])),
                       "CHANGELOG.md has no section for 0.2.1", "0.2.10 does not count as 0.2.1")
        XCTAssertEqual(try errorLine(tag: "v0.2.1", changelog: changelog("changelog-empty-section.md")),
                       "CHANGELOG.md section 0.2.1 is empty")
        XCTAssertEqual(try errorLine(tag: "v0.2.0", changelog: ""), "CHANGELOG.md has no section for 0.2.0")
        XCTAssertEqual(try errorLine(tag: "v0.2.0", changelog: "# Changelog\n\n## 0.2.0 (2026-11-28)"),
                       "CHANGELOG.md section 0.2.0 is empty", "a heading at the end of the file")
        XCTAssertEqual(try errorLine(tag: "v0.2.0", changelog: "### 0.2.0 (2026-11-28)\n\n- Wrong level."),
                       "CHANGELOG.md has no section for 0.2.0", "only ## headings are sections")
    }

    func testSubheadingsStayInsideTheSection() throws {
        let text = "## 0.2.0 (2026-11-28)\n\n### Fixed\n\n- A bug.\n\n## 0.1.0 (2026-11-21)\n\n- Old.\n"
        XCTAssertEqual(try ReleasePlan.make(tag: "v0.2.0", previousTag: nil, changelog: text).notesMarkdown,
                       "### Fixed\n\n- A bug.")
    }

    func testWindowsLineEndingsAreAccepted() throws {
        let text = "## 0.2.0 (2026-11-28)\r\n\r\n- A bug.\r\n- Another.\r\n"
        XCTAssertEqual(try ReleasePlan.make(tag: "v0.2.0", previousTag: nil, changelog: text).notesMarkdown,
                       "- A bug.\n- Another.")
    }

    /// The HTML Sparkle shows for a 0.2.0 section with this body.
    private func html(_ body: String) throws -> String {
        try ReleasePlan.make(tag: "v0.2.0", previousTag: nil, changelog: "## 0.2.0 (2026-11-28)\n\n\(body)\n").notesHTML
    }

    func testHTMLHasParagraphsAndBulletLists() throws {
        XCTAssertEqual(try ReleasePlan.make(tag: "v0.2.0", previousTag: nil, changelog: changelog()).notesHTML,
                       "<p>First release with automatic updates.</p>\n<ul>\n<li>Check for Updates… in the menu.</li>\n</ul>")
        XCTAssertEqual(try html("One paragraph\nwrapped over two lines.\n\nA second paragraph."),
                       "<p>One paragraph wrapped over two lines.</p>\n<p>A second paragraph.</p>")
        XCTAssertEqual(try html("- First\n- Second item,\n  wrapped.\n\nAfter the list."),
                       "<ul>\n<li>First</li>\n<li>Second item, wrapped.</li>\n</ul>\n<p>After the list.</p>")
        XCTAssertEqual(try html("Before:\n- a\n- b\nAfter, no blank line."),
                       "<p>Before:</p>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n<p>After, no blank line.</p>")
        XCTAssertEqual(try html("- a\n\n- b"), "<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>",
                       "a blank line ends a list")
        XCTAssertEqual(try html("-not a bullet"), "<p>-not a bullet</p>")
    }

    func testHTMLHasInlineCode() throws {
        XCTAssertEqual(try ReleasePlan.make(tag: "v0.2.1", previousTag: nil, changelog: changelog()).notesHTML,
                       "<ul>\n<li>Fixed the <code>Undo</code> row after a rename.</li>\n<li>Faster startup.</li>\n</ul>")
        XCTAssertEqual(try html("Run `a` then `b`."), "<p>Run <code>a</code> then <code>b</code>.</p>")
        XCTAssertEqual(try html("Type `<b>&\"` here."), "<p>Type <code>&lt;b&gt;&amp;&quot;</code> here.</p>")
        XCTAssertEqual(try html("A lone ` backtick."), "<p>A lone ` backtick.</p>")
        XCTAssertEqual(try html("`a` and a lone `"), "<p><code>a</code> and a lone `</p>")
    }

    func testHTMLEscapesEverythingElse() throws {
        XCTAssertEqual(try html("<script>alert(\"hi\")</script>"),
                       "<p>&lt;script&gt;alert(&quot;hi&quot;)&lt;/script&gt;</p>")
        XCTAssertEqual(try html("Tom & Jerry's <b>"), "<p>Tom &amp; Jerry&#39;s &lt;b&gt;</p>")
        XCTAssertEqual(try html("- <img src=x onerror=alert(1)>"), "<ul>\n<li>&lt;img src=x onerror=alert(1)&gt;</li>\n</ul>")
        XCTAssertEqual(try html("&amp; stays as typed"), "<p>&amp;amp; stays as typed</p>")
        XCTAssertEqual(try html("### Fixed\n\n**bold** and [a link](https://example.com)"),
                       "<p>### Fixed</p>\n<p>**bold** and [a link](https://example.com)</p>", "other Markdown is plain text")
    }

    func testArchiveNameAndTitleCarryTheVersion() throws {
        let plan = try ReleasePlan.make(tag: "v1.10.3", previousTag: "v1.9.0", changelog: changelog(sections: ["1.10.3"]))
        XCTAssertEqual(plan.archiveName, "Shotkeeper-1.10.3.zip")
        XCTAssertEqual(plan.title, "Shotkeeper 1.10.3")
        XCTAssertEqual(plan.marketingVersion, "1.10.3")
        XCTAssertEqual(plan.tag, "v1.10.3")
    }

    func testOutputFilesAreTheMarkdownNotesAndTheHTMLNamedAfterTheZip() throws {
        let plan = try ReleasePlan.make(tag: "v0.2.1", previousTag: "v0.2.0", changelog: changelog())
        // generate_appcast pairs Shotkeeper-0.2.1.zip with Shotkeeper-0.2.1.html (same name, other extension).
        XCTAssertEqual(plan.outputFiles, [
            "notes.md": "- Fixed the `Undo` row after a rename.\n- Faster startup.\n",
            "Shotkeeper-0.2.1.html":
                "<ul>\n<li>Fixed the <code>Undo</code> row after a rename.</li>\n<li>Faster startup.</li>\n</ul>\n",
        ])
    }

    func testGitHubOutputLines() throws {
        let plan = try ReleasePlan.make(tag: "v0.2.1", previousTag: "v0.2.0", changelog: changelog())
        XCTAssertEqual(plan.githubOutput(directory: "/tmp/plan"), """
            version=0.2.1
            build_number=201
            tag=v0.2.1
            archive_name=Shotkeeper-0.2.1.zip
            title=Shotkeeper 0.2.1
            notes_markdown_file=/tmp/plan/notes.md
            notes_html_file=/tmp/plan/Shotkeeper-0.2.1.html

            """)
    }

    func testTagRejectionsEachHaveTheirOwnLine() throws {
        XCTAssertEqual(try errorLine(tag: "0.2.0"), "Tag 0.2.0 does not start with v (expected vMAJOR.MINOR.PATCH)")
        XCTAssertEqual(try errorLine(tag: "V0.2.0"), "Tag V0.2.0 does not start with v (expected vMAJOR.MINOR.PATCH)")
        XCTAssertEqual(try errorLine(tag: "v0.2"), "Tag v0.2 is not vMAJOR.MINOR.PATCH")
        XCTAssertEqual(try errorLine(tag: "v0.2.0.1"), "Tag v0.2.0.1 is not vMAJOR.MINOR.PATCH")
        XCTAssertEqual(try errorLine(tag: "v0..2"), "Tag v0..2 is not vMAJOR.MINOR.PATCH")
        XCTAssertEqual(try errorLine(tag: "v0.2.x"), "Tag v0.2.x is not vMAJOR.MINOR.PATCH")
        XCTAssertEqual(try errorLine(tag: "v0.2.0-beta.1"),
                       "Tag v0.2.0-beta.1 has a pre-release or build suffix; releases are vMAJOR.MINOR.PATCH only")
        XCTAssertEqual(try errorLine(tag: "v0.2.0+5"), "Tag v0.2.0+5 has a pre-release or build suffix; releases are vMAJOR.MINOR.PATCH only")
        XCTAssertEqual(try errorLine(tag: "v0.02.0"), "Tag v0.02.0 has a leading zero")
        XCTAssertEqual(try errorLine(tag: "v01.2.0"), "Tag v01.2.0 has a leading zero")
        XCTAssertEqual(try errorLine(tag: "v0.2.00"), "Tag v0.2.00 has a leading zero")
        XCTAssertEqual(try errorLine(tag: "v0.100.0"), "Tag v0.100.0: minor and patch must be 0-99 (build number MAJOR×10000+MINOR×100+PATCH)")
        XCTAssertEqual(try errorLine(tag: "v0.2.100"), "Tag v0.2.100: minor and patch must be 0-99 (build number MAJOR×10000+MINOR×100+PATCH)")
        XCTAssertEqual(try errorLine(tag: "v0.0.9"), "Tag v0.0.9 is below v0.1.0, the first version a release may have")
        XCTAssertEqual(try errorLine(tag: "v0.0.0"), "Tag v0.0.0 is below v0.1.0, the first version a release may have")
        XCTAssertEqual(try errorLine(tag: "v99999999999999999999.0.0"), "Tag v99999999999999999999.0.0: major version is too large")
        XCTAssertEqual(try errorLine(tag: "v1000000000000000.0.0"), "Tag v1000000000000000.0.0: major version is too large")
    }
}
