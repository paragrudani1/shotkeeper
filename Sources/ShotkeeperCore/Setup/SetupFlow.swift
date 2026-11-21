import Foundation

/// The five pages of first-run setup (spec "PR 3").
public enum SetupStep: Int, CaseIterable, Sendable {
    case welcome = 1, privacy, connect, tryIt, done

    public static let count = SetupStep.allCases.count

    /// "Step 2 of 5": shown next to the dots, and their accessibility value.
    public var progressText: String { "Step \(rawValue) of \(Self.count)" }
}

/// What the app must do when the primary button is pressed. The flow itself only moves between steps.
public enum SetupPrimaryAction: Equatable, Sendable {
    /// Step 1 "Get Started", step 4 "Skip"/"Continue".
    case next
    /// Step 2 "I Agree": store the upload consent (the only place it is stored).
    case acceptConsent
    /// Step 3 "Continue": save the chosen backend (the token goes to the Keychain now, never earlier).
    case saveConnection(AppSettings.Backend)
    /// Step 3 "Skip": change nothing; step 4 then shows that no model is connected.
    case skipConnection
    /// Step 5 "Finish": apply "Open Shotkeeper when I log in" and close.
    case finish
}

public struct SetupPrimaryButton: Equatable, Sendable {
    public var title: String
    public var isEnabled: Bool
    public var action: SetupPrimaryAction
}

/// The local model, as far as step 3 cares.
public enum SetupLocalModelState: Equatable, Sendable {
    case notInstalled
    /// Install or download running.
    case installing
    case installed
    case failed
}

/// What step 3 knows about the user's input. The token itself stays in the app (`hasTokenDraft` only), so this
/// value can be compared, logged by a test failure, or snapshotted without carrying a secret.
public struct SetupConnectionInputs: Equatable, Sendable {
    public var accountID: String
    public var hasTokenDraft: Bool
    public var hasSavedToken: Bool
    public var localModel: SetupLocalModelState

    public init(accountID: String = "", hasTokenDraft: Bool = false, hasSavedToken: Bool = false,
                localModel: SetupLocalModelState = .notInstalled) {
        self.accountID = accountID
        self.hasTokenDraft = hasTokenDraft
        self.hasSavedToken = hasSavedToken
        self.localModel = localModel
    }

    /// Clairic can be saved: an account ID and a token (typed now or saved earlier).
    public var clairicComplete: Bool {
        !BackendGate.trimmed(accountID).isEmpty && (hasTokenDraft || hasSavedToken)
    }

    /// Local can be saved once its install was started (it finishes in the background) or is done.
    public var localComplete: Bool { localModel == .installing || localModel == .installed }
}

/// Setup's step state machine: which step shows, Back, and the primary button's title, enabled state and action.
/// The app renders it and performs `primaryAction()` before calling `advance()`.
public struct SetupFlow: Equatable, Sendable {
    public private(set) var step: SetupStep = .welcome
    /// Step 2's checkbox. Starts ticked when consent was given before (setup run again from Settings).
    public var consentChecked: Bool
    /// The selected card in step 3.
    public private(set) var choice: AppSettings.Backend
    public var inputs: SetupConnectionInputs
    /// Step 4's state.
    public var tryIt: TryItState = .waiting(note: nil)
    /// Step 5's checkbox: on for a first run; a re-run shows the current setting.
    public var openAtLogin: Bool
    public let cards: SetupCards

    public init(settings: AppSettings, cards: SetupCards, inputs: SetupConnectionInputs = SetupConnectionInputs()) {
        self.cards = cards
        self.inputs = inputs
        let isRerun = settings.hasSeenPrivacyNotice
        consentChecked = isRerun
        openAtLogin = isRerun ? settings.launchAtLogin : true
        // A re-run preselects what is configured; a first run (or a custom endpoint) the recommendation.
        if isRerun, let card = cards.card(for: settings.backend), card.isAvailable {
            choice = settings.backend
        } else {
            choice = cards.recommended
        }
        if self.inputs.accountID.isEmpty, let account = settings.clairicAccountID { self.inputs.accountID = account }
    }

    public var showsBack: Bool { step == .privacy || step == .connect || step == .tryIt }

    public var primary: SetupPrimaryButton {
        switch step {
        case .welcome:
            return SetupPrimaryButton(title: "Get Started", isEnabled: true, action: .next)
        case .privacy:
            return SetupPrimaryButton(title: "I Agree", isEnabled: consentChecked, action: .acceptConsent)
        case .connect:
            let complete = choice == .clairic ? inputs.clairicComplete : inputs.localComplete
            return complete ? SetupPrimaryButton(title: "Continue", isEnabled: true, action: .saveConnection(choice))
                            : SetupPrimaryButton(title: "Skip", isEnabled: true, action: .skipConnection)
        case .tryIt:
            switch tryIt {
            case .result, .notConnected:
                return SetupPrimaryButton(title: "Continue", isEnabled: true, action: .next)
            case .waiting, .problem:
                return SetupPrimaryButton(title: "Skip", isEnabled: true, action: .next)
            }
        case .done:
            return SetupPrimaryButton(title: "Finish", isEnabled: true, action: .finish)
        }
    }

    /// The action to perform for the primary button (Return), or nil while it is disabled.
    public func primaryAction() -> SetupPrimaryAction? {
        let button = primary
        return button.isEnabled ? button.action : nil
    }

