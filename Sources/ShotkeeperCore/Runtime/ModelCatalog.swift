import Foundation

/// A downloadable Inkling 2 Mini MLX build. Facts from the Hugging Face API and model cards on 2026-11-21;
/// see docs/research/model-backends.md ("MLX quant catalog").
public struct ModelVariant: Sendable, Equatable, Identifiable, Hashable {
    public enum Quality: String, Sendable {
        /// Close to the original weights.
        case full
        /// Small, measurable loss (≈ +1.4% perplexity for the 3-bit build).
        case good
        /// Noticeably weaker (≈ +10% perplexity, weaker image recognition for the 2-bit build).
        case reduced
    }

    /// Hugging Face repo id.
    public var id: String
    public var displayName: String
    public var bits: Int
    /// Git revision pinned for downloads (the repo `sha` on 2026-11-21), so a re-upload can't change what we load.
    public var revision: String
    /// Sum of repo file sizes in GB (10^9 bytes).
    public var approxDownloadGB: Double
    /// Smallest Mac memory (GB, as Apple sells it) the build is offered on.
    public var minRAMGB: Int
    public var quality: Quality
    /// Shown next to the option in setup, if any.
    public var warning: String?
    /// True when the model card itself says to serve it with `mlx_lm.server`. False = published in mlx-vlm format;
    /// loading with the pinned mlx-lm build is not verified yet (no Mac on the build box).
    public var verifiedWithMLXLM: Bool

    public init(id: String, displayName: String, bits: Int, revision: String, approxDownloadGB: Double, minRAMGB: Int,
                quality: Quality, warning: String?, verifiedWithMLXLM: Bool) {
        self.id = id
        self.displayName = displayName
        self.bits = bits
        self.revision = revision
        self.approxDownloadGB = approxDownloadGB
        self.minRAMGB = minRAMGB
        self.quality = quality
        self.warning = warning
        self.verifiedWithMLXLM = verifiedWithMLXLM
    }
}

public enum ModelCatalog {
    /// https://huggingface.co/mlx-community/Inkling-2-Mini-4bit: 17.33 GB, README serves it with `mlx_lm.server`.
    public static let inkling4bit = ModelVariant(
        id: "mlx-community/Inkling-2-Mini-4bit", displayName: "Inkling 2 Mini (4-bit)", bits: 4,
        revision: "9856dc53edead71405f8348930937c3638ff21a2", approxDownloadGB: 17.3, minRAMGB: 32,
        quality: .full, warning: nil, verifiedWithMLXLM: true)

    /// https://huggingface.co/VisualInference/Inkling-2-Mini-MLX-3bit: 13.46 GB download (11.9 GiB weights),
    /// card says "for Macs with 24 GB of memory", peak 12.7–14.1 GiB, +1.4% perplexity. mlx-vlm format.
    public static let inkling3bit = ModelVariant(
        id: "VisualInference/Inkling-2-Mini-MLX-3bit", displayName: "Inkling 2 Mini (3-bit)", bits: 3,
        revision: "ab80e9d5290b3e0c5af093bfd89d2f534c3ffb5b", approxDownloadGB: 13.5, minRAMGB: 24,
        quality: .good, warning: nil, verifiedWithMLXLM: false)

    /// https://huggingface.co/VisualInference/Inkling-2-Mini-MLX-2bit: 10.40 GB download (9.1 GiB weights),
    /// card says "for Macs with 16 GB (tight) or 18 GB", +10% perplexity, weaker image recognition. mlx-vlm format.
    public static let inkling2bit = ModelVariant(
        id: "VisualInference/Inkling-2-Mini-MLX-2bit", displayName: "Inkling 2 Mini (2-bit)", bits: 2,
        revision: "66cf4fbfecdd3198202dc8918e2ba6e22561519d", approxDownloadGB: 10.4, minRAMGB: 16,
        quality: .reduced,
        warning: "Lower quality (weaker image recognition) and tight on memory: other apps may slow down while it runs.",
        verifiedWithMLXLM: false)

    /// Largest first.
    public static let all: [ModelVariant] = [inkling4bit, inkling3bit, inkling2bit]

    public static func variant(id: String) -> ModelVariant? { all.first { $0.id == id } }
}
