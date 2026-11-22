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
    /// Their routing slugs: the provider segment of the endpoint `tag`s `primeintellect/fp4` and `io-net/nvfp4` in
    /// `GET /api/v1/models/thinkingmachines/inkling-2-mini/endpoints` (2026-11-22; = the `slug`s in
    /// `GET /api/v1/providers`). A base slug "matches all eligible endpoints for that provider" (openrouter.md,
    /// "Pinning the providers"). Sent as `provider.only` for `defaultModel` only, so screenshots go exactly where
    /// the consent text says.
    public static let providerSlugs = ["primeintellect", "io-net"]

    /// openrouter.md, "App attribution headers": `HTTP-Referer` is required for attribution; `X-OpenRouter-Title` is
    /// the display name, `X-Title` its legacy name.
    public static let appURL = "https://github.com/paragrudani1/shotkeeper"
    public static let appTitle = "Shotkeeper"

    /// openrouter.md, "Privacy routing": only endpoints that keep no prompts (`zdr`) and do not collect data
    /// (`data_collection: deny`); both Inkling 2 Mini endpoints stay eligible. `require_parameters` routes only to
    /// providers that honour every parameter sent (reasoning off, json_schema, logprobs); both do. For `defaultModel`
    /// `only` pins the two providers the consent names; another model's providers are not known in advance, so its
    /// consent names "the provider that serves <model>" instead.
    public static func providerRouting(model: String) -> AnalysisJSON {
        var routing: [String: AnalysisJSON] = ["data_collection": "deny", "zdr": true, "require_parameters": true]
        if model == defaultModel { routing["only"] = .array(providerSlugs.map { .string($0) }) }
        return .object(routing)
    }

    /// The model a setting means: trimmed, empty = `defaultModel`. Also the model part of an OpenRouter grant.
    public static func effectiveModel(_ setting: String?) -> String {
        let trimmed = setting?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultModel : trimmed
    }

    /// "OpenRouter, then to Prime Intellect or io.net" for the default model, else "OpenRouter, then to the provider
    /// that serves <model>": the destination as the consent prompt and setup name it.
    public static func destinationPhrase(model: String) -> String {
        model == defaultModel ? "OpenRouter, then to " + providerNames.joined(separator: " or ")
                              : "OpenRouter, then to the provider that serves \(model)"
    }

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

    /// The profile for `model` (an effective model ID): only `provider` routing depends on it.
    public static func profile(model: String = defaultModel) -> OpenAICompatibleProfile {
        var p = OpenAICompatibleProfile(backendID: "openrouter", producedByPrefix: "openrouter", serviceName: "OpenRouter")
        p.headers = ["HTTP-Referer": appURL, "X-OpenRouter-Title": appTitle, "X-Title": appTitle]
        // openrouter.md, "Logprobs": `logprobs: true` returns `choices[].logprobs.content[]` (both providers list it).
        p.extraBody = ["reasoning": reasoningOff, "logprobs": true, "provider": providerRouting(model: model)]
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
    }

    /// The analyzer configuration for `apiKey`; `model` nil or blank = `defaultModel`.
    public static func configuration(apiKey: String, model: String? = nil,
                                     timeout: TimeInterval = 60) -> OpenAICompatibleAnalyzer.Configuration {
        let model = effectiveModel(model)
        return OpenAICompatibleAnalyzer.Configuration(baseURL: baseURL, model: model, apiKey: apiKey,
                                                      maxTokens: maxTokens, timeout: timeout, profile: profile(model: model))
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

    /// Hold texts (`AnalyzerError.accountState`): what the menu and the toast say. The queue waits for Resume.
    public static let outOfCreditsText = "OpenRouter is out of credits. Add credits, then choose Resume"
    public static let spendingLimitText = "Your OpenRouter key reached its spending limit. Raise the limit on "
        + "openrouter.ai or wait until it resets, then choose Resume"
    public static let noEndpointText = "OpenRouter has no provider for this model that Shotkeeper may use. Check the "
        + "model in Settings → Model, then choose Resume"
    public static let noEligibleProviderText = "No OpenRouter provider for this model meets Shotkeeper's privacy "
        + "settings right now. Choose Resume to try again"

    /// Statuses whose meaning the docs refine; nil = the shared mapping (401/403 unauthorized, 429 rate limited,
    /// 408/5xx server error, other 4xx bad request).
    /// - 402 with a `Retry-After` header (the docs: the in-flight budget, "wait for [Retry-After] and retry") →
    ///   `rateLimited`. Any other 402 ("A `402` without the header is not a wait-and-retry case") holds the queue until
    ///   Resume: `limit_source: openrouter_key_limit` (the key's credit limit) → `accountState(spendingLimitText)`,
    ///   else (credits, an in-flight budget without the header) → `accountState(outOfCreditsText)`.
    /// - 403 with `metadata.limit_source` (guardrail, workspace or key budget, "rejected with a `403` before it
    ///   reaches a provider") → `accountState(spendingLimitText)`. 403 with `error_type` `content_policy_violation`
    ///   or `refusal`: this image was declined, the key is fine → `badRequest(403)`, the queue is not held.
    /// - 404 (other than `image_not_found`): no endpoint the request may use ("If no provider satisfies both, the
    ///   request fails with a 404", provider-selection page) → `accountState(noEndpointText)`.
    /// - 503 without `error_type: provider_overloaded`: "no available model provider that meets your routing
    ///   requirements" → `accountState(noEligibleProviderText)`. `provider_overloaded` stays a retried server error.
    /// 404 and 503 hold only when they are OpenRouter's own routing answer: the HTTP status itself (not an error
    /// embedded in a 200 mid-generation, `embedded`), with an OpenRouter `error` body and no `Retry-After` (which
    /// "may come on 429 and 503"). An HTML edge page, a 503 with `Retry-After` or an embedded 404/503 → nil (retried).
    public static func refineError(status: Int, headers: HTTPURLResponse?, body: Data,
                                   embedded: Bool = false) -> AnalyzerError? {
        let error = (try? AnalysisJSON.parse(body))?["error"]
        let metadata = error?["metadata"]
        let type = metadata?["error_type"]?.stringValue
        let retryAfter = HTTPErrorMapping.retryAfter(HTTPErrorMapping.headerValue(headers, "Retry-After"))
        let isRoutingAnswer = !embedded && error?.objectValue != nil && retryAfter == nil
        switch status {
        case 402:
            if let retryAfter { return .rateLimited(retryAfter: retryAfter) }
            if metadata?["limit_source"]?.stringValue == "openrouter_key_limit" { return .accountState(spendingLimitText) }
            return .accountState(outOfCreditsText)
        case 403:
            if metadata?["limit_source"]?.stringValue != nil { return .accountState(spendingLimitText) }
            if let type, ["content_policy_violation", "refusal"].contains(type) {
                return .badRequest(status: 403, message: errorMessage(from: body))
            }
            return nil
        case 404:
            return isRoutingAnswer && type != "image_not_found" ? .accountState(noEndpointText) : nil
        case 503:
            return isRoutingAnswer && type != "provider_overloaded" ? .accountState(noEligibleProviderText) : nil
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
