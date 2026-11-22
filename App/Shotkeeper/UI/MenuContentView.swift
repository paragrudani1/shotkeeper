import AppKit
import Observation
import ShotkeeperCore
import SwiftUI

/// Everything the menu shows, as plain values (built from the coordinator by `make`, or by hand in snapshots).
struct MenuViewState {
    struct Download: Equatable {
        var text: String
        var fraction: Double
    }

    var status: MenuStatusSummary
    var message: String?
    var showsFixSettings = false
    var showsFinishSetup = false
    var download: Download?
    var recents: [RecentItem] = []
    var now: Date
    var time = TimeLabel()
    var undoTitle: String
    var canUndo: Bool
    var isPaused: Bool
    /// The registered search shortcut ("⌥⌘S"); nil when none is registered (the row then shows no shortcut).
    var searchShortcut: String?
    var version: String
    /// Pause/Resume only while watching (or paused): before setup there is nothing to pause.
    var showsPauseResume = true
    /// "Process Existing Screenshots…" only once a backend is usable (it refuses before setup).
    var showsProcessExisting = true

    /// Selectable rows in display order (keyboard ↑/↓ walks these).
    var rows: [MenuRowID] {
        var rows: [MenuRowID] = []
        if showsFixSettings { rows.append(.fixSettings) }
        if showsFinishSetup { rows.append(.finishSetup) }
        rows += recents.map { .recent($0.id) }
        if canUndo { rows.append(.undo) }
        if showsPauseResume { rows.append(isPaused ? .resume : .pause) }
        if showsProcessExisting { rows.append(.processExisting) }
        rows += [.search, .settings, .about, .quit]
        return rows
    }

