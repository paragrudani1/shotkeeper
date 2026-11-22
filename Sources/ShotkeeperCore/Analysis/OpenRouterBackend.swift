import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Inkling 2 Mini through OpenRouter: the `.openRouter` backend. It is the shared `OpenAICompatibleAnalyzer` with
/// this profile and configuration. Every fact here is from docs/research/openrouter.md (OpenRouter docs and public
/// API, read 2026-11-22).
public enum OpenRouterBackend {
    /// Where screenshots go: the consent destination (`UploadTarget.openRouter`) names this host.
    public static let host = "openrouter.ai"
    /// openrouter.md: server `https://openrouter.ai/api/v1` + `POST /chat/completions`.
    public static let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    /// openrouter.md: model `id` (canonical slug `thinkingmachines/inkling-2-mini-20261120`).
    public static let defaultModel = "thinkingmachines/inkling-2-mini"
    /// The providers that serve `defaultModel` (openrouter.md, endpoints snapshot), as the privacy text names them.
    public static let providerNames = ["Prime Intellect", "io.net"]

    /// openrouter.md, "App attribution headers": `HTTP-Referer` is required for attribution; `X-OpenRouter-Title` is
    /// the display name, `X-Title` its legacy name.
    public static let appURL = "https://github.com/paragrudani1/shotkeeper"
    public static let appTitle = "Shotkeeper"

    /// openrouter.md, "Privacy routing": only endpoints that keep no prompts (`zdr`) and do not collect data
    /// (`data_collection: deny`); both Inkling 2 Mini endpoints stay eligible. `require_parameters` routes only to
    /// providers that honour every parameter sent (reasoning off, json_schema, logprobs); both do.
    public static let providerRouting: AnalysisJSON = ["data_collection": "deny", "zdr": true, "require_parameters": true]

    /// openrouter.md, "Disabling reasoning": `reasoning.effort: "none"` disables reasoning; the model lists `none` in
    /// `supported_efforts` and reasoning is not `mandatory`. (`exclude` would only hide it, still billed.)
    public static let reasoningOff: AnalysisJSON = ["effort": "none"]

    /// openrouter.md, "Image input": PNG, JPEG, WebP, GIF.
    public static let supportedMimeTypes: Set<String> = ["image/png", "image/jpeg", "image/webp", "image/gif"]

    /// The JSON answer is ~150–350 tokens (key_text ≤ 500 characters). Sent as `max_tokens`: io.net does not list
    /// `max_completion_tokens`, and `require_parameters` would then exclude it (openrouter.md, parameter table).
    public static let maxTokens = 800

    public static let keysURL = URL(string: "https://openrouter.ai/keys")!
    public static let creditsURL = URL(string: "https://openrouter.ai/settings/credits")!
    public static let privacyPolicyURL = URL(string: "https://openrouter.ai/privacy")!
    public static let providerDataPolicyURL = URL(string: "https://openrouter.ai/docs/guides/privacy/provider-logging")!
    public static let zeroDataRetentionURL = URL(string: "https://openrouter.ai/docs/guides/features/zdr")!

    public static let profile: OpenAICompatibleProfile = {
        var p = OpenAICompatibleProfile(backendID: "openrouter", producedByPrefix: "openrouter", serviceName: "OpenRouter")
        p.headers = ["HTTP-Referer": appURL, "X-OpenRouter-Title": appTitle, "X-Title": appTitle]
        // openrouter.md, "Logprobs": `logprobs: true` returns `choices[].logprobs.content[]` (both providers list it).
        p.extraBody = ["reasoning": reasoningOff, "logprobs": true, "provider": providerRouting]
        p.retriesWithoutExtrasOn400 = false
        p.requiresAPIKey = true
        // openrouter.md, "Image input": "we recommend sending the text prompt first, then the images".
        p.textBeforeImage = true
        p.supportedMimeTypes = supportedMimeTypes
        p.titleConfidence = .tokenLogprobs
        p.validatesTitle = true
        p.reportsBilledTokens = true
        p.errorDialect = .openRouter
        return p
    }()

    /// The analyzer configuration for `apiKey`; `model` nil or blank = `defaultModel`.
    public static func configuration(apiKey: String, model: String? = nil,
                                     timeout: TimeInterval = 60) -> OpenAICompatibleAnalyzer.Configuration {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return OpenAICompatibleAnalyzer.Configuration(baseURL: baseURL, model: trimmed.isEmpty ? defaultModel : trimmed,
                                                      apiKey: apiKey, maxTokens: maxTokens, timeout: timeout,
                                                      profile: profile)
    }

    // MARK: Errors (openrouter.md, "Errors and status codes")

    /// `{"error": {"code", "message", "metadata": {"error_type", "limit_source", …}}}`: "message (error_type)", else
    /// the generic body prefix. Never contains the key (OpenRouter does not echo it).
    public static func errorMessage(from body: Data) -> String {
        guard let error = (try? AnalysisJSON.parse(body))?["error"], let message = error["message"]?.stringValue else {
            return HTTPErrorMapping.genericMessage(from: body)
        }
        let type = error["metadata"]?["error_type"]?.stringValue
        return String((type.map { "\(message) (\($0))" } ?? message).prefix(300))
    }

    /// Statuses whose meaning the docs refine; nil = the shared mapping (401/403 unauthorized, 429 rate limited,
    /// 408/5xx server error, other 4xx bad request).
    /// - 402 with `metadata.limit_source == "openrouter_in_flight_budget"`: "transient … wait for [Retry-After] and
    ///   retry" → `rateLimited`. Any other 402 ("insufficient credits") → `badRequest(402)`, not retried.
    /// - 403 with `error_type` `content_policy_violation` or `refusal`: this image was declined, the key is fine →
    ///   `badRequest(403)`, so the queue is not held.
    public static func refineError(status: Int, headers: HTTPURLResponse?, body: Data) -> AnalyzerError? {
        let error = (try? AnalysisJSON.parse(body))?["error"]
        let metadata = error?["metadata"]
        switch status {
        case 402:
            if metadata?["limit_source"]?.stringValue == "openrouter_in_flight_budget" {
                return .rateLimited(retryAfter: HTTPErrorMapping.retryAfter(HTTPErrorMapping.headerValue(headers, "Retry-After")))
            }
            return .badRequest(status: 402, message: errorMessage(from: body))
        case 403:
            if let type = metadata?["error_type"]?.stringValue, ["content_policy_violation", "refusal"].contains(type) {
                return .badRequest(status: 403, message: errorMessage(from: body))
            }
            return nil
        default:
            return nil
        }
    }
}

/// What OpenRouter costs per 1,000 screenshots. **Nil until measured** by the live test (docs/wiki/openrouter-backend.md):
/// the docs give token prices but not how many prompt tokens one image costs for this model (openrouter.md, "Where
/// the docs are silent"), so no estimate is shown. While nil, setup and Settings show no price line.
public enum OpenRouterPricing {
    /// US dollars per 1,000 full-screen screenshots at `maxImageLongSide` 1280, from `usage.cost` of live calls.
    public static let measuredUSDPerThousandScreenshots: Double? = nil

    /// "About $0.25 for 1,000 screenshots", or nil while not measured.
    public static func perThousandText(usd: Double? = measuredUSDPerThousandScreenshots) -> String? {
        usd.map(PriceText.perThousandScreenshots)
    }
}
