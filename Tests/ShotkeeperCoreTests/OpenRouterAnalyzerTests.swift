import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShotkeeperCore

/// OpenRouter backend: the shared `OpenAICompatibleAnalyzer` with `OpenRouterBackend.profile`. Fixtures are built
/// from the documented shapes (Tests/ShotkeeperCoreTests/Fixtures/README.md, docs/research/openrouter.md).
final class OpenRouterAnalyzerTests: XCTestCase {
    private func analyzer(_ transport: ScriptedTransport, key: String = "sk-or-v1-test", model: String? = nil)
        -> OpenAICompatibleAnalyzer {
        OpenAICompatibleAnalyzer(configuration: OpenRouterBackend.configuration(apiKey: key, model: model), transport: transport)
    }

    private func fixture(_ name: String) throws -> ScriptedTransport.Step { .ok(try Fixture.data(name)) }

    private func analyze(_ steps: [ScriptedTransport.Step]) async throws -> (ScreenshotAnalysis, ScriptedTransport) {
        let transport = ScriptedTransport(steps)
        let result = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
        return (result, transport)
    }

    // MARK: Request

    func testRequestBody() async throws {
        let transport = ScriptedTransport([try fixture("openrouter-response-success.json")])
        let image = samplePNG()
        _ = try await analyzer(transport).analyze(image, context: sampleContext)
        let request = transport.request(0)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-v1-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://github.com/paragrudani1/shotkeeper")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Shotkeeper")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-OpenRouter-Title"), "Shotkeeper")

        let body = try jsonBody(request)
        XCTAssertEqual(body["model"], "thinkingmachines/inkling-2-mini")
        XCTAssertEqual(body["temperature"], 0)
        XCTAssertEqual(body["stream"], false)
        XCTAssertEqual(body["max_tokens"], 800)
        XCTAssertNil(body["max_completion_tokens"], "io.net does not list it; require_parameters would exclude io.net")
        // Reasoning off with the documented switch; not the local-server variants, not `exclude` (still billed).
        XCTAssertEqual(body["reasoning"], ["effort": "none"])
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["chat_template_kwargs"])
        XCTAssertEqual(body["logprobs"], true)
        XCTAssertEqual(body["provider"], ["data_collection": "deny", "zdr": true, "require_parameters": true])
        XCTAssertNil(body["usage"], "usage accounting is automatic; `usage.include` is deprecated")

        let format = try XCTUnwrap(body["response_format"])
        XCTAssertEqual(format["type"], "json_schema")
        XCTAssertEqual(format["json_schema"]?["name"], "screenshot_analysis")
        XCTAssertEqual(format["json_schema"]?["strict"], true)
        XCTAssertEqual(format["json_schema"]?["schema"], OpenAICompatibleAnalyzer.jsonSchema)

