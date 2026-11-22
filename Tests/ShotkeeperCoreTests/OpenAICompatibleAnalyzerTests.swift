import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShotkeeperCore

/// Chat-completion envelope (docs/research/openai-compatible-chat.md) around a model output string.
private func completion(_ content: String, finishReason: String = "stop", reasoning: String? = nil) -> ScriptedTransport.Step {
    var message: [String: AnalysisJSON] = ["role": "assistant", "content": .string(content)]
    if let reasoning { message["reasoning_content"] = .string(reasoning) }
    let body: AnalysisJSON = [
        "id": "chatcmpl-1", "object": "chat.completion", "model": "test-model",
        "choices": [["index": 0, "message": .object(message), "finish_reason": .string(finishReason)]],
        "usage": ["prompt_tokens": 900, "completion_tokens": 80, "total_tokens": 980],
    ]
    return .ok(try! body.encoded())
}

private let goodJSON = """
{"title": "Slack thread about launch dates", "source_app_or_site": "Slack", "content_type": "chat",
 "description": "A Slack conversation where the team agrees on a launch date.", "tags": ["Launch", "planning", "#slack"],
 "key_text": "Let's ship on the 24th", "date_mentioned": "2026-11-24"}
"""

final class OpenAICompatibleAnalyzerTests: XCTestCase {
    private func analyzer(_ transport: ScriptedTransport, base: String = "http://127.0.0.1:8080") -> OpenAICompatibleAnalyzer {
        OpenAICompatibleAnalyzer(
            configuration: .init(baseURL: URL(string: base)!, model: "mlx-community/Inkling-2-Mini-4bit"),
            transport: transport)
    }

    // MARK: Request

    func testRequestShape() async throws {
        let transport = ScriptedTransport([completion(goodJSON)])
        let image = samplePNG()
        _ = try await analyzer(transport).analyze(image, context: sampleContext)
        let request = transport.request(0)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try jsonBody(request)
        XCTAssertEqual(body["model"], "mlx-community/Inkling-2-Mini-4bit")
        XCTAssertEqual(body["temperature"], 0)
        XCTAssertEqual(body["max_tokens"], 400)
        XCTAssertEqual(body["stream"], false)
        XCTAssertEqual(body["reasoning_effort"], "none")
        XCTAssertEqual(body["chat_template_kwargs"], ["reasoning_effort": "none"])

        let format = try XCTUnwrap(body["response_format"])
        XCTAssertEqual(format["type"], "json_schema")
        XCTAssertEqual(format["json_schema"]?["name"], "screenshot_analysis")
        XCTAssertEqual(format["json_schema"]?["strict"], true)
        let schema = try XCTUnwrap(format["json_schema"]?["schema"])
        XCTAssertEqual(schema["additionalProperties"], false)
        XCTAssertEqual(Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []), Set(AnalysisFields.all))
        XCTAssertEqual(Set(schema["properties"]?.objectValue?.keys.map { $0 } ?? []), Set(AnalysisFields.all))
        XCTAssertEqual(schema["properties"]?["content_type"]?["enum"],
                       .array(ContentType.allCases.map { .string($0.rawValue) }))
        XCTAssertEqual(schema["properties"]?["date_mentioned"]?["type"], ["string", "null"])