    /// After the app performed `primaryAction()`. Step 4 always starts waiting again.
    public mutating func advance() {
        guard let next = SetupStep(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .tryIt { tryIt = .waiting(note: nil) }
    }

    /// Back (steps 2–4; Esc). Returns false where there is no Back.
    @discardableResult
    public mutating func back() -> Bool {
        guard showsBack, let previous = SetupStep(rawValue: step.rawValue - 1) else { return false }
        step = previous
        return true
    }

    /// Selects a card; an unavailable card cannot be selected. Returns whether the choice changed.
    @discardableResult
    public mutating func choose(_ backend: AppSettings.Backend) -> Bool {
        guard backend != choice, cards.card(for: backend)?.isAvailable == true else { return false }
        choice = backend
        return true
    }

    /// ←/→/↑/↓ on the cards: the other available card.
    @discardableResult
    public mutating func chooseNext() -> Bool {
        choose(choice == .clairic ? .localInkling : .clairic)
    }
}

/// Step 4: what happened to the first screenshot since the step opened.
public enum TryItState: Equatable, Sendable {
    /// Spinner, "Waiting for a new screenshot…", and an optional line (local model still downloading, paused).
    case waiting(note: String?)
    /// No usable backend (step 3 skipped): nothing can be named yet.
    case notConnected(String)
    case result(TryItResult)
    /// The last screenshot did not work; still waiting for the next one.
    case problem(String)
}

/// The result card: "✓ It works", the old name struck through, the new name, the tags.
public struct TryItResult: Equatable, Sendable {
    public var path: String
    public var oldName: String
    /// Nil when the name was kept (low title confidence or renaming turned off).
    public var newName: String?
    public var hashtags: [String]

    public var headline: String { "It works" }
    /// Under the names when the name was kept.
    public var detail: String? {
        newName == nil ? "Shotkeeper kept the name, and the screenshot is in the index, so search finds it." : nil
    }

    public var accessibilityLabel: String {
        var parts = [headline]
        if let newName { parts.append("\(oldName) was renamed to \(newName)") } else { parts.append("\(oldName) kept its name") }
        if !hashtags.isEmpty { parts.append("Tags: " + hashtags.map { String($0.dropFirst()) }.joined(separator: ", ")) }
        return parts.joined(separator: ". ")
    }
}

/// Step 4 rules. Pure: the app feeds it the coordinator's pipeline events (the same ones the toast uses).
public enum TryIt {
    public static let waitingText = "Waiting for a new screenshot…"
    public static let instruction = "Take a screenshot of anything on your screen with ⌘⇧4. Shotkeeper shows you the result here."
    public static let notConnectedText = "Shotkeeper is not connected to a model yet, so it cannot name screenshots. "
        + "Go Back to connect one, or do it later in Settings → Model."

    /// The state when step 4 opens.
    public static func initialState(readiness: BackendReadiness, note: String? = nil) -> TryItState {
        readiness == .ready ? .waiting(note: note) : .notConnected(notConnectedText)
    }

    /// Updates the waiting line (download progress, pause) without leaving a result or problem.
    public static func withNote(_ note: String?, in state: TryItState) -> TryItState {
        if case .waiting = state { return .waiting(note: note) }
        return state
    }

    /// "Downloading Inkling 2 Mini · 4.1 of 10.4 GB. Your screenshot is named when it finishes." / paused text.
    public static func waitingNote(localDownload: (fraction: Double, totalGB: Double)?, isInstalling: Bool,
                                   isPaused: Bool) -> String? {
        if isPaused { return "Shotkeeper is paused. Resume it from the menu bar to see a result." }
        if let download = localDownload {
            return MenuText.download(fraction: download.fraction, totalGB: download.totalGB)
                + ". Your screenshot is named when it finishes."
        }
        if isInstalling { return "Installing the local model. Your screenshot is named when it is ready." }
        return nil
    }

    /// The next state after a pipeline event. A shown result stays; events that say nothing about the user's new
    /// screenshot (already indexed, missing, restored by Undo) change nothing.
    /// - Parameter entry: the index row at the report's final path (for the tags), if any.
    public static func apply(_ event: ScreenshotEvent, entry: IndexedScreenshot?, to state: TryItState) -> TryItState {
        if case .result = state { return state }
        if case .notConnected = state { return state }
        switch event {
        case .failed(_, let problem):
            return .problem("Could not name that screenshot: \(problem.message). Take another one to try again.")
        case .processed(let report):
            switch report.outcome {
            case .processed(let finalURL, let renamed, _):
                let oldName = report.originalURL.lastPathComponent
                return .result(TryItResult(path: finalURL.path, oldName: oldName,
                                           newName: renamed ? finalURL.lastPathComponent : nil,
                                           hashtags: (entry?.tags ?? []).map { "#\($0)" }))
            case .skipped(.excluded):
                return .problem("That screenshot matches an exclude rule, so Shotkeeper left it alone. Take another one.")
            case .skipped(.paused):
                return .problem("Shotkeeper is paused, so it left that screenshot alone. Resume it from the menu bar, then take another one.")
            case .skipped(.missing), .skipped(.alreadyIndexed), .skipped(.restoredByUndo):
                return state
            }
        }
    }
}