        // Text first, then the image (OpenRouter's advice); the system message is text only.
        let messages = try XCTUnwrap(body["messages"]?.arrayValue)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertNotNil(messages[0]["content"]?.stringValue)
        let parts = try XCTUnwrap(messages[1]["content"]?.arrayValue)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"], "text")
        XCTAssertEqual(parts[1], ["type": "image_url",
                                  "image_url": ["url": .string("data:image/png;base64,\(image.data.base64EncodedString())")]])
    }

    func testModelOverrideAndBlankModel() throws {
        XCTAssertEqual(OpenRouterBackend.configuration(apiKey: "k", model: "  ").model, OpenRouterBackend.defaultModel)
        XCTAssertEqual(OpenRouterBackend.configuration(apiKey: "k", model: nil).model, "thinkingmachines/inkling-2-mini")
        let custom = OpenRouterBackend.configuration(apiKey: "k", model: " thinkingmachines/inkling-2-mini-20261120 ")
        XCTAssertEqual(custom.model, "thinkingmachines/inkling-2-mini-20261120")
        XCTAssertEqual(custom.baseURL.absoluteString, "https://openrouter.ai/api/v1")
        let a = OpenAICompatibleAnalyzer(configuration: custom, transport: ScriptedTransport([]))
        XCTAssertEqual(a.backendID, "openrouter")
        XCTAssertEqual(a.producedBy, "openrouter:thinkingmachines/inkling-2-mini-20261120")
    }

    func testMissingKeyIsNotConfiguredAndSendsNothing() async {
        let transport = ScriptedTransport([])
        await assertAnalyzerError(.notConfigured("OpenRouter API key is not set")) {
            _ = try await self.analyzer(transport, key: "  ").analyze(samplePNG(), context: sampleContext)
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testUnsupportedImageTypeIsRefusedBeforeSending() async {
        let transport = ScriptedTransport([])
        var image = samplePNG()
        image.mimeType = "image/heic"
        await assertAnalyzerErrorCase({ _ = try await self.analyzer(transport).analyze(image, context: sampleContext) }) {
            if case .badRequest(status: 0, _) = $0 { return true } else { return false }
        }
        XCTAssertEqual(transport.requestCount, 0)
    }

    // MARK: Responses

    func testSuccessUsesTitleTokenLogprobsAndReportsPromptTokens() async throws {
        let (result, transport) = try await analyze([try fixture("openrouter-response-success.json")])
        XCTAssertEqual(transport.requestCount, 1)
        XCTAssertEqual(result.title, "Stripe invoice for October")
        XCTAssertEqual(result.sourceAppOrSite, "Stripe")
        XCTAssertEqual(result.contentType, .receipt)
        XCTAssertEqual(result.tags, ["invoice", "stripe", "billing", "october"])
        XCTAssertEqual(result.keyText, "Invoice #INV-2041 Total due $48.00")
        XCTAssertEqual(result.dateMentioned, "2026-11-15")
        XCTAssertEqual(result.producedBy, "openrouter:thinkingmachines/inkling-2-mini")
        XCTAssertEqual(result.billedInputTokens, 1450)
        // The fixture's four title tokens: -0.02, -0.15, -0.30, -0.05 → exp(mean) ≈ 0.85.
        XCTAssertEqual(result.titleConfidence, exp((-0.02 - 0.15 - 0.30 - 0.05) / 4), accuracy: 1e-9)
    }

    func testReasoningOffReplyWithoutLogprobsFallsBackToParsedConfidence() async throws {
        let (result, _) = try await analyze([try fixture("openrouter-response-reasoning-off.json")])
        XCTAssertEqual(result.title, "GitHub pull request review")
        XCTAssertEqual(result.contentType, .code)
        XCTAssertNil(result.dateMentioned)
        XCTAssertEqual(result.titleConfidence, 1.0, "no logprobs: valid JSON counts as 1.0, like the local backend")
        XCTAssertEqual(result.billedInputTokens, 1390)
    }

    func testMalformedJSONGetsOneRepairCallWithoutTheImage() async throws {
        let repaired = #"{"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"{\"title\": \"Coffee shop receipt\", \"source_app_or_site\": null, \"content_type\": \"receipt\", \"description\": \"A receipt.\", \"tags\": [\"coffee\"], \"key_text\": null, \"date_mentioned\": null}"}}],"usage":{"prompt_tokens":300,"completion_tokens":40,"total_tokens":340,"cost":0.0000345}}"#
        let (result, transport) = try await analyze([try fixture("openrouter-response-malformed.json"), .ok(repaired)])
        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertEqual(result.title, "Coffee shop receipt")
        XCTAssertEqual(result.titleConfidence, 0.6)
        XCTAssertEqual(result.billedInputTokens, 1700, "both calls are billed")
        let repair = transport.request(1)
        XCTAssertFalse(String(decoding: repair.httpBody!, as: UTF8.self).contains("data:image"))
        XCTAssertEqual(try jsonBody(repair)["reasoning"], ["effort": "none"], "the repair call keeps reasoning off")
        XCTAssertEqual(repair.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-v1-test")
    }

    func testMalformedTwiceIsInvalidResponse() async {
        let transport = ScriptedTransport([try! fixture("openrouter-response-malformed.json"),
                                           try! fixture("openrouter-response-malformed.json")])
        await assertAnalyzerErrorCase({ _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext) }) {
            if case .invalidResponse = $0 { return true } else { return false }
        }
    }

    func testTitleThatFailsTheRulesKeepsTheName() async throws {
        let content = #"{\"title\": \"Slack\", \"source_app_or_site\": \"Slack\", \"content_type\": \"chat\", \"description\": \"A chat.\", \"tags\": [\"slack\"], \"key_text\": null, \"date_mentioned\": null}"#
        let body = #"{"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"\#(content)"}}]}"#
        let (result, _) = try await analyze([.ok(body)])
        XCTAssertNil(result.title)
        XCTAssertEqual(result.titleConfidence, 0)
        XCTAssertEqual(result.contentType, .chat, "the other fields are still indexed")
    }

    // MARK: Errors

    func testOutOfCreditsIsAFinalBadRequestWithReadableText() async throws {
        let transport = ScriptedTransport([.status(402, String(decoding: try Fixture.data("openrouter-error-402.json"), as: UTF8.self))])
        do {
            _ = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
            XCTFail("expected 402")
        } catch let error as AnalyzerError {
            guard case .badRequest(402, let message) = error else { return XCTFail("got \(error)") }
            XCTAssertTrue(message.hasPrefix("Your account or API key has insufficient credits"))
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(UserFacingError.problem(for: error).message,
                           "the model backend is out of credits (HTTP 402). Add credits, then try again")
            XCTAssertEqual(ConnectionTestText.failure(error, backend: .openRouter),
                           "OpenRouter is out of credits. Add credits at openrouter.ai/settings/credits, then try again.")
        }
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testInFlightBudget402IsRetriedAfterRetryAfter() async throws {
        let body = String(decoding: try Fixture.data("openrouter-error-402-in-flight.json"), as: UTF8.self)
        let transport = ScriptedTransport([.status(402, body, headers: ["Retry-After": "30"])])
        await assertAnalyzerError(.rateLimited(retryAfter: 30)) {
            _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext)
        }
    }

    func testRateLimitedUsesRetryAfter() async throws {
        let body = String(decoding: try Fixture.data("openrouter-error-429.json"), as: UTF8.self)
        let transport = ScriptedTransport([.status(429, body, headers: ["Retry-After": "60"])])
        await assertAnalyzerError(.rateLimited(retryAfter: 60)) {
            _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext)
        }
    }

    func testStatusMapping() async {
        func error(_ status: Int, _ body: String) async -> AnalyzerError? {
            let transport = ScriptedTransport([.status(status, body)])
            do { _ = try await analyzer(transport).analyze(samplePNG(), context: sampleContext); return nil } catch {
                return error as? AnalyzerError
            }
        }
        let invalidKey = #"{"error":{"code":401,"message":"Missing Authentication header"}}"#
        guard case .unauthorized(let message) = await error(401, invalidKey) else { return XCTFail("401") }
        XCTAssertTrue(message.contains("Missing Authentication header"))

        let policy = #"{"error":{"code":403,"message":"Input flagged","metadata":{"error_type":"content_policy_violation"}}}"#
        let declined = await error(403, policy)
        XCTAssertEqual(declined, .badRequest(status: 403, message: "Input flagged (content_policy_violation)"),
                       "a declined image fails alone; the key is fine, so the queue is not held")
        let budget = #"{"error":{"code":403,"message":"Budget limit exceeded (weekly limit).","metadata":{"limit_source":"openrouter_key_limit"}}}"#
        guard case .unauthorized = await error(403, budget) else { return XCTFail("budget 403 holds the queue") }

        let noProvider = #"{"error":{"code":503,"message":"No available provider","metadata":{"error_type":"provider_overloaded"}}}"#
        let unavailable = await error(503, noProvider)
        XCTAssertEqual(unavailable, .serverError(status: 503, message: "No available provider (provider_overloaded)"))
        XCTAssertEqual(unavailable?.isRetryable, true)

        let invalid = #"{"error":{"code":400,"message":"Image too large","metadata":{"error_type":"image_too_large"}}}"#
        let tooLarge = await error(400, invalid)
        XCTAssertEqual(tooLarge, .badRequest(status: 400, message: "Image too large (image_too_large)"))
    }

    func testABadRequestIsNotResentWithoutParameters() async {
        // Unlike a local server, OpenRouter's parameters are documented: a 400 naming one is a real error.
        let transport = ScriptedTransport([.status(400, #"{"error":{"code":400,"message":"unsupported response_format"}}"#)])
        await assertAnalyzerErrorCase({ _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext) }) {
            if case .badRequest(400, _) = $0 { return true } else { return false }
        }
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testErrorInsideA200BodyIsMappedByItsCode() async throws {
        let transport = ScriptedTransport([try fixture("openrouter-response-error-in-200.json")])
        await assertAnalyzerError(.serverError(status: 502, message: "Provider returned error")) {
            _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext)
        }
        let choiceError = #"{"choices":[{"index":0,"finish_reason":"error","message":{"role":"assistant","content":"{\"title\": \"Par"},"error":{"code":429,"message":"Rate limit exceeded","metadata":{"error_type":"rate_limit_exceeded"}}}]}"#
        let second = ScriptedTransport([.ok(choiceError)])
        await assertAnalyzerError(.rateLimited(retryAfter: nil)) {
            _ = try await self.analyzer(second).analyze(samplePNG(), context: sampleContext)
        }
        let inFlight = #"{"error":{"code":402,"message":"in flight","metadata":{"limit_source":"openrouter_in_flight_budget"}}}"#
        await assertAnalyzerError(.rateLimited(retryAfter: nil)) {
            _ = try await self.analyzer(ScriptedTransport([.ok(inFlight)])).analyze(samplePNG(), context: sampleContext)
        }
    }

    func testErrorMessageNeverEchoesTheBodyWhenItIsNotOpenRouterShaped() {
        XCTAssertEqual(OpenRouterBackend.errorMessage(from: Data("<html>Bad gateway</html>".utf8)), "<html>Bad gateway</html>")
        XCTAssertEqual(OpenRouterBackend.errorMessage(from: Data(#"{"error":{"code":401,"message":"No API key"}}"#.utf8)),
                       "No API key")
    }

    // MARK: Pricing

    func testPriceStaysHiddenUntilMeasured() {
        XCTAssertNil(OpenRouterPricing.measuredUSDPerThousandScreenshots, "set only from the live test")
        XCTAssertNil(OpenRouterPricing.perThousandText())
        XCTAssertEqual(OpenRouterPricing.perThousandText(usd: 0.25), "About $0.25 for 1,000 screenshots")
        XCTAssertEqual(OpenRouterPricing.perThousandText(usd: 1.6), "About $2 for 1,000 screenshots")
    }
}

final class TitleTokenConfidenceTests: XCTestCase {
    private func tokens(_ pairs: [(String, Double)]) -> [TokenLogprob] { pairs.map { TokenLogprob(token: $0.0, logprob: $0.1) } }

    func testTitleTokensOnly() throws {
        let t = tokens([("{\"", -0.5), ("title", -0.5), ("\": \"", -0.5), ("Tweet", -0.1), (" about", -0.2), (" chips", -0.3),
                        ("\", \"", -2), ("tags", -2), ("\": [\"chips\"]}", -2)])
        XCTAssertEqual(try XCTUnwrap(TitleTokenConfidence.confidence(tokens: t)), exp(-0.2), accuracy: 1e-9)
    }

    func testATokenStraddlingTheQuoteCounts() throws {
        // `": "Tw` carries the first letters of the title, so it is part of the title's probability.
        let t = tokens([("{\"title", 0), ("\": \"Tw", -0.4), ("eet", -0.2), ("\"}", -1)])
        XCTAssertEqual(try XCTUnwrap(TitleTokenConfidence.confidence(tokens: t)), exp(-0.3), accuracy: 1e-9)
    }

    func testIgnoresTitleInsideOtherValuesAndNestedObjects() throws {
        let json = #"{"description": "the \"title\": \"fake\" text", "meta": {"title": "nested"}, "title": "Real one"}"#
        let range = try XCTUnwrap(TitleTokenConfidence.valueRange(of: "title", in: Array(json.utf8)))
        XCTAssertEqual(String(decoding: Array(json.utf8)[range], as: UTF8.self), "Real one")
    }

    func testProseOrFenceBeforeTheObjectIsSkipped() throws {
        let json = "```json\n{\"title\": \"Fenced\"}\n```"
        let range = try XCTUnwrap(TitleTokenConfidence.valueRange(of: "title", in: Array(json.utf8)))
        XCTAssertEqual(String(decoding: Array(json.utf8)[range], as: UTF8.self), "Fenced")
    }

    func testNilWithoutATitleOrWithAnEmptyOne() {
        XCTAssertNil(TitleTokenConfidence.confidence(tokens: tokens([("{\"tags\": []}", -0.1)])))
        XCTAssertNil(TitleTokenConfidence.confidence(tokens: tokens([("{\"title\": \"\"}", -0.1)])))
        XCTAssertNil(TitleTokenConfidence.confidence(tokens: tokens([("{\"title\": null}", -0.1)])))
        XCTAssertNil(TitleTokenConfidence.confidence(tokens: []))
    }

    func testNonFiniteLogprobsAreSkipped() throws {
        let t = tokens([("{\"title\": \"", 0), ("A", -.infinity), ("B", -0.1), ("\"}", 0)])
        XCTAssertEqual(try XCTUnwrap(TitleTokenConfidence.confidence(tokens: t)), exp(-0.1), accuracy: 1e-9)
    }
}

final class TitleRulesTests: XCTestCase {
    private func problem(_ title: String, source: String? = nil) -> TitleRules.Problem? {
        TitleRules.problem(with: title, sourceAppOrSite: source)
    }

    func testGoodTitlesPass() {
        XCTAssertNil(problem("Stripe invoice for October", source: "Stripe"))
        XCTAssertNil(problem("GitHub pull request review", source: "GitHub"))
        XCTAssertNil(problem("Tweet about semiconductor flashcards", source: "X"))
        XCTAssertNil(problem("NYT article on rate cuts", source: "nytimes.com"))
        XCTAssertNil(problem("Q3 roadmap"))
        XCTAssertNil(problem("Rechnung für Oktober"))
    }

    func testGenericTitles() {
        for title in ["Screenshot", "Image", "Untitled", "Screen", "Untitled image", "Screenshot 2026-11-22 at 10.00.01"] {
            XCTAssertEqual(problem(title), .generic, title)
        }
    }

    func testOnlyDigitsOrADate() {
        for title in ["2026-11-22", "12345", "11/22/2026", "Nov 22, 2026", "Monday 3rd March 2026", "22 November"] {
            XCTAssertEqual(problem(title), .onlyDigitsOrDate, title)
        }
        XCTAssertNil(problem("November budget 2026"), "a date plus a subject is fine")
    }

    func testLengthBounds() {
        XCTAssertEqual(problem("Ab"), .tooShort)
        XCTAssertEqual(problem(String(repeating: "word ", count: 13)), .tooLong)
        XCTAssertEqual(problem(String(repeating: "a", count: 121)), .tooLong)
        XCTAssertNil(problem(String(repeating: "a", count: 60)))
    }

    func testNotFilenameSafe() {
        XCTAssertEqual(problem("/// ..."), .notFilenameSafe)
        XCTAssertEqual(problem("   "), .notFilenameSafe)
    }

    func testMostlyTheAppOrSiteName() {
        XCTAssertEqual(problem("Slack", source: "Slack"), .mostlyAppName)
        XCTAssertEqual(problem("Google Chrome window", source: "Google Chrome"), .mostlyAppName)
        XCTAssertEqual(problem("nytimes.com", source: "nytimes.com"), .mostlyAppName)
        XCTAssertEqual(problem("Figma screenshot", source: "Figma"), .mostlyAppName)
        XCTAssertNil(problem("Slack thread about launch dates", source: "Slack"))
        XCTAssertNil(problem("Slack", source: nil), "no source answer: nothing to compare")
    }
}