        let messages = try XCTUnwrap(body["messages"]?.arrayValue)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertTrue(messages[0]["content"]?.stringValue?.contains("\"title\"") == true)
        XCTAssertEqual(messages[1]["role"], "user")
        let parts = try XCTUnwrap(messages[1]["content"]?.arrayValue)
        XCTAssertEqual(parts[0], ["type": "image_url",
                                  "image_url": ["url": .string("data:image/png;base64,\(image.data.base64EncodedString())")]])
        XCTAssertEqual(parts[1]["type"], "text")
    }

    func testURLJoiningAndAPIKey() throws {
        XCTAssertEqual(OpenAICompatibleAnalyzer.chatCompletionsURL(base: URL(string: "http://localhost:1234/v1/")!).absoluteString,
                       "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(OpenAICompatibleAnalyzer.chatCompletionsURL(base: URL(string: "http://localhost:11434")!).absoluteString,
                       "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(OpenAICompatibleAnalyzer.chatCompletionsURL(
            base: URL(string: "http://h/custom/v1/chat/completions")!).absoluteString, "http://h/custom/v1/chat/completions")
        let a = OpenAICompatibleAnalyzer(configuration: .init(baseURL: URL(string: "http://h")!, model: "m", apiKey: "k"),
                                              transport: ScriptedTransport([]))
        XCTAssertEqual(try a.makeRequest(messages: [], includeExtras: true).value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(a.producedBy, "local:m")
    }

    // MARK: Parsing

    func testGoodJSON() async throws {
        let transport = ScriptedTransport([completion(goodJSON)])
        let result = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(result, ScreenshotAnalysis(
            title: "Slack thread about launch dates", titleConfidence: 1.0, sourceAppOrSite: "Slack", contentType: .chat,
            description: "A Slack conversation where the team agrees on a launch date.", tags: ["launch", "planning", "slack"],
            keyText: "Let's ship on the 24th", dateMentioned: "2026-11-24",
            producedBy: "local:mlx-community/Inkling-2-Mini-4bit", billedInputTokens: nil))
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testFencedJSON() async throws {
        let transport = ScriptedTransport([completion("```json\n\(goodJSON)\n```")])
        let result = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(result.title, "Slack thread about launch dates")
        XCTAssertEqual(result.titleConfidence, 1.0)
    }

    func testThinkBlockProseAndTrailingCommasAreIgnored() async throws {
        let content = """
        <think>The image shows {a chat}. Maybe {"title": "wrong"}</think>
        Sure! Here is the JSON you asked for:
        {"title": "Terminal build failure", "content_type": "code", "tags": ["swift", "build",], "key_text": null,
         "source_app_or_site": "Terminal", "description": "A failing swift build.", "date_mentioned": null,}
        Let me know if you need anything else {:)}
        """
        let transport = ScriptedTransport([completion(content, reasoning: "{\"title\": \"from reasoning\"}")])
        let result = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(result.title, "Terminal build failure")
        XCTAssertEqual(result.contentType, .code)
        XCTAssertEqual(result.tags, ["swift", "build"])
        XCTAssertNil(result.keyText)
        XCTAssertNil(result.dateMentioned)
        XCTAssertEqual(result.titleConfidence, 1.0)
    }

    func testTruncatedJSONIsClosedAndTitleConfidenceLowered() async throws {
        let content = #"{"title": "Figma onboarding flow", "content_type": "design", "tags": ["figma", "onboard"#
        let transport = ScriptedTransport([completion(content, finishReason: "length")])
        let result = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(result.title, "Figma onboarding flow")
        XCTAssertEqual(result.contentType, .design)
        XCTAssertEqual(result.tags, ["figma", "onboard"])
        XCTAssertEqual(result.titleConfidence, 0.6)
        XCTAssertEqual(transport.requestCount, 1, "truncation is recovered locally, no repair call")
    }

    func testGarbageThenRepairSucceeds() async throws {
        let transport = ScriptedTransport([
            completion("I think this is a screenshot of a recipe website with pancakes."),
            completion(#"{"title": "Pancake recipe", "content_type": "article", "tags": ["recipe"], "source_app_or_site": null, "description": "A pancake recipe.", "key_text": null, "date_mentioned": null}"#),
        ])
        let result = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(result.title, "Pancake recipe")
        XCTAssertEqual(result.titleConfidence, 0.6)
        XCTAssertEqual(transport.requestCount, 2)
        // The repair call sends the bad output back and no image.
        let repair = try jsonBody(transport.request(1))
        let userContent = try XCTUnwrap(repair["messages"]?[1]?["content"]?.stringValue)
        XCTAssertTrue(userContent.contains("recipe website with pancakes"))
        XCTAssertFalse(String(decoding: transport.request(1).httpBody!, as: UTF8.self).contains("data:image"))
    }

    func testGarbageTwiceIsInvalidResponse() async {
        let transport = ScriptedTransport([completion("no json here"), completion("still {not json")])
        await assertAnalyzerErrorCase({ _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext) }) {
            if case .invalidResponse = $0 { return true } else { return false }
        }
        XCTAssertEqual(transport.requestCount, 2)
    }

    func testUnrelatedJSONObjectTriggersRepair() async throws {
        let transport = ScriptedTransport([completion(#"{"answer": 42}"#), completion(goodJSON)])
        let result = try await analyzer(transport).analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(result.titleConfidence, 0.6)
    }

    func testValidationFallbacks() async throws {
        let content = #"{"title": "Screenshot", "content_type": "meme", "tags": "Alpha, beta, alpha", "key_text": "  ", "date_mentioned": "March 3"}"#
        let result = try await analyzer(ScriptedTransport([completion(content)])).analyze(samplePNG(), context: sampleContext)
        XCTAssertNil(result.title, "generic title")
        XCTAssertEqual(result.titleConfidence, 0, "missing title → 0")
        XCTAssertEqual(result.contentType, .other)
        XCTAssertEqual(result.tags, ["alpha", "beta"])
        XCTAssertNil(result.keyText)
        XCTAssertNil(result.dateMentioned)
    }

    func testContentAsPartsArray() throws {
        let body = #"{"choices":[{"message":{"role":"assistant","content":[{"type":"text","text":"{\"title\":"},{"type":"text","text":"\"X\"}"}]}}]}"#
        XCTAssertEqual(try OpenAICompatibleAnalyzer.messageContent(from: Data(body.utf8)), #"{"title":"X"}"#)
        XCTAssertThrowsError(try OpenAICompatibleAnalyzer.messageContent(from: Data(#"{"error":"x"}"#.utf8)))
    }

    // MARK: Server capability fallback

    func testBadRequestMentioningResponseFormatRetriesWithoutExtrasAndRemembers() async throws {
        let transport = ScriptedTransport([
            .status(400, #"{"error":{"message":"Unsupported parameter: response_format"}}"#),
            completion(goodJSON),
            completion(goodJSON),
        ])
        let a = analyzer(transport)
        XCTAssertTrue(a.sendsStructuredOutputParameters)
        let first = try await a.analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(first.titleConfidence, 1.0)
        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertNotNil(try jsonBody(transport.request(0))["response_format"])
        let retry = try jsonBody(transport.request(1))
        XCTAssertNil(retry["response_format"])
        XCTAssertNil(retry["reasoning_effort"])
        XCTAssertNil(retry["chat_template_kwargs"])
        XCTAssertNotNil(retry["messages"], "image request is resent")
        XCTAssertFalse(a.sendsStructuredOutputParameters)

        _ = try await a.analyze(samplePNG(), context: sampleContext)
        XCTAssertEqual(transport.requestCount, 3, "remembered: no second 400 round trip")
        XCTAssertNil(try jsonBody(transport.request(2))["response_format"])
    }

    func testOtherBadRequestIsNotRetried() async {
        let transport = ScriptedTransport([.status(400, "image too large")])
        await assertAnalyzerError(.badRequest(status: 400, message: "image too large")) {
            _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext)
        }
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testRetryOnlyOnceThenSurfaceError() async {
        let transport = ScriptedTransport([.status(400, "unknown field response_format"), .status(400, "unknown field messages")])
        await assertAnalyzerError(.badRequest(status: 400, message: "unknown field messages")) {
            _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext)
        }
        XCTAssertEqual(transport.requestCount, 2)
    }

    func testConnectionRefusedIsUnreachable() async {
        let transport = ScriptedTransport([.failure(URLError(.cannotConnectToHost))])
        await assertAnalyzerError(.unreachable("Connection refused")) {
            _ = try await self.analyzer(transport).analyze(samplePNG(), context: sampleContext)
        }
    }

    func testEmptyModelIsNotConfigured() async {
        let a = OpenAICompatibleAnalyzer(configuration: .init(baseURL: URL(string: "http://h")!, model: " "),
                                              transport: ScriptedTransport([]))
        await assertAnalyzerErrorCase({ _ = try await a.analyze(samplePNG(), context: sampleContext) }) {
            if case .notConfigured = $0 { return true } else { return false }
        }
    }
}

final class LenientJSONExtractorTests: XCTestCase {
    private func obj(_ s: String) -> [String: AnalysisJSON]? { LenientJSONExtractor.firstObject(in: s)?.object }

    func testPlainAndNested() {
        XCTAssertEqual(obj(#"{"a": {"b": [1, {"c": "}"}]}}"#), ["a": ["b": [1, ["c": "}"]]]])
    }

    func testEscapedQuotesAndBracesInStrings() {
        XCTAssertEqual(obj(#"text {"t": "say \"hi\" {not a brace}"} more"#), ["t": #"say "hi" {not a brace}"#])
    }

    func testSkipsBrokenBraceGroupsInProse() {
        XCTAssertEqual(obj(#"Use {curly} braces. {"ok": true}"#), ["ok": true])
    }

    func testTrailingCommas() {
        XCTAssertEqual(obj(#"{"a": [1, 2, ], "b": 3, }"#), ["a": [1, 2], "b": 3])
        XCTAssertEqual(obj(#"{"a": "x, }"}"#), ["a": "x, }"], "commas inside strings untouched")
    }

    func testTruncationVariants() {
        let cut = LenientJSONExtractor.firstObject(in: #"{"title": "Hello wor"#)
        XCTAssertEqual(cut?.object, ["title": "Hello wor"])
        XCTAssertEqual(cut?.wasTruncated, true)
        XCTAssertEqual(obj(#"{"title": "A", "descr"#), ["title": "A"])
        XCTAssertEqual(obj(#"{"title": "A", "tags":"#), ["title": "A", "tags": nil])
        XCTAssertEqual(obj(#"{"title": "A", "nested": {"x": [1, 2"#), ["title": "A", "nested": ["x": [1, 2]]])
        XCTAssertEqual(obj(#"{"title": "A\"#), ["title": "A"])
        XCTAssertEqual(LenientJSONExtractor.firstObject(in: #"{"a": 1}"#)?.wasTruncated, false)
    }

    func testThinkingVariants() {
        XCTAssertEqual(obj("<think>{\"a\": 1}</think>{\"b\": 2}"), ["b": 2])
        XCTAssertEqual(obj("<THINKING>x</THINKING>\n{\"b\": 2}"), ["b": 2])
        XCTAssertEqual(obj("reasoning without opener {\"a\": 1}</think>{\"b\": 2}"), ["b": 2])
    }

    func testNothing() {
        XCTAssertNil(obj("no braces at all"))
        XCTAssertNil(obj("[1, 2, 3]"))
        XCTAssertNil(obj(""))
    }
}

final class ImageHeaderSnifferTests: XCTestCase {
    func testPNG() {
        let png = samplePNG(width: 2880, height: 1800)
        XCTAssertEqual(ImageHeaderSniffer.sniff(png.data), .init(mimeType: "image/png", width: 2880, height: 1800))
        XCTAssertEqual(ImageHeaderSniffer.payload(for: png.data), png)
    }

    func testJPEGSkipsSegmentsUntilSOF() {
        var b: [UInt8] = [0xFF, 0xD8]
        b += [0xFF, 0xE0, 0x00, 0x10] + Array("JFIF".utf8) + [0] + Array(repeating: 0, count: 9) // APP0, length 16
        b += [0xFF, 0xC4, 0x00, 0x04, 0, 0] // DHT (not a SOF)
        b += [0xFF, 0xC2, 0x00, 0x11, 0x08, 0x02, 0x58, 0x03, 0x20, 0x03] + Array(repeating: 0, count: 9) // SOF2 600×800
        XCTAssertEqual(ImageHeaderSniffer.sniff(Data(b)), .init(mimeType: "image/jpeg", width: 800, height: 600))
    }

    func testWebPVariants() {
        func riff(_ chunk: String, _ payload: [UInt8]) -> Data {
            Data(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8) + Array(chunk.utf8) + [0, 0, 0, 0] + payload
                 + Array(repeating: 0, count: 16))
        }
        // VP8X: flags(4) then 24-bit width-1, height-1.
        XCTAssertEqual(ImageHeaderSniffer.sniff(riff("VP8X", [0, 0, 0, 0, 0xFF, 0x04, 0x00, 0x1F, 0x03, 0x00])),
                       .init(mimeType: "image/webp", width: 1280, height: 800))
        // VP8L: signature 0x2F, 14-bit width-1, 14-bit height-1.
        let w = 99, h = 49
        let bits = (w) | (h << 14)
        XCTAssertEqual(ImageHeaderSniffer.sniff(riff("VP8L", [0x2F, UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24 & 0xFF)])),
                       .init(mimeType: "image/webp", width: 100, height: 50))
        // VP8: 3-byte frame tag, start code 9D 01 2A, 16-bit LE width/height.
        XCTAssertEqual(ImageHeaderSniffer.sniff(riff("VP8 ", [0, 0, 0, 0x9D, 0x01, 0x2A, 0x40, 0x01, 0xF0, 0x00])),
                       .init(mimeType: "image/webp", width: 320, height: 240))
    }

    func testUnknown() {
        XCTAssertNil(ImageHeaderSniffer.sniff(Data("GIF89a......".utf8)))
        XCTAssertNil(ImageHeaderSniffer.sniff(Data()))
    }
}
