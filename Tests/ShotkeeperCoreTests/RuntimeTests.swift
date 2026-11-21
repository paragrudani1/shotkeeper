import XCTest
@testable import ShotkeeperCore

final class BackendRecommenderTests: XCTestCase {
    private func gb(_ n: UInt64) -> UInt64 { n * 1_073_741_824 }

    func testMarketingGB() {
        XCTAssertEqual(BackendRecommender.marketingGB(17_179_869_184), 16)
        XCTAssertEqual(BackendRecommender.marketingGB(gb(24)), 24)
    }

    func testBelow16GBOnlyCloudOrCustom() {
        let r = BackendRecommender.recommend(physicalMemoryBytes: gb(8))
        XCTAssertEqual(r.recommended.backend, .clairic)
        XCTAssertEqual(r.alternatives.map(\.backend), [.customEndpoint])
        XCTAssertEqual(r.notes.count, 1)
    }

    func test16And18GBRecommendClairicWithLocal2BitAlternative() {
        for ram: UInt64 in [16, 18] {
            let r = BackendRecommender.recommend(physicalMemoryBytes: gb(ram))
            XCTAssertEqual(r.recommended.backend, .clairic)
            XCTAssertEqual(r.alternatives.map(\.backend), [.localInkling, .customEndpoint])
            let local = r.alternatives[0]
            XCTAssertEqual(local.model, ModelCatalog.inkling2bit)
            XCTAssertEqual(local.title, "Use local anyway (2-bit, lower quality)")
            XCTAssertTrue(local.warning?.contains("Lower quality") == true)
            XCTAssertTrue(r.notes.isEmpty)
        }
    }

    func test24GBRecommendsLocal3Bit() {
        let r = BackendRecommender.recommend(physicalMemoryBytes: gb(24))
        XCTAssertEqual(r.recommended.backend, .localInkling)
        XCTAssertEqual(r.recommended.model, ModelCatalog.inkling3bit)
        XCTAssertEqual(r.alternatives.map(\.backend), [.clairic, .localInkling, .customEndpoint])
        XCTAssertEqual(r.alternatives[1].model, ModelCatalog.inkling2bit)
    }

    func test24GBWithout3BitBuildFallsBackToClairic() {
        let r = BackendRecommender.recommend(physicalMemoryBytes: gb(24), catalog: [ModelCatalog.inkling4bit, ModelCatalog.inkling2bit])
        XCTAssertEqual(r.recommended.backend, .clairic)
        XCTAssertEqual(r.alternatives.first?.model, ModelCatalog.inkling2bit)
    }

    func test32GBAndUpRecommendsLocal4Bit() {
        for ram: UInt64 in [32, 36, 64, 128] {
            let r = BackendRecommender.recommend(physicalMemoryBytes: gb(ram))
            XCTAssertEqual(r.recommended.model, ModelCatalog.inkling4bit, "\(ram)")
            XCTAssertNil(r.recommended.warning)
            XCTAssertEqual(r.alternatives.first?.backend, .clairic)
            XCTAssertEqual(r.alternatives.last?.backend, .customEndpoint)
        }
    }

    func testCatalog() {
        XCTAssertEqual(ModelCatalog.all.map(\.bits), [4, 3, 2])
        XCTAssertEqual(ModelCatalog.variant(id: "mlx-community/Inkling-2-Mini-4bit"), ModelCatalog.inkling4bit)
        XCTAssertNil(ModelCatalog.variant(id: "nope"))
        for variant in ModelCatalog.all { XCTAssertEqual(variant.revision.count, 40, variant.id) }
    }
}

final class MLXRuntimePlanTests: XCTestCase {
    let support = URL(fileURLWithPath: "/Users/me/Library/Application Support", isDirectory: true)
    let runtime = "/Users/me/Library/Application Support/Shotkeeper/runtime"

    func testUVInstall() {
        let plan = MLXRuntimePlan(applicationSupport: support, uvPath: "/opt/homebrew/bin/uv")
        XCTAssertEqual(plan.installCommands, [
            RuntimeCommand(executable: "/opt/homebrew/bin/uv", arguments: ["venv", "--python", "3.12", "\(runtime)/venv"]),
            RuntimeCommand(executable: "/opt/homebrew/bin/uv", arguments: [
                "pip", "install", "--python", "\(runtime)/venv/bin/python",
                "mlx-lm @ git+https://github.com/ml-explore/mlx-lm.git@0c4c99192230f1943dd468d297f0b8a64ae7b7c2",
                "huggingface_hub>=0.34",
            ]),
        ])
    }

    func testPythonFallbackInstall() {
        let plan = MLXRuntimePlan(applicationSupport: support, uvPath: nil, python3Path: "/opt/homebrew/bin/python3")
        XCTAssertEqual(plan.installCommands.map(\.executable),
                       ["/opt/homebrew/bin/python3", "\(runtime)/venv/bin/python", "\(runtime)/venv/bin/python"])
        XCTAssertEqual(plan.installCommands[0].arguments, ["-m", "venv", "\(runtime)/venv"])
        XCTAssertEqual(plan.installCommands[2].arguments,
                       ["-m", "pip", "install", MLXRuntimePlan.mlxLMPipSpec, MLXRuntimePlan.huggingFaceHubPipSpec])
    }

