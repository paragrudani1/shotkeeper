import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShotkeeperCore

final class ClairicFieldSchemaTests: XCTestCase {
    /// Every key in every field spec must (a) exist in the saved input schema, and (b) be allowed for that field's
    /// type. Allowed-for-type is read from the saved schema's own key descriptions ("text only.", "List only.",
    /// "number, date, time, datetime, and number/date lists only.", …): a key other than `type`/`instructions`
    /// is allowed only when its description names the field's type.
    func testFieldSpecsOnlyUseKeysTheSavedInputSchemaAllowsForTheirType() throws {
        let url = Fixture.repoRoot.appendingPathComponent("docs/research/clairic/schema-input.json")
        let schema = try AnalysisJSON.parse(Data(contentsOf: url))
        let specSchema = try XCTUnwrap(schema["properties"]?["fields"]?["additionalProperties"])
        let keyDocs = try XCTUnwrap(specSchema["properties"]?.objectValue)
        let types = try XCTUnwrap(keyDocs["type"]?["enum"]?.arrayValue).compactMap(\.stringValue)
        let namePattern = try XCTUnwrap(schema["properties"]?["fields"]?["propertyNames"]?["pattern"]?.stringValue)
        let nameRegex = try NSRegularExpression(pattern: namePattern)
        let universal: Set<String> = ["type", "instructions"]

        let fields = ClairicFieldSchema.fields()
        XCTAssertEqual(Set(fields.keys), Set(AnalysisFields.all))
        for (name, spec) in fields {
            XCTAssertNotNil(nameRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)), "bad field name \(name)")
            let type = try XCTUnwrap(spec["type"]?.stringValue, name)
            XCTAssertTrue(types.contains(type), "\(name): unknown type \(type)")
            for key in try XCTUnwrap(spec.objectValue).keys {
                let doc = try XCTUnwrap(keyDocs[key], "\(name).\(key) is not a key in schema-input.json")
                if universal.contains(key) { continue }
                let description = try XCTUnwrap(doc["description"]?.stringValue, "\(key) has no description").lowercased()
                XCTAssertTrue(description.contains(type), "\(name).\(key) not allowed for type \(type): \"\(description)\"")
            }
            if type == "enum" { XCTAssertNotNil(spec["enum"], "enum fields require `enum`") }
            if type == "list" { XCTAssertNotNil(spec["items"], "list fields require `items`") }
            if let items = spec["items"]?.stringValue { XCTAssertTrue(["text", "number", "date"].contains(items)) }
            // `knowledge` is "Not combinable with source_only".
            XCTAssertFalse(spec["knowledge"] != nil && spec["source_only"] != nil, name)
        }
    }

    func testCostShape() {
        // 3 text passes (title, description, key_text) + 1 shared pass.
        XCTAssertEqual(ClairicFieldSchema.expectedPasses, 4)
        XCTAssertEqual(ClairicFieldSchema.fields()[AnalysisFields.sourceAppOrSite]?["type"], "list")
        XCTAssertEqual(ClairicFieldSchema.fields()[AnalysisFields.contentType]?["nullable"], false)
        XCTAssertEqual(ClairicFieldSchema.fields()[AnalysisFields.title]?["knowledge"], true)
    }

    func testImageTokenFormulaMatchesDocExample() {
        // model-backends.md / model page: 1024×640 → 642 tokens.
        XCTAssertEqual(ClairicFieldSchema.estimatedImageTokens(width: 1024, height: 640), 642)
        XCTAssertEqual(ClairicFieldSchema.estimatedImageTokens(width: 1280, height: 800), 1002)
        // Small images are scaled up to ~256×256 → 8×8 patches + 2.
        XCTAssertEqual(ClairicFieldSchema.estimatedImageTokens(width: 100, height: 100), 66)
        XCTAssertEqual(ClairicFieldSchema.estimatedImageTokens(width: 0, height: 10), 0)
    }
}

final class CloudflareClairicAnalyzerTests: XCTestCase {
    private let credentials = ClairicCredentials(accountID: "0123456789abcdef0123456789abcdef", apiToken: "test-token-not-real")

    private func analyzer(_ transport: ScriptedTransport) -> CloudflareClairicAnalyzer {
        CloudflareClairicAnalyzer(credentials: credentials, transport: transport, timeZone: TimeZone(identifier: "UTC")!)
    }

    // MARK: Request

    func testRequestURLHeadersAndExactBody() throws {
        let image = samplePNG()
        let request = try analyzer(ScriptedTransport([])).makeRequest(image: image, context: sampleContext)
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.cloudflare.com/client/v4/accounts/0123456789abcdef0123456789abcdef/ai/run/@cf/cloudflare/clairic")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-not-real")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try jsonBody(request)
        XCTAssertEqual(body.objectValue.map { Set($0.keys) }, ["model", "state", "fields", "images", "reference_date"])
        XCTAssertEqual(body["model"], "@cf/cloudflare/clairic")
        XCTAssertEqual(body["state"], "")
        XCTAssertEqual(body["reference_date"], "2026-03-15")
        XCTAssertEqual(body["images"], [["content_type": "image/png", "base64": .string(image.data.base64EncodedString())]])

