import Foundation

/// Where one job would send a screenshot, named the way consent is given: the user's Cloudflare account, OpenRouter,
/// one custom endpoint identity (scheme + host + port), or nowhere (the local model).
public enum UploadTarget: Hashable, Sendable {
    /// The local model: nothing leaves this Mac.
    case thisMac
    /// The user's Cloudflare account (Clairic).
    case cloudflare
    /// OpenRouter (`OpenRouterBackend.host`) for this model (`OpenRouterBackend.effectiveModel`), and through it the
    /// model's provider. Consent for one model does not cover another (another model, other providers).
    case openRouter(model: String)
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
        case .openRouter:
            self = .openRouter(model: OpenRouterBackend.effectiveModel(settings.openRouterModel))
        case .customEndpoint:
            self = CustomEndpointIdentity(url: settings.customEndpointURL).map { .customEndpoint($0) } ?? .unidentifiedEndpoint
        }
    }
}

/// The user asked, while `target` was selected and allowed, to send these particular files ("Process Existing
/// Screenshots…", "Analyze Again"). It lifts only the time rule, and only while `target` is still the job's target
/// and still allowed (`UploadConsent.decide`). It carries no reason: `decide` never branches on why the user asked.
public struct UserUploadAuthorization: Hashable, Sendable {
    public let target: UploadTarget

    /// Internal on purpose: app code gets an authorization only from `UserUploadRequests.authorization(for:)`, whose
    /// generation stamp drops the request when the backend, endpoint or grants change. An authorization built at the
    /// click would skip that check (review of PR #17).
    init(target: UploadTarget) {
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
    /// The file was taken before the target was allowed, and no user request for this target covers it.
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
    /// same identity, OpenRouter only by a grant naming the same model; the local model and an unidentified endpoint
    /// have none.
    public static func grant(for target: UploadTarget, in grants: [AppSettings.UploadGrant]) -> AppSettings.UploadGrant? {
        switch target {
        case .thisMac, .unidentifiedEndpoint:
            return nil
        case .cloudflare:
            return grants.first { $0.destination == .cloudflare }
        case .openRouter(let model):
            return grants.first { $0.destination == .openRouter && $0.openRouterModel == model }
        case .customEndpoint(let identity):
            return grants.first { $0.destination == .customEndpoint && $0.endpoint == identity }
        }
    }

    /// - Parameters:
    ///   - target: where the job's analyzer sends the file.
    ///   - grants: the user's grants with their times (`AppSettings.uploadGrants`, from the same snapshot).
    ///   - capturedAt: the file's effective capture time (`effectiveCaptureTime`), `.distantPast` when unknown.
    ///   - userRequest: the user's request to send this file ("Process Existing Screenshots…", "Analyze Again"),
    ///     still valid (`UserUploadRequests.authorization(for:)`), if any.
    /// - Returns: `.allow` for the local model; for a cloud target only when a grant covers it AND (the file was
    ///   taken at or after `grantedAt`, OR the user asked to send it while this very target was selected and
    ///   allowed). A user request never lifts `.destinationNotAllowed`.
    public static func decide(target: UploadTarget, grants: [AppSettings.UploadGrant], capturedAt: Date,
                              userRequest: UserUploadAuthorization? = nil) -> UploadDecision {
        if target == .thisMac { return .allow }
        guard let grant = grant(for: target, in: grants) else { return .skip(.destinationNotAllowed) }
        if capturedAt >= grant.grantedAt { return .allow }
        if let userRequest, userRequest.target == target { return .allow }
        return .skip(.takenBeforeGrant(grantedAt: grant.grantedAt))
    }

    /// `decide` for the backend selected in `settings`, with its grants.
    public static func decide(settings: AppSettings, capturedAt: Date,
                              userRequest: UserUploadAuthorization? = nil) -> UploadDecision {
        decide(target: UploadTarget(settings: settings), grants: settings.uploadGrants, capturedAt: capturedAt,
               userRequest: userRequest)
    }

    /// The earliest moment the file can claim: the earliest of its creation date, its modification date and the time
    /// in its screenshot name. A copy, download or AirDrop gets a fresh creation date but keeps the name; an extracted
    /// archive or an `rsync -t` copy keeps the modification date. None readable: `.distantPast`, so the time rule
    /// fails closed. (An edit gives a fresh modification date, but the earliest date wins.)
    public static func effectiveCaptureTime(creationDate: Date?, modificationDate: Date? = nil, nameDate: Date?) -> Date {
        [creationDate, modificationDate, nameDate].compactMap { $0 }.min() ?? .distantPast
    }

    /// `effectiveCaptureTime` for a file on disk: its creation and modification dates, and
    /// `ScreenshotDetector.captureDate` in `timeZone`. A file that cannot be read gives `.distantPast`.
    public static func effectiveCaptureTime(of url: URL, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return effectiveCaptureTime(creationDate: attributes?[.creationDate] as? Date,
                                    modificationDate: attributes?[.modificationDate] as? Date,
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

/// One user request to send particular files ("Process Existing Screenshots…", "Analyze Again"): the target selected
/// then, stamped with the `UserUploadRequests.generation` it was made in. `ProcessingQueue` carries it with each job
/// it was enqueued for, for the whole job (every retry and hold), and drops it when the job ends.
public struct UserUploadRequest: Equatable, Sendable {
    public let authorization: UserUploadAuthorization
    public let generation: Int
}

/// Issues user upload requests and invalidates them all at once. The app calls `invalidateAll()` whenever the
/// backend, endpoint or grants change; from then on every earlier request, wherever it is (a queued job, a job being
/// retried), counts as none (`authorization(for:)`). Synchronous, so a change applies before the next attempt starts.
public final class UserUploadRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0

    public init() {}

    /// Read it when the user asks; pass it to `request(for:madeIn:)` once the files are known (for Process Existing,
    /// after the folder scan).
    public var generation: Int { lock.withLock { current } }

    /// A request for `target`, or nil when `invalidateAll()` ran since `generation` was read (the destination
    /// changed in between, e.g. during the folder scan).
    public func request(for target: UploadTarget, madeIn generation: Int) -> UserUploadRequest? {
        lock.withLock {
            generation == current ? UserUploadRequest(authorization: UserUploadAuthorization(target: target),
                                                      generation: generation) : nil
        }
    }

    /// What a job attempt may pass to the processor: the request's authorization while it is still valid.
    public func authorization(for request: UserUploadRequest?) -> UserUploadAuthorization? {
        guard let request else { return nil }
        return lock.withLock { request.generation == current ? request.authorization : nil }
    }

    public func invalidateAll() {
        lock.withLock { current += 1 }
    }
}
