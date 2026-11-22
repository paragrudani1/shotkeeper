import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The network seam for analyzers. Production uses `URLSessionTransport`; tests inject a scripted transport.
/// Implementations return every HTTP response (any status) and throw only for transport failures (`URLError` etc.).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnalyzerError.invalidResponse("Not an HTTP response")
        }
        return (data, http)
    }
}

/// Maps transport outcomes onto `AnalyzerError` so the queue can decide retry vs. give up.
public enum HTTPErrorMapping {
    /// Sends `request` and returns the body for 2xx; maps everything else to `AnalyzerError`.
    /// `describeBody` extracts a provider-specific error message from a non-2xx body. `refine` lets a backend map a
    /// status its docs give a special meaning (e.g. OpenRouter's transient 402); nil falls back to `map(status:…)`.
    public static func send(_ request: URLRequest, via transport: any HTTPTransport,
                            describeBody: (Data) -> String = genericMessage(from:),
                            refine: (Int, HTTPURLResponse, Data) -> AnalyzerError? = { _, _, _ in nil })
        async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as AnalyzerError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(transportError: error)
        }
        if !(200..<300).contains(response.statusCode), let error = refine(response.statusCode, response, data) {
            throw error
        }
        if let error = map(status: response.statusCode, headers: response, body: data, describeBody: describeBody) {
            throw error
        }
        return (data, response)
    }

    /// nil for 2xx. 429 → rateLimited (Retry-After seconds or HTTP-date), 401/403 → unauthorized,
    /// 5xx (and 408) → serverError, other non-2xx → badRequest.
    public static func map(status: Int, headers: HTTPURLResponse?, body: Data, now: Date = Date(),
                           describeBody: (Data) -> String = genericMessage(from:)) -> AnalyzerError? {
        switch status {
        case 200..<300:
            return nil
        case 429:
            return .rateLimited(retryAfter: retryAfter(headerValue(headers, "Retry-After"), now: now))
        case 401, 403:
            return .unauthorized("HTTP \(status): \(describeBody(body))")
        case 408, 500..<600:
            return .serverError(status: status, message: describeBody(body))
        default:
            return .badRequest(status: status, message: describeBody(body))
        }
    }

    /// Timeouts, refused connections, DNS failures, offline: all `unreachable` (retryable).
    public static func map(transportError error: any Error) -> AnalyzerError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .unreachable("Timed out")
            case .cannotConnectToHost:
                return .unreachable("Connection refused")
            case .cannotFindHost, .dnsLookupFailed:
                return .unreachable("Host not found")
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .unreachable("Offline")
            case .cancelled:
                return .unreachable("Cancelled")
            default:
                return .unreachable("URLError \(urlError.code.rawValue)")
            }
        }
        return .unreachable(String(describing: type(of: error)))
    }

    /// `Retry-After` is either delta-seconds or an HTTP-date (RFC 9110 §10.2.3).
    public static func retryAfter(_ value: String?, now: Date = Date()) -> Double? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = Double(raw), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    static func headerValue(_ response: HTTPURLResponse?, _ name: String) -> String? {
        guard let response else { return nil }
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, k.caseInsensitiveCompare(name) == .orderedSame { return value as? String }
        }
        return nil
    }

    /// First 300 characters of a UTF-8 body, whitespace-collapsed. Bodies never contain our credentials.
    public static func genericMessage(from body: Data) -> String {
        let text = String(decoding: body.prefix(2048), as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? "(empty body)" : String(text.prefix(300))
    }
}
