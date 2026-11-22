import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What differs between OpenAI-compatible `/chat/completions` backends. The request, the tolerant parse and the
/// repair round trip are shared (`OpenAICompatibleAnalyzer`); a profile only says what to add or how to read it.
/// `.localServer` is the on-device / custom endpoint behaviour; OpenRouter's is `OpenRouterBackend.profile`.
public struct OpenAICompatibleProfile: Sendable, Equatable {
    /// How the backend phrases errors (beyond the shared HTTP status mapping).
    public enum ErrorDialect: Sendable, Equatable {
        /// Status codes only (`HTTPErrorMapping`).
        case generic
        /// OpenRouter's `{"error": {code, message, metadata}}` (docs/research/openrouter.md, "Errors").
        case openRouter
    }

    /// Where `ScreenshotAnalysis.titleConfidence` comes from.
    public enum TitleConfidence: Sendable, Equatable {
        /// 1.0 when the reply parsed as JSON, 0.6 when it had to be closed (truncated) or repaired.
        case fixed
        /// The title tokens' per-token probability from `choices[0].logprobs` (`TitleTokenConfidence`); 0.7
        /// (`OpenAICompatibleAnalyzer.unmeasuredConfidence`) when the reply carries none, 0.6 when repaired.
        case tokenLogprobs
    }

    /// For logs and the index, e.g. "local-openai" or "openrouter".
    public var backendID: String
    /// `producedBy` = "<prefix>:<model>".
    public var producedByPrefix: String
    /// Names the server in `invalidResponse` messages ("Local server", "OpenRouter").
    public var serviceName: String
    /// Extra request headers (never secrets; the API key goes in `Authorization` only).
    public var headers: [String: String] = [:]
    /// Body members sent together with `response_format` (reasoning switch, logprobs, provider routing…).
    public var extraBody: [String: AnalysisJSON] = [:]
    /// Local servers differ: after a 400 that names an unknown parameter, resend once without `response_format`
    /// and `extraBody`, and keep doing so for this instance. Off for a backend whose parameters are documented.
    public var retriesWithoutExtrasOn400 = false
    /// Refuse to send without an API key (`notConfigured`).
    public var requiresAPIKey = false
    /// User content order: text before the image (OpenRouter's advice) instead of image first.
    public var textBeforeImage = false
    /// Image types the backend documents; nil = send whatever the preparer produced.
    public var supportedMimeTypes: Set<String>? = nil
    public var titleConfidence: TitleConfidence = .fixed
    /// Apply `TitleRules` to the title; a title that fails keeps the original filename.
    public var validatesTitle = false
    /// Report `usage.prompt_tokens` (summed over the calls of one analysis) as `billedInputTokens`.
    public var reportsBilledTokens = false
    public var errorDialect: ErrorDialect = .generic

    public init(backendID: String, producedByPrefix: String, serviceName: String) {
        self.backendID = backendID
        self.producedByPrefix = producedByPrefix
        self.serviceName = serviceName
    }

    /// Any OpenAI-compatible server the user runs (managed `mlx_lm.server`, LM Studio, llama-server, Ollama).
    /// llama-server: top-level `reasoning_effort: "none"` disables thinking; Inkling's chat template reads
    /// `reasoning_effort` (docs/research/model-backends.md), which servers pass through `chat_template_kwargs`
    /// (docs/research/openai-compatible-chat.md). Neither is standard, hence the 400 fallback.
    public static let localServer: OpenAICompatibleProfile = {
        var p = OpenAICompatibleProfile(backendID: "local-openai", producedByPrefix: "local", serviceName: "Local server")
        p.extraBody = ["reasoning_effort": "none", "chat_template_kwargs": ["reasoning_effort": "none"]]
        p.retriesWithoutExtrasOn400 = true
        return p
    }()
}

