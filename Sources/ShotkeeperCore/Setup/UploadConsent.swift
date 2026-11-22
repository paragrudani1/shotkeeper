import Foundation

/// Where one job would send a screenshot, named the way consent is given: the user's Cloudflare account, one custom
/// endpoint identity (scheme + host + port), or nowhere (the local model).
public enum UploadTarget: Hashable, Sendable {
    /// The local model: nothing leaves this Mac.
    case thisMac
    /// The user's Cloudflare account (Clairic).
    case cloudflare
    /// A custom OpenAI-compatible endpoint.
    case customEndpoint(CustomEndpointIdentity)
    /// A custom endpoint whose URL is not http(s) with a host. It has no identity, so it can never be allowed.
    case unidentifiedEndpoint

    /// The target of the backend selected in `settings`.
    public init(settings: AppSettings) {
        switch settings.backend {
        case .localInkling:
            self = .thisMac
        case .clairic:
            self = .cloudflare
        case .customEndpoint:
            self = CustomEndpointIdentity(url: settings.customEndpointURL).map { .customEndpoint($0) } ?? .unidentifiedEndpoint
        }
    }
}

/// "Process Existing Screenshots…" for one file: the user asked, while `target` was selected and allowed, to send
/// screenshots that already exist. It lifts only the time rule, and only while `target` is still the job's target
/// and still allowed (`UploadConsent.decide`).
public struct ProcessExistingAuthorization: Hashable, Sendable {
    public var target: UploadTarget

    public init(target: UploadTarget) {
        self.target = target
    }
}

public enum UploadDecision: Equatable, Sendable {
    case allow
    case skip(UploadSkipReason)
}

public enum UploadSkipReason: Equatable, Sendable {
    /// No grant covers the target (for a custom endpoint: this endpoint), or the endpoint has no identity.
    case destinationNotAllowed
    /// The file was taken before the target was allowed, and no Process Existing request for this target covers it.
    case takenBeforeGrant(grantedAt: Date)
}

/// THE consent rule (CODING_STANDARDS #2), one pure function: may this file go to this target now?
///
/// `ScreenshotProcessor` calls `decide` right before `analyze`, on the analyzer + settings pair it then uses
/// (`AnalyzerSnapshot`), so no later settings change can send a file the decision did not cover. Everything else
/// that talks about consent (readiness, the Settings prompt, the watcher gate) reads `grant(for:in:)`, the same
/// matching rule, and only decides what the UI offers.
public enum UploadConsent {
    /// The grant that covers `target`, nil when none does. A custom endpoint is covered only by a grant naming the
    /// same identity; the local model and an unidentified endpoint have none.
    public static func grant(for target: UploadTarget, in grants: [AppSettings.UploadGrant]) -> AppSettings.UploadGrant? {
        switch target {
        case .thisMac, .unidentifiedEndpoint:
            return nil
        case .cloudflare:
            return grants.first { $0.destination == .cloudflare }
        case .customEndpoint(let identity):
            return grants.first { $0.destination == .customEndpoint && $0.endpoint == identity }
        }
    }

    /// - Parameters:
    ///   - target: where the job's analyzer sends the file.
    ///   - grants: the user's grants with their times (`AppSettings.uploadGrants`, from the same snapshot).
    ///   - capturedAt: the file's effective capture time (`effectiveCaptureTime`), `.distantPast` when unknown.
    ///   - processExisting: the user's "Process Existing Screenshots…" request for this file, if any.
    /// - Returns: `.allow` for the local model; for a cloud target only when a grant covers it AND (the file was
    ///   taken at or after `grantedAt`, OR a Process Existing request was made for this very target).
    public static func decide(target: UploadTarget, grants: [AppSettings.UploadGrant], capturedAt: Date,
                              processExisting: ProcessExistingAuthorization? = nil) -> UploadDecision {
        if target == .thisMac { return .allow }
        guard let grant = grant(for: target, in: grants) else { return .skip(.destinationNotAllowed) }
        if capturedAt >= grant.grantedAt { return .allow }
        if let processExisting, processExisting.target == target { return .allow }
        return .skip(.takenBeforeGrant(grantedAt: grant.grantedAt))
    }

    /// `decide` for the backend selected in `settings`, with its grants.
    public static func decide(settings: AppSettings, capturedAt: Date,
                              processExisting: ProcessExistingAuthorization? = nil) -> UploadDecision {
        decide(target: UploadTarget(settings: settings), grants: settings.uploadGrants, capturedAt: capturedAt,
               processExisting: processExisting)
    }

    /// The earliest moment the file can claim: the earlier of its creation date and the time in its screenshot name
    /// (a copy, download or AirDrop gets a fresh creation date but keeps the name). Neither readable:
    /// `.distantPast`, so the time rule fails closed.
    public static func effectiveCaptureTime(creationDate: Date?, nameDate: Date?) -> Date {
        [creationDate, nameDate].compactMap { $0 }.min() ?? .distantPast
    }

    /// `effectiveCaptureTime` for a file on disk (its creation date, and `ScreenshotDetector.captureDate`).
    public static func effectiveCaptureTime(of url: URL, timeZone: TimeZone = .current) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return effectiveCaptureTime(creationDate: attributes?[.creationDate] as? Date,
                                    nameDate: ScreenshotDetector.captureDate(fromFilename: url.lastPathComponent,
                                                                             timeZone: timeZone))
    }
}

/// The analyzer a job uses and the settings it was built from, read together. The app keeps one of these in a
/// single locked value and replaces it whole on every rebuild, so the consent decision and the upload always see
/// the same backend.
public struct AnalyzerSnapshot: Sendable {
    public let analyzer: any ScreenshotAnalyzer
    public let settings: AppSettings

    public init(analyzer: any ScreenshotAnalyzer, settings: AppSettings) {
        self.analyzer = analyzer
        self.settings = settings
    }
}

/// The open "Process Existing Screenshots…" requests, by path, each with the target that was selected when the user
/// asked. A job takes its path's request when it starts, so one run uses it whatever the outcome (processed,
/// skipped, failed or held): a held job retried later gets the normal time rule. The app clears all requests when
/// the backend, endpoint or grants change.
public final class ProcessExistingRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String: ProcessExistingAuthorization] = [:]
    private var clearedCount = 0

    public init() {}

    /// Changes on every `removeAll`. Read it when the user clicks and pass it to `add`, so a destination change
    /// while the folder is scanned drops the request instead of attaching it after the clear.
    public var generation: Int { lock.withLock { clearedCount } }

    /// Records the requests unless `removeAll` ran since `generation` was read. Returns whether they were added.
    @discardableResult
    public func add(_ urls: [URL], for target: UploadTarget, generation: Int) -> Bool {
        lock.withLock {
            guard generation == clearedCount else { return false }
            for url in urls { requests[Self.key(url)] = ProcessExistingAuthorization(target: target) }
            return true
        }
    }

    /// Removes and returns the request for `url`.
    public func take(_ url: URL) -> ProcessExistingAuthorization? {
        lock.withLock { requests.removeValue(forKey: Self.key(url)) }
    }

    public func removeAll() {
        lock.withLock {
            requests.removeAll()
            clearedCount += 1
        }
    }

    public var count: Int { lock.withLock { requests.count } }

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }
}
