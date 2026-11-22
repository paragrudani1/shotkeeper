import AppKit
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

    /// The Model tab's segmented picker (spec: short names).
    static func shortName(for backend: AppSettings.Backend) -> String {
        switch backend {
        case .clairic: return "Clairic"
        case .localInkling: return "Local"
        case .customEndpoint: return "Custom"
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

/// Result line under a "Test Connection" button. Colours meet 4.5:1 (systemGreen/systemRed text do not on white).
struct TestResultView: View {
    let result: Result<String, AnalyzerFailure>?
    let isRunning: Bool

    var body: some View {
        if isRunning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Sending a test image…").foregroundStyle(Brand.secondaryText)
            }
        } else if let result {
            switch result {
            case .success(let text):
                Label {
                    Text("Connected. \(text)").fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .failure(let failure):
                Label {
                    Text(failure.message).foregroundStyle(Brand.errorText).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(Brand.errorText)
                }
            }
        }
    }
}

// MARK: Model tab

/// Settings → Model: a segmented picker (Clairic / Local / Custom), the consent row, the selected backend's fields
/// (saved as you type; tokens to the Keychain after a pause), Test Connection, and the local model install.
struct ModelSettingsTab: View {
    let coordinator: AppCoordinator
    /// Snapshots show a download without running one.
    var installStateOverride: LocalInstallState?
    @State private var asking: ConsentRequest?

    var body: some View {
        DraftEditor(coordinator: coordinator) { draft in
            Form {
                Section {
                    Picker("Model", selection: draft.backend) {
                        ForEach(AppSettings.Backend.allCases, id: \.self) { backend in
                            Text(BackendCopy.shortName(for: backend)).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Which model names your screenshots")
                    Text(BackendCopy.privacy(for: draft.wrappedValue.backend))
                        .foregroundStyle(Brand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let request = BackendGate.consentRequest(for: coordinator.settings) {
                        UploadConsentRow(request: request) { asking = $0 }
                    }
                }
                switch draft.wrappedValue.backend {
                case .clairic:
                    ClairicSettingsSection(coordinator: coordinator, draft: draft)
                case .localInkling:
                    LocalModelSettingsSection(coordinator: coordinator, draft: draft, stateOverride: installStateOverride)
                case .customEndpoint:
                    CustomEndpointSettingsSection(coordinator: coordinator, draft: draft)
                }
                Section("Requests") {
                    Stepper("Longest image side sent: \(draft.wrappedValue.maxImageLongSide) px",
                            value: draft.maxImageLongSide, in: 512...2048, step: 128)
                    Stepper("Requests per minute: \(draft.wrappedValue.requestsPerMinute)",
                            value: draft.requestsPerMinute, in: 1...120)
                }
            }
            .formStyle(.grouped)
            .modifier(UploadConsentPrompt(coordinator: coordinator, asking: $asking))
        }
    }
}

/// The consent row while the selected backend's destination is not allowed: says so; "Allow…" opens the
/// confirmation (`UploadConsentPrompt`). PR 3's flow, unchanged: nothing is sent before "Allow".
private struct UploadConsentRow: View {
    let request: ConsentRequest
    let ask: (ConsentRequest) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text("\(request.prompt). Nothing is sent until you allow it.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Allow…") { ask(request) }
                .help("Allow Shotkeeper to send new screenshots there")
        }
    }
}

/// The confirmation that names the destination ("Screenshots will be sent to http://gpu-box.lan:8080"). It asks by
/// itself when the backend is switched; a URL being typed only shows the row (no dialog per keystroke, also now that
/// fields save as you type). The dialog shows the request captured when it opened (`presenting`), so its text and its
/// "Allow" stay the same while it is open; "Allow" grants exactly that endpoint, nothing if the settings no longer
/// match (`BackendGate.granting(_:expectedEndpoint:in:)`). Attached to the whole Form, so it is there whether or not
/// the row is shown.
struct UploadConsentPrompt: ViewModifier {
    let coordinator: AppCoordinator
    @Binding var asking: ConsentRequest?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(asking.map { "\($0.prompt)." } ?? "", isPresented: isAsking, titleVisibility: .visible,
                                presenting: asking) { request in
                Button("Allow") { coordinator.allowUploads(to: request.destination, endpoint: request.endpoint) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Shotkeeper sends each new screenshot there to name it. Screenshots taken before you allow it "
                     + "are left alone, unless you choose Process Existing Screenshots.")
            }
            .onChange(of: coordinator.settings.backend) { _, _ in
                if let request = BackendGate.consentRequest(for: coordinator.settings) { asking = request }
            }
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })
    }
}

