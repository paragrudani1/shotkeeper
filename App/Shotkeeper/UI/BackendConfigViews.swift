import ShotkeeperCore
import SwiftUI

/// Wording shared by the setup window and Settings. Pure, so it is unit-tested.
enum BackendCopy {
    static let clairicPrivacy = "Screenshots are sent to your own Cloudflare account (Workers AI) for analysis, using "
        + "your API token. Shotkeeper has no server of its own and sends them nowhere else."
    static let localPrivacy = "100% on-device, nothing leaves your Mac."
    static let customPrivacy = "Screenshots are sent to the endpoint you enter. If it is not on this Mac, they leave this Mac."
    static let tokenHelpURL = URL(string: "https://developers.cloudflare.com/workers-ai/get-started/rest-api/")!
    static let tokenHelpText = "Create a token with Workers AI Read + Edit permissions (Cloudflare docs)"

    static func privacy(for backend: AppSettings.Backend) -> String {
        switch backend {
        case .clairic: return clairicPrivacy
        case .localInkling: return localPrivacy
        case .customEndpoint: return customPrivacy
        }
    }

    static func name(for backend: AppSettings.Backend) -> String {
        switch backend {
        case .clairic: return "Cloudflare Clairic"
        case .localInkling: return "Inkling 2 Mini, on this Mac"
        case .customEndpoint: return "Custom endpoint"
        }
    }

    /// Option title for the setup list. The reduced-quality local fallback names its costs explicitly.
    static func title(for option: BackendOption) -> String {
        if option.backend == .localInkling, let model = option.model, model.quality == .reduced {
            return "Use local anyway (\(model.bits)-bit, lower quality, high memory use)"
        }
        return option.title
    }

    static func describe(_ phase: RuntimePhase) -> String {
        switch phase {
        case .notInstalled: return "Not installed"
        case .installing(let step): return step
        case .downloading(let fraction): return "Downloading… \(Int((fraction * 100).rounded()))%"
        case .ready: return "Installed (starts when needed)"
        case .starting: return "Starting the model server…"
        case .running(let port): return "Running on 127.0.0.1:\(port)"
        case .failed(let message): return message
        }
    }
}

/// Result line under a "Test connection" button.
struct TestResultView: View {
    let result: Result<String, AnalyzerFailure>?
    let isRunning: Bool

