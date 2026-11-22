import AppKit
import Observation
import ShotkeeperCore
import SwiftUI

enum SettingsTab: Hashable {
    case general, model, exclusions
}

/// Which settings tab shows. Kept by the app delegate so "Change Shortcut…" in setup can switch an open window.
@MainActor
@Observable
final class SettingsNavigation {
    var tab: SettingsTab = .general
}

/// Tabbed settings. Each tab edits a draft copy of `AppSettings` and hands every change to the coordinator,
/// which saves it and applies what changed (analyzer, queue rate, watcher, idle timer, login item).
struct SettingsView: View {
    let coordinator: AppCoordinator
    @Bindable var navigation: SettingsNavigation
    let showSetup: () -> Void

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettingsTab(coordinator: coordinator, showSetup: showSetup)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            BackendSettingsTab(coordinator: coordinator)
                .tabItem { Label("Model", systemImage: "cpu") }
                .tag(SettingsTab.model)
            ExcludeRulesTab(coordinator: coordinator)
                .tabItem { Label("Exclusions", systemImage: "eye.slash") }
                .tag(SettingsTab.exclusions)
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 520)
    }
}

/// Keeps a local draft in sync with the coordinator: edits apply immediately, outside changes flow back in.
private struct DraftEditor<Content: View>: View {
    let coordinator: AppCoordinator
    @ViewBuilder let content: (Binding<AppSettings>) -> Content
    @State private var draft = AppSettings()
    @State private var loaded = false

    var body: some View {
        content($draft)
            .onAppear {
                draft = coordinator.settings
                loaded = true
            }
            .onChange(of: draft) { _, new in if loaded { coordinator.updateSettings(new) } }
            .onChange(of: coordinator.settings) { _, new in if new != draft { draft = new } }
    }
}

private struct GeneralSettingsTab: View {
    let coordinator: AppCoordinator
    let showSetup: () -> Void

