import Foundation
import ShotkeeperCore

/// Fails every call with `.notConfigured`, so the queue holds in `.error(message)` (nothing is marked failed)
/// until the user fixes settings and the coordinator calls `resume()`.
struct UnconfiguredAnalyzer: ScreenshotAnalyzer {
    let backendID: String
    let reason: String

    func analyze(_ image: ImagePayload, context: AnalysisContext) async throws -> ScreenshotAnalysis {
        throw AnalyzerError.notConfigured(reason)
    }
}

/// What the local backend needs from the managed `mlx_lm.server` (implemented by `LocalModelRuntime`).
protocol LocalModelServing: Sendable {
    /// Starts the server if needed and marks a request in flight. Returns the server base URL (`http://127.0.0.1:<port>`).
    /// Throws `AnalyzerError.notConfigured` when the runtime or model is not installed, `.unreachable` when it
    /// could not start.
    func beginRequest(for variant: ModelVariant) async throws -> URL
    /// Pair of `beginRequest`; feeds the idle timer.
    func endRequest() async
    /// The `model` value to send: the same string the server was launched with (`--model <local dir>`).
    func modelArgument(for variant: ModelVariant) -> String
}

/// Inkling via the app-managed server: starts it on demand, then delegates to `OpenAICompatibleAnalyzer`.
/// One analyzer instance is kept per server URL so its "server rejected structured-output parameters" fallback
/// is remembered across screenshots.
final class ManagedLocalAnalyzer: ScreenshotAnalyzer, @unchecked Sendable {
    let backendID = "local-inkling"
    let variant: ModelVariant
    private let runtime: any LocalModelServing
    private let lock = NSLock()
    private var cached: (url: URL, analyzer: OpenAICompatibleAnalyzer)?

    init(variant: ModelVariant, runtime: any LocalModelServing) {
        self.variant = variant
        self.runtime = runtime
    }

    func analyze(_ image: ImagePayload, context: AnalysisContext) async throws -> ScreenshotAnalysis {
        let baseURL = try await runtime.beginRequest(for: variant)
        do {
            let result = try await analyzer(for: baseURL).analyze(image, context: context)  // lint-allow: analyze (wrapper: forwards its own call)
            await runtime.endRequest()
            return result
        } catch {
            await runtime.endRequest()
            throw error
        }
    }

    private func analyzer(for baseURL: URL) -> OpenAICompatibleAnalyzer {
        lock.withLock {
            if let cached, cached.url == baseURL { return cached.analyzer }
            // mlx_lm.server takes `model` per request (docs/research/openai-compatible-chat.md); sending the
            // value it was launched with makes it use the already-loaded weights.
            let analyzer = OpenAICompatibleAnalyzer(configuration: .init(
                baseURL: baseURL, model: runtime.modelArgument(for: variant), maxTokens: 400, timeout: 180))
            cached = (baseURL, analyzer)
            return analyzer
        }
    }
}

/// Builds the active `ScreenshotAnalyzer` from settings + credentials. Pure apart from reading the credential store,
/// so it is unit-tested with `InMemoryCredentialStore` and a fake runtime.
enum AnalyzerFactory {
    static func make(settings: AppSettings, credentials: any CredentialStore,
                     localRuntime: (any LocalModelServing)?,
                     physicalMemoryBytes: UInt64 = SystemInfo.physicalMemoryBytes) -> any ScreenshotAnalyzer {
        // Account/token/URL/model checks are core `BackendGate`. Its consent check here only gives the "Needs
        // attention" hold and costs nothing; whether a file is sent is decided by `UploadConsent.decide` in the
        // processor (CODING_STANDARDS #2).
        switch settings.backend {
        case .clairic:
            let token: String
            do {
                token = (try credentials.secret(for: .cloudflareAPIToken) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return UnconfiguredAnalyzer(backendID: "clairic", reason: "Could not read the API token from the Keychain")
            }
            let readiness = BackendGate.readiness(settings: settings, hasClairicToken: !token.isEmpty)
            if let reason = BackendGate.reason(for: readiness) {
                return UnconfiguredAnalyzer(backendID: "clairic", reason: reason)
            }
            let accountID = settings.clairicAccountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CloudflareClairicAnalyzer(credentials: ClairicCredentials(accountID: accountID, apiToken: token))

        case .openRouter:
            let key: String
            do {
                key = (try credentials.secret(for: .openRouterAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return UnconfiguredAnalyzer(backendID: "openrouter", reason: "Could not read the OpenRouter API key from the Keychain")
            }
            let readiness = BackendGate.readiness(settings: settings, hasClairicToken: false, hasOpenRouterKey: !key.isEmpty)
            if let reason = BackendGate.reason(for: readiness) {
                return UnconfiguredAnalyzer(backendID: "openrouter", reason: reason)
            }
            // The shared OpenAI-compatible client with OpenRouter's profile (core `OpenRouterBackend`).
            return OpenAICompatibleAnalyzer(configuration: OpenRouterBackend.configuration(apiKey: key,
                                                                                        model: settings.openRouterModel))

        case .customEndpoint:
            let readiness = BackendGate.readiness(settings: settings, hasClairicToken: false)
            if let reason = BackendGate.reason(for: readiness) {
                return UnconfiguredAnalyzer(backendID: "local-openai", reason: reason)
            }
            guard let url = settings.customEndpointURL else {
                return UnconfiguredAnalyzer(backendID: "local-openai", reason: "Custom endpoint URL is not set")
            }
            let model = settings.customModelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = (try? credentials.secret(for: .customEndpointAPIKey))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return OpenAICompatibleAnalyzer(configuration: .init(
                baseURL: url, model: model, apiKey: (key?.isEmpty ?? true) ? nil : key))

        case .localInkling:
            guard let runtime = localRuntime else {
                return UnconfiguredAnalyzer(backendID: "local-inkling", reason: "Local model runtime is unavailable")
            }
            return ManagedLocalAnalyzer(variant: localVariant(for: settings, physicalMemoryBytes: physicalMemoryBytes),
                                        runtime: runtime)
        }
    }

    /// The saved variant, else the recommender's local pick, else the smallest build (the user chose local anyway).
    static func localVariant(for settings: AppSettings,
                             physicalMemoryBytes: UInt64 = SystemInfo.physicalMemoryBytes) -> ModelVariant {
        if let id = settings.localModelVariantID, let variant = ModelCatalog.variant(id: id) { return variant }
        let recommendation = BackendRecommender.recommend(physicalMemoryBytes: physicalMemoryBytes)
        let options = [recommendation.recommended] + recommendation.alternatives
        if let model = options.first(where: { $0.backend == .localInkling })?.model { return model }
        return ModelCatalog.all.last ?? ModelCatalog.inkling2bit
    }
}
