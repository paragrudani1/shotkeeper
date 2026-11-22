import AppKit
import Observation
import ShotkeeperCore
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
    case general, model, exclusions, about
}

/// Which settings tab shows. Kept by the app delegate so setup's "Change Shortcut…" and the toast's
/// "Fix Settings…" can switch an open window.
@MainActor
@Observable
final class SettingsNavigation {
    var tab: SettingsTab = .general
    /// Bumped by setup's "Change Shortcut…": General scrolls to the recorder, which starts recording.
    var recordShortcutRequest = 0
    /// The last request General acted on, so reopening the tab later does not start recording again.
    var handledRecordShortcutRequest = 0

    /// True once per "Change Shortcut…" click.
    func takeRecordShortcutRequest() -> Bool {
        guard recordShortcutRequest > handledRecordShortcutRequest else { return false }
        handledRecordShortcutRequest = recordShortcutRequest
        return true
    }
}

/// The Settings scene's content (spec PR 4): toolbar tabs General · Model · Exclusions · About, a grouped Form on
/// each. Each tab edits a draft copy of `AppSettings` and hands every change to the coordinator, which saves it and
/// applies what changed (analyzer, queue rate, watcher, idle timer, login item).
struct SettingsView: View {
    let coordinator: AppCoordinator
    @Bindable var navigation: SettingsNavigation
    let showSetup: () -> Void

    static let size = CGSize(width: 640, height: 560)

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettingsTab(coordinator: coordinator, navigation: navigation, showSetup: showSetup)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ModelSettingsTab(coordinator: coordinator)
                .tabItem { Label("Model", systemImage: "cpu") }
                .tag(SettingsTab.model)
            ExclusionsSettingsTab(coordinator: coordinator)
                .tabItem { Label("Exclusions", systemImage: "eye.slash") }
                .tag(SettingsTab.exclusions)
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// Keeps a local draft in sync with the coordinator: edits apply immediately, outside changes flow back in.
struct DraftEditor<Content: View>: View {
    let coordinator: AppCoordinator
    @ViewBuilder let content: (Binding<AppSettings>) -> Content
    @State private var draft: AppSettings

    init(coordinator: AppCoordinator, @ViewBuilder content: @escaping (Binding<AppSettings>) -> Content) {
        self.coordinator = coordinator
        self.content = content
        _draft = State(initialValue: coordinator.settings)
    }

    var body: some View {
        content($draft)
            .onAppear { draft = coordinator.settings }
            .onChange(of: draft) { _, new in coordinator.updateSettings(new) }
            .onChange(of: coordinator.settings) { _, new in if new != draft { draft = new } }
    }
}

// MARK: General

struct GeneralSettingsTab: View {
    let coordinator: AppCoordinator
    let navigation: SettingsNavigation
    let showSetup: () -> Void
    @State private var recorder: ShortcutRecorderModel

    init(coordinator: AppCoordinator, navigation: SettingsNavigation, showSetup: @escaping () -> Void,
         recorder: ShortcutRecorderModel? = nil) {
        self.coordinator = coordinator
        self.navigation = navigation
        self.showSetup = showSetup
        _recorder = State(initialValue: recorder ?? ShortcutRecorderModel { coordinator.changeSearchShortcut(to: $0) })
    }

