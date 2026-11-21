import XCTest
@testable import ShotkeeperCore

final class ExcludeRulesTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let file = URL(fileURLWithPath: "/Users/me/Desktop/Screenshot 2026-01-13 at 10.22.11.png")

    func testGlob() {
        XCTAssertTrue(Glob.matches(pattern: "*.png", name: "a.png"))
        XCTAssertTrue(Glob.matches(pattern: "screenshot*10.22*", name: "screenshot 2026 at 10.22.11.png"))
        XCTAssertTrue(Glob.matches(pattern: "a?c", name: "abc"))
        XCTAssertFalse(Glob.matches(pattern: "a?c", name: "abbc"))
        XCTAssertFalse(Glob.matches(pattern: "*.jpg", name: "a.png"))
        XCTAssertTrue(Glob.matches(pattern: "*", name: ""))
        XCTAssertTrue(Glob.matches(pattern: "**x*", name: "aaxbb"))
    }

    func testFilenameRules() {
        XCTAssertTrue(ExcludeRules.Rule(.filenameGlob, "*AT 10.22*").matches(file))
        XCTAssertFalse(ExcludeRules.Rule(.filenameGlob, "*.jpg").matches(file))
        XCTAssertTrue(ExcludeRules.Rule(.filenameContains, "2026-01").matches(file))
        XCTAssertFalse(ExcludeRules.Rule(.filenameContains, "bank").matches(file))
        XCTAssertFalse(ExcludeRules.Rule(.filenameContains, "").matches(file))
    }

    func testFolderRule() {
        XCTAssertTrue(ExcludeRules.Rule(.folder, "/Users/me/Desktop").matches(file))
        XCTAssertTrue(ExcludeRules.Rule(.folder, "/Users/me/Desktop/").matches(file))
        XCTAssertTrue(ExcludeRules.Rule(.folder, "/Users/me").matches(file))
        XCTAssertFalse(ExcludeRules.Rule(.folder, "/Users/me/Desk").matches(file))
        XCTAssertFalse(ExcludeRules.Rule(.folder, "/Users/me/Desktop/Private").matches(file))
        XCTAssertFalse(ExcludeRules.Rule(.folder, "").matches(file))
    }

    func testPauseWindow() {
        var rules = ExcludeRules()
        XCTAssertNil(rules.exclusion(for: file, capturedAt: now, now: now))
        rules.pause(for: 600, from: now)
        let until = now.addingTimeInterval(600)
        XCTAssertEqual(rules.exclusion(for: file, capturedAt: now, now: now), .paused(until: until))
        // Captured during the pause but processed after it ended: still skipped.
        XCTAssertEqual(rules.exclusion(for: file, capturedAt: now.addingTimeInterval(60), now: now.addingTimeInterval(3600)),
                       .paused(until: until))
        // Captured before the pause, processed after: not skipped.
        XCTAssertNil(rules.exclusion(for: file, capturedAt: now.addingTimeInterval(-60), now: now.addingTimeInterval(3600)))
        XCTAssertFalse(rules.isPaused(at: until))
        rules.resume()
        XCTAssertNil(rules.exclusion(for: file, capturedAt: now, now: now))
    }

    func testRuleExclusionAndCodable() throws {
        let rules = ExcludeRules(rules: [.init(.filenameContains, "10.22")])
        XCTAssertEqual(rules.exclusion(for: file, capturedAt: nil, now: now), .rule(.init(.filenameContains, "10.22")))
        let decoded = try JSONDecoder().decode(ExcludeRules.self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded, rules)
        XCTAssertEqual(try JSONDecoder().decode(ExcludeRules.self, from: Data("{}".utf8)), ExcludeRules())
    }
}
