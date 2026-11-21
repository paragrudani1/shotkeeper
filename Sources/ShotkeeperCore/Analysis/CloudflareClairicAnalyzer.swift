import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cloudflare account credentials, injected by the app (Keychain) or the CLI (environment).
/// `description` never reveals the token.
public struct ClairicCredentials: Sendable, Equatable, CustomStringConvertible {
    public var accountID: String
    public var apiToken: String

    public init(accountID: String, apiToken: String) {
        self.accountID = accountID
        self.apiToken = apiToken
    }

    public var description: String { "ClairicCredentials(accountID: <redacted>, apiToken: <redacted>)" }
}

/// Primary backend: Cloudflare Workers AI `@cf/cloudflare/clairic`.
///
/// Facts used here (no guessing): docs/research/clairic/model-page-2026-11-21.md, schema-input.json,
/// schema-output.json, workers-ai-rest-api-2026-11-21.md; digest in docs/research/model-backends.md.
public struct CloudflareClairicAnalyzer: ScreenshotAnalyzer {
    public static let modelID = "@cf/cloudflare/clairic"
    public static let producedBy = "clairic@cf/cloudflare/clairic"
    /// schema-input.json `images`: "4 MiB each".
    public static let maxImageBytes = 4 * 1024 * 1024
    /// schema-input.json `images`: "request body max 16 MiB".
    public static let maxBodyBytes = 16 * 1024 * 1024
    /// schema-input.json `images`: "embedded PNG, JPEG or WebP images".
    public static let supportedMimeTypes: Set<String> = ["image/png", "image/jpeg", "image/webp"]
    /// Per-item confidence below which a list item is dropped (only for list-shaped answers, e.g. older schemas).
    public static let minimumTagConfidence = 0.3

    public let backendID = "clairic"
    private let credentials: ClairicCredentials
    private let transport: any HTTPTransport
    private let timeZone: TimeZone
    private let timeout: TimeInterval

    public init(credentials: ClairicCredentials, transport: any HTTPTransport = URLSessionTransport(),
                timeZone: TimeZone = .current, timeout: TimeInterval = 60) {
        self.credentials = credentials
        self.transport = transport
        self.timeZone = timeZone
        self.timeout = timeout
    }

    public func analyze(_ image: ImagePayload, context: AnalysisContext) async throws -> ScreenshotAnalysis {
        let request = try makeRequest(image: image, context: context)
        let (data, response) = try await HTTPErrorMapping.send(request, via: transport,
                                                               describeBody: Self.cloudflareErrorMessage(from:))
        return try Self.parseResponse(data, status: response.statusCode)
    }

    // MARK: Request

