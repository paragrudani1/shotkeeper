import ShotkeeperCore
import SwiftUI

/// First-run setup (spec "PR 3"): a 720×520 window with five steps, step dots and Back / primary buttons.
/// The step rules are core `SetupFlow`; this view renders `SetupModel.current`.
/// Keys: Return = the primary button (when enabled), Esc = Back (steps 2–4), ←/→ switch the model cards.
struct SetupView: View {
    static let size = CGSize(width: 720, height: 520)
    static let windowTitle = "Set Up Shotkeeper"

    @Bindable var model: SetupModel

    var body: some View {
        let flow = model.current
        VStack(spacing: 0) {
            Group {
                switch flow.step {
                case .welcome: WelcomeStep(searchShortcut: model.services.searchShortcut())
                case .privacy: PrivacyStep(model: model)
                case .connect: ConnectStep(model: model, flow: flow)
                case .tryIt: TryItStep(state: flow.tryIt)
                case .done: DoneStep(model: model)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer(flow)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func primaryHint(_ flow: SetupFlow) -> String? {
        guard flow.primary.action == .saveConnection(.openRouter) else { return nil }
        return BackendCopy.openRouterAgreement(destination: model.openRouterDestination)
    }

    private func footer(_ flow: SetupFlow) -> some View {
        HStack(spacing: 12) {
            StepDots(step: flow.step)
            Text(flow.step.progressText)
                .font(.system(size: 12))
                .foregroundStyle(Brand.secondaryText)
                .accessibilityHidden(true) // the dots carry it as their value
            Spacer()
            if flow.showsBack {
                Button("Back") { model.goBack() }
                    .buttonStyle(PanelSecondaryButtonStyle(large: true))
                    .keyboardShortcut(.cancelAction)
            }
            if flow.primary.isDefaultAction {
                Button(flow.primary.title) { model.pressPrimary() }
                    .buttonStyle(BrandPrimaryButtonStyle(large: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!flow.primary.isEnabled)
                    // "Agree and Continue" is OpenRouter's consent: VoiceOver and the tooltip say what it allows.
                    .help(primaryHint(flow) ?? "")
                    .accessibilityHint(primaryHint(flow) ?? "")
            } else {
                // Step 3's "Skip": not the default, so Return in a half-filled field does not skip the step.
                Button(flow.primary.title) { model.pressPrimary() }
                    .buttonStyle(PanelSecondaryButtonStyle(large: true))
                    .disabled(!flow.primary.isEnabled)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }
}

/// Five dots, indigo up to the current step. VoiceOver: "Setup progress, Step 2 of 5".
struct StepDots: View {
    let step: SetupStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SetupStep.allCases, id: \.self) { dot in
                Circle()
                    .fill(dot.rawValue <= step.rawValue ? Brand.indigo : Color.primary.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue(step.progressText)
    }
}

private struct StepTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Step 1

private struct WelcomeStep: View {
    let searchShortcut: HotKeyShortcut

    var body: some View {
        VStack(spacing: 12) {
            AppIconView(size: 72)
            Text("Shotkeeper names your screenshots for you")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("It reads each new screenshot, gives it a clear name, and makes it easy to find again.")
                .font(.system(size: 13))
                .foregroundStyle(Brand.secondaryText)
                .multilineTextAlignment(.center)
            beforeAfter.padding(.top, 8)
            HStack(alignment: .top, spacing: 20) {
                FeatureColumn(symbol: "textformat", title: "Clear names",
                              text: "Each screenshot gets a name that says what is in it.")
                FeatureColumn(symbol: "magnifyingglass", title: "Search by memory",
                              text: "Press \(searchShortcut.display) and type what you remember: words, an app, a tag.")
                FeatureColumn(symbol: "arrow.uturn.backward.circle", title: "Safe",
                              text: "It never deletes a file. You can undo every rename.")
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
    }

    private var beforeAfter: some View {
        HStack(spacing: 12) {
            Text("Screenshot 2026-11-21 at 16.24.11.png")
                .strikethrough()
                .foregroundStyle(Brand.secondaryText)
            Image(systemName: "arrow.right")
                .foregroundStyle(Brand.secondaryText)
            Text("Tweet semiconductor flashcards.png")
                .fontWeight(.semibold)
                .foregroundStyle(Brand.indigoText)
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: Screenshot 2026-11-21 at 16.24.11.png becomes Tweet semiconductor flashcards.png")
    }
}

private struct FeatureColumn: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Brand.indigoText)
                .frame(height: 22)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Brand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Step 2

private struct PrivacyStep: View {
    @Bindable var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(title: "Your screenshots go to your Cloudflare account")
            VStack(alignment: .leading, spacing: 16) {
                PrivacyRow(symbol: "icloud.and.arrow.up",
                           text: "Each new screenshot is sent to Cloudflare Workers AI, with your own Cloudflare account and API token.")
                PrivacyRow(symbol: "internaldrive",
                           text: "Shotkeeper has no server. The index of your screenshots stays on this Mac.")
                PrivacyRow(symbol: "pause.circle",
                           text: "For private screenshots, use Pause in the menu bar, or exclude rules in Settings.")
                PrivacyRow(symbol: "laptopcomputer",
                           text: "On Macs with 24 GB of memory or more, a local model can keep everything on this Mac.")
            }
            Toggle(isOn: $model.flow.consentChecked) {
                Text("I understand that my screenshots are sent to my Cloudflare account.")
                    .font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            // Space ticks it without "Keyboard navigation" (the step has no text field to type into).
            .keyboardShortcut(.space, modifiers: [])
            .help("Space")
            .padding(.top, 8)
        }
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Brand.indigoText)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Step 3

private struct ConnectStep: View {
    @Bindable var model: SetupModel
    let flow: SetupFlow
    @FocusState private var focusedCard: AppSettings.Backend?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: "Connect a model",
                      subtitle: "Choose where Shotkeeper's model runs. You can change it later in Settings.")
            // Up to three cards in one row; four (a re-run with a custom endpoint) in two rows of two. Each row is an
            // HStack sized to its tallest card, so the cards in a row have the same height.
            VStack(spacing: 12) {
                ForEach(Self.rows(flow.cards), id: \.first?.id) { row in
                    HStack(spacing: 12) {
                        ForEach(row) { card in
                            ModelCardButton(card: card, isSelected: flow.choice == card.backend) { model.choose(card.backend) }
                                .focused($focusedCard, equals: card.backend)
                                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                                    let key: SetupFlow.ArrowKey
                                    switch press.key {
                                    case .leftArrow: key = .left
                                    case .rightArrow: key = .right
                                    case .upArrow: key = .up
                                    default: key = .down
                                    }
                                    model.move(key)
                                    focusedCard = model.flow.choice
                                    return .handled
                                }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            switch flow.choice {
            case .localInkling:
                LocalModelSetup(model: model, card: flow.cards.local)
            case .clairic:
                ClairicSetup(model: model, hasSavedToken: flow.inputs.hasSavedToken, complete: flow.inputs.clairicComplete)
            case .openRouter:
                OpenRouterSetup(model: model, hasSavedKey: flow.inputs.hasSavedOpenRouterKey)
            case .customEndpoint:
                Text("Continue keeps the custom endpoint you set up in Settings → Model.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.secondaryText)
            }
        }
        .task(id: flow.choice) {
            if flow.choice == .localInkling { await model.refreshLocal() }
        }
    }

    /// Rows of `SetupCards.columns` cards (core decides the layout, so the arrow keys follow the same grid).
    static func rows(_ cards: SetupCards) -> [[SetupModelCard]] {
        let all = cards.all
        let columns = max(1, cards.columns)
        return stride(from: 0, to: all.count, by: columns).map { Array(all[$0..<min($0 + columns, all.count)]) }
    }
}

/// A selectable card: a real button (Space activates it with keyboard navigation on), with the selected trait.
private struct ModelCardButton: View {
    let card: SetupModelCard
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        if card.isAvailable {
            Button(action: select) { content }
                .buttonStyle(.plain)
                .accessibilityLabel(card.accessibilityLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            // Not a disabled button: a disabled label is dimmed below 4.5:1, and the reason must stay readable.
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(card.title), not available on this Mac. \(card.subtitle)")
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Brand.indigo : Color.secondary)
                .opacity(card.isAvailable ? 1 : 0.4)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { title; badges }
                    VStack(alignment: .leading, spacing: 4) { title; HStack(spacing: 6) { badges } }
                }
                Text(card.subtitle)
                    .font(.system(size: 12))
                    // The reason a card is unavailable must stay readable: full primary, not dimmed.
                    .foregroundStyle(card.isAvailable ? Brand.secondaryText : Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Brand.indigo.opacity(0.10) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isSelected ? Brand.indigo : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var title: some View {
        Text(card.title).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(card.isAvailable ? Color.primary : Brand.secondaryText)
    }

    @ViewBuilder private var badges: some View {
        ForEach(card.badges, id: \.self) { badge in
            let recommended = badge == "Recommended"
            Text(badge)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(recommended ? Brand.indigoText : Brand.warningText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(recommended ? Brand.indigo.opacity(0.14) : Color.orange.opacity(0.2)))
                .fixedSize()
        }
    }
}

private struct ClairicSetup: View {
    enum Field { case account, token }

    @Bindable var model: SetupModel
    let hasSavedToken: Bool
    /// When complete, Return is the default "Continue"; when not, Return moves to the next empty field.
    let complete: Bool
    @FocusState private var focused: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Account ID").gridColumnAlignment(.trailing)
                    TextField("Account ID", text: $model.accountID,
                              prompt: Text("From the Workers AI page of the Cloudflare dashboard"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .account)
                        .onSubmit { focusNextEmptyField() }
                }
                GridRow {
                    Text("API token")
                    SecureField("API token", text: $model.tokenDraft,
                                prompt: Text(hasSavedToken ? "Saved in the Keychain; type to replace" : "Workers AI API token"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .token)
                        .onSubmit { focusNextEmptyField() }
                }
            }
            .font(.system(size: 13))
            .frame(maxWidth: 520)
            HStack(spacing: 14) {
                Button("Test Connection") { model.runTest() }
                    .disabled(model.test == .running)
                ConnectionTestLine(state: model.test)
            }
            Link("How do I get these?", destination: BackendCopy.tokenHelpURL)
                .font(.system(size: 12))
                .help(BackendCopy.tokenHelpText)
        }
        .onAppear { if model.accountID.isEmpty { focused = .account } }
    }

    private func focusNextEmptyField() {
        guard !complete else { return }
        if model.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focused = .account
        } else {
            focused = .token
        }
    }
}

/// OpenRouter: the API key (to the Keychain on "Agree and Continue"), where screenshots go with links to the
/// policies, what "Agree and Continue" allows (step 2 names Cloudflare only, so the footer's default button is the
/// consent; Return presses it), and Test Connection.
private struct OpenRouterSetup: View {
    @Bindable var model: SetupModel
    let hasSavedKey: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("API key")
                    SecureField("API key", text: $model.openRouterKeyDraft,
                                prompt: Text(hasSavedKey ? "Saved in the Keychain; type to replace" : "sk-or-v1-…"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
            }
            .font(.system(size: 13))
            .frame(maxWidth: 520)
            Text(BackendCopy.openRouterPrivacy(model: model.openRouterModel))
                .font(.system(size: 12))
                .foregroundStyle(Brand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Link("Get a key", destination: OpenRouterBackend.keysURL)
                    .help("Create a key and add credits at openrouter.ai")
                Link("OpenRouter privacy policy", destination: OpenRouterBackend.privacyPolicyURL)
                Link("Provider data policies", destination: OpenRouterBackend.providerDataPolicyURL)
            }
            .font(.system(size: 12))
            Text(BackendCopy.openRouterAgreement(destination: model.openRouterDestination))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Button("Test Connection") { model.runTest() }
                    .disabled(model.test == .running)
                ConnectionTestLine(state: model.test)
            }
        }
    }
}

/// "Sending a test image…" → "✓ Connected. The test image was analyzed." or a red, readable error.
struct ConnectionTestLine: View {
    let state: ConnectionTestState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(ConnectionTestText.sending).foregroundStyle(Brand.secondaryText)
            }
            .font(.system(size: 12))
        case .succeeded:
            Label {
                Text(ConnectionTestText.success)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.system(size: 12))
        case .failed(let message):
            Label {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "xmark.octagon.fill")
            }
            .font(.system(size: 12))
            .foregroundStyle(Brand.errorText)
        }
    }
}

private struct LocalModelSetup: View {
    @Bindable var model: SetupModel
    let card: SetupModelCard

    var body: some View {
        let phase = model.services.runtimePhase()
        VStack(alignment: .leading, spacing: 12) {
            if let note = card.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                    Text(note).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .foregroundStyle(Brand.warningText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.14)))
            }
            HStack(spacing: 10) {
                switch phase {
                case .notInstalled, .failed:
                    if let title = card.installButtonTitle {
                        Button(title) { model.install() }.disabled(model.isInstalling)
                    }
                    if case .failed(let message) = phase {
                        Text(message).font(.system(size: 12)).foregroundStyle(Brand.errorText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .installing(let step):
                    ProgressView().controlSize(.small)
                    Text(step).font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                    Button("Cancel") { model.cancelInstall() }
                case .downloading(let fraction):
                    let text = MenuText.download(fraction: fraction, totalGB: card.model?.approxDownloadGB ?? 0)
                    ProgressView(value: fraction).frame(width: 180).accessibilityLabel(text)
                    Text(text).font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                    Button("Cancel") { model.cancelInstall() }
                case .ready, .starting, .running:
                    Label {
                        Text("Installed")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .font(.system(size: 12))
                }
            }
            Text("It downloads to ~/Library/Application Support/Shotkeeper. You can continue while it downloads.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.secondaryText)
        }
    }
}

// MARK: Step 4

private struct TryItStep: View {
    let state: TryItState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: "Try it now", subtitle: TryIt.instruction)
            if case .result(let result) = state {
                TryItResultCard(result: result)
            } else {
                dropZone
            }
        }
    }

