import Foundation

/// Every user setting. Codable; decoding tolerates missing or unknown keys (each missing key gets its default),
/// so settings saved by an older build keep loading after new settings are added.
/// Secrets are NOT here: the Cloudflare API token lives in a `CredentialStore` (Keychain in the app).
public struct AppSettings: Codable, Equatable, Sendable {
    public enum Backend: String, Codable, Sendable, CaseIterable {
        /// Cloudflare Workers AI Clairic (default; recommended below 24 GB RAM).
        case clairic
        /// Inkling 2 Mini run by the app's managed `mlx_lm.server`.
        case localInkling
        /// Any OpenAI-compatible endpoint the user runs (e.g. their own llama.cpp/mlx server).
        case customEndpoint
    }

    /// Where a backend sends screenshots off this Mac. Consent is given per destination (`acceptedUploadDestinations`).
    public enum UploadDestination: String, Codable, Sendable, CaseIterable {
        /// The user's own Cloudflare account (Clairic). Granted by setup step 2's "I Agree".
        case cloudflare
        /// The custom OpenAI-compatible endpoint, for the host in `acceptedCustomEndpointHost`. Granted by the
        /// confirmation in Settings → Model that names the host.
        case customEndpoint
    }

    public var backend: Backend = .clairic
    /// Cloudflare account id (not secret). The API token is in the `CredentialStore` under `.cloudflareAPIToken`.
    public var clairicAccountID: String?
    /// `ModelVariant.id` (Hugging Face repo id) for `.localInkling`; nil = use the `BackendRecommender` choice.
    public var localModelVariantID: String?
    public var customEndpointURL: URL?
    public var customModelName: String?
    /// Stop the managed local server after this many idle minutes. 0 = never.
    public var idleTimeoutMinutes: Int = 10
    /// Folder to watch; nil = the macOS screenshot location (`com.apple.screencapture location`, else Desktop).
    public var watchedFolderOverride: URL?
    /// Destination for `moveEnabled`.
    public var organizedFolder: URL?
    public var renameEnabled: Bool = true
    public var moveEnabled: Bool = false
    public var launchAtLogin: Bool = false
    /// Rename only when the backend's title confidence is at least this.
    public var minTitleConfidence: Double = 0.5
    /// Token-bucket rate for model requests.
    public var requestsPerMinute: Int = 30
    /// Longest image side in pixels handed to the analyzer (the `ImagePreparer` downscales). Main Clairic cost lever.
    public var maxImageLongSide: Int = 1280
    /// Write Finder tags and a Finder comment.
    public var writeFinderMetadata: Bool = true
    public var excludeRules: ExcludeRules = ExcludeRules()
    /// Setup's privacy step was completed once ("I Agree"). Decides whether setup opens at launch; it is NOT the
    /// upload consent any more (2026-11-21): that is `acceptedUploadDestinations`.
    public var hasSeenPrivacyNotice: Bool = false
    /// Destinations the user allowed screenshots to be sent to. Empty = nothing may leave this Mac.
    /// Settings files written before this key existed are migrated once in `init(from:)`.
    public var acceptedUploadDestinations: Set<UploadDestination> = []
    /// The custom endpoint host the user allowed (lowercased). A different host needs a new confirmation.
    public var acceptedCustomEndpointHost: String?
    /// Show the rename toast after each rename (and the batch summary).
    public var showRenameToast: Bool = true
    /// Play a short sound after a rename.
    public var playRenameSound: Bool = false

    public init() {}

    public static let defaults = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case backend, clairicAccountID, localModelVariantID, customEndpointURL, customModelName, idleTimeoutMinutes,
             watchedFolderOverride, organizedFolder, renameEnabled, moveEnabled, launchAtLogin, minTitleConfidence,
             requestsPerMinute, maxImageLongSide, writeFinderMetadata, excludeRules, hasSeenPrivacyNotice,
             acceptedUploadDestinations, acceptedCustomEndpointHost, showRenameToast, playRenameSound
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            // Missing key, null, or a value of the wrong type (e.g. an enum case this build doesn't know) → default.
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        var s = AppSettings()
        s.backend = value(.backend, s.backend)
        s.clairicAccountID = value(.clairicAccountID, s.clairicAccountID)
        s.localModelVariantID = value(.localModelVariantID, s.localModelVariantID)
        s.customEndpointURL = value(.customEndpointURL, s.customEndpointURL)
        s.customModelName = value(.customModelName, s.customModelName)
        s.idleTimeoutMinutes = value(.idleTimeoutMinutes, s.idleTimeoutMinutes)
        s.watchedFolderOverride = value(.watchedFolderOverride, s.watchedFolderOverride)
        s.organizedFolder = value(.organizedFolder, s.organizedFolder)
        s.renameEnabled = value(.renameEnabled, s.renameEnabled)
        s.moveEnabled = value(.moveEnabled, s.moveEnabled)
        s.launchAtLogin = value(.launchAtLogin, s.launchAtLogin)
        s.minTitleConfidence = value(.minTitleConfidence, s.minTitleConfidence)
        s.requestsPerMinute = value(.requestsPerMinute, s.requestsPerMinute)
        s.maxImageLongSide = value(.maxImageLongSide, s.maxImageLongSide)
        s.writeFinderMetadata = value(.writeFinderMetadata, s.writeFinderMetadata)
        s.excludeRules = value(.excludeRules, s.excludeRules)
        s.hasSeenPrivacyNotice = value(.hasSeenPrivacyNotice, s.hasSeenPrivacyNotice)
        if c.contains(.acceptedUploadDestinations) {
            s.acceptedUploadDestinations = value(.acceptedUploadDestinations, s.acceptedUploadDestinations)
            s.acceptedCustomEndpointHost = value(.acceptedCustomEndpointHost, s.acceptedCustomEndpointHost)
        } else {
            s.migrateLegacyConsent()
        }
        s.showRenameToast = value(.showRenameToast, s.showRenameToast)
        s.playRenameSound = value(.playRenameSound, s.playRenameSound)
        self = s
    }

    /// Settings from before per-destination consent: the old setup set `hasSeenPrivacyNotice` for every backend,
    /// local included, after showing a notice about the backend it was saving. So the flag counts as consent only
    /// for the destination of the backend stored with it; a stored local backend grants nothing.
    mutating func migrateLegacyConsent() {
        acceptedUploadDestinations = []
        acceptedCustomEndpointHost = nil
        guard hasSeenPrivacyNotice else { return }
        switch backend {
        case .clairic:
            acceptedUploadDestinations = [.cloudflare]
        case .customEndpoint:
            if let host = AppSettings.normalizedHost(customEndpointURL) {
                acceptedUploadDestinations = [.customEndpoint]
                acceptedCustomEndpointHost = host
            }
        case .localInkling:
            break
        }
    }

    /// Lowercased host of an http(s) URL, nil otherwise.
    public static func normalizedHost(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    /// JSON for storage (e.g. a file in Application Support or a UserDefaults blob).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decodes stored JSON; returns defaults if the data is unreadable.
    public static func decode(_ data: Data) -> AppSettings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }
}
