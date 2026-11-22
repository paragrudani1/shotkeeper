import AppKit
import ShotkeeperCore
import SwiftUI

/// What the search window's controls do. The panel controller supplies real ones; snapshots use `.none`.
struct SearchViewActions {
    var open: (URL) -> Void
    var copy: (URL) -> Void
    var reveal: (URL) -> Void
    var quickLook: () -> Void
    var processExisting: () -> Void

    @MainActor static let none = SearchViewActions(open: { _ in }, copy: { _ in }, reveal: { _ in }, quickLook: {},
                                                   processExisting: {})
}

/// The search window (spec PR 2): 880×540, radius 16. Row 1 field, row 2 type chips, a 330 pt list and a preview,
/// a 36 pt footer with key hints. The material and the shadow come from the panel; `opaqueBackground` draws the
/// window background instead, for snapshots (offscreen rendering cannot show behind-window blur).
struct SearchView: View {
    static let size = CGSize(width: 880, height: 540)
    static let cornerRadius: CGFloat = 16
    static let listWidth: CGFloat = 330

    let model: SearchViewModel
    var actions: SearchViewActions
    var opaqueBackground = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            chipRow
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if opaqueBackground { Color(nsColor: .windowBackgroundColor) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .onAppear { fieldFocused = true }
        .onChange(of: model.focusRequest) { _, _ in fieldFocused = true }
    }

    // MARK: Rows 1 and 2

    private var searchRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search screenshots by what is in them",
                      text: Binding(get: { model.state.text }, set: { model.setText($0) }))
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($fieldFocused)
                .accessibilityLabel("Search screenshots")
            if model.state.showsClearButton {
                Button {
                    model.setText("")
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(SearchChip.allCases, id: \.self) { chip in
                let selected = model.state.chip == chip
                Button(chip.title) { model.selectChip(chip) }
                    .buttonStyle(SearchChipStyle(isSelected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .help(chip.help)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type")
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch model.state.phase {
        case .loading:
            Color.clear
        case .results:
            HStack(spacing: 0) {
                SearchResultList(model: model, actions: actions)
                    .frame(width: Self.listWidth)
                Divider()
                if let item = model.selected {
                    SearchPreview(item: item, model: model, actions: actions)
                } else {
                    Color.clear
                }
            }
        case .noMatch(let message):
            SearchMessageView(symbol: "magnifyingglass", tint: .secondary, title: message.title, message: message.message) {
                Button("Clear search") { model.clearSearch() }
                    .buttonStyle(PanelSecondaryButtonStyle())
                    .help("Clear the search text and the type")
            }
        case .emptyIndex:
            SearchMessageView(symbol: "viewfinder", tint: Brand.indigo, title: "No screenshots yet",
                              message: "Take a screenshot with ⌘⇧4. Shotkeeper gives it a name from its content, and it shows up here in a few seconds.") {
                Button("Process Existing Screenshots…", action: actions.processExisting)
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .help("Name and index the screenshots already in the watched folder")
            }
        case .error(let message):
            SearchMessageView(symbol: "exclamationmark.triangle", tint: Color(nsColor: .systemOrange),
                              title: message.title, message: message.message) { EmptyView() }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Text(model.state.footerText)
                .font(.system(size: 12))
                .foregroundStyle(Brand.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            KeyHint(keys: "↑↓", label: "Select", spoken: "Up or Down Arrow")
            KeyHint(keys: "↩", label: "Open", spoken: "Return")
            KeyHint(keys: "Space", label: "Quick Look", spoken: "Space")
            KeyHint(keys: "⌘C", label: "Copy", spoken: "Command C")
            KeyHint(keys: "esc", label: "Close", spoken: "Escape")
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }
}

/// Type chip: the selected one is filled indigo with white text; the others have a light neutral fill.
struct SearchChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.primary))
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(Capsule().fill(isSelected ? AnyShapeStyle(Brand.indigo)
                                                  : AnyShapeStyle(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07))))
            .contentShape(Capsule())
    }
}

