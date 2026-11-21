import Foundation

/// One choice the setup screen can show.
public struct BackendOption: Sendable, Equatable {
    public var backend: AppSettings.Backend
    /// Set for `.localInkling`.
    public var model: ModelVariant?
    public var title: String
    public var detail: String
    public var warning: String?

    public init(backend: AppSettings.Backend, model: ModelVariant? = nil, title: String, detail: String, warning: String? = nil) {
        self.backend = backend
        self.model = model
        self.title = title
        self.detail = detail
        self.warning = warning
    }
}

public struct BackendRecommendation: Sendable, Equatable {
    public var recommended: BackendOption
    /// Other valid choices, best first.
    public var alternatives: [BackendOption]
    /// Whole-screen notes (e.g. "this Mac has too little memory for a local model").
    public var notes: [String]
}

/// Physical RAM → which backend to suggest. Rules (user decision, 2026-11-21, docs/wiki/model-backend.md):
/// - < 24 GB: Clairic. On 16–23 GB, "use local anyway (2-bit, lower quality)" is an alternative with a warning.
/// - ≥ 24 GB: local Inkling with the largest build that fits (3-bit at 24 GB when the catalog has one, 4-bit at ≥ 32 GB);
///   with no fitting build, Clairic.
/// A custom OpenAI-compatible endpoint is always offered last.
public enum BackendRecommender {
    public static func recommend(physicalMemoryBytes: UInt64, catalog: [ModelVariant] = ModelCatalog.all) -> BackendRecommendation {
        let ramGB = marketingGB(physicalMemoryBytes)
        let clairic = BackendOption(
            backend: .clairic, title: "Cloudflare Clairic",
            detail: "Screenshots are sent to your Cloudflare account for analysis. Fast, low cost, uses no memory on this Mac.")
        let custom = BackendOption(
            backend: .customEndpoint, title: "Custom endpoint",
            detail: "Any OpenAI-compatible server you run yourself (e.g. on another machine).")
        let fitting = catalog.filter { $0.minRAMGB <= ramGB }.sorted { $0.bits > $1.bits }

        if ramGB >= 24, let best = fitting.first(where: { $0.quality != .reduced }) {
            let others = fitting.filter { $0 != best }.map { local($0, ramGB: ramGB, anyway: $0.quality == .reduced) }
            return BackendRecommendation(recommended: local(best, ramGB: ramGB, anyway: false),
                                         alternatives: [clairic] + others + [custom], notes: [])
        }

        var alternatives: [BackendOption] = []
        var notes: [String] = []
        if let smallest = fitting.last {
            alternatives.append(local(smallest, ramGB: ramGB, anyway: true))
        } else {
            let needed = catalog.map(\.minRAMGB).min() ?? 16
            notes.append("This Mac has \(ramGB) GB of memory; running Inkling 2 Mini locally needs at least \(needed) GB.")
        }
        return BackendRecommendation(recommended: clairic, alternatives: alternatives + [custom], notes: notes)
    }

    /// Bytes → the GB figure Apple sells (17179869184 → 16). Rounds to the nearest GiB.
    static func marketingGB(_ bytes: UInt64) -> Int {
        Int((Double(bytes) / 1_073_741_824).rounded())
    }

    private static func local(_ model: ModelVariant, ramGB: Int, anyway: Bool) -> BackendOption {
        let title = anyway ? "Use local anyway (\(model.bits)-bit, lower quality)" : "\(model.displayName), on this Mac"
        let detail = "Private: screenshots never leave this Mac. One-time download of about \(Int(model.approxDownloadGB.rounded())) GB."
        var warnings: [String] = []
        if let warning = model.warning { warnings.append(warning) }
        if !model.verifiedWithMLXLM { warnings.append("Experimental build: not yet tested with the built-in model server.") }
        return BackendOption(backend: .localInkling, model: model, title: title, detail: detail,
                             warning: warnings.isEmpty ? nil : warnings.joined(separator: " "))
    }
}
