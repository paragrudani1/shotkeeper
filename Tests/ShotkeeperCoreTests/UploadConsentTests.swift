import XCTest
@testable import ShotkeeperCore

/// `UploadConsent.decide`, the one consent decision (CODING_STANDARDS #2), against every path from the three PR 6
/// consent reviews, the upgrade cases and the clock edges.
final class UploadConsentTests: XCTestCase {
    let grantedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let endpointA = CustomEndpointIdentity(scheme: "http", host: "a.lan", port: 8080)
    let endpointB = CustomEndpointIdentity(scheme: "http", host: "b.lan", port: 8080)

    private var cloudflare: AppSettings.UploadGrant { .init(destination: .cloudflare, grantedAt: grantedAt) }
    private func custom(_ endpoint: CustomEndpointIdentity, at date: Date? = nil) -> AppSettings.UploadGrant {
        .init(destination: .customEndpoint, grantedAt: date ?? grantedAt, endpoint: endpoint)
    }
    private var before: Date { grantedAt.addingTimeInterval(-1) }
    private var after: Date { grantedAt.addingTimeInterval(1) }

    // MARK: Destination rule

    func testTheLocalModelIsAlwaysAllowed() {
        for date in [Date.distantPast, before, after] {
            XCTAssertEqual(UploadConsent.decide(target: .thisMac, grants: [], capturedAt: date), .allow)
        }
    }