    /// workers-ai-rest-api-2026-11-21.md: `POST https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/{model}`,
    /// header `Authorization: Bearer {API_TOKEN}`.
    public func makeRequest(image: ImagePayload, context: AnalysisContext) throws -> URLRequest {
        let accountID = credentials.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = credentials.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty, !token.isEmpty else {
            throw AnalyzerError.notConfigured("Cloudflare account ID and API token are required")
        }
        // Account IDs are hex; refuse anything that could alter the URL path.
        guard accountID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw AnalyzerError.notConfigured("Cloudflare account ID has unexpected characters")
        }
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(accountID)/ai/run/\(Self.modelID)") else {
            throw AnalyzerError.notConfigured("Could not build the Cloudflare URL")
        }
        let body = try Self.requestBody(image: image, context: context, timeZone: timeZone).encoded()
        guard body.count <= Self.maxBodyBytes else {
            throw AnalyzerError.badRequest(status: 0, message: "Request body is \(body.count) bytes; Clairic allows 16 MiB")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }

    /// Body per schema-input.json: `model` (pattern `^(clairic|@cf/cloudflare/clairic)$`), `state` ("Must be non-empty
    /// unless images or documents are sent": we send none, saving state tokens on every pass), `fields`,
    /// `images` (`{content_type, base64}` form), `reference_date` ("ISO date that anchors dates written without a year").
    /// Local validation (`badRequest(status: 0, …)`) happens before anything is sent.
    public static func requestBody(image: ImagePayload, context: AnalysisContext, timeZone: TimeZone) throws -> AnalysisJSON {
        let mime = image.mimeType.lowercased()
        guard supportedMimeTypes.contains(mime) else {
            throw AnalyzerError.badRequest(status: 0, message: "Unsupported image type \(image.mimeType); Clairic takes PNG, JPEG or WebP")
        }
        guard !image.data.isEmpty else {
            throw AnalyzerError.badRequest(status: 0, message: "Image is empty")
        }
        guard image.data.count <= maxImageBytes else {
            throw AnalyzerError.badRequest(status: 0, message: "Image is \(image.data.count) bytes; Clairic allows 4 MiB per image")
        }
        return [
            "model": .string(modelID),
            "state": "",
            "fields": .object(ClairicFieldSchema.fields()),
            "images": [["content_type": .string(mime), "base64": .string(image.data.base64EncodedString())]],
            "reference_date": .string(isoDate(context.capturedAt, timeZone: timeZone)),
        ]
    }

    static func isoDate(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    // MARK: Response

    /// REST responses are wrapped `{result, success, errors, messages}` (workers-ai-rest-api-2026-11-21.md);
    /// the model page sample and schema-output.json describe the inner object. Both are accepted.
    public static func parseResponse(_ data: Data, status: Int = 200) throws -> ScreenshotAnalysis {
        let root: AnalysisJSON
        do { root = try AnalysisJSON.parse(data) } catch {
            throw AnalyzerError.invalidResponse("Clairic response is not JSON")
        }
        let inner: AnalysisJSON
        if root["answers"] != nil {
            inner = root
        } else if root["success"] != nil || root["result"] != nil || root["errors"] != nil {
            if root["success"]?.boolValue == false || (root["result"] == nil || root["result"]!.isNull) {
                let message = errorMessages(root)
                throw AnalyzerError.invalidResponse("Cloudflare reported failure: \(message.isEmpty ? "no result" : message)")
            }
            inner = root["result"]!
        } else {
            throw AnalyzerError.invalidResponse("Clairic response has neither `result` nor `answers`")
        }
        guard let answers = inner["answers"]?.objectValue else {
            throw AnalyzerError.invalidResponse("Clairic response has no `answers`")
        }
        return analysis(from: answers, usage: inner["usage"])
    }

    /// schema-output.json `answers.additionalProperties`: generated answers carry `valid` and `confidence`
    /// ("0 when invalid"); `value` is null when undetermined; lists carry `value[]` + `confidences[]`;
    /// typed answers (date) carry `guess`, which we ignore when `value` is null.
    static func analysis(from answers: [String: AnalysisJSON], usage: AnalysisJSON?) -> ScreenshotAnalysis {
        func usable(_ name: String) -> AnalysisJSON? {
            guard let a = answers[name], a["valid"]?.boolValue != false, let v = a["value"], !v.isNull else { return nil }
            return v
        }
        func text(_ name: String) -> String? {
            guard let s = usable(name)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        func list(_ name: String) -> [String] {
            guard let a = answers[name], a["valid"]?.boolValue != false, let v = a["value"] else { return [] }
            if let s = v.stringValue { return [s] } // tolerate a scalar where a one-item list was asked for
            guard let items = v.arrayValue else { return [] }
            let confidences = a["confidences"]?.arrayValue
            return items.enumerated().compactMap { i, item in
                guard let s = item.stringValue else { return nil }
                if let c = confidences?[safe: i]?.doubleValue, c < minimumTagConfidence { return nil }
                return s
            }
        }

        /// Tags arrive as one comma-separated text answer (current schema) or as a list (older schema, fixtures).
        func tags() -> [String] {
            if let s = text(AnalysisFields.tags) {
                return s.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline }).map(String.init)
            }
            return list(AnalysisFields.tags)
        }

        var title: String?
        var titleConfidence = 0.0
        if let raw = text(AnalysisFields.title), let stem = FilenameSanitizer.stem(from: raw) {
            title = stem
            titleConfidence = min(1, max(0, perTokenConfidence(answers[AnalysisFields.title]) ?? 0))
        }

        let contentType = text(AnalysisFields.contentType).flatMap { ContentType(rawValue: $0.lowercased()) } ?? .other
        let source = (text(AnalysisFields.sourceAppOrSite).map { [$0] } ?? list(AnalysisFields.sourceAppOrSite)).lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        let date = text(AnalysisFields.dateMentioned).flatMap(AnalysisNormalize.isoDate)

        return ScreenshotAnalysis(
            title: title,
            titleConfidence: titleConfidence,
            sourceAppOrSite: source,
            contentType: contentType,
            description: text(AnalysisFields.description),
            tags: TagNormalizer.normalize(tags()),
            keyText: text(AnalysisFields.keyText),
            dateMentioned: date,
            producedBy: producedBy,
            billedInputTokens: usage?["input_tokens"]?.intValue
        )
    }

    /// Title confidence on a per-token scale: `exp(log_probability / tokens)`, the geometric mean token probability.
    /// schema-output.json: `confidence` is the "probability of the returned value" (live: `confidence_method`
    /// `ar_sequence_probability`), so it shrinks with length; a good 7-token title scored 0.38 on the first live call
    /// and would never pass the 0.5 rename threshold. `log_probability` ("of the generated sequence. Present only when
    /// valid") and `tokens` ("completion tokens, including retries") are documented there too. Falls back to
    /// `confidence` when either is missing.
    static func perTokenConfidence(_ answer: AnalysisJSON?) -> Double? {
        guard let answer else { return nil }
        if let logP = answer["log_probability"]?.doubleValue, let tokens = answer["tokens"]?.doubleValue,
           tokens > 0, logP <= 0, logP.isFinite {
            return exp(logP / tokens)
        }
        return answer["confidence"]?.doubleValue
    }

    /// Error text from the REST envelope's `errors` (and `messages`). The element shape is not in the saved docs
    /// (the sample shows `[]`), so this accepts strings or objects with `message`/`code`.
    static func errorMessages(_ root: AnalysisJSON) -> String {
        var parts: [String] = []
        for key in ["errors", "messages"] {
            for e in root[key]?.arrayValue ?? [] {
                if let s = e.stringValue {
                    parts.append(s)
                } else if let m = e["message"]?.stringValue {
                    if let code = e["code"]?.intValue { parts.append("\(code): \(m)") } else { parts.append(m) }
                }
            }
        }
        return String(parts.joined(separator: "; ").prefix(300))
    }

    /// Message for a non-2xx response: Cloudflare envelope errors when present, else the raw body prefix.
    public static func cloudflareErrorMessage(from body: Data) -> String {
        if let root = try? AnalysisJSON.parse(body) {
            let m = errorMessages(root)
            if !m.isEmpty { return m }
        }
        return HTTPErrorMapping.genericMessage(from: body)
    }
}

enum AnalysisNormalize {
    /// Accepts `yyyy-MM-dd` (optionally followed by a time part) with a plausible month/day; anything else is nil.
    static func isoDate(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 10 else { return nil }
        let day = String(s.prefix(10))
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...9999).contains(y), (1...12).contains(m), (1...31).contains(d) else { return nil }
        if s.count > 10 {
            let next = s[s.index(s.startIndex, offsetBy: 10)]
            guard next == "T" || next == " " else { return nil }
        }
        return day
    }
}

fileprivate extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
