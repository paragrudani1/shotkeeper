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
/// backend and accepted its privacy notice. The app's analyzer factory and its folder watcher both ask this.
///
/// Consent is `AppSettings.hasSeenPrivacyNotice`, set only by setup step 2's "I Agree". Test Connection is not
/// gated: it sends only a generated image, never a user file.
public enum BackendGate {
    public static let consentReason = "Finish setup to accept where screenshots are sent (menu → Finish Setup…)"

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
        return settings.hasSeenPrivacyNotice ? .ready : .needsConsent
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
        case .needsConsent: return "Setup is not finished"
        case .notConfigured(let reason): return reason
        }
    }

    static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
