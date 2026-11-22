import Foundation

/// Whether the chosen backend may analyze the user's screenshots now.
public enum BackendReadiness: Equatable, Sendable {
    case ready
    /// Settings are complete, but the backend sends screenshots off this Mac and the user has not accepted the
    /// privacy notice (setup step 2, "I Agree").
    case needsConsent
    /// Something is missing; the reason is a short sentence fragment ("Cloudflare API token is not set").
    case notConfigured(String)
}

/// What the app shows and offers around consent (CODING_STANDARDS #2): readiness, the watcher gate, the Settings
/// confirmation and granting. It never decides whether a file is sent: that is `UploadConsent.decide`, called by
/// `ScreenshotProcessor` right before `analyze`. Both match grants with `UploadConsent.grant(for:in:)`.
///
/// Consent is per destination with a time (`AppSettings.uploadGrants`): `.cloudflare` when setup saves Clairic after
/// step 2's "I Agree", or from the Settings confirmation; `.customEndpoint` from the Settings confirmation naming the
/// endpoint, for that endpoint only (scheme + host + port). Test Connection is not gated: it sends only a generated
/// image, never a user file.
public enum BackendGate {
    public static let consentReason = "Finish setup to allow where screenshots are sent (or allow it in Settings → Model)"

    /// True for backends that send screenshots off this Mac. A custom endpoint counts even when it is on
    /// 127.0.0.1: the app cannot tell where a URL really ends up.
    public static func sendsScreenshotsOffThisMac(_ backend: AppSettings.Backend) -> Bool {
        destination(of: backend) != nil
    }

    /// Where `backend` sends screenshots; nil for the local model.
    public static func destination(of backend: AppSettings.Backend) -> AppSettings.UploadDestination? {
        switch backend {
        case .clairic: return .cloudflare
        case .customEndpoint: return .customEndpoint
        case .localInkling: return nil
        }
    }

    /// The grant that covers the selected backend now (`UploadConsent.grant(for:in:)`). Nil for local (nothing to
    /// grant) and when not allowed.
    public static func activeGrant(_ settings: AppSettings) -> AppSettings.UploadGrant? {
        UploadConsent.grant(for: UploadTarget(settings: settings), in: settings.uploadGrants)
    }

    /// The user allowed sending to the selected backend's destination (always true for local).
    public static func hasUploadConsent(_ settings: AppSettings) -> Bool {
        destination(of: settings.backend) == nil || activeGrant(settings) != nil
    }

    /// The confirmation Settings shows before allowing the selected backend's destination, and the endpoint it
    /// names. Nil when nothing needs allowing (local, already allowed) or there is no endpoint to name yet.
    public static func consentRequest(for settings: AppSettings) -> ConsentRequest? {
        guard let destination = destination(of: settings.backend), !hasUploadConsent(settings) else { return nil }
        switch destination {
        case .cloudflare:
            return ConsentRequest(prompt: "Screenshots will be sent to your Cloudflare account", destination: .cloudflare,
                                  endpoint: nil)
        case .customEndpoint:
            guard let endpoint = CustomEndpointIdentity(url: settings.customEndpointURL) else { return nil }
            return ConsentRequest(prompt: "Screenshots will be sent to \(endpoint.display)", destination: .customEndpoint,
                                  endpoint: endpoint)
        }
    }

    /// `settings` with `destination` allowed from `now`, rounded UP to the next whole second: settings store dates
    /// without fractions, and rounding down would let a file taken in that fraction before the grant pass after a
    /// reload. For a custom endpoint, `expectedEndpoint` is the one the confirmation named: when the configured
    /// endpoint is no longer that one, nothing is granted. An existing grant for the same destination and endpoint
    /// keeps its (earlier) time.
    public static func granting(_ destination: AppSettings.UploadDestination, expectedEndpoint: CustomEndpointIdentity? = nil,
                                in settings: AppSettings, at now: Date = Date()) -> AppSettings {
        var settings = settings
        let endpoint: CustomEndpointIdentity?
        switch destination {
        case .cloudflare:
            endpoint = nil
        case .customEndpoint:
            guard let current = CustomEndpointIdentity(url: settings.customEndpointURL), current == expectedEndpoint else {
                return settings
            }
            endpoint = current
        }
        if let existing = settings.grant(for: destination), existing.endpoint == endpoint { return settings }
        settings.uploadGrants.removeAll { $0.destination == destination }
        settings.uploadGrants.append(AppSettings.UploadGrant(destination: destination, grantedAt: roundedUp(now),
                                                             endpoint: endpoint))
        return settings
    }

    public static func readiness(settings: AppSettings, hasClairicToken: Bool) -> BackendReadiness {
        switch settings.backend {
        case .clairic:
            if trimmed(settings.clairicAccountID).isEmpty { return .notConfigured("Cloudflare account ID is not set") }
            if !hasClairicToken { return .notConfigured("Cloudflare API token is not set") }
        case .customEndpoint:
            guard let url = settings.customEndpointURL, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", url.host != nil else {
                return .notConfigured("Custom endpoint URL is not set")
            }
            if trimmed(settings.customModelName).isEmpty { return .notConfigured("Custom endpoint model name is not set") }
        case .localInkling:
            return .ready
        }
        return hasUploadConsent(settings) ? .ready : .needsConsent
    }

    /// Whether the app may watch the screenshot folder: only with a usable backend, so nothing is queued (and later
    /// uploaded) before the user finished choosing where screenshots go.
    public static func mayWatch(settings: AppSettings, hasClairicToken: Bool) -> Bool {
        readiness(settings: settings, hasClairicToken: hasClairicToken) == .ready
    }

    /// Why an analyzer holds the queue (shown as "Needs attention: …"), nil when ready.
    public static func reason(for readiness: BackendReadiness) -> String? {
        switch readiness {
        case .ready: return nil
        case .needsConsent: return consentReason
        case .notConfigured(let reason): return reason
        }
    }

    /// The menu's second line while the folder is not watched ("Not watching yet"), nil when ready.
    public static func statusReason(for readiness: BackendReadiness) -> String? {
        switch readiness {
        case .ready: return nil
        case .needsConsent: return "Not allowed to send screenshots yet"
        case .notConfigured(let reason): return reason
        }
    }

    /// The next whole second (unchanged when already whole). Whole seconds since 1970 and since 2001 coincide.
    static func roundedUp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
    }

    static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// The Settings confirmation for one destination: what it says and exactly what "Allow" grants.
public struct ConsentRequest: Equatable, Sendable {
    public var prompt: String
    public var destination: AppSettings.UploadDestination
    /// The endpoint named, for `.customEndpoint`.
    public var endpoint: CustomEndpointIdentity?

    public init(prompt: String, destination: AppSettings.UploadDestination, endpoint: CustomEndpointIdentity?) {
        self.prompt = prompt
        self.destination = destination
        self.endpoint = endpoint
    }
}
