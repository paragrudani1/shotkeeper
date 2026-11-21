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

/// The consent gate (CODING_STANDARDS #2): no user screenshot goes to a cloud backend unless the user chose that
/// backend and accepted sending to its destination. The app's analyzer factory, its folder watcher and the
/// processor (which skips files while consent is missing) all ask this.
///
/// Consent is per destination (`AppSettings.acceptedUploadDestinations`): `.cloudflare` from setup step 2's
/// "I Agree" (its text names Cloudflare), `.customEndpoint` from the Settings confirmation that names the host,
/// and only for that host. Test Connection is not gated: it sends only a generated image, never a user file.
public enum BackendGate {
    public static let consentReason = "Finish setup to allow where screenshots are sent (or allow it in Settings → Model)"

    /// True for backends that send screenshots off this Mac. A custom endpoint counts even when it is on
    /// 127.0.0.1: the app cannot tell where a URL really ends up.
    public static func sendsScreenshotsOffThisMac(_ backend: AppSettings.Backend) -> Bool {
        switch backend {
        case .clairic, .customEndpoint: return true
        case .localInkling: return false
        }
    }

    /// - Parameter hasClairicToken: a non-empty Cloudflare API token is in the credential store.
    /// The local backend is ready once chosen: the managed runtime reports "not installed" itself, and nothing
    /// leaves the Mac, so it needs no consent.
    /// Where `backend` sends screenshots; nil for the local model.
    public static func destination(of backend: AppSettings.Backend) -> AppSettings.UploadDestination? {
        switch backend {
        case .clairic: return .cloudflare
        case .customEndpoint: return .customEndpoint
        case .localInkling: return nil
        }
    }

    /// The user allowed sending to the selected backend's destination (always true for local). For a custom
    /// endpoint the allowed host must be the URL's host.
    public static func hasUploadConsent(_ settings: AppSettings) -> Bool {
        guard let destination = destination(of: settings.backend) else { return true }
        guard settings.acceptedUploadDestinations.contains(destination) else { return false }
        if destination == .customEndpoint {
            guard let host = AppSettings.normalizedHost(settings.customEndpointURL) else { return false }
            return settings.acceptedCustomEndpointHost == host
        }
        return true
    }

    /// Returns `settings` with consent for `destination` granted (for a custom endpoint: its current host).
    public static func granting(_ destination: AppSettings.UploadDestination, in settings: AppSettings) -> AppSettings {
        var settings = settings
        switch destination {
        case .cloudflare:
            settings.acceptedUploadDestinations.insert(.cloudflare)
        case .customEndpoint:
            guard let host = AppSettings.normalizedHost(settings.customEndpointURL) else { return settings }
            settings.acceptedUploadDestinations.insert(.customEndpoint)
            settings.acceptedCustomEndpointHost = host
        }
        return settings
    }

    /// The confirmation Settings shows before allowing the selected backend's destination: "Screenshots will be
    /// sent to llm.lan" / "… to your Cloudflare account". Nil when nothing needs allowing (local, already allowed)
    /// or there is no host to name yet.
    public static func consentPrompt(for settings: AppSettings) -> String? {
        guard let destination = destination(of: settings.backend), !hasUploadConsent(settings) else { return nil }
        switch destination {
        case .cloudflare:
            return "Screenshots will be sent to your Cloudflare account"
        case .customEndpoint:
            return AppSettings.normalizedHost(settings.customEndpointURL).map { "Screenshots will be sent to \($0)" }
        }
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

    static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
