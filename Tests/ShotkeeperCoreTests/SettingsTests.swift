import XCTest
@testable import ShotkeeperCore

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = AppSettings()
        XCTAssertEqual(s.backend, .clairic)
        XCTAssertNil(s.clairicAccountID)
        XCTAssertEqual(s.idleTimeoutMinutes, 10)
        XCTAssertTrue(s.renameEnabled)
        XCTAssertFalse(s.moveEnabled)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertEqual(s.minTitleConfidence, 0.5)
        XCTAssertEqual(s.requestsPerMinute, 30)
        XCTAssertEqual(s.maxImageLongSide, 1280)
        XCTAssertEqual(s.excludeRules, ExcludeRules())
        XCTAssertFalse(s.hasSeenPrivacyNotice)
    }

    func testEmptyObjectDecodesToDefaults() {
        XCTAssertEqual(AppSettings.decode(Data("{}".utf8)), AppSettings())
    }

    func testMissingKeysKeepDefaultsAndUnknownKeysAreIgnored() {
        let json = """
        {"backend":"localInkling","requestsPerMinute":10,"localModelVariantID":"mlx-community/Inkling-2-Mini-4bit",
         "organizedFolder":"file:///Users/me/Shots/","someFutureSetting":{"x":1},
         "excludeRules":{"rules":[{"kind":"filenameContains","pattern":"bank"}]}}
        """
        let s = AppSettings.decode(Data(json.utf8))
        XCTAssertEqual(s.backend, .localInkling)
        XCTAssertEqual(s.requestsPerMinute, 10)
        XCTAssertEqual(s.localModelVariantID, "mlx-community/Inkling-2-Mini-4bit")
        XCTAssertEqual(s.organizedFolder?.path, "/Users/me/Shots")
        XCTAssertEqual(s.excludeRules.rules, [.init(.filenameContains, "bank")])
        XCTAssertEqual(s.idleTimeoutMinutes, 10)
        XCTAssertTrue(s.renameEnabled)
    }

    func testBadValuesFallBackPerKey() {
        let s = AppSettings.decode(Data(#"{"backend":"quantumCloud","renameEnabled":"yes","moveEnabled":true}"#.utf8))
        XCTAssertEqual(s.backend, .clairic)
        XCTAssertTrue(s.renameEnabled)
        XCTAssertTrue(s.moveEnabled)
        XCTAssertEqual(AppSettings.decode(Data("not json".utf8)), AppSettings())
    }

    func testRoundTrip() throws {
        var s = AppSettings()
        s.backend = .customEndpoint
        s.customEndpointURL = URL(string: "http://127.0.0.1:8080/v1")
        s.customModelName = "inkling"
        s.clairicAccountID = "abc123"
        s.excludeRules.pause(for: 600, from: Date(timeIntervalSince1970: 1_800_000_000))
        s.hasSeenPrivacyNotice = true
        XCTAssertEqual(AppSettings.decode(try s.encoded()), s)
        XCTAssertFalse(String(decoding: try s.encoded(), as: UTF8.self).lowercased().contains("token"), "no secrets in settings")
    }

    func testInMemoryCredentialStore() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.secret(for: .cloudflareAPIToken))
        try store.setSecret("s3cret", for: .cloudflareAPIToken)
        XCTAssertEqual(try store.secret(for: .cloudflareAPIToken), "s3cret")
        XCTAssertNil(try store.secret(for: .customEndpointAPIKey))
        try store.removeSecret(for: .cloudflareAPIToken)
        XCTAssertNil(try store.secret(for: .cloudflareAPIToken))
    }
}