    private var dropZone: some View {
        let isConnected: Bool = { if case .notConnected = state { return false } else { return true } }()
        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(isConnected ? Brand.indigo.opacity(0.05) : Color.primary.opacity(0.03))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isConnected ? Brand.indigo : Color.primary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            zoneContent
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .frame(height: 280)
    }

    @ViewBuilder private var zoneContent: some View {
        switch state {
        case .waiting(let note):
            VStack(spacing: 12) {
                ProgressView()
                Text(TryIt.waitingText).font(.system(size: 14, weight: .medium))
                if let note {
                    Text(note).font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        case .problem(let text):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26)).foregroundStyle(.orange).accessibilityHidden(true)
                Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(TryIt.waitingText).font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
        case .notConnected(let text):
            VStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 30)).foregroundStyle(Brand.secondaryText).accessibilityHidden(true)
                Text("No model connected").font(.system(size: 15, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        case .result:
            EmptyView()
        }
    }
}

/// The real first screenshot: a large thumbnail, "✓ It works", the old name struck through, the new name, tags.
struct TryItResultCard: View {
    let result: TryItResult

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ThumbnailView(path: result.path, side: 180, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(result.headline).font(.system(size: 15, weight: .semibold))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(result.oldName)
                    .strikethrough(result.newName != nil)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.secondaryText)
                    .lineLimit(2)
                if let newName = result.newName {
                    Text(newName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = result.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !result.hashtags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(result.hashtags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Brand.indigoText)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(Brand.indigo.opacity(0.14)))
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.accessibilityLabel)
    }
}

// MARK: Step 5

private struct DoneStep: View {
    @Bindable var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(title: "You are all set")
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    let shortcut = model.services.searchShortcut()
                    Text(shortcut.display)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(minWidth: 56, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                        .accessibilityLabel(shortcut.spokenDisplay)
                    Text("Search your screenshots from any app.").font(.system(size: 13))
                    Spacer()
                    Button("Change Shortcut…") { model.services.openShortcutSettings() }
                }
                .padding(14)
                Divider().padding(.leading, 14)
                HStack(spacing: 14) {
                    MenuBarGlyphView(size: 18)
                        .frame(width: 56, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
                    Text("Find Shotkeeper in the menu bar: recent screenshots, Undo and Pause.").font(.system(size: 13))
                    Spacer()
                }
                .padding(14)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
            Toggle(isOn: $model.flow.openAtLogin) {
                Text("Open Shotkeeper when I log in").font(.system(size: 13))
            }
            .toggleStyle(.checkbox)
            .keyboardShortcut(.space, modifiers: []) // as on step 2: no text field here
            .help("Space")
        }
    }
}
