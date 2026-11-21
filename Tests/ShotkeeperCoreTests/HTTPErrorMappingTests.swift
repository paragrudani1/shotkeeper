import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShotkeeperCore

final class HTTPErrorMappingTests: XCTestCase {
    private func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    private func map(_ status: Int, _ headers: [String: String] = [:], body: String = "oops") -> AnalyzerError? {
        HTTPErrorMapping.map(status: status, headers: response(status, headers), body: Data(body.utf8),
                             now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testSuccessIsNil() {
        XCTAssertNil(map(200))
        XCTAssertNil(map(204))
    }

    func testRateLimitWithSecondsDateAndMissingHeader() {
        XCTAssertEqual(map(429, ["Retry-After": "12"]), .rateLimited(retryAfter: 12))
        XCTAssertEqual(map(429, ["retry-after": "1.5"]), .rateLimited(retryAfter: 1.5))
        // 1_700_000_000 = Tue, 14 Nov 2023 22:13:20 GMT; +30 s.
        XCTAssertEqual(map(429, ["Retry-After": "Tue, 14 Nov 2023 22:13:50 GMT"]), .rateLimited(retryAfter: 30))
        XCTAssertEqual(map(429, ["Retry-After": "Tue, 14 Nov 2023 22:00:00 GMT"]), .rateLimited(retryAfter: 0))
        XCTAssertEqual(map(429), .rateLimited(retryAfter: nil))
        XCTAssertEqual(map(429, ["Retry-After": "soon"]), .rateLimited(retryAfter: nil))
    }

    func testAuthServerAndClientErrors() {
        XCTAssertEqual(map(401), .unauthorized("HTTP 401: oops"))
        XCTAssertEqual(map(403), .unauthorized("HTTP 403: oops"))
        XCTAssertEqual(map(500), .serverError(status: 500, message: "oops"))
        XCTAssertEqual(map(503), .serverError(status: 503, message: "oops"))
        XCTAssertEqual(map(408), .serverError(status: 408, message: "oops"))
        XCTAssertEqual(map(400), .badRequest(status: 400, message: "oops"))
        XCTAssertEqual(map(413), .badRequest(status: 413, message: "oops"))
        XCTAssertEqual(map(404, body: ""), .badRequest(status: 404, message: "(empty body)"))
    }

    func testRetryability() {
        XCTAssertTrue(map(429)!.isRetryable)
        XCTAssertTrue(map(502)!.isRetryable)
        XCTAssertFalse(map(401)!.isRetryable)
        XCTAssertFalse(map(422)!.isRetryable)
    }

    func testTransportErrorsAreUnreachable() {
        XCTAssertEqual(HTTPErrorMapping.map(transportError: URLError(.timedOut)), .unreachable("Timed out"))
        XCTAssertEqual(HTTPErrorMapping.map(transportError: URLError(.cannotConnectToHost)), .unreachable("Connection refused"))
        XCTAssertEqual(HTTPErrorMapping.map(transportError: URLError(.cannotFindHost)), .unreachable("Host not found"))
        XCTAssertEqual(HTTPErrorMapping.map(transportError: URLError(.notConnectedToInternet)), .unreachable("Offline"))
        struct Other: Error {}
        XCTAssertEqual(HTTPErrorMapping.map(transportError: Other()), .unreachable("Other"))
    }

    func testSendMapsTransportFailureAndStatus() async {
        let refused = ScriptedTransport([.failure(URLError(.cannotConnectToHost))])
        let req = URLRequest(url: URL(string: "http://127.0.0.1:9")!)
        await assertAnalyzerError(.unreachable("Connection refused")) {
            _ = try await HTTPErrorMapping.send(req, via: refused)
        }
        let limited = ScriptedTransport([.status(429, "", headers: ["Retry-After": "7"])])
        await assertAnalyzerError(.rateLimited(retryAfter: 7)) {
            _ = try await HTTPErrorMapping.send(req, via: limited)
        }
    }

    func testGenericMessageTruncatesAndCollapses() {
        let long = String(repeating: "x ", count: 1000)
        XCTAssertEqual(HTTPErrorMapping.genericMessage(from: Data(long.utf8)).count, 300)
        XCTAssertEqual(HTTPErrorMapping.genericMessage(from: Data("a\n\n b".utf8)), "a b")
    }
}
