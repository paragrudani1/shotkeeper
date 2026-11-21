import ShotkeeperCore
import SwiftUI

/// First-run window (also opened from Settings): recommends a backend for this Mac's memory, explains where
/// screenshots go, collects credentials, and tests the connection before the user commits.
struct SetupView: View {
    let coordinator: AppCoordinator
    let onDone: () -> Void

    @State private var draft: AppSettings
    @State private var selection: Int = 0
    @State private var tokenDraft = ""
    @State private var apiKeyDraft = ""
    private let options: [BackendOption]
    private let notes: [String]

    init(coordinator: AppCoordinator, onDone: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onDone = onDone
        let recommendation = coordinator.recommendation
        let options = [recommendation.recommended] + recommendation.alternatives
        self.options = options
        self.notes = recommendation.notes
        _draft = State(initialValue: coordinator.settings)
        // Preselect what is already configured, else the recommendation.
        let current = coordinator.settings
        let index = current.hasSeenPrivacyNotice ? options.firstIndex(where: { $0.backend == current.backend }) : nil
        _selection = State(initialValue: index ?? 0)
    }

    private var option: BackendOption { options[selection] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up Shotkeeper").font(.title2.bold())
            Text("Shotkeeper renames, tags and indexes new screenshots with a vision model. "
                 + "This Mac has \(Int((Double(coordinator.physicalMemoryBytes) / 1_073_741_824).rounded())) GB of memory.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(notes, id: \.self) { Label($0, systemImage: "info.circle").font(.callout) }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                    OptionRow(option: option, isRecommended: offset == 0, isSelected: offset == selection)
                        .onTapGesture { select(offset) }
                }
            }

            Divider()
            ScrollView {
                Group {
                    switch option.backend {
                    case .clairic:
                        ClairicConfigView(coordinator: coordinator, draft: $draft, tokenDraft: $tokenDraft)
                    case .localInkling:
                        LocalModelConfigView(coordinator: coordinator, draft: $draft)
                    case .customEndpoint:
                        CustomEndpointConfigView(coordinator: coordinator, draft: $draft, apiKeyDraft: $apiKeyDraft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Later") { onDone() }
                Button("Use \(BackendCopy.name(for: option.backend))") { finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 600)
    }

    private func select(_ offset: Int) {
        selection = offset
        if let model = options[offset].model { draft.localModelVariantID = model.id }
    }

    private func finish() {
        if !tokenDraft.isEmpty { coordinator.setSecret(tokenDraft, for: .cloudflareAPIToken) }
        if !apiKeyDraft.isEmpty { coordinator.setSecret(apiKeyDraft, for: .customEndpointAPIKey) }
        var updated = draft
        updated.backend = option.backend
        if let model = option.model, updated.localModelVariantID == nil { updated.localModelVariantID = model.id }
        updated.hasSeenPrivacyNotice = true
        coordinator.updateSettings(updated)
        tokenDraft = ""
        apiKeyDraft = ""
        onDone()
    }
}

private struct OptionRow: View {
    let option: BackendOption
    let isRecommended: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(BackendCopy.title(for: option)).font(.headline)
                    if isRecommended {
                        Text("Recommended").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                Text(option.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = option.warning {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