    func testPythonVersionCheck() {
        XCTAssertTrue(MLXRuntimePlan.isSupportedPython(versionOutput: "Python 3.12.4\n"))
        XCTAssertTrue(MLXRuntimePlan.isSupportedPython(versionOutput: "Python 3.11.0"))
        XCTAssertTrue(MLXRuntimePlan.isSupportedPython(versionOutput: "Python 4.0"))
        XCTAssertFalse(MLXRuntimePlan.isSupportedPython(versionOutput: "Python 3.9.6"))
        XCTAssertFalse(MLXRuntimePlan.isSupportedPython(versionOutput: "garbage"))
    }

    func testDownloadCommand() {
        let plan = MLXRuntimePlan(applicationSupport: support, uvPath: nil)
        let command = plan.downloadCommand(for: ModelCatalog.inkling4bit)
        XCTAssertEqual(command.executable, "\(runtime)/venv/bin/hf")
        XCTAssertEqual(command.arguments, ["download", "mlx-community/Inkling-2-Mini-4bit",
                                           "--revision", "9856dc53edead71405f8348930937c3638ff21a2",
                                           "--local-dir", "\(runtime)/models/mlx-community--Inkling-2-Mini-4bit"])
        XCTAssertEqual(command.environment["HF_HUB_DISABLE_TELEMETRY"], "1")
    }

    func testServerCommand() {
        let plan = MLXRuntimePlan(applicationSupport: support, uvPath: nil)
        let model = plan.localModelDirectory(for: ModelCatalog.inkling3bit).path
        let command = plan.serverCommand(model: model, port: 51234)
        XCTAssertEqual(command.executable, "\(runtime)/venv/bin/mlx_lm.server")
        XCTAssertEqual(command.arguments, ["--model", "\(runtime)/models/VisualInference--Inkling-2-Mini-MLX-3bit",
                                           "--host", "127.0.0.1", "--port", "51234",
                                           "--chat-template-args", #"{"reasoning_effort":"none"}"#])
        XCTAssertEqual(command.environment["HF_HUB_OFFLINE"], "1")
        let byRepo = plan.serverCommand(model: "mlx-community/Inkling-2-Mini-4bit", port: 8080, reasoningEffort: nil)
        XCTAssertEqual(byRepo.arguments, ["--model", "mlx-community/Inkling-2-Mini-4bit", "--host", "127.0.0.1", "--port", "8080"])
        XCTAssertNil(byRepo.environment["HF_HUB_OFFLINE"])
        XCTAssertEqual(MLXRuntimePlan.healthURL(port: 51234).absoluteString, "http://127.0.0.1:51234/health")
    }
}

final class RuntimePolicyTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testIdlePolicy() {
        let policy = IdlePolicy(idleTimeoutMinutes: 10)
        XCTAssertFalse(policy.shouldStop(lastActivity: t0, now: t0.addingTimeInterval(599), inFlight: 0))
        XCTAssertTrue(policy.shouldStop(lastActivity: t0, now: t0.addingTimeInterval(600), inFlight: 0))
        XCTAssertFalse(policy.shouldStop(lastActivity: t0, now: t0.addingTimeInterval(6000), inFlight: 1))
        XCTAssertEqual(policy.nextCheck(lastActivity: t0), t0.addingTimeInterval(600))
        let never = IdlePolicy(idleTimeoutMinutes: 0)
        XCTAssertFalse(never.shouldStop(lastActivity: t0, now: t0.addingTimeInterval(1e9), inFlight: 0))
        XCTAssertNil(never.nextCheck(lastActivity: t0))
    }

    func testRestartPolicyBacksOffThenGivesUp() {
        var policy = RestartPolicy(maxCrashes: 3, window: 600)
        XCTAssertEqual(policy.recordCrash(at: t0), .restart(after: 2))
        XCTAssertEqual(policy.recordCrash(at: t0.addingTimeInterval(10)), .restart(after: 4))
        XCTAssertEqual(policy.recordCrash(at: t0.addingTimeInterval(20)), .giveUp)
        policy.reset()
        XCTAssertEqual(policy.recordCrash(at: t0.addingTimeInterval(30)), .restart(after: 2))
    }

    func testRestartPolicyForgetsOldCrashes() {
        var policy = RestartPolicy(maxCrashes: 3, window: 600)
        _ = policy.recordCrash(at: t0)
        _ = policy.recordCrash(at: t0.addingTimeInterval(100))
        XCTAssertEqual(policy.recordCrash(at: t0.addingTimeInterval(650)), .restart(after: 4), "first crash left the window")
        XCTAssertEqual(policy.crashes.count, 2)
    }
}
