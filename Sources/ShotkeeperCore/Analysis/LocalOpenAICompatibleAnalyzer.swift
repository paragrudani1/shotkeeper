import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Optional on-device backend: any OpenAI-compatible `/v1/chat/completions` server with vision
/// (managed `mlx_lm.server` running Inkling 2 Mini, LM Studio, llama-server, Ollama).
///
/// Request/response facts: docs/research/openai-compatible-chat.md (llama.cpp server README, mlx-lm SERVER.md,
/// OpenAI structured outputs) and docs/research/model-backends.md (Inkling `reasoning_effort` template variable).
public final class LocalOpenAICompatibleAnalyzer: ScreenshotAnalyzer {
    public struct Configuration: Sendable, Equatable {
        /// e.g. http://127.0.0.1:8080 (mlx_lm.server default). A trailing `/v1` is accepted.
        public var baseURL: URL
        public var model: String
        /// Optional bearer token for servers that require one. Never logged.
        public var apiKey: String?
        public var maxTokens: Int
        public var timeout: TimeInterval

        public init(baseURL: URL, model: String, apiKey: String? = nil, maxTokens: Int = 400, timeout: TimeInterval = 120) {
            self.baseURL = baseURL
            self.model = model
            self.apiKey = apiKey
            self.maxTokens = maxTokens
            self.timeout = timeout
        }
    }

    public let backendID = "local-openai"
    public let configuration: Configuration
    private let transport: any HTTPTransport
    /// Flips to false (for the lifetime of this instance) after a server rejects the optional parameters.
    private let extrasSupported = LockedFlag(true)

    public init(configuration: Configuration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    public var producedBy: String { "local:\(configuration.model)" }

    /// Whether `response_format` / reasoning parameters are currently being sent (false after a 400 fallback).
    public var sendsStructuredOutputParameters: Bool { extrasSupported.value }

    public func analyze(_ image: ImagePayload, context: AnalysisContext) async throws -> ScreenshotAnalysis {
        guard !configuration.model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AnalyzerError.notConfigured("No local model name configured")
        }
        let first = try await complete(messages: Self.analysisMessages(image: image, context: context))
        if let extraction = LenientJSONExtractor.firstObject(in: first), Self.looksLikeAnalysis(extraction.object) {
            // A truncated object that needed closing is treated like a repaired one: the title may be cut short.
            return makeAnalysis(extraction.object, titleConfidence: extraction.wasTruncated ? 0.6 : 1.0)
        }
        // One repair round trip without the image: ask the model to restate its own output as valid JSON.
        let repaired = try await complete(messages: Self.repairMessages(badOutput: first))
        if let extraction = LenientJSONExtractor.firstObject(in: repaired), Self.looksLikeAnalysis(extraction.object) {
            return makeAnalysis(extraction.object, titleConfidence: 0.6)
        }
        throw AnalyzerError.invalidResponse("Local model did not return valid JSON after one repair attempt")
    }

    // MARK: Transport

    /// Sends one chat completion and returns `choices[0].message.content` as text.
    private func complete(messages: [AnalysisJSON]) async throws -> String {
        let useExtras = extrasSupported.value
        do {
            return try await send(makeRequest(messages: messages, includeExtras: useExtras))
        } catch AnalyzerError.badRequest(let status, let message)
                    where status == 400 && useExtras && Self.isUnsupportedParameterError(message) {
            extrasSupported.set(false)
            return try await send(makeRequest(messages: messages, includeExtras: false))
        }
    }

    private func send(_ request: URLRequest) async throws -> String {
        let (data, _) = try await HTTPErrorMapping.send(request, via: transport)
        return try Self.messageContent(from: data)
    }

    /// 400 bodies that mean "I don't know these parameters" (llama.cpp, vLLM, LM Studio, Ollama wording varies).
    static func isUnsupportedParameterError(_ message: String) -> Bool {
        let m = message.lowercased()
        return ["response_format", "json_schema", "reasoning_effort", "chat_template_kwargs", "unknown", "unrecognized",
                "unsupported", "not supported", "extra", "not permitted", "invalid parameter"].contains { m.contains($0) }
    }

    // MARK: Request

