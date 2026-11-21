import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShotkeeperCore

/// Scripted `HTTPTransport`: returns queued responses in order and records every request. No network.
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    enum Step {
        case response(status: Int, body: Data, headers: [String: String])
        case failure(any Error)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) { self.steps = steps }

    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
    func request(_ i: Int) -> URLRequest { lock.lock(); defer { lock.unlock() }; return requests[i] }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let step: Step = {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
            return steps.isEmpty ? .failure(URLError(.resourceUnavailable)) : steps.removeFirst()
        }()
        switch step {
        case .failure(let error):
            throw error
        case .response(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (body, response)
        }
    }
}

extension ScriptedTransport.Step {
    static func ok(_ body: Data) -> Self { .response(status: 200, body: body, headers: ["Content-Type": "application/json"]) }
    static func ok(_ body: String) -> Self { .ok(Data(body.utf8)) }
    static func status(_ status: Int, _ body: String = "", headers: [String: String] = [:]) -> Self {
        .response(status: status, body: Data(body.utf8), headers: headers)
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("missing fixture \(name)") // should never happen; fails loudly in CI output
        }
        return try Data(contentsOf: url)
    }

    /// Repository root, for tests that read saved research files (docs/research/...).
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

/// A tiny but valid-looking PNG header (the analyzers never decode the image).
func samplePNG(width: Int = 1280, height: Int = 800, padding: Int = 32) -> ImagePayload {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]
    bytes += Array("IHDR".utf8)
    for v in [width, height] { bytes += [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    bytes += [8, 6, 0, 0, 0] + Array(repeating: 0, count: padding)
    return ImagePayload(data: Data(bytes), mimeType: "image/png", pixelWidth: width, pixelHeight: height)
}

let sampleContext = AnalysisContext(
    originalFilename: "Screenshot 2026-03-15 at 10.22.11.png",
    capturedAt: ISO8601DateFormatter().date(from: "2026-03-15T10:22:11Z")!
)

func jsonBody(_ request: URLRequest) throws -> AnalysisJSON {
    try AnalysisJSON.parse(XCTUnwrap(request.httpBody))
}

func assertAnalyzerError(_ expected: AnalyzerError, file: StaticString = #filePath, line: UInt = #line,
                         _ body: () async throws -> Void) async {
    do {
        try await body()
        XCTFail("expected \(expected), got success", file: file, line: line)
    } catch let error as AnalyzerError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("expected \(expected), got \(error)", file: file, line: line)
    }
}

/// Matches an AnalyzerError by case only (messages vary).
func assertAnalyzerErrorCase(file: StaticString = #filePath, line: UInt = #line,
                             _ body: () async throws -> Void, matches: (AnalyzerError) -> Bool) async {
    do {
        try await body()
        XCTFail("expected an AnalyzerError, got success", file: file, line: line)
    } catch let error as AnalyzerError {
        XCTAssertTrue(matches(error), "unexpected \(error)", file: file, line: line)
    } catch {
        XCTFail("expected AnalyzerError, got \(error)", file: file, line: line)
    }
}
