import XCTest
@testable import ShotkeeperCore

private let gb: UInt64 = 1_073_741_824

private func clairicSettings(account: String? = "acct", consent: Bool) -> AppSettings {
    var settings = AppSettings()
    settings.backend = .clairic
    settings.clairicAccountID = account
    settings.hasSeenPrivacyNotice = consent
    settings.uploadGrants = consent ? [AppSettings.cloudflareSinceEver] : []
    return settings
}

final class BackendGateTests: XCTestCase {
    func testClairicNeedsAccountTokenAndConsent() {
        XCTAssertEqual(BackendGate.readiness(settings: clairicSettings(account: nil, consent: true), hasClairicToken: true),
                       .notConfigured("Cloudflare account ID is not set"))
        XCTAssertEqual(BackendGate.readiness(settings: clairicSettings(account: "  ", consent: true), hasClairicToken: true),
                       .notConfigured("Cloudflare account ID is not set"))
        XCTAssertEqual(BackendGate.readiness(settings: clairicSettings(consent: true), hasClairicToken: false),
                       .notConfigured("Cloudflare API token is not set"))
        // Working credentials alone never upload: consent is still missing.
        XCTAssertEqual(BackendGate.readiness(settings: clairicSettings(consent: false), hasClairicToken: true), .needsConsent)
        XCTAssertEqual(BackendGate.readiness(settings: clairicSettings(consent: true), hasClairicToken: true), .ready)
    }

