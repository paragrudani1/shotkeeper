import Foundation

/// Every user setting. Codable; decoding tolerates missing or unknown keys (each missing key gets its default),
/// so settings saved by an older build keep loading after new settings are added.
/// Secrets are NOT here: the Cloudflare API token lives in a `CredentialStore` (Keychain in the app).
public struct AppSettings: Codable, Equatable, Sendable {
    public enum Backend: String, Codable, Sendable, CaseIterable {
        /// Cloudflare Workers AI Clairic (default; recommended below 24 GB RAM).
        case clairic
        /// Inkling 2 Mini through OpenRouter (`OpenRouterBackend`), with the user's OpenRouter API key.
        case openRouter
        /// Inkling 2 Mini run by the app's managed `mlx_lm.server`.
        case localInkling
        /// Any OpenAI-compatible endpoint the user runs (e.g. their own llama.cpp/mlx server).
        case customEndpoint
    }

    /// Where a backend sends screenshots off this Mac. Consent is given per destination (`uploadGrants`).
    public enum UploadDestination: String, Codable, Sendable, CaseIterable {
        /// The user's own Cloudflare account (Clairic). Granted when setup's step 3 saves Clairic after step 2's
        /// "I Agree", or by the Settings → Model confirmation.
        case cloudflare
        /// The custom OpenAI-compatible endpoint named in the grant (`UploadGrant.endpoint`). Granted by the
        /// Settings → Model confirmation that names it.
        case customEndpoint
        /// OpenRouter (`openrouter.ai`) for one model (`UploadGrant.openRouterModel`), which passes screenshots on to
        /// that model's provider (Prime Intellect or io.net for the default model). Granted by setup step 3's
        /// "Agree and Continue" or by the Settings → Model confirmation, for the model they name. Never granted by
        /// the legacy-consent migration.
        case openRouter
    }

    /// The user's permission to send screenshots to one destination, from `grantedAt` on. Screenshots taken before
    /// it are never sent there by the watcher (only an explicit "Process Existing Screenshots…" may).
    public struct UploadGrant: Codable, Equatable, Sendable {
        public var destination: UploadDestination
        public var grantedAt: Date
        /// The endpoint allowed, for `.customEndpoint`; nil otherwise.
        public var endpoint: CustomEndpointIdentity?
        /// The model allowed, for `.openRouter` (`OpenRouterBackend.effectiveModel`); nil otherwise. A grant without
        /// one covers no model.
        public var openRouterModel: String?

        public init(destination: UploadDestination, grantedAt: Date, endpoint: CustomEndpointIdentity? = nil,
                    openRouterModel: String? = nil) {
            self.destination = destination
            self.grantedAt = grantedAt
            self.endpoint = endpoint
            self.openRouterModel = openRouterModel
        }
    }

    public var backend: Backend = .clairic
    /// Cloudflare account id (not secret). The API token is in the `CredentialStore` under `.cloudflareAPIToken`.
    public var clairicAccountID: String?
    /// `ModelVariant.id` (Hugging Face repo id) for `.localInkling`; nil = use the `BackendRecommender` choice.
    public var localModelVariantID: String?
    public var customEndpointURL: URL?
    public var customModelName: String?
    /// OpenRouter model ID (Settings → Model → Advanced); nil = `OpenRouterBackend.defaultModel`. The API key is in
    /// the `CredentialStore` under `.openRouterAPIKey`.
    public var openRouterModel: String?
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
    /// Destinations the user allowed, with when. Empty = nothing may leave this Mac. At most one grant per
    /// destination, except OpenRouter: one per model, so going back to a model keeps its first grant time. Settings files written before this key existed are migrated once in `init(from:)`.
    public var uploadGrants: [UploadGrant] = []

    /// The allowed destinations (whatever endpoint or time).
    public var acceptedUploadDestinations: Set<UploadDestination> { Set(uploadGrants.map(\.destination)) }

