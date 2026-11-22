import Foundation
import XCTest
@testable import ShotkeeperCore

/// A fresh temp directory per test, removed afterwards (only ever our own files).
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("shotkeeper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ name: String, contents: String = "content", in subfolder: String? = nil) throws -> URL {
        var dir = url
        if let subfolder {
            dir = url.appendingPathComponent(subfolder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let file = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file
    }

    func names(in subfolder: String? = nil) throws -> [String] {
        let dir = subfolder.map { url.appendingPathComponent($0) } ?? url
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }
}

func read(_ url: URL) -> String? {
    FileManager.default.contents(atPath: url.path).flatMap { String(data: $0, encoding: .utf8) }
}

/// Mutable value shared with @Sendable closures.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    var get: Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
    func mutate<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
}

/// Clock whose sleeps return at once and advance time; records every sleep.
final class FakeClock: QueueClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var recorded: [Double] = []

    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    var sleeps: [Double] { lock.withLock { recorded } }
    func now() -> Date { lock.withLock { current } }
    func sleep(seconds: Double) async throws {
        lock.withLock {
            recorded.append(seconds)
            current = current.addingTimeInterval(seconds)
        }
        await Task.yield()
    }
}

/// Returns queued results in order; the last one repeats.
final class StubAnalyzer: ScreenshotAnalyzer, @unchecked Sendable {
    let backendID = "stub"
    private let results: Locked<[Result<ScreenshotAnalysis, AnalyzerError>]>
    let calls = Locked<[AnalysisContext]>([])

    init(_ results: [Result<ScreenshotAnalysis, AnalyzerError>]) { self.results = Locked(results) }
    convenience init(_ analysis: ScreenshotAnalysis) { self.init([.success(analysis)]) }

    func analyze(_ image: ImagePayload, context: AnalysisContext) async throws -> ScreenshotAnalysis {
        calls.mutate { $0.append(context) }
        let next = results.mutate { $0.count > 1 ? $0.removeFirst() : $0[0] }
        return try next.get()
    }
}

/// In-memory xattrs.
final class RecordingMetadataWriter: FileMetadataWriter, @unchecked Sendable {
    let attributes = Locked<[String: [String: Data]]>([:])

    func readExtendedAttribute(_ name: String, of url: URL) throws -> Data? {
        attributes.get[url.standardizedFileURL.path]?[name]
    }

    func writeExtendedAttribute(_ name: String, data: Data, to url: URL) throws {
        attributes.mutate { $0[url.standardizedFileURL.path, default: [:]][name] = data }
    }
}

func analysis(title: String?, confidence: Double = 0.9, tags: [String] = ["invoice", "acme"],
              description: String? = "An invoice from Acme Corp", tokens: Int? = 640) -> ScreenshotAnalysis {
    ScreenshotAnalysis(title: title, titleConfidence: confidence, sourceAppOrSite: "Mail", contentType: .receipt,
                       description: description, tags: tags, keyText: "Total 42.00 EUR", dateMentioned: "2026-01-13",
                       producedBy: "stub", billedInputTokens: tokens)
}

/// Lets queued Tasks run.
func settle(_ rounds: Int = 200) async {
    for _ in 0..<rounds { await Task.yield() }
}

extension AppSettings {
    /// Test shorthand: Cloudflare allowed since `.distantPast` (an upgraded or long-configured user).
    static let cloudflareSinceEver = UploadGrant(destination: .cloudflare, grantedAt: .distantPast)
}