/// Account ID (saved as you type), API token (Keychain, saved after a pause), the help link and Test Connection.
private struct ClairicSettingsSection: View {
    let coordinator: AppCoordinator
    @Binding var draft: AppSettings
    @State private var tokenDraft = ""

    var body: some View {
        Section("Cloudflare account") {
            TextField("Account ID", text: Binding(
                get: { draft.clairicAccountID ?? "" },
                set: { draft.clairicAccountID = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }),
                prompt: Text("32 characters, from the Cloudflare dashboard"))
            SecretField(title: "API token", key: .cloudflareAPIToken, coordinator: coordinator, text: $tokenDraft,
                        removeTitle: "Remove saved token",
                        removeMessage: "Shotkeeper stops naming screenshots with Clairic until you enter a token again.")
            LabeledContent {
                Link("How do I get these?", destination: BackendCopy.tokenHelpURL)
                    .help(BackendCopy.tokenHelpText)
            } label: {
                EmptyView()
            }
            TestConnectionRow(coordinator: coordinator) {
                var candidate = draft
                candidate.backend = .clairic
                return (candidate, [.cloudflareAPIToken: tokenDraft])
            }
        }
    }
}

/// URL and model name (saved as you type), optional API key (Keychain), Test Connection.
private struct CustomEndpointSettingsSection: View {
    let coordinator: AppCoordinator
    @Binding var draft: AppSettings
    @State private var keyDraft = ""

    var body: some View {
        Section("Endpoint") {
            TextField("Base URL", text: Binding(
                get: { draft.customEndpointURL?.absoluteString ?? "" },
                set: { draft.customEndpointURL = URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
                prompt: Text("http://127.0.0.1:8080"))
            TextField("Model name", text: Binding(
                get: { draft.customModelName ?? "" },
                set: { draft.customModelName = $0.isEmpty ? nil : $0 }))
            SecretField(title: "API key (optional)", key: .customEndpointAPIKey, coordinator: coordinator, text: $keyDraft,
                        removeTitle: "Remove saved API key",
                        removeMessage: "Requests to the endpoint are sent without a key from now on.")
            TestConnectionRow(coordinator: coordinator) {
                var candidate = draft
                candidate.backend = .customEndpoint
                return (candidate, [.customEndpointAPIKey: keyDraft])
            }
        }
    }
}

/// A token or key field that saves to the Keychain as you type: 1 s after the last change, on Return, and when the
/// field goes away. There is no Save button. An empty field never removes the saved value; "Remove saved token"
/// does, after a confirmation. The typed text stays in the field (masked), so a pause while typing saves a partial
/// value that the next keystrokes replace.
struct SecretField: View {
    let title: String
    let key: CredentialKey
    let coordinator: AppCoordinator
    @Binding var text: String
    let removeTitle: String
    let removeMessage: String
    static let saveDelay: Duration = .seconds(1)

    @State private var saveTask: Task<Void, Never>?
    @State private var confirmingRemove = false
    @State private var savedText: String?

    var body: some View {
        let hasSaved = coordinator.hasSecret(key)
        SecureField(title, text: $text,
                    prompt: Text(hasSaved ? "Saved in Keychain (type to replace)" : "Paste it here"))
            .onChange(of: text) { _, _ in scheduleSave() }
            .onSubmit { saveNow() }
            .onDisappear { saveNow() }
        if hasSaved || savedText != nil {
            LabeledContent {
                HStack(spacing: 10) {
                    if savedText != nil, savedText == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Brand.secondaryText)
                    }
                    if hasSaved {
                        Button(removeTitle + "…", role: .destructive) { confirmingRemove = true }
                    }
                }
            } label: {
                EmptyView()
            }
            .confirmationDialog(removeTitle + "?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button(removeTitle, role: .destructive) {
                    saveTask?.cancel()
                    text = ""
                    savedText = nil
                    coordinator.setSecret("", for: key)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(removeMessage)
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saveTask = Task {
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != savedText else { return }
        coordinator.setSecret(value, for: key)
        savedText = value
    }
}

/// "Test Connection" and its result line. `candidate` returns the unsaved settings and typed secrets to test with
/// (an empty secret uses the saved one). Only the generated test image is sent.
private struct TestConnectionRow: View {
    let coordinator: AppCoordinator
    let candidate: () -> (AppSettings, [CredentialKey: String])
    @State private var result: Result<String, AnalyzerFailure>?
    @State private var testing = false
    @State private var run = 0

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 6) {
                Button("Test Connection") { test() }
                    .disabled(testing)
                    .help("Sends a generated test image, never one of your screenshots")
                TestResultView(result: result, isRunning: testing)
            }
        } label: {
            EmptyView()
        }
    }