/// A keycap and its action in the footer ("⌘C Copy").
struct KeyHint: View {
    let keys: String
    let label: String
    let spoken: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.secondaryText)
                .padding(.horizontal, 5)
                .frame(minWidth: 20, minHeight: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Brand.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spoken): \(label)")
    }
}

/// Centered icon, title, text and an optional button (no match, empty index, error).
struct SearchMessageView<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(tint)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Brand.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            accessory().padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - List

struct SearchResultList: View {
    let model: SearchViewModel
    let actions: SearchViewActions

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.state.items.enumerated()), id: \.element.id) { offset, item in
                        SearchResultRow(item: item, isSelected: offset == model.state.selectedIndex,
                                        now: model.now(), time: model.time) { clickCount in
                            // AppKit clicks: select on the first mouse-down (no double-click delay), open on the second.
                            if clickCount >= 2 { actions.open(URL(fileURLWithPath: item.path)) } else { model.select(offset) }
                        }
                        .id(item.id)
                        .accessibilityAction { model.select(offset) }
                        .accessibilityAction(named: "Open") { actions.open(URL(fileURLWithPath: item.path)) }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.state.selected?.id) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)  // no anchor: scrolls only as far as needed
            }
        }
        .accessibilityLabel("Results")
    }
}

struct SearchResultRow: View {
    let item: SearchResultItem
    let isSelected: Bool
    let now: Date
    let time: TimeLabel
    /// Mouse-down on the row with its click count (1 = select, 2 = open).
    var onMouseDown: (Int) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.thumbnailSource) private var thumbnails

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(path: item.path, side: 44, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.subtitle(now: now, time: time))
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.indigo.opacity(colorScheme == .dark ? 0.34 : 0.14))
            }
        }
        .overlay {
            FileDragArea(path: item.path, dragImage: { thumbnails.cached(item.path, 44) }, onMouseDown: onMouseDown)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel(now: now, time: time))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Preview

struct SearchPreview: View {
    let item: SearchResultItem
    let model: SearchViewModel
    let actions: SearchViewActions

    private var url: URL { URL(fileURLWithPath: item.path) }

    var body: some View {
        // Height budget (540 window): the body is ~410 pt; image 220 + title + a 2-line description + tags + the
        // metadata grid + the buttons fit without scrolling. Longer text scrolls; the buttons stay put.
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    PreviewImageView(path: item.path, title: item.title, pill: model.pill,
                                     onDoubleClick: { actions.open(url) })
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let description = item.description {
                            Text(description)
                                .font(.system(size: 13))
                                .foregroundStyle(Brand.secondaryText)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !item.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(item.tags, id: \.self) { tag in
                                Button("#\(tag)") { model.clickTag(tag) }
                                    .buttonStyle(TagChipStyle())
                                    .accessibilityLabel("Tag \(tag)")
                                    .help("Search for #\(tag)")
                            }
                        }
                    }
                    metadataGrid
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                Button("Open") { actions.open(url) }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .help("Open in the default app (↩)")
                Button("Copy Image") { actions.copy(url) }
                    .buttonStyle(PanelSecondaryButtonStyle())
                    .help("Copy the image (⌘C)")
                Button("Reveal in Finder") { actions.reveal(url) }
                    .buttonStyle(PanelSecondaryButtonStyle())
                    .help("Show the file in Finder (⌘R)")
                Button("Quick Look", action: actions.quickLook)
                    .buttonStyle(PanelSecondaryButtonStyle())
                    .help("Preview with Quick Look (Space)")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 2) {
            let rows = item.metadata(time: model.time)
            GridRow {
                ForEach(rows, id: \.label) { row in
                    Text(row.label).font(.system(size: 11)).foregroundStyle(Brand.secondaryText)
                }
            }
            GridRow {
                ForEach(rows, id: \.label) { row in
                    Text(row.value).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        .accessibilityLabel("\(row.label): \(row.value)")
                }
            }
        }
    }
}