    func testCustomEndpointNeedsURLModelAndConsent() {
        var settings = AppSettings()
        settings.backend = .customEndpoint
        settings.hasSeenPrivacyNotice = true
        settings.uploadGrants = [AppSettings.cloudflareSinceEver,
                                 .init(destination: .customEndpoint, grantedAt: .distantPast,
                                       endpoint: CustomEndpointIdentity(scheme: "http", host: "127.0.0.1", port: 8080))]
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false),
                       .notConfigured("Custom endpoint URL is not set"))
        settings.customEndpointURL = URL(string: "ftp://example.com")
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false),
                       .notConfigured("Custom endpoint URL is not set"))
        settings.customEndpointURL = URL(string: "http://127.0.0.1:8080")
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false),
                       .notConfigured("Custom endpoint model name is not set"))
        settings.customModelName = "inkling"
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false), .ready)
        // Even a 127.0.0.1 URL counts as leaving the Mac: the app cannot tell where it ends up.
        settings.uploadGrants = [AppSettings.cloudflareSinceEver]
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false), .needsConsent,
                       "Cloudflare consent does not cover a custom endpoint")
        XCTAssertTrue(BackendGate.sendsScreenshotsOffThisMac(.customEndpoint))
    }

    func testCustomEndpointConsentIsForTheNamedEndpointOnly() {
        var settings = AppSettings()
        settings.backend = .customEndpoint
        settings.customEndpointURL = URL(string: "http://LLM.lan:8080/v1")
        settings.customModelName = "m"
        let named = CustomEndpointIdentity(url: settings.customEndpointURL)
        XCTAssertEqual(named, CustomEndpointIdentity(scheme: "http", host: "llm.lan", port: 8080))
        XCTAssertFalse(BackendGate.hasUploadConsent(settings))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        settings = BackendGate.granting(.customEndpoint, expectedEndpoint: named, in: settings, at: now)
        XCTAssertEqual(settings.grant(for: .customEndpoint)?.grantedAt, now)
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false), .ready)
        XCTAssertNil(settings.grant(for: .cloudflare), "allowing one destination grants only it")

        for other in ["http://llm.lan:9999", "https://llm.lan:8080", "https://other.example.com"] {
            var moved = settings
            moved.customEndpointURL = URL(string: other)
            XCTAssertEqual(BackendGate.readiness(settings: moved, hasClairicToken: false), .needsConsent,
                           "\(other) is another endpoint (scheme, host and port)")
        }
        var otherPath = settings
        otherPath.customEndpointURL = URL(string: "http://llm.lan:8080/other/path")
        XCTAssertEqual(BackendGate.readiness(settings: otherPath, hasClairicToken: false), .ready)
    }

    func testAllowGrantsOnlyTheEndpointTheDialogNamed() {
        var settings = AppSettings()
        settings.backend = .customEndpoint
        settings.customEndpointURL = URL(string: "http://a.lan:8080")
        let shown = CustomEndpointIdentity(url: settings.customEndpointURL)
        settings.customEndpointURL = URL(string: "http://b.lan:8080") // edited while the dialog was open
        XCTAssertEqual(BackendGate.granting(.customEndpoint, expectedEndpoint: shown, in: settings), settings,
                       "a mismatch grants nothing")
        XCTAssertEqual(BackendGate.granting(.customEndpoint, expectedEndpoint: nil, in: settings), settings)
        var noURL = AppSettings()
        noURL.backend = .customEndpoint
        XCTAssertEqual(BackendGate.granting(.customEndpoint, expectedEndpoint: shown, in: noURL), noURL)
    }

    func testGrantTimesAndRegranting() {
        let grantedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var settings = BackendGate.granting(.cloudflare, in: AppSettings(), at: grantedAt)
        XCTAssertEqual(settings.grant(for: .cloudflare)?.grantedAt, grantedAt, "a whole second stays as it is")
        // Granting again keeps the first time.
        let again = BackendGate.granting(.cloudflare, in: settings, at: grantedAt.addingTimeInterval(500))
        XCTAssertEqual(again.grant(for: .cloudflare)?.grantedAt, grantedAt)
        // A new endpoint replaces the old grant with a new time.
        settings.backend = .customEndpoint
        settings.customEndpointURL = URL(string: "http://a.lan:8080")
        settings = BackendGate.granting(.customEndpoint, expectedEndpoint: CustomEndpointIdentity(url: settings.customEndpointURL),
                                        in: settings, at: grantedAt)
        settings.customEndpointURL = URL(string: "http://b.lan:8080")
        settings = BackendGate.granting(.customEndpoint, expectedEndpoint: CustomEndpointIdentity(url: settings.customEndpointURL),
                                        in: settings, at: grantedAt.addingTimeInterval(600))
        XCTAssertEqual(settings.grant(for: .customEndpoint),
                       AppSettings.UploadGrant(destination: .customEndpoint, grantedAt: grantedAt.addingTimeInterval(600),
                                               endpoint: CustomEndpointIdentity(scheme: "http", host: "b.lan", port: 8080)))
        XCTAssertEqual(settings.uploadGrants.count, 2, "one grant per destination")
    }

    /// Review N1: settings store whole seconds, so a grant at .25 is saved as the NEXT second. Rounding down would
    /// let a file taken between the whole second and the click through after a reload.
    func testGrantTimeIsRoundedUpToTheNextWholeSecond() throws {
        let click = Date(timeIntervalSince1970: 1_800_000_000.25)
        let settings = BackendGate.granting(.cloudflare, in: AppSettings(), at: click)
        XCTAssertEqual(settings.grant(for: .cloudflare)?.grantedAt, Date(timeIntervalSince1970: 1_800_000_001))
        let reloaded = AppSettings.decode(try settings.encoded())
        XCTAssertEqual(reloaded.uploadGrants, settings.uploadGrants, "survives a save and reload unchanged")
        let takenBeforeTheClick = Date(timeIntervalSince1970: 1_800_000_000.1)
        XCTAssertEqual(UploadConsent.decide(settings: reloaded, capturedAt: takenBeforeTheClick),
                       .skip(.takenBeforeGrant(grantedAt: Date(timeIntervalSince1970: 1_800_000_001))))
        XCTAssertEqual(BackendGate.granting(.cloudflare, in: AppSettings(), at: .distantPast).grant(for: .cloudflare)?.grantedAt,
                       .distantPast)
    }

    func testEndpointDisplay() {
        XCTAssertEqual(CustomEndpointIdentity(url: URL(string: "https://GPU-box.lan/v1"))?.display, "gpu-box.lan:443")
        XCTAssertEqual(CustomEndpointIdentity(url: URL(string: "http://gpu-box.lan"))?.display, "http://gpu-box.lan:80")
        XCTAssertEqual(CustomEndpointIdentity(url: URL(string: "http://[::1]:8080"))?.display, "http://[::1]:8080")
        XCTAssertNil(CustomEndpointIdentity(url: URL(string: "ftp://x.lan")))
        XCTAssertNil(CustomEndpointIdentity(url: nil))
    }

    func testConsentPromptNamesTheDestination() {
        var settings = AppSettings()
        XCTAssertEqual(BackendGate.consentRequest(for: settings)?.prompt, "Screenshots will be sent to your Cloudflare account")
        settings = BackendGate.granting(.cloudflare, in: settings)
        XCTAssertNil(BackendGate.consentRequest(for: settings)?.prompt)
        settings.backend = .customEndpoint
        XCTAssertNil(BackendGate.consentRequest(for: settings)?.prompt, "no endpoint to name yet")
        settings.customEndpointURL = URL(string: "https://GPU-box.lan:8443/v1")
        XCTAssertEqual(BackendGate.consentRequest(for: settings)?.prompt, "Screenshots will be sent to gpu-box.lan:8443")
        XCTAssertEqual(BackendGate.consentRequest(for: settings)?.endpoint,
                       CustomEndpointIdentity(scheme: "https", host: "gpu-box.lan", port: 8443))
        settings.customEndpointURL = URL(string: "http://gpu-box.lan:8080")
        XCTAssertEqual(BackendGate.consentRequest(for: settings)?.prompt, "Screenshots will be sent to http://gpu-box.lan:8080",
                       "an unencrypted endpoint says so")
        settings.backend = .localInkling
        XCTAssertNil(BackendGate.consentRequest(for: settings)?.prompt)
    }

    func testOpenRouterNeedsAKeyAndItsOwnConsent() {
        var settings = AppSettings()
        settings.backend = .openRouter
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: true),
                       .notConfigured("OpenRouter API key is not set"), "a caller that does not pass the key fails closed")
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false, hasOpenRouterKey: true), .needsConsent)
        settings.uploadGrants = [AppSettings.cloudflareSinceEver]
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: true, hasOpenRouterKey: true), .needsConsent,
                       "Cloudflare's consent is not OpenRouter's")
        let model = OpenRouterBackend.defaultModel
        XCTAssertEqual(BackendGate.consentRequest(for: settings),
                       ConsentRequest(prompt: "Screenshots will be sent to OpenRouter, then to Prime Intellect or io.net",
                                      destination: .openRouter, endpoint: nil, openRouterModel: model))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(BackendGate.granting(.openRouter, in: settings, at: now), settings, "Allow must name the model")
        settings = BackendGate.granting(.openRouter, expectedOpenRouterModel: model, in: settings, at: now)
        XCTAssertEqual(settings.grant(for: .openRouter),
                       AppSettings.UploadGrant(destination: .openRouter, grantedAt: now, openRouterModel: model))
        XCTAssertNotNil(settings.grant(for: .cloudflare), "granting OpenRouter keeps the Cloudflare grant")
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false, hasOpenRouterKey: true), .ready)
        XCTAssertTrue(BackendGate.mayWatch(settings: settings, hasClairicToken: false, hasOpenRouterKey: true))
        XCTAssertFalse(BackendGate.mayWatch(settings: settings, hasClairicToken: false))
        XCTAssertNil(BackendGate.consentRequest(for: settings))
        XCTAssertEqual(BackendGate.granting(.openRouter, expectedOpenRouterModel: model, in: settings,
                                            at: now.addingTimeInterval(60)).grant(for: .openRouter)?.grantedAt,
                       now, "granting again keeps the first time")
        XCTAssertTrue(BackendGate.sendsScreenshotsOffThisMac(.openRouter))
        XCTAssertEqual(BackendGate.destination(of: .openRouter), .openRouter)
    }

    func testDestinations() {
        XCTAssertEqual(BackendGate.destination(of: .clairic), .cloudflare)
        XCTAssertEqual(BackendGate.destination(of: .customEndpoint), .customEndpoint)
        XCTAssertNil(BackendGate.destination(of: .localInkling))
        var settings = AppSettings()
        settings = BackendGate.granting(.cloudflare, in: settings)
        XCTAssertEqual(settings.acceptedUploadDestinations, [.cloudflare])
        XCTAssertTrue(BackendGate.hasUploadConsent(settings))
        // The old flag alone is no consent any more.
        var flagOnly = AppSettings()
        flagOnly.hasSeenPrivacyNotice = true
        XCTAssertFalse(BackendGate.hasUploadConsent(flagOnly))
    }

    func testLocalNeedsNoUploadConsent() {
        var settings = AppSettings()
        settings.backend = .localInkling
        settings.hasSeenPrivacyNotice = false
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false), .ready)
        XCTAssertTrue(BackendGate.mayWatch(settings: settings, hasClairicToken: false))
        XCTAssertFalse(BackendGate.sendsScreenshotsOffThisMac(.localInkling))
        XCTAssertTrue(BackendGate.sendsScreenshotsOffThisMac(.clairic))
    }

    func testWatchingWaitsForAUsableBackend() {
        // A fresh install: default Clairic backend, nothing entered, no consent.
        XCTAssertFalse(BackendGate.mayWatch(settings: AppSettings(), hasClairicToken: false))
        XCTAssertFalse(BackendGate.mayWatch(settings: clairicSettings(consent: false), hasClairicToken: true))
        XCTAssertFalse(BackendGate.mayWatch(settings: clairicSettings(consent: true), hasClairicToken: false))
        XCTAssertTrue(BackendGate.mayWatch(settings: clairicSettings(consent: true), hasClairicToken: true))
    }

    func testReasons() {
        XCTAssertNil(BackendGate.reason(for: .ready))
        XCTAssertEqual(BackendGate.reason(for: .needsConsent), BackendGate.consentReason)
        XCTAssertEqual(BackendGate.reason(for: .notConfigured("x")), "x")
        XCTAssertNil(BackendGate.statusReason(for: .ready))
        XCTAssertEqual(BackendGate.statusReason(for: .needsConsent), "Not allowed to send screenshots yet")
        XCTAssertEqual(BackendGate.statusReason(for: .notConfigured("Cloudflare API token is not set")),
                       "Cloudflare API token is not set")
    }

    func testMenuSaysNotWatchingYet() {
        let summary = MenuText.status(queue: .idle, watchedFolderName: "Desktop", indexedCount: 0,
                                      notWatchingReason: "Setup is not finished", now: Date())
        XCTAssertEqual(summary, MenuStatusSummary(dot: .orange, headline: "Not watching yet", detail: "Setup is not finished"))
        let skipping = MenuText.status(queue: .idle, watchedFolderName: "Desktop", indexedCount: 0,
                                       skippingForConsent: true, now: Date())
        XCTAssertEqual(skipping, MenuStatusSummary(dot: .orange, headline: "Watching Desktop",
                                                   detail: MenuText.skippingForConsentText))
        // A hard failure still wins.
        XCTAssertEqual(MenuText.status(queue: .idle, watchedFolderName: nil, indexedCount: 0, failure: "boom",
                                       notWatchingReason: "x", now: Date()).dot, .red)
    }
}

