import Foundation
import ShotkeeperCore
import XCTest
@testable import Shotkeeper

/// Drives the real `LocalModelRuntime` with a fake `mlx_lm.server` (a shell script) in a temp Application Support.
final class LocalModelRuntimeTests: TempDirectoryTestCase {
    private var launches: URL { directory.appendingPathComponent("launches.txt") }

    /// Installs a fake server that records each launch and exits 1 at once, plus the model's "downloaded" marker.
    private func installCrashingServer(for variant: ModelVariant) throws {
        let plan = MLXRuntimePlan(applicationSupport: directory, uvPath: nil)
        let server = URL(fileURLWithPath: plan.serverExecutable)
        try FileManager.default.createDirectory(at: server.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\necho launched >> '\(launches.path)'\nexit 1\n".write(to: server, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
        let model = plan.localModelDirectory(for: variant)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data().write(to: model.appendingPathComponent(LocalModelRuntime.downloadCompleteMarker))
    }

    private var launchCount: Int {
        ((try? String(contentsOf: launches, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    /// A crash schedules a delayed restart (2 s). Switching backends or quitting calls `stop()`; the restart must not
    /// relaunch a ~10 GB server afterwards.
    func testStopCancelsAPendingCrashRestart() async throws {
        let variant = ModelCatalog.inkling2bit
        try installCrashingServer(for: variant)
        let runtime = LocalModelRuntime(applicationSupport: directory, logDirectory: directory.appendingPathComponent("logs"),
                                        idleTimeoutMinutes: 0) { _ in }
        let installed = await runtime.isInstalled(variant)
        XCTAssertTrue(installed)

        let request = Task { try await runtime.beginRequest(for: variant) }
        var pending = false
        for _ in 0..<300 where !pending {
            try await Task.sleep(for: .milliseconds(10))
            pending = await runtime.hasPendingRestart
        }
        XCTAssertTrue(pending, "the crash should have scheduled a restart")
        XCTAssertEqual(launchCount, 1)

        await runtime.stop()
        _ = try? await request.value
        try await Task.sleep(for: .seconds(3.5))
        XCTAssertEqual(launchCount, 1, "stop() must cancel the scheduled restart")
        let stillPending = await runtime.hasPendingRestart
        XCTAssertFalse(stillPending)
        let phase = await runtime.phase
        XCTAssertNotEqual(phase, .starting)
    }
}