/// "#tag": indigo text on a light indigo fill.
struct TagChipStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Brand.indigoText)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Brand.indigo.opacity((colorScheme == .dark ? 0.22 : 0.12)
                                                              + (configuration.isPressed ? 0.1 : 0))))
            .contentShape(Capsule())
    }
}

/// The large preview: 220 pt tall, aspect fit, radius 12, thin border, and the "✓ Copied" pill.
struct PreviewImageView: View {
    static let height: CGFloat = 220
    /// Longest side requested from QuickLook (points); the image is scaled to fit.
    static let requestSide: CGFloat = 640

    let path: String
    let title: String
    let pill: SearchPill?
    var onDoubleClick: () -> Void = {}
    @Environment(\.thumbnailSource) private var source
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (path: String, image: NSImage)?

    var body: some View {
        let image = loaded?.path == path ? loaded?.image : source.cached(path, Self.requestSide)
        ZStack {
            Color.primary.opacity(0.04)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(.tertiary)
            }
            switch pill {
            case .copied?:
                pillLabel("Copied", symbol: "checkmark")
            case .problem(let message)?:
                pillLabel(message, symbol: "exclamationmark.triangle.fill")
            case nil:
                EmptyView()
            }
        }
        .overlay {
            FileDragArea(path: path, dragImage: { loadedImage }, onMouseDown: { if $0 >= 2 { onDoubleClick() } })
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.15), value: pill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(title)")
        .accessibilityAddTraits(.isImage)
        .task(id: path) {
            guard source.cached(path, Self.requestSide) == nil else { return }
            if let image = await source.load(path, Self.requestSide, displayScale) { loaded = (path, image) }
        }
    }

    private var loadedImage: NSImage? {
        loaded?.path == path ? loaded?.image : source.cached(path, Self.requestSide)
    }

    /// "✓ Copied", or a short problem ("This file is no longer there…"). Announced by the controller, so hidden here.
    private func pillLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .padding(.horizontal, 24)
            .transition(.opacity)
            .accessibilityHidden(true)
    }
}

/// A transparent AppKit view over a result (row or preview image) that drags the file and reports clicks.
/// The drag puts `public.file-url` on the pasteboard (an `NSURL` writer), which Finder, Mail, Slack and browsers accept;
/// a SwiftUI `NSItemProvider(contentsOf:)` becomes a file promise, which Slack and Chrome often refuse. The only
/// operation offered is `.copy`, whatever modifier keys are held, so Finder never moves the user's file.
struct FileDragArea: NSViewRepresentable {
    let path: String
    var dragImage: () -> NSImage?
    var onMouseDown: (Int) -> Void

    func makeNSView(context: Context) -> FileDragView {
        let view = FileDragView()
        view.setAccessibilityElement(false)  // the SwiftUI element above carries the label and actions
        return view
    }

    func updateNSView(_ view: FileDragView, context: Context) {
        view.path = path
        view.dragImage = dragImage
        view.onMouseDown = onMouseDown
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var path = ""
    var dragImage: () -> NSImage? = { nil }
    var onMouseDown: (Int) -> Void = { _ in }
    private var mouseDownLocation: NSPoint?
    /// Points the mouse must move with the button down before a drag starts.
    static let dragThreshold: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        onMouseDown(event.clickCount)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let location = event.locationInWindow
        guard hypot(location.x - start.x, location.y - start.y) >= Self.dragThreshold else { return }
        mouseDownLocation = nil
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = dragImage() ?? NSWorkspace.shared.icon(forFile: path)
        let side: CGFloat = 64
        let point = convert(location, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
                              contents: image)
        beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    nonisolated func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

/// Wraps children onto new lines (tag chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
