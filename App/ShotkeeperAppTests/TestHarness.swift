import Foundation
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

// Shared helpers for the app tests (2026-11-28 prefactor): one way to build a coordinator, one way to wait for
// state that arrives through a Task, one row builder. Feature tests use these instead of copying them.

/// Temp folder per test.
class TempDirectoryTestCase: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(type(of: self))-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension AppCoordinator {
    /// A coordinator for tests: index, undo log and settings in `<directory>/support`, the local runtime in
    /// `directory`, logs in `<directory>/logs`, credentials in memory. It never watches a folder or registers
    /// anything with the system (`startServices()` is not called).
    static func forTesting(in directory: URL, credentials: any CredentialStore = InMemoryCredentialStore(),
                           memoryGB: UInt64 = 16) -> AppCoordinator {
        AppCoordinator(supportDirectory: directory.appendingPathComponent("support"), credentials: credentials,
                       physicalMemoryBytes: memoryGB * 1_073_741_824,
                       applicationSupport: directory, logDirectory: directory.appendingPathComponent("logs"))
    }
}

/// Waits until `condition` holds, polling every 10 ms for up to 5 s (state that reaches the coordinator through an
/// AsyncStream task). Returns whether it held; callers assert afterwards.
@MainActor
@discardableResult
func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let tries = Int(timeout / .milliseconds(10))
    var tried = 0
    while !condition(), tried < tries {
        tried += 1
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// Builds `IndexedScreenshot` rows for app tests and snapshots. Defaults are a processed (`done`) screenshot named
/// after `title` in `folder`; override only what a test is about.
enum ScreenshotRow {
    static func make(_ title: String, folder: String = "/tmp", originalFilename: String? = nil,
                     contentHash: String? = nil, capturedAt: Date? = nil, processedAt: Date? = nil,
                     titleConfidence: Double? = nil, source: String? = nil, type: ContentType? = nil,
                     description: String? = nil, tags: [String] = [], status: ProcessingStatus = .done,
                     id: Int64 = 0) -> IndexedScreenshot {
        IndexedScreenshot(id: id, path: "\(folder)/\(title).png", originalFilename: originalFilename ?? title,
                          contentHash: contentHash ?? title, capturedAt: capturedAt, processedAt: processedAt,
                          title: title, titleConfidence: titleConfidence, sourceAppOrSite: source, contentType: type,
                          description: description, tags: tags, status: status)
    }
}