final class ClairicPricingTests: XCTestCase {
    func testStandardPriceForAThousandFullScreenScreenshots() {
        // 1,242 + 7 × 1,000 = 8,242 tokens per 1280×800 screenshot × $0.24/M × 1,000 = $1.978.
        XCTAssertEqual(ClairicPricing.usdPerThousandScreenshots(), 1.978, accuracy: 0.0005)
        XCTAssertEqual(ClairicPricing.perThousandText(), "About $2 for 1,000 screenshots")
    }

    func testSmallImagesAreQuotedInCents() {
        // 512×320: 16×10 = 160 image tokens; 1,242 + 7 × 160 = 2,362 tokens → $0.567.
        XCTAssertEqual(ClairicPricing.perThousandText(longSide: 512), "About $0.57 for 1,000 screenshots")
    }
}

final class SetupCardsTests: XCTestCase {
    func testOpenRouterCardHasNoPriceUntilMeasuredAndIsNeverRecommended() {
        for ram in [8, 16, 24, 32] {
            let cards = SetupCards.make(physicalMemoryBytes: UInt64(ram) * gb)
            XCTAssertEqual(cards.openRouter.title, "OpenRouter · Inkling 2 Mini")
            XCTAssertEqual(cards.openRouter.subtitle, "Inkling 2 Mini in the cloud, with your OpenRouter key and credits.")
            XCTAssertFalse(cards.openRouter.subtitle.contains("$"), "no unmeasured estimate")
            XCTAssertEqual(cards.openRouter.badges, [])
            XCTAssertFalse(cards.openRouter.isRecommended)
            XCTAssertTrue(cards.openRouter.isAvailable)
            XCTAssertNotEqual(cards.recommended, .openRouter)
        }
        let measured = SetupCards.make(physicalMemoryBytes: 16 * gb, openRouterPrice: "About $0.25 for 1,000 screenshots")
        XCTAssertEqual(measured.openRouter.subtitle,
                       "Inkling 2 Mini in the cloud, with your OpenRouter key and credits. About $0.25 for 1,000 screenshots.")
    }