/// The shared OpenAI-compatible `/chat/completions` client: the on-device / custom endpoint backend
/// (`OpenAICompatibleProfile.localServer`) and OpenRouter (`OpenRouterBackend.profile`).
///
/// Request/response facts: docs/research/openai-compatible-chat.md (llama.cpp server README, mlx-lm SERVER.md,
/// OpenAI structured outputs), docs/research/model-backends.md (Inkling `reasoning_effort` template variable) and
/// docs/research/openrouter.md (OpenRouter's request, response, logprobs and error shapes).
public final class OpenAICompatibleAnalyzer: ScreenshotAnalyzer {
    public struct Configuration: Sendable, Equatable {
        /// e.g. http://127.0.0.1:8080 (mlx_lm.server default). A trailing `/v1` is accepted.
        public var baseURL: URL
        public var model: String
        /// Bearer token. Never logged.
        public var apiKey: String?
        public var maxTokens: Int
        public var timeout: TimeInterval
        public var profile: OpenAICompatibleProfile

        public init(baseURL: URL, model: String, apiKey: String? = nil, maxTokens: Int = 400, timeout: TimeInterval = 120,
                    profile: OpenAICompatibleProfile = .localServer) {
            self.baseURL = baseURL
            self.model = model
            self.apiKey = apiKey
            self.maxTokens = maxTokens
            self.timeout = timeout
            self.profile = profile
        }
    }

    /// `.tokenLogprobs` profile, JSON parsed but no logprobs to measure the title with.
    public static let unmeasuredConfidence = 0.7

    public let configuration: Configuration
    private let transport: any HTTPTransport
    /// Flips to false (for the lifetime of this instance) after a server rejects the optional parameters.
    private let extrasSupported = LockedFlag(true)

    public init(configuration: Configuration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    private var profile: OpenAICompatibleProfile { configuration.profile }
    public var backendID: String { profile.backendID }
    public var producedBy: String { "\(profile.producedByPrefix):\(configuration.model)" }

    /// Whether `response_format` / `extraBody` are currently being sent (false after a 400 fallback).
    public var sendsStructuredOutputParameters: Bool { extrasSupported.value }

    public func analyze(_ image: ImagePayload, context: AnalysisContext) async throws -> ScreenshotAnalysis {
        guard !configuration.model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AnalyzerError.notConfigured("No model name configured")
        }
        if let types = profile.supportedMimeTypes, !types.contains(image.mimeType.lowercased()) {
            throw AnalyzerError.badRequest(status: 0, message: "Unsupported image type \(image.mimeType)")
        }
        let first = try await complete(messages: analysisMessages(image: image, context: context))
        if let extraction = LenientJSONExtractor.firstObject(in: first.content), Self.looksLikeAnalysis(extraction.object) {
            // A truncated object that needed closing is treated like a repaired one: the title may be cut short.
            let confidence: Double
            if extraction.wasTruncated {
                confidence = 0.6
            } else if profile.titleConfidence == .tokenLogprobs {
                // No logprobs back (or no title among them): parsed, but unmeasured, so below a measured "sure".
                confidence = first.tokenLogprobs.flatMap { TitleTokenConfidence.confidence(tokens: $0) }
                    ?? Self.unmeasuredConfidence
            } else {
                confidence = 1.0
            }
            return makeAnalysis(extraction.object, titleConfidence: confidence, promptTokens: first.promptTokens)
        }
        // One repair round trip without the image: ask the model to restate its own output as valid JSON.
        let repaired = try await complete(messages: Self.repairMessages(badOutput: first.content))
        if let extraction = LenientJSONExtractor.firstObject(in: repaired.content), Self.looksLikeAnalysis(extraction.object) {
            return makeAnalysis(extraction.object, titleConfidence: 0.6,
                                promptTokens: Self.sum(first.promptTokens, repaired.promptTokens))
        }
        throw AnalyzerError.invalidResponse("\(profile.serviceName) did not return valid JSON after one repair attempt")
    }

    // MARK: Transport

    /// One chat completion: `choices[0].message.content` as text, the content's token logprobs when returned, and
    /// `usage.prompt_tokens`.
    struct Completion: Equatable {
        var content: String
        var tokenLogprobs: [TokenLogprob]?
        var promptTokens: Int?
    }

    private func complete(messages: [AnalysisJSON]) async throws -> Completion {
        let useExtras = extrasSupported.value
        do {
            return try await send(makeRequest(messages: messages, includeExtras: useExtras))
        } catch AnalyzerError.badRequest(let status, let message)
                    where status == 400 && useExtras && profile.retriesWithoutExtrasOn400
                    && Self.isUnsupportedParameterError(message) {
            extrasSupported.set(false)
            return try await send(makeRequest(messages: messages, includeExtras: false))
        }
    }