    var body: some View {
        DraftEditor(coordinator: coordinator) { draft in
            Form {
                Section("Folders") {
                    FolderRow(title: "Watched folder", url: draft.wrappedValue.watchedFolderOverride,
                              placeholder: "macOS screenshot location (\(coordinator.watchedFolder?.path ?? "Desktop"))",
                              set: { draft.wrappedValue.watchedFolderOverride = $0 })
                    FolderRow(title: "Organized folder", url: draft.wrappedValue.organizedFolder, placeholder: "Not set",
                              set: { draft.wrappedValue.organizedFolder = $0 })
                }
                Section("What to do with new screenshots") {
                    Toggle("Rename with a descriptive title", isOn: draft.renameEnabled)
                    Toggle("Move into the organized folder", isOn: draft.moveEnabled)
                        .disabled(draft.wrappedValue.organizedFolder == nil)
                    Toggle("Write Finder tags and comment", isOn: draft.writeFinderMetadata)
                    LabeledContent("Minimum title confidence") {
                        HStack {
                            Slider(value: draft.minTitleConfidence, in: 0...1, step: 0.05).frame(width: 200)
                            Text(String(format: "%.2f", draft.wrappedValue.minTitleConfidence)).monospacedDigit()
                        }
                    }
                    Stepper("Requests per minute: \(draft.wrappedValue.requestsPerMinute)",
                            value: draft.requestsPerMinute, in: 1...120)
                }
                Section("After a rename") {
                    Toggle("Show a toast after each rename", isOn: draft.showRenameToast)
                    Toggle("Play a sound after a rename", isOn: draft.playRenameSound)
                }
                Section("App") {
                    // Setup's "Change Shortcut…" opens this tab; the shortcut recorder replaces this row in PR 4.
                    LabeledContent("Search shortcut") {
                        Text(GlobalHotKey.Shortcut.defaultSearch.displayString)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 6)
                            .frame(minHeight: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                            .accessibilityLabel("Option Command S")
                    }
                    .help("Changing the shortcut comes with the next Settings update.")
                    Toggle("Launch at login", isOn: draft.launchAtLogin)
                    if LaunchAtLogin.status == .requiresApproval {
                        Button("Approve in System Settings…") { LaunchAtLogin.openSystemSettings() }
                    }
                    HStack {
                        Text(coordinator.statusLine).foregroundStyle(.secondary)
                        Spacer()
                        if coordinator.isPaused {
                            Button("Resume") { coordinator.resume() }
                        } else {
                            Button("Pause 10 minutes") { coordinator.pause(minutes: 10) }
                            Button("Pause") { coordinator.pauseIndefinitely() }
                        }
                    }
                }
                Section {
                    Button("Run setup again…", action: showSetup)
                }
                if let message = coordinator.lastMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct FolderRow: View {
    let title: String
    let url: URL?
    let placeholder: String
    let set: (URL?) -> Void

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(url?.path ?? placeholder).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(url == nil ? .secondary : .primary)
                Button("Choose…") { choose() }
                if url != nil { Button("Clear") { set(nil) } }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let url { panel.directoryURL = url }
        NSApp.activate()
        if panel.runModal() == .OK, let chosen = panel.url { set(chosen.standardizedFileURL) }
    }
}

private struct BackendSettingsTab: View {
    let coordinator: AppCoordinator
    @State private var tokenDraft = ""
    @State private var apiKeyDraft = ""

    var body: some View {
        DraftEditor(coordinator: coordinator) { draft in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Backend", selection: draft.backend) {
                        ForEach(AppSettings.Backend.allCases, id: \.self) { backend in
                            Text(BackendCopy.name(for: backend)).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)

                    UploadConsentRow(coordinator: coordinator)
                    switch draft.wrappedValue.backend {
                    case .clairic:
                        ClairicConfigView(coordinator: coordinator, draft: draft, tokenDraft: $tokenDraft)
                        Button("Save token to Keychain") {
                            coordinator.setSecret(tokenDraft, for: .cloudflareAPIToken)
                            tokenDraft = ""
                        }
                        .disabled(tokenDraft.isEmpty)
                    case .localInkling:
                        LocalModelConfigView(coordinator: coordinator, draft: draft)
                        Stepper(draft.wrappedValue.idleTimeoutMinutes == 0
                                ? "Stop the model server when idle: never"
                                : "Stop the model server after \(draft.wrappedValue.idleTimeoutMinutes) idle minutes",
                                value: draft.idleTimeoutMinutes, in: 0...240)
                    case .customEndpoint:
                        CustomEndpointConfigView(coordinator: coordinator, draft: draft, apiKeyDraft: $apiKeyDraft)
                        Button("Save API key to Keychain") {
                            coordinator.setSecret(apiKeyDraft, for: .customEndpointAPIKey)
                            apiKeyDraft = ""
                        }
                        .disabled(apiKeyDraft.isEmpty)
                    }
                    Stepper("Longest image side sent: \(draft.wrappedValue.maxImageLongSide) px",
                            value: draft.maxImageLongSide, in: 512...2048, step: 128)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }
}

/// While the selected backend's destination is not allowed: says so, and asks with a confirmation that names the
/// destination ("Screenshots will be sent to llm.lan"). Nothing is sent before "Allow" (the processor skips files).
/// It asks by itself when the backend is switched; a URL being typed only shows the row (no dialog per keystroke).
private struct UploadConsentRow: View {
    let coordinator: AppCoordinator
    @State private var asking = false

    var body: some View {
        let settings = coordinator.settings
        // A VStack, not a Group: a Group passes `onChange` to its children, and there are none while allowed.
        VStack(alignment: .leading, spacing: 0) {
            if let request = BackendGate.consentRequest(for: settings) {
                let prompt = request.prompt
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange).accessibilityHidden(true)
                    Text("\(prompt). Nothing is sent until you allow it.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Allow…") { asking = true }
                }
                .font(.callout)
                .confirmationDialog("\(prompt).", isPresented: $asking, titleVisibility: .visible) {
                    // Grants exactly the endpoint this dialog names; nothing if it was edited meanwhile.
                    Button("Allow") { coordinator.allowUploads(to: request.destination, endpoint: request.endpoint) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Shotkeeper sends each new screenshot there to name it. Screenshots taken before you allow it "
                         + "are left alone, unless you choose Process Existing Screenshots.")
                }
            }
        }
        .onChange(of: settings.backend) { _, _ in
            if BackendGate.consentPrompt(for: coordinator.settings) != nil { asking = true }
        }
    }
}

private struct ExcludeRulesTab: View {
    let coordinator: AppCoordinator

    var body: some View {
        DraftEditor(coordinator: coordinator) { draft in
            VStack(alignment: .leading, spacing: 10) {
                Text("Screenshots matching a rule are never analyzed, renamed or indexed.")
                    .foregroundStyle(.secondary)
                List {
                    ForEach(draft.wrappedValue.excludeRules.rules.indices, id: \.self) { index in
                        let rule = ruleBinding(draft, index)
                        HStack {
                            Picker("", selection: rule.kind) {
                                Text("Name matches (glob)").tag(ExcludeRules.Rule.Kind.filenameGlob)
                                Text("Name contains").tag(ExcludeRules.Rule.Kind.filenameContains)
                                Text("In folder").tag(ExcludeRules.Rule.Kind.folder)
                            }
                            .labelsHidden()
                            .frame(width: 180)
                            TextField(placeholder(rule.wrappedValue.kind), text: rule.pattern)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                if draft.wrappedValue.excludeRules.rules.indices.contains(index) {
                                    draft.wrappedValue.excludeRules.rules.remove(at: index)
                                }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    Button("Add rule") {
                        draft.wrappedValue.excludeRules.rules.append(.init(.filenameContains, ""))
                    }
                    Spacer()
                    if let until = draft.wrappedValue.excludeRules.pausedUntil, until > Date() {
                        Text("Skipping screenshots until \(until.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Bounds-checked: SwiftUI may still evaluate a row's binding for a moment after the rule was removed.
    private func ruleBinding(_ draft: Binding<AppSettings>, _ index: Int) -> Binding<ExcludeRules.Rule> {
        Binding(
            get: {
                let rules = draft.wrappedValue.excludeRules.rules
                return rules.indices.contains(index) ? rules[index] : ExcludeRules.Rule(.filenameContains, "")
            },
            set: { newValue in
                if draft.wrappedValue.excludeRules.rules.indices.contains(index) {
                    draft.wrappedValue.excludeRules.rules[index] = newValue
                }
            })
    }

    private func placeholder(_ kind: ExcludeRules.Rule.Kind) -> String {
        switch kind {
        case .filenameGlob: return "*bank*"
        case .filenameContains: return "password"
        case .folder: return "~/Desktop/Private"
        }
    }
}