    private func test() {
        run += 1
        let tag = run
        testing = true
        result = nil
        let (settings, secrets) = candidate()
        Task {
            let outcome = await coordinator.testConnection(settings: settings, secrets: secrets)
            guard tag == run else { return }
            result = outcome
            testing = false
        }
    }
}

// MARK: Local model

/// What the local install area shows. Plain values, so snapshots can show a download.
struct LocalInstallState: Equatable {
    var phase: RuntimePhase
    var stats: DownloadStats?
    /// An install or download runs (Cancel is offered).
    var installing: Bool
    /// Why the last install did not start or failed (disk check, no Python…).
    var problem: String?
    var variantName: String
    var downloadGB: Int

    var isInstalled: Bool {
        switch phase {
        case .ready, .starting, .running: return true
        default: return false
        }
    }
}

private struct LocalModelSettingsSection: View {
    let coordinator: AppCoordinator
    @Binding var draft: AppSettings
    let stateOverride: LocalInstallState?
    @State private var installTask: Task<Void, Never>?
    @State private var confirmingRemove = false

    private var variant: ModelVariant {
        AnalyzerFactory.localVariant(for: draft, physicalMemoryBytes: coordinator.physicalMemoryBytes)
    }

    private var state: LocalInstallState {
        stateOverride ?? LocalInstallState(phase: coordinator.runtimePhase, stats: coordinator.downloadStats,
                                           installing: installTask != nil, problem: coordinator.localInstallProblem,
                                           variantName: variant.displayName,
                                           downloadGB: Int(variant.approxDownloadGB.rounded()))
    }