    var body: some View {
        if isRunning {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Analyzing a generated test image…") }
                .foregroundStyle(.secondary)
        } else if let result {
            switch result {
            case .success(let text):
                Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green).textSelection(.enabled)
            case .failure(let failure):
                Label(failure.message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }
}

/// Account ID + token (Keychain) + test. Edits a draft; the caller decides when to save.
struct ClairicConfigView: View {
    let coordinator: AppCoordinator
    @Binding var draft: AppSettings
    @Binding var tokenDraft: String
    @State private var testResult: Result<String, AnalyzerFailure>?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(BackendCopy.clairicPrivacy, systemImage: "icloud.and.arrow.up")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Cloudflare account ID", text: Binding(
                get: { draft.clairicAccountID ?? "" },
                set: { draft.clairicAccountID = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            SecureField(coordinator.hasSecret(.cloudflareAPIToken) ? "API token (saved in Keychain; type to replace)"
                                                                     : "API token", text: $tokenDraft)
                .textFieldStyle(.roundedBorder)
            Link(BackendCopy.tokenHelpText, destination: BackendCopy.tokenHelpURL).font(.caption)
            HStack {
                Button("Test connection") { runTest() }.disabled(testing)
                if coordinator.hasSecret(.cloudflareAPIToken) {
                    Button("Remove saved token", role: .destructive) {
                        coordinator.setSecret("", for: .cloudflareAPIToken)
                    }
                }
            }
            TestResultView(result: testResult, isRunning: testing)
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        var candidate = draft
        candidate.backend = .clairic
        let token = tokenDraft
        Task {
            testResult = await coordinator.testConnection(settings: candidate, secrets: [.cloudflareAPIToken: token])
            testing = false
        }
    }
}

/// Model variant, warnings, install/download with progress, server state.
struct LocalModelConfigView: View {
    let coordinator: AppCoordinator
    @Binding var draft: AppSettings
    @State private var installTask: Task<Void, Never>?
    @State private var testResult: Result<String, AnalyzerFailure>?
    @State private var testing = false

    private var variant: ModelVariant {
        AnalyzerFactory.localVariant(for: draft, physicalMemoryBytes: coordinator.physicalMemoryBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(BackendCopy.localPrivacy, systemImage: "lock.laptopcomputer").font(.callout)
            Picker("Model", selection: Binding(
                get: { variant.id },
                set: { draft.localModelVariantID = $0 })) {
                ForEach(ModelCatalog.all) { model in
                    Text("\(model.displayName) — \(Int(model.approxDownloadGB.rounded())) GB, for \(model.minRAMGB) GB+ Macs")
                        .tag(model.id)
                }
            }
            if Int((Double(coordinator.physicalMemoryBytes) / 1_073_741_824).rounded()) < variant.minRAMGB {
                Label("This Mac has less memory than this build is meant for.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let warning = variant.warning {
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !variant.verifiedWithMLXLM {
                Label("Experimental build: not yet tested with the built-in model server.", systemImage: "flask")
                    .foregroundStyle(.secondary)
            }
            Text("Installs a private Python environment with mlx-lm and downloads about "
                 + "\(Int(variant.approxDownloadGB.rounded())) GB to ~/Library/Application Support/Shotkeeper/runtime.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(BackendCopy.describe(coordinator.runtimePhase)).font(.callout)
                if case .downloading(let fraction) = coordinator.runtimePhase {
                    ProgressView(value: fraction).frame(width: 160)
                } else if coordinator.runtimePhase.isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            HStack {
                if installTask != nil {
                    Button("Cancel") {
                        Task { await coordinator.localRuntime.cancelInstall() }
                    }
                } else {
                    Button("Install and download") {
                        let selected = variant
                        installTask = Task {
                            await coordinator.installLocalModel(selected)
                            installTask = nil
                        }
                    }
                }
                if case .running = coordinator.runtimePhase {
                    Button("Stop server") { Task { await coordinator.localRuntime.stop() } }
                }
                if case .failed = coordinator.runtimePhase {
                    Button("Retry") { Task { await coordinator.localRuntime.retryAfterFailure() } }
                }
                Button("Test") { runTest() }.disabled(testing || installTask != nil)
            }
            TestResultView(result: testResult, isRunning: testing)
        }
        .task(id: variant.id) { await coordinator.localRuntime.refresh(for: variant) }
    }

    private func runTest() {
        testing = true
        testResult = nil
        var candidate = draft
        candidate.backend = .localInkling
        Task {
            testResult = await coordinator.testConnection(settings: candidate, secrets: [:])
            testing = false
        }
    }
}

/// URL + model name + optional API key + test.
struct CustomEndpointConfigView: View {
    let coordinator: AppCoordinator
    @Binding var draft: AppSettings
    @Binding var apiKeyDraft: String
    @State private var testResult: Result<String, AnalyzerFailure>?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(BackendCopy.customPrivacy, systemImage: "network").font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Base URL, e.g. http://127.0.0.1:8080", text: Binding(
                get: { draft.customEndpointURL?.absoluteString ?? "" },
                set: { draft.customEndpointURL = URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }))
                .textFieldStyle(.roundedBorder)
            TextField("Model name", text: Binding(
                get: { draft.customModelName ?? "" },
                set: { draft.customModelName = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            SecureField(coordinator.hasSecret(.customEndpointAPIKey) ? "API key (saved in Keychain; type to replace)"
                                                                       : "API key (optional)", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
            Button("Test connection") { runTest() }.disabled(testing)
            TestResultView(result: testResult, isRunning: testing)
        }
    }

    private func runTest() {
        testing = true
        testResult = nil
        var candidate = draft
        candidate.backend = .customEndpoint
        let key = apiKeyDraft
        Task {
            testResult = await coordinator.testConnection(settings: candidate, secrets: [.customEndpointAPIKey: key])
            testing = false
        }
    }
}
