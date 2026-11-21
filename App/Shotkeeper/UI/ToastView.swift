import AppKit
import Observation
import ShotkeeperCore
import SwiftUI

/// State the toast view renders. Owned by `ToastController`; snapshot tests build one directly.
@MainActor
@Observable
final class ToastModel {
    var content: ToastContent?
    var countdown: ToastCountdown?
    var isEditing = false
    /// The name being typed (stem, no extension).
    var editText = ""
    /// Shown under the field when a save failed ("That name cannot be used as a file name.").
    var editProblem: String?

    init(content: ToastContent? = nil, countdown: ToastCountdown? = nil) {
        self.content = content
        self.countdown = countdown
    }
}

/// What the toast's controls do. The controller supplies real ones; snapshots use `.none`.
struct ToastActions {
    var close: () -> Void
    var undo: () -> Void
    var beginEdit: () -> Void
    var saveEdit: () -> Void
    var cancelEdit: () -> Void
    var viewInSearch: () -> Void
    var fixSettings: () -> Void

    @MainActor static let none = ToastActions(close: {}, undo: {}, beginEdit: {}, saveEdit: {}, cancelEdit: {},
                                              viewInSearch: {}, fixSettings: {})
}

/// The rename toast (spec PR 1a): 308 pt wide; thumbnail, indigo label, name, "was:" line, close, buttons,
/// and a 3 pt indigo countdown bar. The material background and the shadow come from the panel (`ToastPanel`);
/// `opaqueBackground` draws a solid window background instead, for snapshots (offscreen rendering cannot show
/// behind-window blur).
struct ToastView: View {
    static let width: CGFloat = 308
    static let cornerRadius: CGFloat = 14

    @Bindable var model: ToastModel
    var actions: ToastActions
    var opaqueBackground = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let content = model.content {
                card(content)
                    .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
                    .overlay(alignment: .topTrailing) { closeButton.padding(8) }
                countdownBar
            }
        }
        .frame(width: Self.width)
        .background {
            if opaqueBackground { Color(nsColor: .windowBackgroundColor) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shotkeeper")
    }

    @ViewBuilder
    private func card(_ content: ToastContent) -> some View {
        switch content {
        case .renamed(let toast):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    ThumbnailView(path: toast.currentURL.path, side: 52, cornerRadius: 9)
                        .accessibilityLabel("Screenshot preview")
                    VStack(alignment: .leading, spacing: 3) {
                        brandLabel(toast.label, symbol: "sparkle").padding(.trailing, 22)
                        if model.isEditing {
                            TextField("Name", text: $model.editText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .semibold))
                                .focused($fieldFocused)
                                .onSubmit { actions.saveEdit() }
                                .accessibilityLabel("New name")
                                .onAppear { fieldFocused = true }
                            if let problem = model.editProblem {
                                Text(problem).font(.system(size: 11)).foregroundStyle(Color(nsColor: .systemRed))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(toast.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(toast.subline)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                if model.isEditing {
                    HStack(spacing: 8) {
                        Text("↩ Save · esc Cancel").font(.system(size: 11)).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        Button("Cancel", action: actions.cancelEdit).buttonStyle(PanelSecondaryButtonStyle())
                        Button("Save", action: actions.saveEdit).buttonStyle(BrandPrimaryButtonStyle())
                    }
                } else {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if toast.canUndo {
                            Button(toast.undoTitle, action: actions.undo).buttonStyle(PanelSecondaryButtonStyle())
                                .help("Restore the original name")
                        }
                        Button(toast.editTitle, action: actions.beginEdit).buttonStyle(PanelSecondaryButtonStyle())
                            .help("Type a different name")
                    }
                }
            }
        case .restored(let toast):
            HStack(alignment: .top, spacing: 12) {
                thumbnails(toast.restoredPaths, side: 52)
                VStack(alignment: .leading, spacing: 3) {
                    brandLabel(toast.label, symbol: "arrow.uturn.backward").padding(.trailing, 22)
                    Text(toast.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(toast.subline).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        case .batch(let toast):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    thumbnails(toast.thumbnailPaths, side: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(toast.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                            .padding(.trailing, 22)
                        if let subline = toast.subline {
                            Text(subline).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if toast.canUndo {
                        Button(toast.undoTitle, action: actions.undo).buttonStyle(PanelSecondaryButtonStyle())
                            .help("Restore the original names")
                    }
                    Button(toast.primaryTitle, action: actions.viewInSearch).buttonStyle(BrandPrimaryButtonStyle())
                        .help("Open Search")
                }
            }
        case .error(let toast):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .frame(width: 52, height: 52)
                        .accessibilityLabel("Warning")
                    Text(toast.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 18)
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                }
                if let fix = toast.fixTitle {
                    HStack {
                        Spacer(minLength: 0)
                        Button(fix, action: actions.fixSettings).buttonStyle(BrandPrimaryButtonStyle())
                    }
                }
            }
        }
    }

    private func brandLabel(_ text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Brand.indigoText)
    }

    /// One thumbnail, or a stack of up to three (back to front, offset like a fanned deck).
    @ViewBuilder
    private func thumbnails(_ paths: [String], side: CGFloat) -> some View {
        if paths.count <= 1 {
            ThumbnailView(path: paths.first ?? "", side: side, cornerRadius: 9)
                .accessibilityLabel("Screenshot preview")
        } else {
            let small: CGFloat = 40
            ZStack(alignment: .topLeading) {
                ForEach(Array(paths.suffix(3).enumerated()), id: \.offset) { offset, path in
                    ThumbnailView(path: path, side: small, cornerRadius: 7)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                        .offset(x: CGFloat(offset) * 6, y: CGFloat(offset) * 6)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .accessibilityElement()
            .accessibilityLabel("Screenshot previews")
        }
    }

    private var closeButton: some View {
        Button(action: actions.close) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .help("Close")
    }

    private var countdownBar: some View {
        let running = model.countdown?.isRunning ?? false
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Brand.indigo)
                    .frame(width: geometry.size.width * (model.countdown?.fraction(at: context.date) ?? 0))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
