import Darwin
import XCTest
@testable import Shotkeeper

final class RotatingLogFileTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RotatingLogFileTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCreatesDirectoryAndAppends() throws {
        let log = try RotatingLogFile(url: directory.appendingPathComponent("a.log"), maxBytes: 1_000)
        log.write("one\n")
        log.write("two\n")
        log.close()
        XCTAssertEqual(try String(contentsOf: log.url, encoding: .utf8), "one\ntwo\n")
    }

    func testRotatesAndKeepsAtMostN() throws {
        let log = try RotatingLogFile(url: directory.appendingPathComponent("b.log"), maxBytes: 10, keep: 2)
        for chunk in ["AAAAAAAA\n", "BBBBBBBB\n", "CCCCCCCC\n", "DDDDDDDD\n"] { log.write(chunk) }
        log.close()
        XCTAssertEqual(try String(contentsOf: log.url, encoding: .utf8), "DDDDDDDD\n")
        XCTAssertEqual(try String(contentsOf: log.rotatedURL(1), encoding: .utf8), "CCCCCCCC\n")
        XCTAssertEqual(try String(contentsOf: log.rotatedURL(2), encoding: .utf8), "BBBBBBBB\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.rotatedURL(3).path))
        XCTAssertEqual(log.rotatedURL(1).lastPathComponent, "b.1.log")
    }

    func testReopenAppendsToExistingFile() throws {
        let url = directory.appendingPathComponent("c.log")
        let first = try RotatingLogFile(url: url, maxBytes: 1_000)
        first.write("x")
        first.close()
        let second = try RotatingLogFile(url: url, maxBytes: 1_000)
        second.write("y")
        second.close()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "xy")
    }
}

final class ManagedProcessTests: XCTestCase {
    private var logs: URL!

    override func setUpWithError() throws {
        logs = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManagedProcessTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: logs)
    }

    func testCapturesOutputEnvironmentAndExitCode() async throws {
        let workDir = FileManager.default.temporaryDirectory
        let spec = ProcessSpec(executable: URL(fileURLWithPath: "/bin/sh"),
                               arguments: ["-c", "echo out-$SHOTKEEPER_TEST; echo err >&2; pwd; exit 3"],
                               environment: ["SHOTKEEPER_TEST": "42"], workingDirectory: workDir, logName: "sh")
        let process = try ManagedProcess(spec: spec, logDirectory: logs)
        let exited = expectation(description: "onExit")
        process.onExit = { status in
            XCTAssertEqual(status, .exited(3))
            exited.fulfill()
        }
        try process.start()
        let status = await process.waitForExit()
        await fulfillment(of: [exited], timeout: 5)
        XCTAssertEqual(status, .exited(3))
        XCTAssertEqual(process.lastExit, .exited(3))
        XCTAssertFalse(process.isRunning)

        let log = try String(contentsOf: logs.appendingPathComponent("sh.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("out-42"), log)
        XCTAssertTrue(log.contains("err"), log)
        XCTAssertTrue(log.contains(FolderWatcher.realPath(workDir)) || log.contains(workDir.path), log)
        XCTAssertTrue(log.contains("exited: exited(3)"), log)
    }

    func testTerminateStopsALongRunningChild() async throws {
        let spec = ProcessSpec(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"], logName: "sleep")
        let process = try ManagedProcess(spec: spec, logDirectory: logs)
        try process.start()
        XCTAssertTrue(process.isRunning)
        XCTAssertNotNil(process.processIdentifier)
        process.terminate(gracePeriod: 2)
        let status = await process.waitForExit()
        XCTAssertEqual(status, .signaled(SIGTERM))
    }

    func testTerminateAllRunningStopsRegisteredChildren() async throws {
        let spec = ProcessSpec(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"], logName: "all")
        let a = try ManagedProcess(spec: spec, logDirectory: logs)
        let b = try ManagedProcess(spec: spec, logDirectory: logs)
        try a.start()
        try b.start()
        ManagedProcess.terminateAllRunning(gracePeriod: 2)
        let statusA = await a.waitForExit()
        let statusB = await b.waitForExit()
        XCTAssertEqual(statusA, .signaled(SIGTERM))
        XCTAssertEqual(statusB, .signaled(SIGTERM))
    }

    func testSecondStartThrows() async throws {
        let spec = ProcessSpec(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"], logName: "twice")
        let process = try ManagedProcess(spec: spec, logDirectory: logs)
        try process.start()
        defer { process.terminate(gracePeriod: 1) }
        XCTAssertThrowsError(try process.start()) { error in
            XCTAssertEqual(error as? ManagedProcessError, .alreadyStarted)
        }
    }

    func testMissingExecutableFailsToLaunch() throws {
        let spec = ProcessSpec(executable: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"), logName: "missing")
        let process = try ManagedProcess(spec: spec, logDirectory: logs)
        XCTAssertThrowsError(try process.start()) { error in
            guard case .launchFailed = error as? ManagedProcessError else {
                return XCTFail("unexpected error \(error)")
            }
        }
        XCTAssertFalse(process.isRunning)
    }
}

final class NetworkingTests: XCTestCase {
    func testFreePortIsBindableOnLoopback() throws {
        let port = try FreePort.find()
        XCTAssertGreaterThan(port, 0)

        // The port really is free: bind it ourselves.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(result, 0, "errno \(errno)")
    }

    func testHealthProbeReturnsOnceStatusIs200() async throws {
        let counter = Counter()
        let probe = HealthProbe(url: URL(string: "http://127.0.0.1:1/health")!, timeout: .seconds(5),
                                interval: .milliseconds(10)) { _ in
            let n = counter.increment()
            if n < 3 { throw URLError(.cannotConnectToHost) }
            return n < 5 ? 503 : 200
        }
        try await probe.waitUntilHealthy()
        XCTAssertEqual(counter.value, 5)
    }

    func testHealthProbeTimesOutWithLastStatus() async throws {
        let probe = HealthProbe(url: URL(string: "http://127.0.0.1:1/health")!, timeout: .milliseconds(100),
                                interval: .milliseconds(10)) { _ in 503 }
        do {
            try await probe.waitUntilHealthy()
            XCTFail("expected timeout")
        } catch let error as HealthProbeError {
            XCTAssertEqual(error, .timedOut(lastStatus: 503, lastError: nil))
        }
    }

    func testHealthProbeAgainstClosedPortTimesOut() async throws {
        // Real URLSession against a port nothing listens on: connection refused until the timeout.
        let port = try FreePort.find()
        let probe = HealthProbe(url: URL(string: "http://127.0.0.1:\(port)/health")!, timeout: .milliseconds(500),
                                interval: .milliseconds(50))
        do {
            try await probe.waitUntilHealthy()
            XCTFail("expected timeout")
        } catch let HealthProbeError.timedOut(lastStatus, lastError) {
            XCTAssertNil(lastStatus)
            XCTAssertNotNil(lastError)
        }
    }

    func testPhysicalMemoryIsPlausible() {
        XCTAssertGreaterThan(SystemInfo.physicalMemoryBytes, 1_000_000_000)
        XCTAssertEqual(SystemInfo.physicalMemoryGB, Double(SystemInfo.physicalMemoryBytes) / 1_073_741_824, accuracy: 0.001)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() -> Int { lock.withLock { count += 1; return count } }
}
