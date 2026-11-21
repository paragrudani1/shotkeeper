import XCTest
@testable import Shotkeeper

final class EventDebouncerTests: XCTestCase {
    func testPathIsDueOnlyAfterQuietInterval() {
        var debouncer = EventDebouncer(interval: 0.5)
        let t0 = Date(timeIntervalSince1970: 1_000)
        debouncer.record(path: "/a/x.png", kind: .created, at: t0)
        debouncer.record(path: "/a/x.png", kind: .created, at: t0.addingTimeInterval(0.4))
        XCTAssertTrue(debouncer.takeDue(at: t0.addingTimeInterval(0.6)).isEmpty, "burst extended the quiet window")
        let due = debouncer.takeDue(at: t0.addingTimeInterval(0.9))
        XCTAssertEqual(due.map(\.path), ["/a/x.png"])
        XCTAssertTrue(debouncer.isEmpty)
    }

    func testRenameWinsWithinABurst() {
        var debouncer = EventDebouncer(interval: 0.1)
        let t0 = Date(timeIntervalSince1970: 1_000)
        debouncer.record(path: "/a/y.png", kind: .renamed, at: t0)
        debouncer.record(path: "/a/y.png", kind: .created, at: t0)
        XCTAssertEqual(debouncer.takeDue(at: t0.addingTimeInterval(1)).map(\.kind), [.renamed])
    }

    func testIndependentPathsAreSortedAndIndependent() {
        var debouncer = EventDebouncer(interval: 1)
        let t0 = Date(timeIntervalSince1970: 1_000)
        debouncer.record(path: "/a/b.png", kind: .created, at: t0)
        debouncer.record(path: "/a/a.png", kind: .created, at: t0)
        debouncer.record(path: "/a/c.png", kind: .created, at: t0.addingTimeInterval(5))
        XCTAssertEqual(debouncer.takeDue(at: t0.addingTimeInterval(2)).map(\.path), ["/a/a.png", "/a/b.png"])
        XCTAssertFalse(debouncer.isEmpty)
    }
}

final class FolderWatcherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testEmitsRenamedScreenshotAndIgnoresHiddenAndNested() async throws {
        let watcher = FolderWatcher(folder: root, debounce: 0.3, latency: 0.05)
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300)) // let the stream attach

        // Mimic screencapture: hidden temp file renamed to its final name, plus noise that must be ignored.
        let nested = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("n".utf8).write(to: nested.appendingPathComponent("nested.png"))
        let temp = root.appendingPathComponent(".Screenshot temp.png")
        try Data("png".utf8).write(to: temp)
        let final = root.appendingPathComponent("Screenshot 2026-11-21 at 10.00.00.png")
        try FileManager.default.moveItem(at: temp, to: final)

        let event = try await firstEvent(from: watcher, timeout: 10)
        XCTAssertEqual(event.url.lastPathComponent, final.lastPathComponent)
        XCTAssertEqual(event.kind, .renamed)
    }

    func testToleratesMissingFolderUntilItAppears() async throws {
        let missing = root.appendingPathComponent("later", isDirectory: true)
        let watcher = FolderWatcher(folder: missing, debounce: 0.2, latency: 0.05, pollInterval: 0.2)
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(300))
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(800)) // poll picks it up and attaches the stream
        try Data("png".utf8).write(to: missing.appendingPathComponent("new.png"))

        let event = try await firstEvent(from: watcher, timeout: 10)
        XCTAssertEqual(event.url.lastPathComponent, "new.png")
    }

    private struct Timeout: Error {}

    private func firstEvent(from watcher: FolderWatcher, timeout: TimeInterval) async throws -> FolderEvent {
        let events = watcher.events
        return try await withThrowingTaskGroup(of: FolderEvent?.self) { group in
            group.addTask {
                for await event in events { return event }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw Timeout()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let event = first else { throw Timeout() }
            return event
        }
    }
}