    func testSixteenGigabyteMac() {
        let cards = SetupCards.make(physicalMemoryBytes: 16 * gb)
        XCTAssertEqual(cards.recommended, .clairic)
        XCTAssertEqual(cards.clairic.badges, ["Recommended"])
        XCTAssertEqual(cards.clairic.subtitle, "Best for this Mac (16 GB). About $2 for 1,000 screenshots.")
        XCTAssertEqual(cards.local.badges, ["Experimental"])
        XCTAssertEqual(cards.local.subtitle, "Private, but slow and lower quality on 16 GB. Needs about 10 GB of disk.")
        XCTAssertEqual(cards.local.model, ModelCatalog.inkling2bit)
        XCTAssertTrue(cards.local.isAvailable)
        XCTAssertEqual(cards.local.installButtonTitle, "Install and Download (about 10 GB)")
        XCTAssertNil(cards.clairic.installButtonTitle)
        XCTAssertEqual(cards.local.note, "Lower quality (weaker image recognition) and tight on memory: other apps may slow "
                       + "down while it runs. Experimental build: not yet tested with the built-in model server.")
        XCTAssertNil(cards.clairic.note)
        XCTAssertEqual(cards.clairic.accessibilityLabel,
                       "Cloudflare Clairic, Recommended. Best for this Mac (16 GB). About $2 for 1,000 screenshots.")
    }

    func testEighteenGigabyteMacNamesItsMemory() {
        let cards = SetupCards.make(physicalMemoryBytes: 18 * gb)
        XCTAssertEqual(cards.clairic.subtitle, "Best for this Mac (18 GB). About $2 for 1,000 screenshots.")
        XCTAssertEqual(cards.local.subtitle, "Private, but slow and lower quality on 18 GB. Needs about 10 GB of disk.")
    }

    func testTwentyFourGigabyteMacRecommendsTheLocal3BitBuild() {
        let cards = SetupCards.make(physicalMemoryBytes: 24 * gb)
        XCTAssertEqual(cards.recommended, .localInkling)
        XCTAssertEqual(cards.clairic.badges, [])
        XCTAssertEqual(cards.clairic.subtitle, "Fast, nothing to download. About $2 for 1,000 screenshots.")
        XCTAssertEqual(cards.local.model, ModelCatalog.inkling3bit)
        XCTAssertEqual(cards.local.badges, ["Recommended", "Experimental"], "the 3-bit build is not verified with mlx-lm")
        XCTAssertEqual(cards.local.subtitle, "Private: nothing leaves this Mac. Best for this Mac (24 GB). Needs about 14 GB of disk.")
    }

    func testThirtyTwoGigabyteMacGetsTheVerified4BitBuild() {
        let cards = SetupCards.make(physicalMemoryBytes: 32 * gb)
        XCTAssertEqual(cards.local.model, ModelCatalog.inkling4bit)
        XCTAssertEqual(cards.local.badges, ["Recommended"])
        XCTAssertEqual(cards.local.installButtonTitle, "Install and Download (about 17 GB)")
        XCTAssertNil(cards.local.note, "the 4-bit build has no warning")
    }

    func testEightGigabyteMacCannotPickLocal() {
        let cards = SetupCards.make(physicalMemoryBytes: 8 * gb)
        XCTAssertEqual(cards.recommended, .clairic)
        XCTAssertFalse(cards.local.isAvailable)
        XCTAssertNil(cards.local.model)
        XCTAssertNil(cards.local.installButtonTitle)
        XCTAssertEqual(cards.local.subtitle, "Needs a Mac with at least 16 GB of memory. This Mac has 8 GB.")
    }

    func testCostFollowsTheImageSize() {
        let cards = SetupCards.make(physicalMemoryBytes: 16 * gb, clairicLongSide: 512)
        XCTAssertEqual(cards.clairic.subtitle, "Best for this Mac (16 GB). About $0.57 for 1,000 screenshots.")
    }
}

final class SetupFlowTests: XCTestCase {
    private let cards16 = SetupCards.make(physicalMemoryBytes: 16 * gb)

