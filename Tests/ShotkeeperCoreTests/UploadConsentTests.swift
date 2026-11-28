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

    /// OpenRouter is its own destination: neither Cloudflare nor a custom endpoint grant covers it, nor the other way.
    func testOpenRouterNeedsItsOwnGrant() {
        let openRouter = AppSettings.UploadGrant(destination: .openRouter, grantedAt: grantedAt,
                                                 openRouterModel: OpenRouterBackend.defaultModel)
        let defaultModel = UploadTarget.openRouter(model: OpenRouterBackend.defaultModel)
        XCTAssertEqual(UploadConsent.decide(target: defaultModel, grants: [], capturedAt: after), .skip(.destinationNotAllowed))
        XCTAssertEqual(UploadConsent.decide(target: defaultModel, grants: [cloudflare, custom(endpointA)], capturedAt: after),
                       .skip(.destinationNotAllowed), "Cloudflare or a custom endpoint does not cover OpenRouter")
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [openRouter], capturedAt: after),
                       .skip(.destinationNotAllowed), "OpenRouter does not cover Cloudflare")
        // A custom endpoint at openrouter.ai is still a custom endpoint: only a grant naming it covers it.
        let customAtOpenRouter = CustomEndpointIdentity(scheme: "https", host: "openrouter.ai", port: 443)
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(customAtOpenRouter), grants: [openRouter], capturedAt: after),
                       .skip(.destinationNotAllowed))
        XCTAssertEqual(UploadConsent.decide(target: defaultModel, grants: [openRouter], capturedAt: after), .allow)
        XCTAssertEqual(UploadConsent.decide(target: defaultModel, grants: [openRouter], capturedAt: before),
                       .skip(.takenBeforeGrant(grantedAt: grantedAt)), "the time rule applies as for Cloudflare")
        XCTAssertEqual(UploadConsent.decide(target: defaultModel, grants: [openRouter], capturedAt: before,
                                            userRequest: UserUploadAuthorization(target: defaultModel)), .allow)
        XCTAssertEqual(UploadConsent.decide(target: defaultModel, grants: [openRouter], capturedAt: before,
                                            userRequest: UserUploadAuthorization(target: .cloudflare)),
                       .skip(.takenBeforeGrant(grantedAt: grantedAt)), "a user request for another target lifts nothing")
    }

    /// S1: an OpenRouter grant covers one model; another model has other providers and needs its own "Allow…".
    func testAnOpenRouterGrantCoversOnlyItsModel() {
        var settings = AppSettings()
        settings.backend = .openRouter
        settings = BackendGate.granting(.openRouter, expectedOpenRouterModel: OpenRouterBackend.defaultModel,
                                        in: settings, at: grantedAt)
        XCTAssertEqual(UploadConsent.decide(settings: settings, capturedAt: after), .allow)

        // Changing the model invalidates consent.
        settings.openRouterModel = "vendor/other-model"
        XCTAssertEqual(UploadConsent.decide(settings: settings, capturedAt: after), .skip(.destinationNotAllowed))
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false, hasOpenRouterKey: true), .needsConsent)
        XCTAssertEqual(BackendGate.consentRequest(for: settings)?.prompt,
                       "Screenshots will be sent to OpenRouter, then to the provider that serves vendor/other-model")

        // Every prefix of a model ID typed (and saved) one key at a time is a model of its own: none inherits.
        let typed = "thinkingmachines/inkling-2-mini-20261120"
        for end in typed.indices.dropFirst() {
            settings.openRouterModel = String(typed[..<end])
            guard OpenRouterBackend.effectiveModel(settings.openRouterModel) != OpenRouterBackend.defaultModel else { continue }
            XCTAssertEqual(UploadConsent.decide(settings: settings, capturedAt: after), .skip(.destinationNotAllowed),
                           settings.openRouterModel ?? "")
        }

        // The other model gets its own grant; the default model's grant stays, with its first time.
        settings.openRouterModel = "vendor/other-model"
        let later = grantedAt.addingTimeInterval(3_600)
        XCTAssertEqual(BackendGate.granting(.openRouter, expectedOpenRouterModel: OpenRouterBackend.defaultModel,
                                            in: settings, at: later), settings, "Allow for a model no longer configured grants nothing")
        settings = BackendGate.granting(.openRouter, expectedOpenRouterModel: "vendor/other-model", in: settings, at: later)
        XCTAssertEqual(UploadConsent.decide(settings: settings, capturedAt: grantedAt.addingTimeInterval(10)),
                       .skip(.takenBeforeGrant(grantedAt: later)))
        settings.openRouterModel = nil
        XCTAssertEqual(BackendGate.activeGrant(settings)?.grantedAt, grantedAt, "back on the default model: its original grant")
        XCTAssertEqual(UploadConsent.decide(settings: settings, capturedAt: after), .allow)
        XCTAssertEqual(settings.uploadGrants.filter { $0.destination == .openRouter }.count, 2)

        // A grant without a model (none is ever written so) covers nothing.
        let modelless = AppSettings.UploadGrant(destination: .openRouter, grantedAt: .distantPast)
        XCTAssertEqual(UploadConsent.decide(target: .openRouter(model: OpenRouterBackend.defaultModel), grants: [modelless],
                                            capturedAt: after), .skip(.destinationNotAllowed))
        // A user request for one model lifts nothing for another.
        XCTAssertEqual(UploadConsent.decide(target: .openRouter(model: "vendor/other-model"), grants: settings.uploadGrants,
                                            capturedAt: .distantPast,
                                            userRequest: UserUploadAuthorization(target: .openRouter(
                                                model: OpenRouterBackend.defaultModel))),
                       .skip(.takenBeforeGrant(grantedAt: later)))
    }

    func testTheTargetFollowsTheSelectedBackend() {
        var settings = AppSettings()
        XCTAssertEqual(UploadTarget(settings: settings), .cloudflare)
        settings.backend = .openRouter
        XCTAssertEqual(UploadTarget(settings: settings), .openRouter(model: "thinkingmachines/inkling-2-mini"))
        settings.openRouterModel = "  "
        XCTAssertEqual(UploadTarget(settings: settings), .openRouter(model: "thinkingmachines/inkling-2-mini"), "blank = default")
        settings.openRouterModel = " vendor/other "
        XCTAssertEqual(UploadTarget(settings: settings), .openRouter(model: "vendor/other"))
        settings.openRouterModel = nil
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
                                            userRequest: .init(target: .cloudflare)), .skip(.destinationNotAllowed))
    }

    // MARK: User upload requests ("Process Existing Screenshots…", "Analyze Again")

    func testAUserRequestLiftsOnlyTheTimeRuleForItsOwnTarget() {
        let request = UserUploadAuthorization(target: .cloudflare)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: .distantPast,
                                            userRequest: request), .allow)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [], capturedAt: .distantPast,
                                            userRequest: request), .skip(.destinationNotAllowed),
                       "never the destination rule")
    }

    /// Review 3 B1, path 1: Process Existing on Local (held "not installed"), then setup → Clairic → Continue.
    func testARequestMadeOnLocalNeverCoversCloudflare() {
        let onLocal = UserUploadAuthorization(target: .thisMac)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: before,
                                            userRequest: onLocal), .skip(.takenBeforeGrant(grantedAt: grantedAt)))
    }

    /// Review 3 B1, path 2: a Cloudflare backlog draining to a custom endpoint allowed later.
    func testARequestMadeForCloudflareNeverCoversACustomEndpoint() {
        let forCloudflare = UserUploadAuthorization(target: .cloudflare)
        let grants = [cloudflare, custom(endpointA, at: after)]
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointA), grants: grants, capturedAt: before,
                                            userRequest: forCloudflare),
                       .skip(.takenBeforeGrant(grantedAt: after)))
        let forA = UserUploadAuthorization(target: .customEndpoint(endpointA))
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointB), grants: [custom(endpointB)], capturedAt: before,
                                            userRequest: forA), .skip(.takenBeforeGrant(grantedAt: grantedAt)),
                       "nor one endpoint's request another endpoint")
        XCTAssertEqual(UploadConsent.decide(target: .customEndpoint(endpointA), grants: [custom(endpointA)], capturedAt: before,
                                            userRequest: forA), .allow)
    }

    func testRequestsAreInvalidatedTogether() {
        let requests = UserUploadRequests()
        let clicked = requests.generation
        let request = try! XCTUnwrap(requests.request(for: .cloudflare, madeIn: clicked))
        XCTAssertEqual(requests.authorization(for: request), UserUploadAuthorization(target: .cloudflare))
        XCTAssertNil(requests.authorization(for: nil))
        requests.invalidateAll()
        XCTAssertNil(requests.authorization(for: request), "a destination change: every earlier request counts as none")
        XCTAssertNil(requests.request(for: .cloudflare, madeIn: clicked), "changed during the scan: no request")
        let again = try! XCTUnwrap(requests.request(for: .cloudflare, madeIn: requests.generation))
        XCTAssertNotNil(requests.authorization(for: again))
    }

    /// Parag, 2026-11-28: a user request counts "only if the current backend's destination is allowed".
    func testAUserRequestNeverLiftsDestinationNotAllowed() {
        let openRouter = AppSettings.UploadGrant(destination: .openRouter, grantedAt: grantedAt,
                                                 openRouterModel: OpenRouterBackend.defaultModel)
        let cases: [(UploadTarget, [AppSettings.UploadGrant])] = [
            (.cloudflare, []),
            (.cloudflare, [custom(endpointA), openRouter]),
            (.customEndpoint(endpointB), [custom(endpointA), cloudflare]),
            (.openRouter(model: "vendor/other-model"), [openRouter]),
            (.unidentifiedEndpoint, [cloudflare, custom(endpointA), openRouter]),
        ]
        for (target, grants) in cases {
            for date in [Date.distantPast, before, after] {
                XCTAssertEqual(UploadConsent.decide(target: target, grants: grants, capturedAt: date,
                                                    userRequest: UserUploadAuthorization(target: target)),
                               .skip(.destinationNotAllowed), "\(target) at \(date)")
            }
        }
    }

    func testAUserRequestForAnotherTargetDoesNotCount() {
        let grants = [cloudflare, custom(endpointA), custom(endpointB)]
        let others: [(UploadTarget, UploadTarget)] = [
            (.cloudflare, .customEndpoint(endpointA)),
            (.customEndpoint(endpointA), .cloudflare),
            (.customEndpoint(endpointA), .customEndpoint(endpointB)),
            (.customEndpoint(endpointA), .thisMac),
            (.customEndpoint(endpointA), .unidentifiedEndpoint),
            (.cloudflare, .openRouter(model: OpenRouterBackend.defaultModel)),
        ]
        for (target, requested) in others {
            XCTAssertEqual(UploadConsent.decide(target: target, grants: grants, capturedAt: before,
                                                userRequest: UserUploadAuthorization(target: requested)),
                           .skip(.takenBeforeGrant(grantedAt: grantedAt)), "\(requested) for \(target)")
        }
    }

    /// A backend, endpoint or grant change between the click and the attempt: the request counts as none.
    func testAnInvalidatedUserRequestCountsAsNone() {
        let requests = UserUploadRequests()
        let request = requests.request(for: .cloudflare, madeIn: requests.generation)
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: before,
                                            userRequest: requests.authorization(for: request)), .allow)
        requests.invalidateAll()
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: before,
                                            userRequest: requests.authorization(for: request)),
                       .skip(.takenBeforeGrant(grantedAt: grantedAt)))
        XCTAssertEqual(UploadConsent.decide(target: .cloudflare, grants: [cloudflare], capturedAt: after,
                                            userRequest: requests.authorization(for: request)), .allow,
                       "a new file needs no request")
    }

    /// Analyze Again (or Process Existing) on a file taken before the grant.
    func testAFileTakenBeforeTheGrantIsAllowedOnlyWithAUserRequest() {
        for target in [UploadTarget.cloudflare, .customEndpoint(endpointA)] {
            let grants = [cloudflare, custom(endpointA)]
            for date in [Date.distantPast, before, grantedAt.addingTimeInterval(-0.001)] {
                XCTAssertEqual(UploadConsent.decide(target: target, grants: grants, capturedAt: date),
                               .skip(.takenBeforeGrant(grantedAt: grantedAt)), "\(target) without a request")
                XCTAssertEqual(UploadConsent.decide(target: target, grants: grants, capturedAt: date,
                                                    userRequest: UserUploadAuthorization(target: target)),
                               .allow, "\(target) with a request")
            }
        }
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