    private func send(_ request: URLRequest) async throws -> Completion {
        let dialect = profile.errorDialect
        let (data, response) = try await HTTPErrorMapping.send(
            request, via: transport, describeBody: { Self.errorMessage(from: $0, dialect: dialect) },
            refine: { status, headers, body in Self.refineError(status: status, headers: headers, body: body, dialect: dialect) })
        return try Self.completion(from: data, response: response, profile: profile)
    }

    /// 400 bodies that mean "I don't know these parameters" (llama.cpp, vLLM, LM Studio, Ollama wording varies).
    static func isUnsupportedParameterError(_ message: String) -> Bool {
        let m = message.lowercased()
        return ["response_format", "json_schema", "reasoning_effort", "chat_template_kwargs", "unknown", "unrecognized",
                "unsupported", "not supported", "extra", "not permitted", "invalid parameter"].contains { m.contains($0) }
    }

    static func errorMessage(from body: Data, dialect: OpenAICompatibleProfile.ErrorDialect) -> String {
        switch dialect {
        case .generic: return HTTPErrorMapping.genericMessage(from: body)
        case .openRouter: return OpenRouterBackend.errorMessage(from: body)
        }
    }

    static func refineError(status: Int, headers: HTTPURLResponse?, body: Data,
                            dialect: OpenAICompatibleProfile.ErrorDialect, embedded: Bool = false) -> AnalyzerError? {
        switch dialect {
        case .generic: return nil
        case .openRouter:
            return OpenRouterBackend.refineError(status: status, headers: headers, body: body, embedded: embedded)
        }
    }

    // MARK: Request