    public func makeRequest(messages: [AnalysisJSON], includeExtras: Bool) throws -> URLRequest {
        var body: [String: AnalysisJSON] = [
            "model": .string(configuration.model),
            "messages": .array(messages),
            "temperature": 0,
            "max_tokens": .number(Double(configuration.maxTokens)),
            "stream": false,
        ]
        if includeExtras {
            // OpenAI wrapper shape, accepted by llama-server (openai-compatible-chat.md).
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "screenshot_analysis", "strict": true, "schema": Self.jsonSchema],
            ]
            // llama-server: top-level `reasoning_effort: "none"` disables thinking; Inkling's chat template reads
            // `reasoning_effort` (model-backends.md), which servers pass through `chat_template_kwargs`.
            body["reasoning_effort"] = "none"
            body["chat_template_kwargs"] = ["reasoning_effort": "none"]
        }
        var request = URLRequest(url: Self.chatCompletionsURL(base: configuration.baseURL), timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try AnalysisJSON.object(body).encoded()
        return request
    }

    static func chatCompletionsURL(base: URL) -> URL {
        var s = base.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/chat/completions") { return URL(string: s) ?? base }
        if !s.hasSuffix("/v1") { s += "/v1" }
        return URL(string: s + "/chat/completions") ?? base
    }

    static let systemPrompt: String = {
        let types = ContentType.allCases.map(\.rawValue).joined(separator: ", ")
        return """
        You label screenshots for a file organizer. Look at the image and reply with ONLY a JSON object, no prose, \
        no code fences, with exactly these keys:
        "\(AnalysisFields.title)": string. \(AnalysisFields.Instructions.title) At most \(AnalysisFields.titleMaxLength) characters.
        "\(AnalysisFields.sourceAppOrSite)": string or null. \(AnalysisFields.Instructions.sourceAppOrSite)
        "\(AnalysisFields.contentType)": one of \(types). \(AnalysisFields.Instructions.contentType)
        "\(AnalysisFields.description)": string. \(AnalysisFields.Instructions.description)
        "\(AnalysisFields.tags)": array of strings. \(AnalysisFields.Instructions.tags)
        "\(AnalysisFields.keyText)": string or null. \(AnalysisFields.Instructions.keyText) At most \(AnalysisFields.keyTextMaxLength) characters.
        "\(AnalysisFields.dateMentioned)": "YYYY-MM-DD" or null. \(AnalysisFields.Instructions.dateMentioned)
        """
    }()

    /// Strict-mode JSON schema (openai-compatible-chat.md: every property required, `additionalProperties: false`,
    /// nullable as `["string", "null"]`). Same fields as `ClairicFieldSchema`, from `AnalysisFields`.
    static let jsonSchema: AnalysisJSON = [
        "type": "object",
        "additionalProperties": false,
        "required": .array(AnalysisFields.all.map { .string($0) }),
        "properties": [
            AnalysisFields.title: ["type": "string", "maxLength": .number(Double(AnalysisFields.titleMaxLength))],
            AnalysisFields.sourceAppOrSite: ["type": ["string", "null"]],
            AnalysisFields.contentType: ["type": "string", "enum": .array(ContentType.allCases.map { .string($0.rawValue) })],
            AnalysisFields.description: ["type": "string", "maxLength": .number(Double(AnalysisFields.descriptionMaxLength))],
            AnalysisFields.tags: ["type": "array", "items": ["type": "string"], "maxItems": .number(Double(AnalysisFields.maxTags))],
            AnalysisFields.keyText: ["type": ["string", "null"], "maxLength": .number(Double(AnalysisFields.keyTextMaxLength))],
            AnalysisFields.dateMentioned: ["type": ["string", "null"], "description": "Calendar date as YYYY-MM-DD"],
        ],
    ]

    static func analysisMessages(image: ImagePayload, context: AnalysisContext) -> [AnalysisJSON] {
        let dataURL = "data:\(image.mimeType.lowercased());base64,\(image.data.base64EncodedString())"
        let day = CloudflareClairicAnalyzer.isoDate(context.capturedAt, timeZone: .current)
        return [
            ["role": "system", "content": .string(systemPrompt)],
            ["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": .string(dataURL)]],
                ["type": "text", "text": .string("Screenshot taken on \(day). Reply with the JSON object only.")],
            ]],
        ]
    }

    static func repairMessages(badOutput: String) -> [AnalysisJSON] {
        let excerpt = String(badOutput.prefix(4000))
        return [
            ["role": "system", "content": .string(systemPrompt)],
            ["role": "user", "content": .string("""
                Your previous reply was not valid JSON. Rewrite it as a single valid JSON object with the keys above \
                and nothing else: no prose, no code fences. Previous reply:
                \(excerpt)
                """)],
        ]
    }

    // MARK: Response

    /// OpenAI chat completion shape: `choices[0].message.content` (string, or array of `{type:"text", text}` parts).
    /// `reasoning_content` is ignored on purpose.
    static func messageContent(from data: Data) throws -> String {
        guard let root = try? AnalysisJSON.parse(data) else {
            throw AnalyzerError.invalidResponse("Local server response is not JSON")
        }
        guard let message = root["choices"]?[0]?["message"] else {
            throw AnalyzerError.invalidResponse("Local server response has no choices[0].message")
        }
        if let s = message["content"]?.stringValue { return s }
        if let parts = message["content"]?.arrayValue {
            return parts.compactMap { $0["text"]?.stringValue }.joined()
        }
        return "" // null content (e.g. everything went to reasoning): handled by the repair path
    }

    static func looksLikeAnalysis(_ object: [String: AnalysisJSON]) -> Bool {
        AnalysisFields.all.contains { object[$0] != nil }
    }

    private func makeAnalysis(_ o: [String: AnalysisJSON], titleConfidence: Double) -> ScreenshotAnalysis {
        func text(_ key: String, max: Int? = nil) -> String? {
            guard let s = o[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
                  s.lowercased() != "null" else { return nil }
            return max.map { String(s.prefix($0)) } ?? s
        }
        let title = text(AnalysisFields.title).flatMap { FilenameSanitizer.stem(from: $0) }
        let rawTags: [String]
        if let list = o[AnalysisFields.tags]?.arrayValue {
            rawTags = list.compactMap(\.stringValue)
        } else if let s = o[AnalysisFields.tags]?.stringValue {
            rawTags = s.split(separator: ",").map(String.init)
        } else {
            rawTags = []
        }
        return ScreenshotAnalysis(
            title: title,
            titleConfidence: title == nil ? 0 : titleConfidence,
            sourceAppOrSite: text(AnalysisFields.sourceAppOrSite, max: 80),
            contentType: text(AnalysisFields.contentType).flatMap { ContentType(rawValue: $0.lowercased()) } ?? .other,
            description: text(AnalysisFields.description, max: AnalysisFields.descriptionMaxLength * 2),
            tags: TagNormalizer.normalize(rawTags),
            keyText: text(AnalysisFields.keyText, max: AnalysisFields.keyTextMaxLength * 2),
            dateMentioned: text(AnalysisFields.dateMentioned).flatMap(AnalysisNormalize.isoDate),
            producedBy: producedBy,
            billedInputTokens: nil
        )
    }
}

/// A Bool behind a lock, so a `Sendable` analyzer can remember a server capability.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool

    init(_ value: Bool) { stored = value }

    var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
}
