import XCTest
@testable import ShotkeeperCore

private let gb: UInt64 = 1_073_741_824

private func clairicSettings(account: String? = "acct", consent: Bool) -> AppSettings {
    var settings = AppSettings()
    settings.backend = .clairic
    settings.clairicAccountID = account
    settings.hasSeenPrivacyNotice = consent
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
        settings.hasSeenPrivacyNotice = false
        XCTAssertEqual(BackendGate.readiness(settings: settings, hasClairicToken: false), .needsConsent)
        XCTAssertTrue(BackendGate.sendsScreenshotsOffThisMac(.customEndpoint))
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
        XCTAssertEqual(BackendGate.statusReason(for: .needsConsent), "Setup is not finished")
        XCTAssertEqual(BackendGate.statusReason(for: .notConfigured("Cloudflare API token is not set")),
                       "Cloudflare API token is not set")
    }

    func testMenuSaysNotWatchingYet() {
        let summary = MenuText.status(queue: .idle, watchedFolderName: "Desktop", indexedCount: 0,
                                      notWatchingReason: "Setup is not finished", now: Date())
        XCTAssertEqual(summary, MenuStatusSummary(dot: .orange, headline: "Not watching yet", detail: "Setup is not finished"))
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
        XCTAssertEqual(flow.primaryAction(), .skipConnection)
        flow.inputs.accountID = "acct"
        XCTAssertEqual(flow.primaryAction(), .skipConnection, "an account ID without a token is not enough")
        flow.inputs.hasTokenDraft = true
        XCTAssertEqual(flow.primary, SetupPrimaryButton(title: "Continue", isEnabled: true, action: .saveConnection(.clairic)))

        flow.advance()
        XCTAssertEqual(flow.step, .tryIt)
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
        XCTAssertEqual(flow.choice, .localInkling)
        XCTAssertTrue(flow.chooseNext())
        XCTAssertEqual(flow.choice, .clairic)

        var small = SetupFlow(settings: AppSettings(), cards: SetupCards.make(physicalMemoryBytes: 8 * gb))
        XCTAssertFalse(small.choose(.localInkling))
        XCTAssertFalse(small.chooseNext())
        XCTAssertEqual(small.choice, .clairic)
    }

    func testRerunStartsFromTheCurrentSettings() {
        var settings = AppSettings()
        settings.hasSeenPrivacyNotice = true
        settings.backend = .localInkling
        settings.launchAtLogin = false
        let flow = SetupFlow(settings: settings, cards: cards16)
        XCTAssertTrue(flow.consentChecked)
        XCTAssertEqual(flow.choice, .localInkling)
        XCTAssertFalse(flow.openAtLogin, "a re-run keeps the user's login-item choice")

        settings.backend = .customEndpoint
        XCTAssertEqual(SetupFlow(settings: settings, cards: cards16).choice, .clairic, "no card for a custom endpoint")

        settings.backend = .localInkling
        XCTAssertEqual(SetupFlow(settings: settings, cards: SetupCards.make(physicalMemoryBytes: 8 * gb)).choice, .clairic)
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
        let state = TryIt.apply(.processed(report), entry: entry(tags: ["semiconductor", "flashcards"]), to: .waiting(note: nil))
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
        guard case .result(let result) = TryIt.apply(.processed(report), entry: nil, to: .waiting(note: nil)) else {
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
        XCTAssertEqual(TryIt.apply(failed, entry: nil, to: .waiting(note: nil)),
                       .problem("Could not name that screenshot: the model backend rejected the token. Take another one to try again."))
        let excluded = ScreenshotEvent.processed(ProcessingReport(
            originalURL: original, outcome: .skipped(.excluded(.init(.filenameContains, "bank")))))
        guard case .problem(let text) = TryIt.apply(excluded, entry: nil, to: .waiting(note: nil)) else { return XCTFail() }
        XCTAssertTrue(text.contains("exclude rule"))
        let paused = ScreenshotEvent.processed(ProcessingReport(originalURL: original, outcome: .skipped(.paused(until: Date()))))
        guard case .problem(let pausedText) = TryIt.apply(paused, entry: nil, to: .waiting(note: nil)) else { return XCTFail() }
        XCTAssertTrue(pausedText.contains("paused"))
    }

    func testUnrelatedSkipsChangeNothing() {
        for reason in [SkipReason.missing, .alreadyIndexed, .restoredByUndo] {
            let event = ScreenshotEvent.processed(ProcessingReport(originalURL: original, outcome: .skipped(reason)))
            XCTAssertEqual(TryIt.apply(event, entry: nil, to: .waiting(note: "n")), .waiting(note: "n"))
        }
    }

    func testAResultStays() {
        let shown = TryItState.result(TryItResult(path: "/a.png", oldName: "S.png", newName: "A.png", hashtags: []))
        let later = ScreenshotEvent.failed(originalURL: original, problem: UserFacingProblem(message: "x"))
        XCTAssertEqual(TryIt.apply(later, entry: nil, to: shown), shown)
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