    var body: some View {
        DraftEditor(coordinator: coordinator) { draft in
            ScrollViewReader { proxy in
                Form {
                    Section("Folders") {
                        FolderRow(title: "Watched folder", url: draft.wrappedValue.watchedFolderOverride,
                                  fallback: coordinator.watchedFolder ?? ScreenshotLocation.current().folder,
                                  fallbackNote: "the macOS screenshot location",
                                  set: { draft.wrappedValue.watchedFolderOverride = $0 })
                        FolderRow(title: "Organized folder", url: draft.wrappedValue.organizedFolder, fallback: nil,
                                  fallbackNote: "Not set: renamed screenshots stay where they are",
                                  set: { draft.wrappedValue.organizedFolder = $0 })
                    }
                    Section("New screenshots") {
                        Toggle("Rename with a descriptive title", isOn: draft.renameEnabled)
                        if draft.wrappedValue.organizedFolder != nil {
                            Toggle("Move into the organized folder", isOn: draft.moveEnabled)
                        }
                        Toggle("Write Finder tags and comment", isOn: draft.writeFinderMetadata)
                        if draft.wrappedValue.renameEnabled {
                            LabeledContent("Minimum title confidence") {
                                HStack {
                                    Slider(value: draft.minTitleConfidence, in: 0...1, step: 0.05)
                                        .frame(width: 180)
                                        .accessibilityLabel("Minimum title confidence")
                                    Text(String(format: "%.2f", draft.wrappedValue.minTitleConfidence)).monospacedDigit()
                                }
                            }
                            .help("Below this confidence a screenshot keeps its name (it is still indexed)")
                        }
                    }
                    if draft.wrappedValue.renameEnabled {
                        Section("Filename style") {
                            Picker("Filename style", selection: draft.filenameCasing) {
                                Text("Sentence case").tag(FilenameStyle.Casing.sentence)
                                Text("Title Case").tag(FilenameStyle.Casing.title)
                                Text("kebab-case").tag(FilenameStyle.Casing.kebab)
                            }
                            Toggle("Add the date at the start (2026-11-21 …)", isOn: draft.filenameDatePrefix)
                            LabeledContent("Example") {
                                Text(FilenameStyleExample.text(for: draft.wrappedValue.filenameStyle))
                                    .foregroundStyle(Brand.secondaryText)
                            }
                        }
                    }
                    Section("After a rename") {
                        Toggle("Show a toast after each rename", isOn: draft.showRenameToast)
                        Toggle("Play a sound after a rename", isOn: draft.playRenameSound)
                    }
                    Section("Search shortcut") {
                        ShortcutRecorderView(model: recorder, current: draft.wrappedValue.searchShortcut,
                                             launchProblem: coordinator.searchShortcutProblem)
                            .id(GeneralSettingsTab.shortcutAnchor)
                    }
                    Section("App") {
                        Toggle("Open Shotkeeper when I log in", isOn: draft.launchAtLogin)
                        if LaunchAtLogin.status == .requiresApproval {
                            Button("Approve in System Settings…") { LaunchAtLogin.openSystemSettings() }
                        }
                        if coordinator.isWatching || coordinator.isPaused {
                            LabeledContent {
                                HStack {
                                    if coordinator.isPaused {
                                        Button("Resume") { coordinator.resume() }
                                    } else {
                                        Button("Pause for 10 Minutes") { coordinator.pause(minutes: 10) }
                                        Button("Pause") { coordinator.pauseIndefinitely() }
                                            .help("Hold new screenshots until you resume")
                                    }
                                }
                            } label: {
                                Text(coordinator.statusLine).foregroundStyle(Brand.secondaryText)
                            }
                        }
                        LabeledContent {
                            Button("Run Setup Again…", action: showSetup)
                        } label: {
                            Text("First-run setup")
                        }
                    }
                    if let message = coordinator.lastMessage {
                        Section {
                            Text(message).foregroundStyle(Brand.secondaryText)
                        }
                    }
                }
                .formStyle(.grouped)
                .onAppear { if navigation.takeRecordShortcutRequest() { focusRecorder(proxy) } }
                .onChange(of: navigation.recordShortcutRequest) { _, _ in
                    if navigation.takeRecordShortcutRequest() { focusRecorder(proxy) }
                }
                .onDisappear { recorder.stop() }
            }
        }
    }

    static let shortcutAnchor = "search-shortcut"

    /// Setup's "Change Shortcut…": land on the recorder, already recording.
    private func focusRecorder(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(Self.shortcutAnchor, anchor: .center) }
        recorder.start()
    }
}

/// The filename preview under "Filename style": "2026-11-21 Tweet semiconductor flashcards.png".
enum FilenameStyleExample {
    /// 2026-11-21 16:24 UTC, the spec's example date.
    static let date = Date(timeIntervalSince1970: 1_795_278_240)

    static func text(for style: FilenameStyle) -> String {
        (style.stem(from: "Tweet semiconductor flashcards", capturedAt: date,
                    timeZone: TimeZone(secondsFromGMT: 0)!) ?? "") + ".png"
    }
}

/// A folder row: Finder icon + name (full path in the tooltip and for VoiceOver), "Choose…", and "Clear" when set.
private struct FolderRow: View {
    let title: String
    let url: URL?
    /// What is used while nothing is chosen (the screenshot location), shown with a note.
    let fallback: URL?
    let fallbackNote: String
    let set: (URL?) -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let shown = url ?? fallback {
                    HStack(spacing: 5) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: shown.path))
                            .resizable().frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(FileManager.default.displayName(atPath: shown.path))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .help(url == nil ? "\(shown.path) (\(fallbackNote))" : shown.path)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(url == nil ? "\(shown.lastPathComponent), \(fallbackNote)" : shown.path)
                } else {
                    Text(fallbackNote).foregroundStyle(Brand.secondaryText).lineLimit(2)
                }
                Button("Choose…") { choose() }
                if url != nil {
                    Button("Clear") { set(nil) }
                        .help(fallback == nil ? "Stop using this folder" : "Go back to \(fallbackNote)")
                }
            }
        } label: {
            Text(title)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let start = url ?? fallback { panel.directoryURL = start }
        NSApp.activate()
        if panel.runModal() == .OK, let chosen = panel.url { set(chosen.standardizedFileURL) }
    }
}

