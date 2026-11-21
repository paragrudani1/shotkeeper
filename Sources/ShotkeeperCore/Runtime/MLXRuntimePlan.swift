import Foundation

/// A process to run: absolute executable path + argv (no shell, so no quoting issues) + extra environment.
public struct RuntimeCommand: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]

    public init(executable: String, arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

/// Pure planning for the optional local backend: where the venv lives, how to install mlx-lm, how to download a model,
/// and how to launch `mlx_lm.server`. The app runs these commands (Process) and owns the lifecycle.
///
/// Layout under `<Application Support>/Shotkeeper/runtime/`: `venv/` (Python env), `models/<owner>--<name>/` (weights).
public struct MLXRuntimePlan: Sendable, Equatable {
    /// mlx-lm with Inkling 2 Mini support: PR ml-explore/mlx-lm#2086 head, not merged or released on 2026-11-21
    /// (docs/research/model-backends.md). Bump this one constant when a release ships Inkling support.
    public static let mlxLMPipSpec =
        "mlx-lm @ git+https://github.com/ml-explore/mlx-lm.git@0c4c99192230f1943dd468d297f0b8a64ae7b7c2"
    /// Provides the `hf` CLI (`hf download`), added in huggingface_hub 0.34
    /// (https://huggingface.co/docs/huggingface_hub/guides/cli). transformers ≥ 5.7 (an mlx-lm dependency) pulls it in
    /// anyway; listed so the download step never depends on that.
    public static let huggingFaceHubPipSpec = "huggingface_hub>=0.34"
    /// mlx-lm's pyproject.toml at the pinned commit: `requires-python = ">=3.11"`. macOS's own python3 is older,
    /// so `uv` (which fetches its own Python) is preferred.
    public static let minimumPython = (major: 3, minor: 11)
    /// Python `uv venv` asks for.
    public static let uvPythonVersion = "3.12"

    public var runtimeDirectory: URL
    /// Absolute path of `uv`, when found (e.g. `/opt/homebrew/bin/uv`, `~/.local/bin/uv`).
    public var uvPath: String?
    /// Fallback interpreter (must be ≥ 3.11; check with `isSupportedPython(versionOutput:)`).
    public var python3Path: String

    /// `applicationSupport` is `~/Library/Application Support`.
    public init(applicationSupport: URL, uvPath: String?, python3Path: String = "/usr/bin/python3") {
        self.runtimeDirectory = applicationSupport.appendingPathComponent("Shotkeeper/runtime", isDirectory: true)
        self.uvPath = uvPath
        self.python3Path = python3Path
    }

    public var venvDirectory: URL { runtimeDirectory.appendingPathComponent("venv", isDirectory: true) }
    public var modelsDirectory: URL { runtimeDirectory.appendingPathComponent("models", isDirectory: true) }
    public var venvPython: String { venvDirectory.appendingPathComponent("bin/python").path }
    public var serverExecutable: String { venvDirectory.appendingPathComponent("bin/mlx_lm.server").path }
    public var hfExecutable: String { venvDirectory.appendingPathComponent("bin/hf").path }

    /// Create the venv and install mlx-lm + huggingface_hub. Run in order; stop at the first non-zero exit.
    public var installCommands: [RuntimeCommand] {
        let packages = [Self.mlxLMPipSpec, Self.huggingFaceHubPipSpec]
        if let uvPath {
            return [
                RuntimeCommand(executable: uvPath, arguments: ["venv", "--python", Self.uvPythonVersion, venvDirectory.path]),
                RuntimeCommand(executable: uvPath, arguments: ["pip", "install", "--python", venvPython] + packages),
            ]
        }
        return [
            RuntimeCommand(executable: python3Path, arguments: ["-m", "venv", venvDirectory.path]),
            RuntimeCommand(executable: venvPython, arguments: ["-m", "pip", "install", "--upgrade", "pip"]),
            RuntimeCommand(executable: venvPython, arguments: ["-m", "pip", "install"] + packages),
        ]
    }

    /// Run `python3 --version` first when there is no uv; this checks its output ("Python 3.12.4").
    public static func isSupportedPython(versionOutput: String) -> Bool {
        let parts = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Python ", with: "").split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return (parts[0], parts[1]) >= (minimumPython.major, minimumPython.minor)
    }

    /// Where `downloadCommand` puts a model; pass this to `serverCommand(model:)`.
    public func localModelDirectory(for variant: ModelVariant) -> URL {
        modelsDirectory.appendingPathComponent(variant.id.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    /// `hf download <repo> --revision <sha> --local-dir <dir>` (resumable; re-running skips finished files).
    public func downloadCommand(for variant: ModelVariant) -> RuntimeCommand {
        RuntimeCommand(executable: hfExecutable,
                       arguments: ["download", variant.id, "--revision", variant.revision,
                                   "--local-dir", localModelDirectory(for: variant).path],
                       environment: ["HF_HUB_DISABLE_TELEMETRY": "1"])
    }

    /// `mlx_lm.server --model <repo or path> --host 127.0.0.1 --port <port> [--chat-template-args <json>]`.
    /// Flags verified in `mlx_lm/server.py` at the pinned commit, `main()` argparse:
    /// https://raw.githubusercontent.com/ml-explore/mlx-lm/0c4c99192230f1943dd468d297f0b8a64ae7b7c2/mlx_lm/server.py
    /// (`--model`, `--host` default 127.0.0.1, `--port` default 8080, `--chat-template-args` JSON for
    /// `apply_chat_template`). The server also answers `GET /health` and `GET /v1/models`.
    /// `reasoningEffort` sets Inkling's chat-template `reasoning_effort` default ("none" for Shotkeeper); requests can
    /// still override it with `chat_template_kwargs`.
    public func serverCommand(model: String, port: Int, reasoningEffort: String? = "none") -> RuntimeCommand {
        var arguments = ["--model", model, "--host", "127.0.0.1", "--port", String(port)]
        if let reasoningEffort {
            arguments += ["--chat-template-args", #"{"reasoning_effort":"\#(reasoningEffort)"}"#]
        }
        var environment = ["HF_HUB_DISABLE_TELEMETRY": "1"]
        // A local directory needs no network; keep the server from reaching out. A repo id may need to download.
        if model.hasPrefix("/") { environment["HF_HUB_OFFLINE"] = "1" }
        return RuntimeCommand(executable: serverExecutable, arguments: arguments, environment: environment)
    }

    public static func healthURL(port: Int) -> URL { URL(string: "http://127.0.0.1:\(port)/health")! }
    public static func chatCompletionsURL(port: Int) -> URL { URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")! }
}