    func testFirstRunWalksAllFiveSteps() {
        var flow = SetupFlow(settings: AppSettings(), cards: cards16)
        XCTAssertEqual(flow.step, .welcome)
        XCTAssertEqual(flow.step.progressText, "Step 1 of 5")
        XCTAssertFalse(flow.showsBack)
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "Get Started", isEnabled: true, action: .next))
        XCTAssertEqual(flow.choice, .clairic, "recommended for 16 GB")
        XCTAssertTrue(flow.openAtLogin, "on for a first run")
        XCTAssertFalse(flow.consentChecked)

        flow.advance()
        XCTAssertEqual(flow.step, .privacy)
        XCTAssertTrue(flow.showsBack)
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "I Agree", isEnabled: false, action: .acceptConsent))
        XCTAssertNil(flow.primaryAction(), "Return does nothing until the box is ticked")
        flow.consentChecked = true
        XCTAssertEqual(flow.primaryAction(), .acceptConsent)

        flow.advance()
        XCTAssertEqual(flow.step, .connect)
        XCTAssertEqual(flow.primary.title, "Skip")
        XCTAssertFalse(flow.primary.isDefaultAction, "Return in a half-filled field must not skip the step")
        XCTAssertEqual(flow.primaryAction(), .skipConnection)
        flow.inputs.accountID = "acct"
        XCTAssertEqual(flow.primaryAction(), .skipConnection, "an account ID without a token is not enough")
        flow.inputs.hasTokenDraft = true
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "Continue", isEnabled: true, action: .saveConnection(.clairic)))
        XCTAssertTrue(flow.primary.isDefaultAction)

        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        flow.advance(now: opened)
        XCTAssertEqual(flow.tryItOpenedAt, opened)
        XCTAssertTrue(flow.showsBack)
        XCTAssertEqual(flow.tryIt, .waiting(note: nil))
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "Skip", isEnabled: true, action: .next))
        flow.tryIt = .result(TryItResult(path: "/d/a.png", oldName: "Screenshot.png", newName: "A.png", hashtags: []))
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "Continue", isEnabled: true, action: .next))

        flow.advance()
        XCTAssertEqual(flow.step, .done)
        XCTAssertFalse(flow.showsBack)
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "Finish", isEnabled: true, action: .finish))
        flow.advance()
        XCTAssertEqual(flow.step, .done, "nothing after the last step")
    }

    func testBackOnlyOnStepsTwoToFour() {
        var flow = SetupFlow(settings: AppSettings(), cards: cards16)
        XCTAssertFalse(flow.back())
        XCTAssertEqual(flow.step, .welcome)
        flow.advance()
        flow.advance()
        flow.advance() // try it
        XCTAssertTrue(flow.back())
        XCTAssertEqual(flow.step, .connect)
        XCTAssertTrue(flow.back())
        XCTAssertTrue(flow.back())
        XCTAssertEqual(flow.step, .welcome)
        for _ in 0..<4 { flow.advance() }
        XCTAssertEqual(flow.step, .done)
        XCTAssertFalse(flow.back(), "Finish has no Back")
    }

    func testOpenRouterHasOneAgreeAndContinueButton() {
        var flow = SetupFlow(settings: AppSettings(), cards: cards16)
        flow.advance(); flow.consentChecked = true; flow.advance()
        XCTAssertTrue(flow.choose(.openRouter))
        XCTAssertEqual(flow.primaryAction(), .skipConnection)
        flow.inputs.hasOpenRouterKeyDraft = true
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "Agree and Continue", isEnabled: true,
                                                        action: .saveConnection(.openRouter)))
        XCTAssertTrue(flow.primary.isDefaultAction, "Return presses it")
        flow.inputs.hasOpenRouterKeyDraft = false
        flow.inputs.hasSavedOpenRouterKey = true
        XCTAssertEqual(flow.primaryAction(), .saveConnection(.openRouter), "a saved key counts")
        flow.choose(.clairic)
        flow.inputs.accountID = "acct"
        flow.inputs.hasTokenDraft = true
        XCTAssertEqual(flow.primary.title, "Continue", "only OpenRouter's button carries the agreement")
    }

    func testArrowKeysMoveInRowsAndColumns() {
        // One row (three cards): ←/→ and ↑/↓ step through it, wrapping.
        var flow = SetupFlow(settings: AppSettings(), cards: cards16)
        XCTAssertEqual(flow.cards.columns, 3)
        XCTAssertTrue(flow.choose(moving: .right)); XCTAssertEqual(flow.choice, .openRouter)
        XCTAssertTrue(flow.choose(moving: .down)); XCTAssertEqual(flow.choice, .localInkling)
        XCTAssertTrue(flow.choose(moving: .right)); XCTAssertEqual(flow.choice, .clairic, "wraps")
        XCTAssertTrue(flow.choose(moving: .left)); XCTAssertEqual(flow.choice, .localInkling)

        // Two rows of two (re-run with a custom endpoint): Clairic OpenRouter / Local Custom.
        var settings = AppSettings()
        settings.hasSeenPrivacyNotice = true
        var grid = SetupFlow(settings: settings, cards: SetupCards.make(physicalMemoryBytes: 16 * gb, customEndpointHost: "llm.lan"))
        XCTAssertEqual(grid.cards.columns, 2)
        XCTAssertEqual(grid.choice, .clairic)
        XCTAssertTrue(grid.choose(moving: .down)); XCTAssertEqual(grid.choice, .localInkling, "↓ goes to the next row")
        XCTAssertTrue(grid.choose(moving: .right)); XCTAssertEqual(grid.choice, .customEndpoint, "→ stays in the row")
        XCTAssertTrue(grid.choose(moving: .right)); XCTAssertEqual(grid.choice, .localInkling, "wraps within the row")
        XCTAssertTrue(grid.choose(moving: .up)); XCTAssertEqual(grid.choice, .clairic)
        XCTAssertTrue(grid.choose(moving: .up)); XCTAssertEqual(grid.choice, .localInkling, "wraps within the column")
        grid.choose(.openRouter)
        XCTAssertTrue(grid.choose(moving: .down)); XCTAssertEqual(grid.choice, .customEndpoint)

        // An unavailable card is skipped; with nothing else in that column, nothing moves.
        var small = SetupFlow(settings: settings, cards: SetupCards.make(physicalMemoryBytes: 8 * gb, customEndpointHost: "llm.lan"))
        XCTAssertFalse(small.choose(moving: .down), "Local is unavailable on 8 GB")
        XCTAssertEqual(small.choice, .clairic)
        XCTAssertTrue(small.choose(moving: .right)); XCTAssertEqual(small.choice, .openRouter)
        XCTAssertTrue(small.choose(moving: .down)); XCTAssertEqual(small.choice, .customEndpoint)
        XCTAssertFalse(small.choose(moving: .left), "the only other card in that row is unavailable")
    }

    func testSavedTokenIsEnoughForClairic() {
        var flow = SetupFlow(settings: clairicSettings(consent: true), cards: cards16,
                             inputs: SetupConnectionInputs(hasSavedToken: true))
        XCTAssertEqual(flow.inputs.accountID, "acct", "a re-run starts with the saved account ID")
        flow.advance(); flow.advance()
        XCTAssertEqual(flow.primaryAction(), .saveConnection(.clairic))
    }

    func testLocalContinuesOnceTheInstallStarted() {
        var flow = SetupFlow(settings: AppSettings(), cards: cards16)
        flow.advance(); flow.consentChecked = true; flow.advance()
        XCTAssertTrue(flow.choose(.localInkling))
        XCTAssertEqual(flow.primaryAction(), .skipConnection)
        flow.inputs.localModel = .failed
        XCTAssertEqual(flow.primaryAction(), .skipConnection)
        flow.inputs.localModel = .installing
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "Continue", isEnabled: true, action: .saveConnection(.localInkling)))
        flow.inputs.localModel = .installed
        XCTAssertEqual(flow.primaryAction(), .saveConnection(.localInkling))
    }

    func testCardsSelectWithArrowsAndSkipUnavailable() {
        var flow = SetupFlow(settings: AppSettings(), cards: cards16)
        XCTAssertFalse(flow.choose(.clairic), "already selected")
        XCTAssertTrue(flow.chooseNext())
        XCTAssertEqual(flow.choice, .openRouter)
        XCTAssertTrue(flow.chooseNext())
        XCTAssertEqual(flow.choice, .localInkling)
        XCTAssertTrue(flow.chooseNext())
        XCTAssertEqual(flow.choice, .clairic)

        var small = SetupFlow(settings: AppSettings(), cards: SetupCards.make(physicalMemoryBytes: 8 * gb))
        XCTAssertFalse(small.choose(.localInkling))
        XCTAssertTrue(small.chooseNext(), "OpenRouter is available on any Mac")
        XCTAssertEqual(small.choice, .openRouter)
        XCTAssertTrue(small.chooseNext(), "skips the unavailable local card")
        XCTAssertEqual(small.choice, .clairic)
    }

    func testRerunStartsFromTheCurrentSettings() {
        var settings = AppSettings()
        settings.hasSeenPrivacyNotice = true
        settings.uploadGrants = [AppSettings.cloudflareSinceEver]
        settings.backend = .localInkling
        settings.launchAtLogin = false
        let flow = SetupFlow(settings: settings, cards: cards16)
        XCTAssertTrue(flow.consentChecked)
        XCTAssertEqual(flow.choice, .localInkling)
        XCTAssertFalse(flow.openAtLogin, "a re-run keeps the user's login-item choice")

        settings.uploadGrants = []
        XCTAssertFalse(SetupFlow(settings: settings, cards: cards16).consentChecked,
                       "the box shows step 2's own consent (Cloudflare), not the old flag")
        settings.uploadGrants = [AppSettings.cloudflareSinceEver]
        XCTAssertTrue(SetupFlow(settings: settings, cards: cards16, loginItemEnabled: true).openAtLogin,
                      "the login item's real state wins over the saved setting")

        settings.backend = .customEndpoint
        XCTAssertEqual(SetupFlow(settings: settings, cards: cards16).choice, .clairic, "no card without a host")
        let withCustom = SetupCards.make(physicalMemoryBytes: 16 * gb, customEndpointHost: "llm.lan")
        var custom = SetupFlow(settings: settings, cards: withCustom)
        XCTAssertEqual(custom.choice, .customEndpoint, "a re-run keeps the custom endpoint selected")
        custom.advance(); custom.advance()
        XCTAssertEqual(custom.primary, SetupPrimaryButton(title: "Continue", isEnabled: true,
                                                          action: .saveConnection(.customEndpoint)))
        XCTAssertTrue(custom.chooseNext())
        XCTAssertEqual(custom.choice, .clairic, "arrows wrap over all four cards")
        custom.chooseNext(); custom.chooseNext(); custom.chooseNext()
        XCTAssertEqual(custom.choice, .customEndpoint)

        settings.backend = .localInkling
        XCTAssertEqual(SetupFlow(settings: settings, cards: SetupCards.make(physicalMemoryBytes: 8 * gb)).choice, .clairic)
    }

    func testCustomCardOnlyWithAHost() {
        XCTAssertNil(SetupCards.make(physicalMemoryBytes: 16 * gb).custom)
        let cards = SetupCards.make(physicalMemoryBytes: 16 * gb, customEndpointHost: "llm.lan")
        XCTAssertEqual(cards.all.map(\.backend), [.clairic, .openRouter, .localInkling, .customEndpoint])
        XCTAssertEqual(cards.custom?.subtitle, "Keeps using llm.lan. Change it in Settings → Model.")
    }

    func testRecommendedCardIsPreselectedOnBigMacs() {
        XCTAssertEqual(SetupFlow(settings: AppSettings(), cards: SetupCards.make(physicalMemoryBytes: 32 * gb)).choice,
                       .localInkling)
    }

    func testTryItStartsWaitingAgainAfterGoingBack() {
        var flow = SetupFlow(settings: AppSettings(), cards: cards16)
        for _ in 0..<3 { flow.advance() }
        flow.tryIt = .problem("x")
        flow.back()
        flow.advance()
        XCTAssertEqual(flow.tryIt, .waiting(note: nil))
    }

    func testNotConnectedContinues() {
        var flow = SetupFlow(settings: AppSettings(), cards: cards16)
        for _ in 0..<3 { flow.advance() }
        flow.tryIt = .notConnected(TryIt.notConnectedText)
        XCTAssertEqual(flow.primary.title, "Continue")
        flow.tryIt = .problem("x")
        XCTAssertEqual(flow.primary.title, "Skip")
    }
}

