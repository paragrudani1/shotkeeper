import AppKit
import ShotkeeperCore
import SwiftUI

// The Source pill and its in-panel picker (design §4 "Source picker", §5 "Filter pills" and "Pickers"). Built on the
// date filter's `FilterPill`, `InPanelPicker` and `PickerRow`; wording and behaviour are core's (`SearchWindowState`,
// `SourcePickerState`).

/// The Source pill: at most 180 pt, the value truncated at the tail, the full name in the tooltip and VoiceOver value.
/// Disabled with a reason when no screenshot has a source.
struct SourceFilterPill: View {
    static let maxWidth: CGFloat = 180

    let model: SearchViewModel

    var body: some View {
        let state = model.state
        FilterPill(symbol: "macwindow", title: state.sourcePillTitle, isOn: state.source != nil,
                   isOpen: state.sourcePicker != nil, accessibilityName: "Source", accessibilityValue: state.sourcePillValue,
                   help: state.sourcePillHelp, clearName: "Clear source", clearHelp: "Clear the source",
                   toggle: { _ = model.toggleSourcePicker() }, clear: { model.clearSource() },
                   maxWidth: Self.maxWidth, isDisabled: state.sourcePillIsDisabled)
            .anchorPreference(key: FilterPillAnchorKey.self, value: .bounds) { [.source: $0] }
    }
}

/// The source picker (280 pt): a narrow field, then "Any source", a chosen source that is gone (count 0) and the list
/// with counts. Eight rows show, then it scrolls. The narrow field takes the focus while the picker is open and the
/// search field gets it back when it closes (design §6). The panel routes ↑/↓/↩/⌫/esc here
/// (`SearchPanelController.handleInSourcePicker`), and not while an input method is composing in the field.
struct SourcePickerPanel: View {
    static let width: CGFloat = 280
    static let visibleRows = 8

    let model: SearchViewModel
    let picker: SourcePickerState
    var opaqueBackground = false
    @FocusState private var narrowFocused: Bool

    var body: some View {
        InPanelPicker(width: Self.width, accessibilityName: "Source", opaqueBackground: opaqueBackground) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.secondaryText)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                TextField("Filter sources", text: Binding(get: { model.state.sourcePicker?.narrowText ?? "" },
                                                          set: { model.setSourceNarrowText($0) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($narrowFocused)
                    .accessibilityLabel("Filter sources")
            }
            .padding(.horizontal, 6)
            .frame(height: PickerRow.height)
            Divider().padding(.vertical, 4).padding(.horizontal, 6)
            if let message = picker.noMatchMessage {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 26)
                    .frame(maxWidth: .infinity, minHeight: PickerRow.height, alignment: .leading)
            } else {
                rows
            }
        }
        .onAppear { narrowFocused = true }
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(picker.rows.enumerated()), id: \.element.id) { index, row in
                        PickerRow(title: row.title, isCurrent: model.state.isCurrentSource(row),
                                  isHighlighted: index == picker.highlightedIndex, count: row.count,
                                  accessibilityLabel: row.accessibilityLabel,
                                  help: row == .anySource ? nil : row.title) {
                            model.chooseSource(row)
                        }
                        .id(row.id)
                    }
                }
            }
            .scrollIndicators(picker.rows.count > Self.visibleRows ? .automatic : .never)
            .frame(height: CGFloat(min(picker.rows.count, Self.visibleRows)) * PickerRow.height)
            .onChange(of: picker.highlightedIndex) { _, index in
                guard let index, picker.rows.indices.contains(index) else { return }
                proxy.scrollTo(picker.rows[index].id)  // no anchor: scrolls only as far as needed
            }
        }
    }
}
