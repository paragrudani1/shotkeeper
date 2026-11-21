import Foundation

/// What Clairic costs per screenshot at the standard price. The measured token count is
/// `ClairicFieldSchema.estimatedInputTokens` (live calls on 2026-11-21: 1,242 schema tokens + 7 × 1,000 image tokens
/// for a 1280×800 screenshot = 8,242 tokens; docs/wiki/clairic-field-schema.md).
public enum ClairicPricing {
    /// "$0.10 per M input tokens until December 1, 2026, then $0.24 per M input tokens"
    /// (docs/research/clairic/model-page-2026-11-21.md, "Unit Pricing"). Setup quotes the price after the promo.
    public static let standardUSDPerMillionInputTokens = 0.24

    /// US dollars per 1,000 full-screen 16:10 screenshots downscaled to `longSide` (the app's `maxImageLongSide`).
    public static func usdPerThousandScreenshots(longSide: Int = ClairicFieldSchema.recommendedMaxImageLongSide) -> Double {
        let tokens = ClairicFieldSchema.estimatedInputTokens(width: longSide, height: longSide * 10 / 16)
        return Double(tokens) * standardUSDPerMillionInputTokens / 1_000_000 * 1_000
    }

    /// "About $2 for 1,000 screenshots" (whole dollars from $1 up, else cents: "About $0.57 …").
    public static func perThousandText(longSide: Int = ClairicFieldSchema.recommendedMaxImageLongSide) -> String {
        let usd = usdPerThousandScreenshots(longSide: longSide)
        let amount = usd >= 1 ? "$\(Int(usd.rounded()))" : String(format: "$%.2f", usd)
        return "About \(amount) for 1,000 screenshots"
    }
}

/// One selectable model card in setup step 3.
public struct SetupModelCard: Equatable, Sendable, Identifiable {
    public var id: AppSettings.Backend { backend }
    /// `.clairic` or `.localInkling` (a custom endpoint is configured in Settings only).
    public var backend: AppSettings.Backend
    public var title: String
    /// "Recommended", "Experimental".
    public var badges: [String]
    public var subtitle: String
    public var isRecommended: Bool
    /// False when this Mac cannot run it (local model below the catalog's smallest memory size).
    public var isAvailable: Bool
    /// The local build setup installs; nil for Clairic and when no build fits.
    public var model: ModelVariant?
    /// The orange note under the selected local card (quality, memory, experimental build), from `BackendRecommender`.
    public var note: String? = nil

    /// "Install and Download (about 10 GB)" for the local card.
    public var installButtonTitle: String? {
        model.map { "Install and Download (about \(SetupCards.gigabytes($0.approxDownloadGB)) GB)" }
    }

    /// VoiceOver: "Cloudflare Clairic, Recommended. Best for this Mac (16 GB). About $2 for 1,000 screenshots."
    public var accessibilityLabel: String {
        ([title] + badges).joined(separator: ", ") + ". " + subtitle
    }
}

/// The two cards of setup step 3, worded for this Mac's memory. Which one is recommended follows
/// `BackendRecommender` ("recommend by RAM as today").
public struct SetupCards: Equatable, Sendable {
    public var clairic: SetupModelCard
    public var local: SetupModelCard
    public var all: [SetupModelCard] { [clairic, local] }
    public var recommended: AppSettings.Backend { local.isRecommended ? .localInkling : .clairic }

    public func card(for backend: AppSettings.Backend) -> SetupModelCard? { all.first { $0.backend == backend } }