    public func makeRequest(messages: [AnalysisJSON], includeExtras: Bool) throws -> URLRequest {
        let key = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if profile.requiresAPIKey, key.isEmpty {
            throw AnalyzerError.notConfigured("\(profile.serviceName) API key is not set")
        }
        var body: [String: AnalysisJSON] = [
            "model": .string(configuration.model),
            "messages": .array(messages),
            "temperature": 0,
            "max_tokens": .number(Double(configuration.maxTokens)),
            "stream": false,
        ]
        if includeExtras {
            // OpenAI wrapper shape, accepted by llama-server (openai-compatible-chat.md) and OpenRouter
            // (openrouter.md, "Structured output").
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "screenshot_analysis", "strict": true, "schema": Self.jsonSchema],
            ]
            body.merge(profile.extraBody) { _, extra in extra }
        }
        var request = URLRequest(url: Self.chatCompletionsURL(base: configuration.baseURL), timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in profile.headers.sorted(by: { $0.key < $1.key }) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if !key.isEmpty {
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

    /// System prompt, then the user turn: the image as a `data:` URL `image_url` part and one text part, image first
    /// for local servers, text first where the backend asks for it (openrouter.md, "Image input").
    func analysisMessages(image: ImagePayload, context: AnalysisContext) -> [AnalysisJSON] {
        let dataURL = "data:\(image.mimeType.lowercased());base64,\(image.data.base64EncodedString())"
        let day = CloudflareClairicAnalyzer.isoDate(context.capturedAt, timeZone: .current)
        let imagePart: AnalysisJSON = ["type": "image_url", "image_url": ["url": .string(dataURL)]]
        let textPart: AnalysisJSON = ["type": "text", "text": .string("Screenshot taken on \(day). Reply with the JSON object only.")]
        return [
            ["role": "system", "content": .string(Self.systemPrompt)],
            ["role": "user", "content": .array(profile.textBeforeImage ? [textPart, imagePart] : [imagePart, textPart])],
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
    /// `reasoning_content` / `reasoning` are ignored on purpose.
    static func messageContent(from data: Data) throws -> String {
        try completion(from: data, response: nil, profile: .localServer).content
    }

    /// Reads one completion. An error carried in a 2xx body (OpenRouter: a top-level `error` without `choices`, or
    /// `choices[0].error` with `finish_reason: "error"`; openrouter.md, "Errors") is mapped like the status it names.
    static func completion(from data: Data, response: HTTPURLResponse?, profile: OpenAICompatibleProfile) throws -> Completion {
        guard let root = try? AnalysisJSON.parse(data) else {
            throw AnalyzerError.invalidResponse("\(profile.serviceName) response is not JSON")
        }
        let choice = root["choices"]?[0]
        if let error = choice?["error"] ?? (choice == nil ? root["error"] : nil), error.objectValue != nil {
            throw embeddedError(error, response: response, body: data, profile: profile)
        }
        guard let message = choice?["message"] else {
            throw AnalyzerError.invalidResponse("\(profile.serviceName) response has no choices[0].message")
        }
        let content: String
        if let s = message["content"]?.stringValue {
            content = s
        } else if let parts = message["content"]?.arrayValue {
            content = parts.compactMap { $0["text"]?.stringValue }.joined()
        } else {
            content = "" // null content (e.g. everything went to reasoning): handled by the repair path
        }
        // `choices[].logprobs.content[]` = `{token, logprob, bytes, top_logprobs}` (openrouter.md, "Logprobs").
        let logprobs = choice?["logprobs"]?["content"]?.arrayValue?.compactMap { item -> TokenLogprob? in
            guard let token = item["token"]?.stringValue, let logprob = item["logprob"]?.doubleValue else { return nil }
            let bytes = item["bytes"]?.arrayValue?.compactMap { $0.intValue }.compactMap { UInt8(exactly: $0) }
            return TokenLogprob(token: token, logprob: logprob, bytes: (bytes?.isEmpty ?? true) ? nil : bytes)
        }
        return Completion(content: content, tokenLogprobs: (logprobs?.isEmpty ?? true) ? nil : logprobs,
                          promptTokens: root["usage"]?["prompt_tokens"]?.intValue)
    }

    private static func embeddedError(_ error: AnalysisJSON, response: HTTPURLResponse?, body: Data,
                                      profile: OpenAICompatibleProfile) -> AnalyzerError {
        let message = String((error["message"]?.stringValue ?? "no message").prefix(300))
        guard let code = error["code"]?.intValue, !(200..<300).contains(code) else {
            return .invalidResponse("\(profile.serviceName) reported an error: \(message)")
        }
        let wrapped = (try? AnalysisJSON.object(["error": error]).encoded()) ?? body
        if let refined = refineError(status: code, headers: response, body: wrapped, dialect: profile.errorDialect,
                                      embedded: true) {
            return refined
        }
        return HTTPErrorMapping.map(status: code, headers: response, body: body, describeBody: { _ in message })
            ?? .invalidResponse("\(profile.serviceName) reported an error: \(message)")
    }

    static func looksLikeAnalysis(_ object: [String: AnalysisJSON]) -> Bool {
        AnalysisFields.all.contains { object[$0] != nil }
    }

    static func sum(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case (nil, nil): return nil
        default: return (a ?? 0) + (b ?? 0)
        }
    }

    private func makeAnalysis(_ o: [String: AnalysisJSON], titleConfidence: Double, promptTokens: Int?) -> ScreenshotAnalysis {
        func text(_ key: String, max: Int? = nil) -> String? {
            guard let s = o[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
                  s.lowercased() != "null" else { return nil }
            return max.map { String(s.prefix($0)) } ?? s
        }
        let source = text(AnalysisFields.sourceAppOrSite, max: 80)
        var title = text(AnalysisFields.title).flatMap { FilenameSanitizer.stem(from: $0) }
        if profile.validatesTitle, let raw = text(AnalysisFields.title),
           TitleRules.problem(with: raw, sourceAppOrSite: source) != nil {
            title = nil // keeps the original filename ("kept name: no title")
        }
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
            titleConfidence: title == nil ? 0 : min(1, max(0, titleConfidence)),
            sourceAppOrSite: source,
            contentType: text(AnalysisFields.contentType).flatMap { ContentType(rawValue: $0.lowercased()) } ?? .other,
            description: text(AnalysisFields.description, max: AnalysisFields.descriptionMaxLength * 2),
            tags: TagNormalizer.normalize(rawTags),
            keyText: text(AnalysisFields.keyText, max: AnalysisFields.keyTextMaxLength * 2),
            dateMentioned: text(AnalysisFields.dateMentioned).flatMap(AnalysisNormalize.isoDate),
            producedBy: producedBy,
            billedInputTokens: profile.reportsBilledTokens ? promptTokens : nil
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