final class TryItTests: XCTestCase {
    private let original = URL(fileURLWithPath: "/Users/p/Desktop/Screenshot 2026-11-21 at 16.24.11.png")
    private let final = URL(fileURLWithPath: "/Users/p/Desktop/Tweet semiconductor flashcards.png")

    private func entry(tags: [String]) -> IndexedScreenshot {
        IndexedScreenshot(path: final.path, originalFilename: original.lastPathComponent, contentHash: "h",
                          tags: tags, status: .done)
    }

    func testInitialState() {
        XCTAssertEqual(TryIt.initialState(readiness: .ready), .waiting(note: nil))
        XCTAssertEqual(TryIt.initialState(readiness: .ready, note: "n"), .waiting(note: "n"))
        XCTAssertEqual(TryIt.initialState(readiness: .notConfigured("x")), .notConnected(TryIt.notConnectedText))
        XCTAssertEqual(TryIt.initialState(readiness: .needsConsent), .notConnected(TryIt.notConnectedText))
    }

    func testRenameBecomesTheResultCard() {
        let report = ProcessingReport(originalURL: original, outcome: .processed(finalURL: final, renamed: true, moved: false))
        let state = TryIt.apply(.processed(report), entry: entry(tags: ["semiconductor", "flashcards"]), openedAt: nil, to: .waiting(note: nil))
        guard case .result(let result) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(result.oldName, "Screenshot 2026-11-21 at 16.24.11.png")
        XCTAssertEqual(result.newName, "Tweet semiconductor flashcards.png")
        XCTAssertEqual(result.hashtags, ["#semiconductor", "#flashcards"])
        XCTAssertEqual(result.path, final.path)
        XCTAssertEqual(result.headline, "It works")
        XCTAssertNil(result.detail)
        XCTAssertEqual(result.accessibilityLabel,
                       "It works. Screenshot 2026-11-21 at 16.24.11.png was renamed to Tweet semiconductor flashcards.png. "
                       + "Tags: semiconductor, flashcards")
    }

