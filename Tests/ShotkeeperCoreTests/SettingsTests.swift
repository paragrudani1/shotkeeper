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
        XCTAssertEqual(s.uploadGrants, [])
        XCTAssertTrue(s.showRenameToast)
        XCTAssertFalse(s.playRenameSound)
    }

    /// Files from before per-destination consent: the old flag counts only for the stored backend's destination.
    func testUpgradeSeedsConsentOnlyForTheStoredBackend() throws {
        func decode(_ backend: String, flag: Bool, url: String? = nil) -> AppSettings {
            let urlField = url.map { ",\"customEndpointURL\":\"\($0)\"" } ?? ""
            return AppSettings.decode(Data("{\"backend\":\"\(backend)\",\"hasSeenPrivacyNotice\":\(flag)\(urlField)}".utf8))
        }
        let clairic = decode("clairic", flag: true)
        XCTAssertEqual(clairic.uploadGrants, [AppSettings.UploadGrant(destination: .cloudflare, grantedAt: .distantPast)],
                       "an upgraded Clairic user keeps working; .distantPast covers screenshots already sent")
        XCTAssertTrue(clairic.hasSeenPrivacyNotice, "setup does not open again")

        let local = decode("localInkling", flag: true)
        XCTAssertEqual(local.acceptedUploadDestinations, [], "the old setup set the flag for local too: no upload consent")
        XCTAssertTrue(local.hasSeenPrivacyNotice)

        let custom = decode("customEndpoint", flag: true, url: "http://LLM.lan:8080/v1")
        XCTAssertEqual(custom.uploadGrants, [], "a custom endpoint is not migrated: Settings asks once, naming it")

        XCTAssertEqual(decode("clairic", flag: false).uploadGrants, [])

        // Once the key exists it is the truth: an emptied list is not re-seeded from the old flag.
        var saved = clairic
        saved.uploadGrants = []
        XCTAssertEqual(AppSettings.decode(try saved.encoded()).uploadGrants, [])
    }

    func testSettingsFileFromBeforeTheToastSettingsStillDecodes() throws {
        // Written by the build at 7720981 (no toast/sound keys).
        let json = """
        {"backend":"clairic","clairicAccountID":"acct","hasSeenPrivacyNotice":true,"idleTimeoutMinutes":10,
         "launchAtLogin":false,"maxImageLongSide":1280,"minTitleConfidence":0.5,"moveEnabled":false,
         "renameEnabled":true,"requestsPerMinute":30,"writeFinderMetadata":true,"excludeRules":{"rules":[]}}
        """
        let s = AppSettings.decode(Data(json.utf8))
        XCTAssertEqual(s.clairicAccountID, "acct")
        XCTAssertTrue(s.hasSeenPrivacyNotice)
        XCTAssertTrue(s.showRenameToast)
        XCTAssertFalse(s.playRenameSound)

        var changed = s
        changed.showRenameToast = false
        changed.playRenameSound = true
        XCTAssertEqual(AppSettings.decode(try changed.encoded()), changed)
    }

    /// PR 4 added the filename style and the search shortcut. A file from before (written at `7cf9df5`) keeps
    /// every value it had and gets the defaults for the new keys; bad new values fall back per key.
    func testSettingsFileFromBeforeTheFilenameStyleAndShortcutStillDecodes() throws {
        let json = """
        {"backend":"clairic","clairicAccountID":"acct","excludeRules":{"rules":[]},"hasSeenPrivacyNotice":true,
         "idleTimeoutMinutes":10,"launchAtLogin":true,"maxImageLongSide":1280,"minTitleConfidence":0.5,
         "moveEnabled":false,"playRenameSound":true,"renameEnabled":true,"requestsPerMinute":30,
         "showRenameToast":false,"uploadGrants":[{"destination":"cloudflare","grantedAt":"2026-11-22T03:00:00Z"}],
         "writeFinderMetadata":true}
        """
        let s = AppSettings.decode(Data(json.utf8))
        XCTAssertEqual(s.clairicAccountID, "acct")
        XCTAssertTrue(s.launchAtLogin)
        XCTAssertFalse(s.showRenameToast)
        XCTAssertTrue(s.playRenameSound)
        XCTAssertEqual(s.uploadGrants.map(\.destination), [.cloudflare])
        XCTAssertEqual(s.filenameStyle, FilenameStyle(casing: .sentence, datePrefix: false))
        XCTAssertEqual(s.searchShortcut, .defaultSearch)

        var changed = s
        changed.filenameStyle = FilenameStyle(casing: .kebab, datePrefix: true)
        changed.searchShortcut = HotKeyShortcut(keyCode: KeyCode.k, modifiers: [.control, .option])
        XCTAssertEqual(AppSettings.decode(try changed.encoded()), changed)

        let bad = AppSettings.decode(Data(#"{"filenameCasing":"SHOUTING","filenameDatePrefix":"yes"}"#.utf8))
        XCTAssertEqual(bad.filenameStyle, FilenameStyle())
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
        s.uploadGrants = [
            .init(destination: .cloudflare, grantedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            .init(destination: .customEndpoint, grantedAt: Date(timeIntervalSince1970: 1_800_000_100),
                  endpoint: CustomEndpointIdentity(url: URL(string: "http://127.0.0.1:8080/v1"))),
        ]
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
