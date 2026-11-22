import Foundation

/// An image ready to send: already downscaled/compressed by an `ImagePreparer` (ImageIO on macOS).
public struct ImagePayload: Sendable, Equatable {
    public var data: Data
    /// "image/png", "image/jpeg" or "image/webp".
    public var mimeType: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(data: Data, mimeType: String, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Context that helps a backend but is not part of the image.
public struct AnalysisContext: Sendable, Equatable {
    /// Original filename, e.g. "Screenshot 2026-01-13 at 10.22.11.png".
    public var originalFilename: String
    /// When the screenshot was taken; anchors dates without a year (Clairic `reference_date`).
    public var capturedAt: Date

    public init(originalFilename: String, capturedAt: Date) {
        self.originalFilename = originalFilename
        self.capturedAt = capturedAt
    }
}

/// The one seam between the pipeline and a model backend. Implementations:
/// `CloudflareClairicAnalyzer` (primary, cloud) and `OpenAICompatibleAnalyzer` (optional, on-device).
public protocol ScreenshotAnalyzer: Sendable {
    /// Stable id for logs/index, e.g. "clairic" or "local-openai".
    var backendID: String { get }
    func analyze(_ image: ImagePayload, context: AnalysisContext) async throws -> ScreenshotAnalysis
}

/// Errors every analyzer maps its failures into, so the queue can decide retry vs. give up.
public enum AnalyzerError: Error, Equatable, Sendable {
    /// Network down, DNS, connection refused (e.g. local server not started yet). Retry with backoff.
    case unreachable(String)
    /// HTTP 429 or a provider rate limit. Retry after `retryAfter` seconds when known.
    case rateLimited(retryAfter: Double?)
    /// HTTP 5xx or a timeout. Retry with backoff.
    case serverError(status: Int, message: String)
    /// 401/403: bad or missing credentials. Do not retry; surface in the menu bar.
    case unauthorized(String)
    /// 4xx other than the above: the request itself is wrong. Do not retry.
    case badRequest(status: Int, message: String)
    /// The response could not be turned into a `ScreenshotAnalysis` (after any repair attempt).
    case invalidResponse(String)
    /// Backend not configured (no credentials / no endpoint).
    case notConfigured(String)
    /// The account or model is in a state only the user can change: out of credits, a spending limit reached, no
    /// provider allowed to serve the model. Holds the queue like `unauthorized` until Resume; never retried by
    /// itself. The text is Shotkeeper's own sentence (e.g. "OpenRouter is out of credits. Add credits, then choose
    /// Resume"), never a server message.
    case accountState(String)

    public var isRetryable: Bool {
        switch self {
        case .unreachable, .rateLimited, .serverError: return true
        case .unauthorized, .badRequest, .invalidResponse, .notConfigured, .accountState: return false
        }
    }
}