    func testKeptNameStillWorks() {
        let report = ProcessingReport(originalURL: original, outcome: .processed(finalURL: original, renamed: false, moved: false))
        guard case .result(let result) = TryIt.apply(.processed(report), entry: nil, openedAt: nil, to: .waiting(note: nil)) else {
            return XCTFail()
        }
        XCTAssertNil(result.newName)
        XCTAssertEqual(result.hashtags, [])
        XCTAssertNotNil(result.detail)
        XCTAssertEqual(result.accessibilityLabel, "It works. Screenshot 2026-11-21 at 16.24.11.png kept its name")
    }

    func testProblemsKeepWaitingForTheNextScreenshot() {
        let failed = ScreenshotEvent.failed(originalURL: original,
                                            problem: UserFacingProblem(message: "the model backend rejected the token"))
        XCTAssertEqual(TryIt.apply(failed, entry: nil, openedAt: nil, to: .waiting(note: nil)),
                       .problem("Could not name that screenshot: the model backend rejected the token. Take another one to try again."))
        let excluded = ScreenshotEvent.processed(ProcessingReport(
            originalURL: original, outcome: .skipped(.excluded(.init(.filenameContains, "bank")))))
        guard case .problem(let text) = TryIt.apply(excluded, entry: nil, openedAt: nil, to: .waiting(note: nil)) else { return XCTFail() }
        XCTAssertTrue(text.contains("exclude rule"))
        let paused = ScreenshotEvent.processed(ProcessingReport(originalURL: original, outcome: .skipped(.paused(until: Date()))))
        guard case .problem(let pausedText) = TryIt.apply(paused, entry: nil, openedAt: nil, to: .waiting(note: nil)) else { return XCTFail() }
        XCTAssertTrue(pausedText.contains("paused"))
    }

    /// Only screenshots taken since step 4 opened count: a backlog file finishing now is not the user's test.
    func testFilesFromBeforeStepFourAreIgnored() {
        let opened = Date(timeIntervalSince1970: 1_800_000_000)
        var old = entry(tags: [])
        old.capturedAt = opened.addingTimeInterval(-60)
        let report = ProcessingReport(originalURL: original, outcome: .processed(finalURL: final, renamed: true, moved: false))
        XCTAssertEqual(TryIt.apply(.processed(report), entry: old, openedAt: opened, to: .waiting(note: nil)),
                       .waiting(note: nil))
        var justBefore = old
        justBefore.capturedAt = opened.addingTimeInterval(-TryIt.slack + 0.5)
        guard case .result = TryIt.apply(.processed(report), entry: justBefore, openedAt: opened, to: .waiting(note: nil)) else {
            return XCTFail("a screenshot taken a moment before the step opened still counts")
        }
        var after = old
        after.capturedAt = opened.addingTimeInterval(30)
        guard case .result = TryIt.apply(.processed(report), entry: after, openedAt: opened, to: .waiting(note: nil)) else {
            return XCTFail()
        }

        let failed = ScreenshotEvent.failed(originalURL: original, problem: UserFacingProblem(message: "x"))
        XCTAssertEqual(TryIt.apply(failed, entry: nil, fileCreatedAt: opened.addingTimeInterval(-60), openedAt: opened,
                                   to: .waiting(note: nil)), .waiting(note: nil), "an old file failing is not shown")
        guard case .problem = TryIt.apply(failed, entry: nil, fileCreatedAt: opened.addingTimeInterval(10), openedAt: opened,
                                          to: .waiting(note: nil)) else { return XCTFail() }
        guard case .problem = TryIt.apply(failed, entry: nil, openedAt: opened, to: .waiting(note: nil)) else {
            return XCTFail("an unknown date is not a reason to hide a problem")
        }
    }

    func testAwaitingConsentIsExplained() {
        let event = ScreenshotEvent.processed(ProcessingReport(originalURL: original, outcome: .skipped(.awaitingConsent)))
        guard case .problem(let text) = TryIt.apply(event, entry: nil, openedAt: nil, to: .waiting(note: nil)) else {
            return XCTFail()
        }
        XCTAssertTrue(text.contains("not allowed"), text)
    }

    func testUnrelatedSkipsChangeNothing() {
        for reason in [SkipReason.missing, .alreadyIndexed, .restoredByUndo] {
            let event = ScreenshotEvent.processed(ProcessingReport(originalURL: original, outcome: .skipped(reason)))
            XCTAssertEqual(TryIt.apply(event, entry: nil, openedAt: nil, to: .waiting(note: "n")), .waiting(note: "n"))
        }
    }

    func testAResultStays() {
        let shown = TryItState.result(TryItResult(path: "/a.png", oldName: "S.png", newName: "A.png", hashtags: []))
        let later = ScreenshotEvent.failed(originalURL: original, problem: UserFacingProblem(message: "x"))
        XCTAssertEqual(TryIt.apply(later, entry: nil, openedAt: nil, to: shown), shown)
        XCTAssertEqual(TryIt.withNote("n", in: shown), shown)
        XCTAssertEqual(TryIt.withNote("n", in: .waiting(note: nil)), .waiting(note: "n"))
    }