    var body: some View {
        Section("Inkling 2 Mini on this Mac") {
            Picker("Model", selection: Binding(get: { variant.id }, set: { draft.localModelVariantID = $0 })) {
                ForEach(ModelCatalog.all) { model in
                    Text("\(model.displayName), \(Int(model.approxDownloadGB.rounded())) GB, for \(model.minRAMGB) GB+ Macs")
                        .tag(model.id)
                }
            }
            .disabled(state.installing)
            if Int((Double(coordinator.physicalMemoryBytes) / 1_073_741_824).rounded()) < variant.minRAMGB {
                Label("This Mac has less memory than this build is meant for.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Brand.warningText)
            }
            if let warning = variant.warning {
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Brand.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !variant.verifiedWithMLXLM {
                Label("Experimental build: not yet tested with the built-in model server.", systemImage: "flask")
                    .foregroundStyle(Brand.secondaryText)
            }
            LocalInstallView(state: state, actions: actions)
                // On a row, not on the Section: a Section, like a Group, would give each row its own copy.
                .task(id: variant.id) {
                    guard stateOverride == nil else { return }
                    await coordinator.localRuntime.refresh(for: variant)
                }
                .confirmationDialog("Remove \(variant.displayName)?", isPresented: $confirmingRemove,
                                    titleVisibility: .visible) {
                    Button("Remove Model", role: .destructive) {
                        let selected = variant
                        Task { await coordinator.removeLocalModel(selected) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes the \(state.downloadGB) GB download from this Mac. Your screenshots and their "
                         + "names stay as they are. You can download it again later.")
                }
            if state.isInstalled {
                Stepper(draft.idleTimeoutMinutes == 0
                        ? "Stop the model server when idle: never"
                        : "Stop the model server after \(draft.idleTimeoutMinutes) idle minutes",
                        value: $draft.idleTimeoutMinutes, in: 0...240)
            }
        }
    }

    private var actions: LocalInstallView.Actions {
        LocalInstallView.Actions(
            install: {
                let selected = variant
                installTask = Task {
                    await coordinator.installLocalModel(selected)
                    installTask = nil
                }
            },
            cancel: { Task { await coordinator.localRuntime.cancelInstall() } },
            remove: { confirmingRemove = true },
            stopServer: { Task { await coordinator.localRuntime.stop() } },
            retry: { Task { await coordinator.retryLocalRuntime() } },
            test: {
                var candidate = draft
                candidate.backend = .localInkling
                return await coordinator.testConnection(settings: candidate, secrets: [:])
            })
    }
}

/// Install status, progress with bytes, speed and time left, and only the buttons that apply now.
struct LocalInstallView: View {
    struct Actions {
        var install: () -> Void
        var cancel: () -> Void
        var remove: () -> Void
        var stopServer: () -> Void
        var retry: () -> Void
        var test: () async -> Result<String, AnalyzerFailure>

    }

    let state: LocalInstallState
    let actions: Actions
    @State private var testResult: Result<String, AnalyzerFailure>?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .downloading(let fraction) = state.phase {
                Text("Downloading \(state.variantName)")
                ProgressView(value: fraction)
                    .accessibilityLabel("Download progress")
                    .accessibilityValue(state.stats?.summary ?? "\(Int((fraction * 100).rounded())) percent")
                Text(state.stats?.summary ?? "\(Int((fraction * 100).rounded()))%")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(Brand.secondaryText)
            } else {
                HStack(spacing: 8) {
                    Text(BackendCopy.describe(state.phase))
                        .foregroundStyle(statusIsFailure ? Brand.errorText : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if state.phase.isBusy { ProgressView().controlSize(.small) }
                }
            }
            if !state.isInstalled, !state.installing {
                Text("Installs a private Python environment with mlx-lm and downloads about \(state.downloadGB) GB to "
                     + "~/Library/Application Support/Shotkeeper/runtime.")
                    .font(.callout).foregroundStyle(Brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = state.problem, !state.installing {
                Label {
                    Text(problem).foregroundStyle(Brand.errorText).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.errorText)
                }
            }
            HStack {
                if state.installing {
                    Button("Cancel", action: actions.cancel)
                } else if !state.isInstalled {
                    Button("Install and Download (about \(state.downloadGB) GB)", action: actions.install)
                }
                if case .failed = state.phase, !state.installing {
                    Button("Retry", action: actions.retry).help("Start the local model server again")
                }
                if case .running = state.phase {
                    Button("Stop Server", action: actions.stopServer)
                }
                if state.isInstalled {
                    Button("Test Connection") { test() }.disabled(testing)
                        .help("Analyzes a generated test image with the local model")
                    Button("Remove Model…", role: .destructive, action: actions.remove)
                        .help("Delete the downloaded model from this Mac")
                }
            }
            TestResultView(result: testResult, isRunning: testing)
        }
        .padding(.vertical, 2)
    }

    private var statusIsFailure: Bool {
        if case .failed = state.phase { return true }
        return false
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            testResult = await actions.test()
            testing = false
        }
    }
}