    @MainActor
    static func make(from coordinator: AppCoordinator, now: Date = Date(),
                     version: String = MenuViewState.appVersion) -> MenuViewState {
        var download: Download?
        if coordinator.settings.backend == .localInkling, case .downloading(let fraction) = coordinator.runtimePhase {
            download = Download(text: MenuText.download(fraction: fraction,
                                                        totalGB: coordinator.localVariant.approxDownloadGB),
                                fraction: fraction)
        }
        let isError: Bool = { if case .error = coordinator.queueStatus { return true } else { return false } }()
        return MenuViewState(
            status: MenuText.status(queue: coordinator.queueStatus,
                                    watchedFolderName: coordinator.watchedFolder?.lastPathComponent,
                                    indexedCount: coordinator.indexedCount, failure: coordinator.failureText,
                                    notWatchingReason: coordinator.notWatchingReason,
                                    skippingForConsent: coordinator.isSkippingForConsent, now: now),
            message: coordinator.lastMessage,
            showsFixSettings: isError,
            // Also after consent while no backend is usable yet (step 3 skipped): setup is where that is fixed.
            showsFinishSetup: !coordinator.settings.hasSeenPrivacyNotice || coordinator.notWatchingReason != nil
                || coordinator.isSkippingForConsent,
            download: download,
            recents: coordinator.recentItems,
            now: now,
            undoTitle: MenuText.undoItem(for: coordinator.undoCandidate),
            canUndo: coordinator.undoCandidate != nil,
            isPaused: coordinator.isPaused,
            searchShortcut: coordinator.activeSearchShortcut?.display,
            version: version,
            showsPauseResume: coordinator.isWatching || coordinator.isPaused,
            showsProcessExisting: coordinator.readiness == .ready)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

enum MenuRowID: Hashable {
    case fixSettings, finishSetup, recent(Int64), undo, pause, resume, processExisting, search, settings, about, quit
}

/// What the rows do. `reveal` is true for ⌥-click / ⌥-Return on a recent row.
struct MenuActions {
    var perform: (_ row: MenuRowID, _ reveal: Bool) -> Void

    @MainActor static let none = MenuActions { _, _ in }
}

/// Keyboard/mouse highlight shared by hover and ↑/↓, like a real menu.
@MainActor
@Observable
final class MenuHighlight {
    var row: MenuRowID?

    func move(_ delta: Int, in rows: [MenuRowID]) {
        guard !rows.isEmpty else { return }
        guard let current = row, let index = rows.firstIndex(of: current) else {
            row = delta > 0 ? rows.first : rows.last
            return
        }
        row = rows[(index + delta + rows.count) % rows.count]
    }
}

/// The menu bar menu (spec PR 1b), drawn as SwiftUI in a panel so it can show the status dot, thumbnails, times
/// and the download progress bar that a native NSMenu cannot.
struct MenuContentView: View {
    static let width: CGFloat = 300

    let state: MenuViewState
    let actions: MenuActions
    var highlight: MenuHighlight
    var opaqueBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            if let message = state.message {
                Text(message)
                    .font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
            if state.showsFixSettings { row(.fixSettings, "Fix Settings…") }
            if state.showsFinishSetup { row(.finishSetup, "Finish Setup…") }
            if let download = state.download {
                VStack(alignment: .leading, spacing: 5) {
                    Text(download.text).font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                    ProgressView(value: download.fraction).progressViewStyle(.linear).controlSize(.small)
                        .accessibilityLabel(download.text)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            MenuDivider()
            if !state.recents.isEmpty {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.secondaryText)
                    .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(state.recents) { item in recentRow(item) }
                MenuDivider()
            }
            row(.undo, state.undoTitle, shortcut: "⌘Z", enabled: state.canUndo)
            if state.showsPauseResume {
                if state.isPaused {
                    row(.resume, "Resume")
                } else {
                    row(.pause, "Pause for 10 Minutes")
                }
            }
            if state.showsProcessExisting { row(.processExisting, "Process Existing Screenshots…") }
            MenuDivider()
            row(.search, "Search…", shortcut: state.searchShortcut)
            row(.settings, "Settings…", shortcut: "⌘,")
            MenuDivider()
            row(.about, "About Shotkeeper", shortcut: state.version)
            row(.quit, "Quit Shotkeeper", shortcut: "⌘Q")
        }
        .padding(5)
        .frame(width: Self.width)
        .background {
            if opaqueBackground { Color(nsColor: .windowBackgroundColor) }
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Self.color(for: state.status.dot))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.status.headline).font(.system(size: 13, weight: .semibold))
                Text(state.status.detail).font(.system(size: 12)).foregroundStyle(Brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.spokenDot(state.status.dot)). \(state.status.headline). \(state.status.detail)")
    }

    private func row(_ id: MenuRowID, _ title: String, shortcut: String? = nil, enabled: Bool = true) -> some View {
        MenuRowButton(id: id, highlight: highlight, enabled: enabled, action: { actions.perform(id, false) }) { highlighted in
            HStack(spacing: 8) {
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut).foregroundStyle(highlighted ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(Brand.secondaryText))
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(title)
    }

    private func recentRow(_ item: RecentItem) -> some View {
        MenuRowButton(id: .recent(item.id), highlight: highlight, enabled: true, height: 28,
                      action: { actions.perform(.recent(item.id), NSEvent.modifierFlags.contains(.option)) }) { highlighted in
            HStack(spacing: 8) {
                ThumbnailView(path: item.path, side: 22, cornerRadius: 4)
                Text(item.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 12)
                Text(state.time.short(item.date, now: state.now))
                    .foregroundStyle(highlighted ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(Brand.secondaryText))
            }
        }
        .accessibilityLabel(item.accessibilityLabel(now: state.now, time: state.time))
        .accessibilityHint("Opens the screenshot. Option-click reveals it in Finder.")
        .help("Open. ⌥-click to reveal in Finder.")
    }

    static func color(for dot: StatusDot) -> Color {
        switch dot {
        case .green: return Color(nsColor: .systemGreen)
        case .gray: return Color(nsColor: .systemGray)
        case .orange: return Color(nsColor: .systemOrange)
        case .red: return Color(nsColor: .systemRed)
        }
    }

    static func spokenDot(_ dot: StatusDot) -> String {
        switch dot {
        case .green: return "Working"
        case .gray: return "Paused"
        case .orange: return "Needs attention"
        case .red: return "Error"
        }
    }
}

/// A full-width menu row: highlighted (accent fill, white text) on hover or keyboard selection.
private struct MenuRowButton<Label: View>: View {
    let id: MenuRowID
    let highlight: MenuHighlight
    let enabled: Bool
    var height: CGFloat = 22
    let action: () -> Void
    @ViewBuilder let label: (_ highlighted: Bool) -> Label

    var body: some View {
        let highlighted = enabled && highlight.row == id
        Button(action: action) {
            label(highlighted)
                .font(.system(size: 13))
                .foregroundStyle(enabled ? (highlighted ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                                 : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { inside in
            if inside, enabled { highlight.row = id } else if !inside, highlight.row == id { highlight.row = nil }
        }
    }
}

private struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 10).padding(.vertical, 5)
    }
}

/// Live menu: rebuilds `MenuViewState` from the coordinator (observed) once a minute for the time labels.
struct MenuRootView: View {
    let coordinator: AppCoordinator
    let actions: MenuActions
    let highlight: MenuHighlight

    var body: some View {
        TimelineView(.everyMinute) { context in
            MenuContentView(state: .make(from: coordinator, now: context.date),
                            actions: actions, highlight: highlight)
        }
    }
}