    public func grant(for destination: UploadDestination) -> UploadGrant? {
        uploadGrants.first { $0.destination == destination }
    }
    /// Show the rename toast after each rename (and the batch summary).
    public var showRenameToast: Bool = true
    /// Play a short sound after a rename.
    public var playRenameSound: Bool = false
    /// Filename style for renames (Settings → General): casing and the optional date at the start.
    public var filenameCasing: FilenameStyle.Casing = .sentence
    public var filenameDatePrefix: Bool = false
    /// The global shortcut that opens Search (Settings → General → "Search shortcut"). Default ⌥⌘S.
    public var searchShortcut: HotKeyShortcut = .defaultSearch

    public var filenameStyle: FilenameStyle {
        get { FilenameStyle(casing: filenameCasing, datePrefix: filenameDatePrefix) }
        set {
            filenameCasing = newValue.casing
            filenameDatePrefix = newValue.datePrefix
        }
    }

    public init() {}

    public static let defaults = AppSettings()

    /// Adding a setting (2026-11-28): one `case` line here and one `value(...)` line in `init(from:)`, each
    /// on its own line so parallel changes merge without conflicts. `SettingsTests.testEveryPropertyRoundTrips`
    /// fails until both exist.
    private enum CodingKeys: String, CodingKey {
        case backend
        case clairicAccountID
        case localModelVariantID
        case customEndpointURL
        case customModelName
        case openRouterModel
        case idleTimeoutMinutes
        case watchedFolderOverride
        case organizedFolder
        case renameEnabled
        case moveEnabled
        case launchAtLogin
        case minTitleConfidence
        case requestsPerMinute
        case maxImageLongSide
        case writeFinderMetadata
        case excludeRules
        case hasSeenPrivacyNotice
        case uploadGrants
        case showRenameToast
        case playRenameSound
        case filenameCasing
        case filenameDatePrefix
        case searchShortcut
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
        s.openRouterModel = value(.openRouterModel, s.openRouterModel)
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
        if c.contains(.uploadGrants) {
            s.uploadGrants = value(.uploadGrants, s.uploadGrants)
        } else {
            s.migrateLegacyConsent()
        }
        s.showRenameToast = value(.showRenameToast, s.showRenameToast)
        s.playRenameSound = value(.playRenameSound, s.playRenameSound)
        s.filenameCasing = value(.filenameCasing, s.filenameCasing)
        s.filenameDatePrefix = value(.filenameDatePrefix, s.filenameDatePrefix)
        // A stored shortcut that is no longer allowed (rules changed, hand-edited file) falls back to the default.
        let shortcut = value(.searchShortcut, s.searchShortcut)
        s.searchShortcut = HotKeyRules.problem(with: shortcut) == nil ? shortcut : .defaultSearch
        self = s
    }

    /// Settings from before per-destination consent. The old setup set `hasSeenPrivacyNotice` for every backend,
    /// local included, and its notice named Cloudflare. So the flag becomes a Cloudflare grant only when Clairic is
    /// the stored backend, dated `.distantPast` (that user already sent screenshots there). A custom endpoint is not
    /// migrated: Settings asks once, naming the endpoint. A stored local backend grants nothing. OpenRouter did not
    /// exist then, so nothing ever becomes an OpenRouter grant here.
    mutating func migrateLegacyConsent() {
        uploadGrants = []
        if hasSeenPrivacyNotice, backend == .clairic {
            uploadGrants = [UploadGrant(destination: .cloudflare, grantedAt: .distantPast)]
        }
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

/// Who a custom endpoint really is: scheme + lowercased host + effective port. Consent for one identity does not
/// cover another (another port can be another server, http vs https another channel).
public struct CustomEndpointIdentity: Codable, Equatable, Hashable, Sendable {
    public var scheme: String
    public var host: String
    public var port: Int

    public init(scheme: String, host: String, port: Int) {
        self.scheme = scheme
        self.host = host
        self.port = port
    }

    /// Nil unless `url` is http(s) with a host. The port defaults to 80 / 443.
    public init?(url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        self.init(scheme: scheme, host: host, port: url.port ?? (scheme == "https" ? 443 : 80))
    }

    /// "gpu-box.lan:8443" for https, "http://gpu-box.lan:8080" otherwise (unencrypted is named). IPv6 in brackets.
    public var display: String {
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return scheme == "https" ? "\(hostPart):\(port)" : "http://\(hostPart):\(port)"
    }
}