    public static func make(physicalMemoryBytes: UInt64, catalog: [ModelVariant] = ModelCatalog.all,
                            clairicLongSide: Int = ClairicFieldSchema.recommendedMaxImageLongSide) -> SetupCards {
        let ramGB = BackendRecommender.marketingGB(physicalMemoryBytes)
        let recommendation = BackendRecommender.recommend(physicalMemoryBytes: physicalMemoryBytes, catalog: catalog)
        let localRecommended = recommendation.recommended.backend == .localInkling
        let localOption = ([recommendation.recommended] + recommendation.alternatives)
            .first { $0.backend == .localInkling }
        let cost = ClairicPricing.perThousandText(longSide: clairicLongSide) + "."

        let clairic = SetupModelCard(
            backend: .clairic, title: "Cloudflare Clairic", badges: localRecommended ? [] : ["Recommended"],
            subtitle: (localRecommended ? "Fast, nothing to download. " : "Best for this Mac (\(ramGB) GB). ") + cost,
            isRecommended: !localRecommended, isAvailable: true, model: nil)

        let local: SetupModelCard
        if let model = localOption?.model {
            let disk = "Needs about \(gigabytes(model.approxDownloadGB)) GB of disk."
            var badges: [String] = []
            if localRecommended { badges.append("Recommended") }
            if model.quality == .reduced || !model.verifiedWithMLXLM { badges.append("Experimental") }
            let subtitle = model.quality == .reduced
                ? "Private, but slow and lower quality on \(ramGB) GB. \(disk)"
                : "Private: nothing leaves this Mac. \(localRecommended ? "Best for this Mac (\(ramGB) GB). " : "")\(disk)"
            local = SetupModelCard(backend: .localInkling, title: "Inkling 2 Mini, on this Mac", badges: badges,
                                   subtitle: subtitle, isRecommended: localRecommended, isAvailable: true, model: model,
                                   note: localOption?.warning)
        } else {
            let needed = catalog.map(\.minRAMGB).min() ?? 16
            local = SetupModelCard(backend: .localInkling, title: "Inkling 2 Mini, on this Mac", badges: [],
                                   subtitle: "Needs a Mac with at least \(needed) GB of memory. This Mac has \(ramGB) GB.",
                                   isRecommended: false, isAvailable: false, model: nil)
        }
        return SetupCards(clairic: clairic, local: local)
    }

    /// 10.4 → 10, 13.5 → 14 (the catalog's sizes are 10^9 bytes, like Finder's).
    static func gigabytes(_ value: Double) -> Int { Int(value.rounded()) }
}

/// Text for setup's "Test Connection" (also used by Settings): never a raw error, never a secret.
public enum ConnectionTestText {
    public static let sending = "Sending a test image…"
    public static let success = "Connected. The test image was analyzed."

    /// A short, readable sentence for a failed test.
    public static func failure(_ error: any Error, backend: AppSettings.Backend) -> String {
        guard let error = error as? AnalyzerError else { return UserFacingError.problem(for: error).sentence }
        let isClairic = backend == .clairic
        let server: String = {
            switch backend {
            case .clairic: return "Cloudflare"
            case .localInkling: return "The local model"
            case .customEndpoint: return "The server"
            }
        }()
        switch error {
        case .notConfigured(let reason):
            return UserFacingProblem(message: reason).sentence
        case .unauthorized:
            return isClairic
                ? "Cloudflare did not accept the token. Check the account ID, and that the token has Workers AI Read and Edit permissions."
                : "\(server) did not accept the API key."
        case .unreachable:
            switch backend {
            case .clairic: return "Could not reach Cloudflare. Check the internet connection and try again."
            case .localInkling: return "Could not reach the local model server."
            case .customEndpoint: return "Could not reach the server at that URL."
            }
        case .rateLimited:
            return "\(server) is limiting requests right now. Try again in a minute."
        case .serverError(let status, _):
            return "\(server) had a problem (HTTP \(status)). Try again in a minute."
        case .badRequest(let status, _):
            if status == 0 { return "The test image could not be sent." }
            if isClairic, status == 404 {
                return "Cloudflare could not find this account (HTTP 404). Check the account ID."
            }
            return isClairic ? "Cloudflare rejected the test request (HTTP \(status)). Check the account ID."
                             : "\(server) rejected the test request (HTTP \(status)). Check the model name."
        case .invalidResponse:
            return "\(server) answered, but the answer could not be read. Try again."
        }
    }
}