    func testWaitingNotes() {
        XCTAssertNil(TryIt.waitingNote(localDownload: nil, isInstalling: false, isPaused: false))
        XCTAssertEqual(TryIt.waitingNote(localDownload: (0.45, 9.1), isInstalling: false, isPaused: false),
                       "Downloading Inkling 2 Mini · 4.1 of 9.1 GB. Your screenshot is named when it finishes.")
        XCTAssertEqual(TryIt.waitingNote(localDownload: nil, isInstalling: true, isPaused: false),
                       "Installing the local model. Your screenshot is named when it is ready.")
        XCTAssertEqual(TryIt.waitingNote(localDownload: (0.45, 9.1), isInstalling: false, isPaused: true),
                       "Shotkeeper is paused. Resume it from the menu bar to see a result.")
    }
}

final class ConnectionTestTextTests: XCTestCase {
    func testClairicErrorsAreReadable() {
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.unauthorized("HTTP 401: bad token"), backend: .clairic),
                       "Cloudflare did not accept the token. Check the account ID, and that the token has Workers AI Read and Edit permissions.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.unreachable("The Internet connection appears to be offline."),
                                                  backend: .clairic),
                       "Could not reach Cloudflare. Check the internet connection and try again.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.badRequest(status: 404, message: "{\"errors\":[]}"), backend: .clairic),
                       "Cloudflare could not find this account (HTTP 404). Check the account ID.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.badRequest(status: 400, message: "x"), backend: .clairic),
                       "Cloudflare rejected the test request (HTTP 400). Check the account ID.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.serverError(status: 503, message: "x"), backend: .clairic),
                       "Cloudflare had a problem (HTTP 503). Try again in a minute.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.rateLimited(retryAfter: 3), backend: .clairic),
                       "Cloudflare is limiting requests right now. Try again in a minute.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.invalidResponse("x"), backend: .clairic),
                       "Cloudflare answered, but the answer could not be read. Try again.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.notConfigured("Cloudflare account ID is not set"), backend: .clairic),
                       "Cloudflare account ID is not set.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.badRequest(status: 0, message: "Image is empty"), backend: .clairic),
                       "The test image could not be sent.")
    }

    func testServerMessagesNeverReachTheText() {
        let secretish = "Authorization: Bearer abc123 /Users/p/private"
        let errors: [AnalyzerError] = [.unauthorized(secretish), .unreachable(secretish), .serverError(status: 500, message: secretish),
                                       .badRequest(status: 422, message: secretish), .invalidResponse(secretish)]
        for backend in AppSettings.Backend.allCases {
            for error in errors {
                let text = ConnectionTestText.failure(error, backend: backend)
                XCTAssertFalse(text.contains("abc123"), text)
                XCTAssertFalse(text.contains("/Users"), text)
            }
        }
    }

    func testOtherBackendsAndErrors() {
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.unreachable("x"), backend: .localInkling),
                       "Could not reach the local model server.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.unreachable("x"), backend: .customEndpoint),
                       "Could not reach the server at that URL.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.unauthorized("x"), backend: .customEndpoint),
                       "The server did not accept the API key.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.badRequest(status: 422, message: "x"), backend: .customEndpoint),
                       "The server rejected the test request (HTTP 422). Check the model name.")
        XCTAssertEqual(ConnectionTestText.failure(ImagePreparerError.unreadable("test image"), backend: .clairic),
                       "The image could not be read.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.unauthorized("x"), backend: .openRouter),
                       "OpenRouter did not accept the API key. Check the key at openrouter.ai/keys.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.unreachable("x"), backend: .openRouter),
                       "Could not reach OpenRouter. Check the internet connection and try again.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.rateLimited(retryAfter: nil), backend: .openRouter),
                       "OpenRouter is limiting requests right now. Try again in a minute.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.serverError(status: 503, message: "x"), backend: .openRouter),
                       "OpenRouter had a problem (HTTP 503). Try again in a minute.")
        XCTAssertEqual(ConnectionTestText.failure(AnalyzerError.notConfigured("OpenRouter API key is not set"), backend: .openRouter),
                       "OpenRouter API key is not set.")
    }
}

final class IconGeometryTests: XCTestCase {
    func testAppIconProportionsFollowTheSpec() {
        let icon = IconGeometry.appIcon
        XCTAssertEqual(icon.backgroundCornerRadius, 0.225)
        XCTAssertEqual(icon.cornerStroke, 0.056)
        XCTAssertEqual(icon.sparkleRadius * 2, 0.27, accuracy: 1e-9, "sparkle ≈ 27% of the size")
        XCTAssertEqual(IconGeometry.backgroundRGB, 0x5856D6)
    }

    func testCornersAreSymmetricLShapesInsideTheIcon() {
        for geometry in [IconGeometry.appIcon, .menuBarGlyph] {
            let corners = geometry.viewfinderCorners
            XCTAssertEqual(corners.count, 4)
            for corner in corners {
                XCTAssertEqual(corner.count, 3)
                let vertex = corner[1]
                for end in [corner[0], corner[2]] {
                    let length = abs(end.x - vertex.x) + abs(end.y - vertex.y)
                    XCTAssertEqual(length, geometry.cornerArm, accuracy: 1e-9)
                    XCTAssertTrue(end.x == vertex.x || end.y == vertex.y, "each arm is straight")
                }
                for point in corner { XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y)) }
            }
            // Mirror symmetry: top-left mirrored horizontally is top-right.
            XCTAssertEqual(corners[0].map { IconPoint(1 - $0.x, $0.y) }, corners[1].reversed())
        }
    }

    func testSparkleIsCenteredAndScales() {
        let (tips, controls) = IconGeometry.appIcon.sparkle()
        XCTAssertEqual(tips.count, 4)
        XCTAssertEqual(controls.count, 4)
        XCTAssertEqual(tips[0].y, 0.5 - 0.135, accuracy: 1e-9)
        XCTAssertEqual(tips[1].x, 0.5 + 0.135, accuracy: 1e-9)
        let big = IconGeometry.menuBarGlyph.sparkle(scale: 1.35).tips
        XCTAssertEqual(big[1].x - 0.5, 0.2 * 1.35, accuracy: 1e-9)
        for control in controls {
            XCTAssertLessThan(abs(control.x - 0.5), 0.135 * 0.5, "the sides curve inward")
        }
    }
}