// MARK: Exclusions

struct ExclusionsSettingsTab: View {
    let coordinator: AppCoordinator
    /// Spec text for the empty state.
    static let emptyText = "No rules yet. Screenshots that match a rule are never sent, renamed or indexed."

    var body: some View {
        DraftEditor(coordinator: coordinator) { draft in
            Form {
                Section("Exclude rules") {
                    if draft.wrappedValue.excludeRules.rules.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(Self.emptyText)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Brand.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Add Rule") { addRule(draft) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(draft.wrappedValue.excludeRules.rules.indices, id: \.self) { index in
                            ExcludeRuleRow(rule: ruleBinding(draft, index)) {
                                if draft.wrappedValue.excludeRules.rules.indices.contains(index) {
                                    draft.wrappedValue.excludeRules.rules.remove(at: index)
                                }
                            }
                        }
                    }
                }
                if !draft.wrappedValue.excludeRules.rules.isEmpty {
                    Section {
                        LabeledContent {
                            Button("Add Rule") { addRule(draft) }
                        } label: {
                            Text("Screenshots that match a rule are never sent, renamed or indexed.")
                                .foregroundStyle(Brand.secondaryText)
                        }
                    }
                }
                if let until = draft.wrappedValue.excludeRules.pausedUntil, until > Date() {
                    Section {
                        Text("Skipping screenshots until \(until.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(Brand.secondaryText)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func addRule(_ draft: Binding<AppSettings>) {
        draft.wrappedValue.excludeRules.rules.append(.init(.filenameContains, ""))
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
}

private struct ExcludeRuleRow: View {
    @Binding var rule: ExcludeRules.Rule
    let remove: () -> Void

    var body: some View {
        HStack {
            Picker("Rule type", selection: $rule.kind) {
                Text("Name matches (glob)").tag(ExcludeRules.Rule.Kind.filenameGlob)
                Text("Name contains").tag(ExcludeRules.Rule.Kind.filenameContains)
                Text("In folder").tag(ExcludeRules.Rule.Kind.folder)
            }
            .labelsHidden()
            .frame(width: 180)
            TextField("Pattern", text: $rule.pattern, prompt: Text(placeholder))
                .labelsHidden()
                .accessibilityLabel("Pattern")
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
            .accessibilityLabel(rule.pattern.isEmpty ? "Remove rule" : "Remove rule \(rule.pattern)")
        }
    }

    private var placeholder: String {
        switch rule.kind {
        case .filenameGlob: return "*bank*"
        case .filenameContains: return "password"
        case .folder: return "~/Desktop/Private"
        }
    }
}

// MARK: About

/// Where About's links go: the README on GitHub (the repo is public since 2026-11-22) and its "Privacy" section.
enum AboutLinks {
    static let readme = URL(string: "https://github.com/paragrudani1/shotkeeper#readme")!
    static let privacy = URL(string: "https://github.com/paragrudani1/shotkeeper#privacy")!

    /// "Version 0.1.0 (1)".
    static func versionText(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    /// "Open Log Folder": `~/Library/Logs/Shotkeeper`, created when missing (the local model's logs go there), so
    /// Finder always shows the place where logs appear instead of failing or showing another folder.
    @MainActor
    static func openLogFolder(_ folder: URL = LogLocation.directory) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

struct AboutSettingsTab: View {
    var version = AboutLinks.versionText()

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    AppIconView(size: 96)
                    Text("Shotkeeper").font(.system(size: 20, weight: .bold))
                    Text(version).foregroundStyle(Brand.secondaryText)
                    Text("Names, tags and indexes your screenshots.")
                        .foregroundStyle(Brand.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Shotkeeper, \(version). Names, tags and indexes your screenshots.")
            }
            Section {
                LabeledContent("Read Me") {
                    Link("Open on GitHub", destination: AboutLinks.readme)
                        .help(AboutLinks.readme.absoluteString)
                }
                LabeledContent("Privacy") {
                    Link("What is sent where", destination: AboutLinks.privacy)
                        .help(AboutLinks.privacy.absoluteString)
                }
                LabeledContent("Logs") {
                    Button("Open Log Folder") { AboutLinks.openLogFolder() }
                        .help("~/Library/Logs/Shotkeeper")
                }
            }
        }
        .formStyle(.grouped)
    }
}