    func testACloudTargetNeedsItsOwnGrant() {
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [], capturedAt: after), .skip(.destinationNotAllowed))
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [custom(endpointA)], capturedAt: after),
                       .skip(.destinationNotAllowed), "a custom grant does not cover Cloudflare")
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointA), grants: [cloudflare], capturedAt: after),
                       .skip(.destinationNotAllowed), "Cloudflare does not cover a custom endpoint")
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: after), .allow)
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointA), grants: [custom(endpointA)], capturedAt: after),
                       .allow)
    }

    /// Review 2: custom host A → B; scheme and port are part of the identity.
    func testACustomGrantCoversOnlyItsEndpointIdentity() {
        let others = [endpointB, CustomEndpointIdentity(scheme: "https", host: "a.lan", port: 8080),
                      CustomEndpointIdentity(scheme: "http", host: "a.lan", port: 9090)]
        for other in others {
            XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(other), grants: [custom(endpointA)], capturedAt: after),
                           .skip(.destinationNotAllowed), other.display)
        }
        // An endpoint without an identity (not http(s), no host) can never be allowed, whatever is stored.
        let nilEndpoint = AppSettings.UploadGrant(destination: .customEndpoint, grantedAt: .distantPast, endpoint: nil)
        XCTAssertEqual(UploadConsent.decide(target: .unidentifiedEndpoint, grants: [nilEndpoint, custom(endpointA)],
                                            capturedAt: after), .skip(.destinationNotAllowed))
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointA), grants: [nilEndpoint], capturedAt: after),
                       .skip(.destinationNotAllowed))
    }

    func testTheTargetFollowsTheSelectedBackend() {
        var settings = AppSettings()
        XCTAssertEqual(UploadTarget(settings: settings), .cloudflare)
        settings.backend = .localInkling
        XCTAssertEqual(UploadTarget(settings: settings), .thisMac)
        settings.backend = .customEndpoint
        XCTAssertEqual(UploadTarget(settings: settings), .unidentifiedEndpoint)
        settings.customEndpointURL = URL(string: "ftp://a.lan")
        XCTAssertEqual(UploadTarget(settings: settings), .unidentifiedEndpoint)
        settings.customEndpointURL = URL(string: "http://A.lan:8080/v1")
        XCTAssertEqual(UploadTarget(settings: settings), .customEndpoint(endpointA))
    }

    // MARK: Time rule and clock edges

    func testAFileTakenBeforeTheGrantIsSkipped() {
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: before),
                       .skip(.takenBeforeGrant(grantedAt: grantedAt)))
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: grantedAt), .allow,
                       "taken at the grant second counts as after")
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare],
                                            capturedAt: grantedAt.addingTimeInterval(-0.001)),
                       .skip(.takenBeforeGrant(grantedAt: grantedAt)))
    }

    /// Review 3 S1: an unreadable date fails closed.
    func testAnUnknownCaptureTimeFailsClosed() {
        let unknown = UploadConsent.effectiveCaptureTime(creationDate: nil, nameDate: nil)
        XCTAssertEqual(unknown, .distantPast)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: unknown),
                       .skip(.takenBeforeGrant(grantedAt: grantedAt)))
    }

    /// Review 3 S2: a copy, download or AirDrop gets a fresh creation date but keeps the screenshot name.
    func testTheEarlierOfCreationAndNameTimeCounts() {
        let named = grantedAt.addingTimeInterval(-86_400)
        let recreated = grantedAt.addingTimeInterval(3_600)
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(creationDate: recreated, nameDate: named), named)
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(creationDate: named, nameDate: recreated), named,
                       "a name claiming a later time never wins")
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(creationDate: recreated, nameDate: nil), recreated)
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(creationDate: nil, nameDate: named), named)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare],
                                            capturedAt: UploadConsent.effectiveCaptureTime(creationDate: recreated,
                                                                                           nameDate: named)),
                       .skip(.takenBeforeGrant(grantedAt: grantedAt)))
    }

    func testEffectiveCaptureTimeOfAFileReadsItsName() throws {
        let dir = try TempDir()
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let copied = try dir.file("Screenshot 2020-05-06 at 07.08.09.png") // created and modified now
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(of: copied, timeZone: utc),
                       Date(timeIntervalSince1970: 1_588_748_889))
        let gone = dir.url.appendingPathComponent("holiday.png")
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(of: gone, timeZone: utc), .distantPast, "nothing readable")
    }

    // MARK: Upgrade

    func testUpgradedSettings() {
        func decode(_ json: String) -> AppSettings { AppSettings.decode(Data(json.utf8)) }
        let clairic = decode(#"{"backend":"clairic","hasSeenPrivacyNotice":true}"#)
        XCTAssertEqual(UploadConsent.decide(settings: clairic, capturedAt: .distantPast), .allow,
                       "an upgraded Clairic user had already sent everything there")
        let custom = decode(#"{"backend":"customEndpoint","hasSeenPrivacyNotice":true,"customEndpointURL":"http://a.lan:8080"}"#)
        XCTAssertEqual(UploadConsent.decide(settings: custom, capturedAt: after), .skip(.destinationNotAllowed))
        var local = decode(#"{"backend":"localInkling","hasSeenPrivacyNotice":true}"#)
        XCTAssertEqual(UploadConsent.decide(settings: local, capturedAt: .distantPast), .allow)
        local.backend = .clairic
        XCTAssertEqual(UploadConsent.decide(settings: local, capturedAt: after), .skip(.destinationNotAllowed),
                       "the old flag with Local grants Cloudflare nothing")
        let broken = decode(#"{"backend":"clairic","hasSeenPrivacyNotice":true,"uploadGrants":"nonsense"}"#)
        XCTAssertEqual(broken.uploadGrants, [])
        XCTAssertEqual(UploadConsent.decide(settings: broken, capturedAt: after), .skip(.destinationNotAllowed))
    }

    func testRevokingNeverWidens() {
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: after), .allow)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [], capturedAt: after), .skip(.destinationNotAllowed))
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [], capturedAt: after,
                                            processExisting: .init(target: .cloudflare)), .skip(.destinationNotAllowed))
    }

    // MARK: Process Existing

    func testProcessExistingLiftsOnlyTheTimeRuleForItsOwnTarget() {
        let request = ProcessExistingAuthorization(target: .cloudflare)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: .distantPast,
                                            processExisting: request), .allow)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [], capturedAt: .distantPast,
                                            processExisting: request), .skip(.destinationNotAllowed),
                       "never the destination rule")
    }

    /// Review 3 B1, path 1: Process Existing on Local (held "not installed"), then setup → Clairic → Continue.
    func testARequestMadeOnLocalNeverCoversCloudflare() {
        let onLocal = ProcessExistingAuthorization(target: .thisMac)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: before,
                                            processExisting: onLocal), .skip(.takenBeforeGrant(grantedAt: grantedAt)))
    }

    /// Review 3 B1, path 2: a Cloudflare backlog draining to a custom endpoint allowed later.
    func testARequestMadeForCloudflareNeverCoversACustomEndpoint() {
        let forCloudflare = ProcessExistingAuthorization(target: .cloudflare)
        let grants = [cloudflare, custom(endpointA, at: after)]
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointA), grants: grants, capturedAt: before,
                                            processExisting: forCloudflare),
                       .skip(.takenBeforeGrant(grantedAt: after)))
        let forA = ProcessExistingAuthorization(target: .customEndpoint(endpointA))
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointB), grants: [custom(endpointB)], capturedAt: before,
                                            processExisting: forA), .skip(.takenBeforeGrant(grantedAt: grantedAt)),
                       "nor one endpoint's request another endpoint")
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointA), grants: [custom(endpointA)], capturedAt: before,
                                            processExisting: forA), .allow)
    }

    func testRequestsAreInvalidatedTogether() {
        let requests = ProcessExistingRequests()
        let clicked = requests.generation
        let request = try! XCTUnwrap(requests.request(for: .cloudflare, madeIn: clicked))
        XCTAssertEqual(requests.authorization(for: request), ProcessExistingAuthorization(target: .cloudflare))
        XCTAssertNil(requests.authorization(for: nil))
        requests.invalidateAll()
        XCTAssertNil(requests.authorization(for: request), "a destination change: every earlier request counts as none")
        XCTAssertNil(requests.request(for: .cloudflare, madeIn: clicked), "changed during the scan: no request")
        let again = try! XCTUnwrap(requests.request(for: .cloudflare, madeIn: requests.generation))
        XCTAssertNotNil(requests.authorization(for: again))
    }

    /// Review 4 nit: an extracted archive or `rsync -t` copy keeps the modification date.
    func testTheModificationDateCountsWhenItIsTheEarliest() {
        let old = grantedAt.addingTimeInterval(-86_400)
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(creationDate: after, modificationDate: old, nameDate: nil), old)
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(creationDate: old, modificationDate: after, nameDate: nil), old,
                       "an edit (fresh modification date) does not make a file new")
        XCTAssertEqual(UploadConsent.effectiveCaptureTime(creationDate: nil, modificationDate: nil, nameDate: nil), .distantPast)
    }
}