        let expectedFields = try AnalysisJSON.parse(#"""
        {
          "title": {"type": "text", "maxLength": 60, "knowledge": true,
                    "instructions": "A 3-6 word descriptive filename for this screenshot in sentence case, naming the subject, e.g. \"Tweet semiconductor flashcards\" or \"Stripe invoice for October\". No dates, no file extension, never just \"Screenshot\"."},
          "description": {"type": "text", "maxLength": 240, "knowledge": true,
                          "instructions": "One or two sentences describing what the screenshot shows and why it might matter."},
          "key_text": {"type": "text", "maxLength": 500,
                       "instructions": "The main visible text of the screenshot (headline, message or code), verbatim, without UI chrome."},
          "source_app_or_site": {"type": "list", "items": "text", "max_items": 1, "knowledge": true,
                                 "instructions": "The app or website shown, as its common name (e.g. \"X\", \"Slack\", \"GitHub\", \"Figma\", \"Terminal\", \"nytimes.com\"). Null if it cannot be told."},
          "content_type": {"type": "enum", "enum": ["tweet", "article", "code", "chat", "receipt", "design", "other"],
                           "nullable": false, "instructions": "The kind of content shown in the screenshot."},
          "tags": {"type": "list", "items": "text", "max_items": 8, "knowledge": true,
                   "instructions": "Up to 8 short lowercase keywords (1-2 words each) for finding this screenshot later."},
          "date_mentioned": {"type": "date", "source_only": true,
                             "instructions": "The most prominent calendar date printed in the screenshot content (post date, due date, event date). Null if none."}
        }
        """#)
        XCTAssertEqual(body["fields"], expectedFields)
        // Integral numbers are encoded without a fraction.
        let raw = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(raw.contains(#""max_items":8"#), raw.prefix(200).description)
    }

    func testReferenceDateUsesConfiguredTimeZone() throws {
        let late = AnalysisContext(originalFilename: "x.png", capturedAt: ISO8601DateFormatter().date(from: "2026-03-15T23:30:00Z")!)
        let tokyo = CloudflareClairicAnalyzer(credentials: credentials, transport: ScriptedTransport([]),
                                              timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(try jsonBody(tokyo.makeRequest(image: samplePNG(), context: late))["reference_date"], "2026-03-16")
    }

    func testNotConfigured() async {
        for creds in [ClairicCredentials(accountID: "", apiToken: "t"), ClairicCredentials(accountID: "abc", apiToken: "  "),
                      ClairicCredentials(accountID: "abc/../x", apiToken: "t")] {
            let transport = ScriptedTransport([])
            let a = CloudflareClairicAnalyzer(credentials: creds, transport: transport)
            await assertAnalyzerErrorCase({ _ = try await a.analyze(samplePNG(), context: sampleContext) }) {
                if case .notConfigured = $0 { return true } else { return false }
            }
            XCTAssertEqual(transport.requestCount, 0)
        }
    }

    func testCredentialsDescriptionRedactsToken() {
        XCTAssertFalse(String(describing: credentials).contains("test-token-not-real"))
        XCTAssertFalse("\(credentials)".contains("0123456789abcdef"))
    }

    func testPayloadLimitsAreCheckedBeforeSending() async {
        let transport = ScriptedTransport([])
        let a = analyzer(transport)
        let big = ImagePayload(data: Data(count: 4 * 1024 * 1024 + 1), mimeType: "image/png", pixelWidth: 10, pixelHeight: 10)
        let gif = ImagePayload(data: Data([1, 2, 3]), mimeType: "image/gif", pixelWidth: 1, pixelHeight: 1)
        let empty = ImagePayload(data: Data(), mimeType: "image/png", pixelWidth: 1, pixelHeight: 1)
        for image in [big, gif, empty] {
            await assertAnalyzerErrorCase({ _ = try await a.analyze(image, context: sampleContext) }) {
                if case .badRequest(status: 0, _) = $0 { return true } else { return false }
            }
        }
        XCTAssertEqual(transport.requestCount, 0)
        // Exactly 4 MiB is allowed.
        let max = ImagePayload(data: Data(count: 4 * 1024 * 1024), mimeType: "image/jpeg", pixelWidth: 10, pixelHeight: 10)
        XCTAssertNoThrow(try a.makeRequest(image: max, context: sampleContext))
    }

    // MARK: Response

    func testParsesWrappedDocShapedResponse() async throws {
        let transport = ScriptedTransport([.ok(try Fixture.data("clairic-response-wrapped.json"))])
        let result = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(result, ScreenshotAnalysis(
            title: "Tweet - semiconductor flashcards",
            titleConfidence: 0.87,
            sourceAppOrSite: "X",
            contentType: .tweet,
            description: "A tweet sharing a set of flashcards that explain semiconductor manufacturing steps.",
            tags: ["semiconductors", "flashcards", "chips", "wafer fab"], // "learning" < 0.3, "screenshot" generic, dup removed
            keyText: "I made 40 flashcards on how chips are made, from wafer to packaging.",
            dateMentioned: "2026-03-14",
            producedBy: "clairic@cf/cloudflare/clairic",
            billedInputTokens: 4618
        ))
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testParsesUnwrappedBodyAndIgnoresDateGuess() throws {
        let result = try CloudflareClairicAnalyzer.parseResponse(Fixture.data("clairic-response-unwrapped.json"))
        XCTAssertEqual(result.title, "Stripe invoice for October")
        XCTAssertEqual(result.titleConfidence, 0.64)
        XCTAssertNil(result.description, "null value")
        XCTAssertNil(result.sourceAppOrSite, "empty list")
        XCTAssertEqual(result.contentType, .receipt)
        XCTAssertEqual(result.tags, ["invoice", "billing"])
        XCTAssertNil(result.dateMentioned, "guess must be ignored when value is null")
        XCTAssertEqual(result.billedInputTokens, 3178)
    }

    func testInvalidAnswersBecomeNilAndZeroConfidence() throws {
        let result = try CloudflareClairicAnalyzer.parseResponse(Fixture.data("clairic-response-invalid-title.json"))
        XCTAssertNil(result.title)
        XCTAssertEqual(result.titleConfidence, 0)
        XCTAssertEqual(result.contentType, .other, "invalid enum answer falls back to .other")
        XCTAssertNil(result.sourceAppOrSite, "item confidence 0.2 < 0.3")
        XCTAssertEqual(result.tags, [], "item confidence 0.25 < 0.3")
        XCTAssertNil(result.keyText)
        XCTAssertNil(result.dateMentioned, "non-ISO value rejected")
        XCTAssertEqual(result.description, "A blurry photo of a whiteboard.")
    }

    func testGenericTitleIsDroppedWithZeroConfidence() throws {
        let result = try CloudflareClairicAnalyzer.parseResponse(Fixture.data("clairic-response-generic-title.json"))
        XCTAssertNil(result.title)
        XCTAssertEqual(result.titleConfidence, 0)
        XCTAssertEqual(result.tags, [])
        XCTAssertNil(result.description)
    }

    func testLowConfidenceValidTitleIsKeptSoThePipelineThresholdDecides() throws {
        let body = #"{"answers":{"title":{"type":"text","value":"Blurry receipt","valid":true,"confidence":0.12}},"usage":{"input_tokens":5,"output_tokens":1}}"#
        let result = try CloudflareClairicAnalyzer.parseResponse(Data(body.utf8))
        XCTAssertEqual(result.title, "Blurry receipt")
        XCTAssertEqual(result.titleConfidence, 0.12)
    }

    func testSuccessFalseBecomesInvalidResponseWithMessage() async throws {
        let transport = ScriptedTransport([.ok(try Fixture.data("clairic-response-failure.json"))])
        await assertAnalyzerError(.invalidResponse("Cloudflare reported failure: 5006: Error: oneOf at '/' not met")) {
            _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext)
        }
    }

    func testGarbageAndMissingAnswers() {
        XCTAssertThrowsError(try CloudflareClairicAnalyzer.parseResponse(Data("<html>".utf8))) {
            XCTAssertEqual($0 as? AnalyzerError, .invalidResponse("Clairic response is not JSON"))
        }
        XCTAssertThrowsError(try CloudflareClairicAnalyzer.parseResponse(Data(#"{"result":{"model":"x"},"success":true}"#.utf8))) {
            XCTAssertEqual($0 as? AnalyzerError, .invalidResponse("Clairic response has no `answers`"))
        }
    }

    func testHTTPErrorMapping() async {
        let envelope = #"{"result":null,"success":false,"errors":[{"code":10000,"message":"Authentication error"}],"messages":[]}"#
        let cases: [(ScriptedTransport.Step, AnalyzerError)] = [
            (.status(401, envelope), .unauthorized("HTTP 401: 10000: Authentication error")),
            (.status(403, "forbidden"), .unauthorized("HTTP 403: forbidden")),
            (.status(429, "{}", headers: ["Retry-After": "20"]), .rateLimited(retryAfter: 20)),
            (.status(500, "internal"), .serverError(status: 500, message: "internal")),
            (.status(400, #"{"success":false,"errors":[{"code":5006,"message":"bad field"}]}"#), .badRequest(status: 400, message: "5006: bad field")),
            (.failure(URLError(.timedOut)), .unreachable("Timed out")),
        ]
        for (step, expected) in cases {
            let transport = ScriptedTransport([step])
            await assertAnalyzerError(expected) {
                _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext)
            }
        }
    }
}
