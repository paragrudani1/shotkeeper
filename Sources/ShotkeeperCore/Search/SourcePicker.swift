import Foundation

/// A row of the in-panel source picker (design §4, "Source picker").
public enum SourcePickerRow: Hashable, Sendable, Identifiable {
    /// "Any source": clears the filter.
    case anySource
    /// A source with its count over the whole index (0 for a chosen source that has no rows left).
    case source(SourceFacet)

    public var id: SourceKey? {
        if case .source(let facet) = self { return facet.key }
        return nil
    }

    public var title: String {
        switch self {
        case .anySource: return "Any source"
        case .source(let facet): return facet.displayName
        }
    }

    /// The right-aligned count; nil for "Any source".
    public var count: Int? {
        if case .source(let facet) = self { return facet.count }
        return nil
    }

    /// VoiceOver: "Slack, 64 screenshots" (design §5, "Pickers").
    public var accessibilityLabel: String {
        switch self {
        case .anySource: return title
        case .source(let facet): return "\(facet.displayName), \(MenuText.screenshots(facet.count))"
        }
    }
}

/// The open source picker: what is typed in its narrow field, the rows that match, and the keyboard highlight.
/// `SearchWindowState.sourcePicker` is nil while it is closed. The app draws it inside the panel, like the date picker.
public struct SourcePickerState: Equatable, Sendable {
    /// The narrow field's text.
    public internal(set) var narrowText = ""
    /// Without narrowing: "Any source", a chosen source that is gone (count 0), then the list. While narrowing: the
    /// sources whose name contains the folded text, in list order.
    public internal(set) var rows: [SourcePickerRow] = []
    /// The row ↑/↓ move and ↩ chooses; nil when nothing matches.
    public internal(set) var highlightedIndex: Int?

    public var highlighted: SourcePickerRow? {
        highlightedIndex.flatMap { rows.indices.contains($0) ? rows[$0] : nil }
    }

    /// "No source matches “zz”" when the narrow field matches nothing; else nil.
    public var noMatchMessage: String? {
        rows.isEmpty ? "No source matches “\(narrowText.trimmingCharacters(in: .whitespacesAndNewlines))”" : nil
    }

    /// ⌫ clears the source only when the narrow field is empty; otherwise it deletes in the field.
    public var deleteClearsSource: Bool { narrowText.isEmpty }
}

extension SearchWindowState {
    /// Why the Source pill is disabled (its tooltip and VoiceOver value).
    public static let sourceDisabledReason = "No screenshot has an app or site yet."

    // MARK: Source pill (design §5, "Filter pills")

    /// "Source" when off, else the chosen source's name (the view truncates it at 180 pt).
    public var sourcePillTitle: String { sourceName ?? "Source" }

    /// VoiceOver value: "any source", the full name, or why the pill is disabled. The label is "Source".
    public var sourcePillValue: String {
        sourcePillIsDisabled ? Self.sourceDisabledReason : sourceName ?? "any source"
    }

    public var sourcePillHelp: String {
        if sourcePillIsDisabled { return Self.sourceDisabledReason }
        return sourceName.map { "\($0). Change the source (⌘S)" } ?? "Filter by app or site (⌘S)"
    }

    /// The loaded list is empty (empty index, or no row has a source) and no source is chosen. Never disabled before
    /// the list has loaded, nor while a source is chosen (it can always be cleared).
    public var sourcePillIsDisabled: Bool { source == nil && sources?.isEmpty == true }

    // MARK: Pickers

    /// The date or the source picker is open.
    public var isPickerOpen: Bool { datePicker != nil || sourcePicker != nil }

    /// Closes any open picker without a change (Esc, a click outside it, the panel hiding).
    public mutating func closePickers() {
        datePicker = nil
        sourcePicker = nil
    }

    /// The row with the check mark.
    public func isCurrentSource(_ row: SourcePickerRow) -> Bool {
        row.id == source
    }

    // MARK: Source picker (design §4 "Source picker", §6 keys)

    /// ⌘S or a click on the Source pill: opens the picker (closing the date picker) with the current source
    /// highlighted, or closes it. Returns false when the pill is disabled and nothing opened: the app beeps.
    @discardableResult
    public mutating func toggleSourcePicker() -> Bool {
        if sourcePicker != nil {
            sourcePicker = nil
            return true
        }
        guard !sourcePillIsDisabled else { return false }
        datePicker = nil
        var picker = SourcePickerState()
        picker.rows = sourcePickerRows(matching: "")
        picker.highlightedIndex = picker.rows.firstIndex { isCurrentSource($0) } ?? 0
        sourcePicker = picker
        return true
    }

    public mutating func closeSourcePicker() {
        sourcePicker = nil
    }

    /// Typing in the narrow field: narrows by a folded substring match on the name, and highlights the first match,
    /// so "sl ↩" picks Slack.
    public mutating func setSourceNarrowText(_ text: String) {
        guard var picker = sourcePicker, picker.narrowText != text else { return }
        picker.narrowText = text
        picker.rows = sourcePickerRows(matching: text)
        picker.highlightedIndex = picker.rows.isEmpty ? nil : 0
        sourcePicker = picker
    }

    /// ↑/↓ in the picker, clamped to its rows.
    public mutating func moveSourceHighlight(by delta: Int) {
        guard let picker = sourcePicker, !picker.rows.isEmpty else { return }
        let current = picker.highlightedIndex ?? (delta > 0 ? -1 : picker.rows.count)
        sourcePicker?.highlightedIndex = min(max(current + delta, 0), picker.rows.count - 1)
    }

    /// ↩: chooses the highlighted row. Nothing happens when nothing matches (the picker stays open).
    @discardableResult
    public mutating func chooseHighlightedSource() -> Bool {
        guard let row = sourcePicker?.highlighted else { return false }
        return chooseSource(row)
    }

    /// A row was chosen (click or ↩): sets the source and closes the picker. Returns true when a search must run.
    @discardableResult
    public mutating func chooseSource(_ row: SourcePickerRow) -> Bool {
        guard sourcePicker != nil else { return false }
        sourcePicker = nil
        switch row {
        case .anySource: return setSource(nil)
        case .source(let facet): return setSource(facet)
        }
    }

    /// ⌫ in the picker with an empty narrow field: clears the source and closes the picker (⌘S ⌫).
    @discardableResult
    public mutating func clearSourceFromPicker() -> Bool {
        sourcePicker = nil
        return setSource(nil)
    }

    /// The picker's rows for `text` (see `SourcePickerState.rows`).
    func sourcePickerRows(matching text: String) -> [SourcePickerRow] {
        let list = sources ?? []
        var facets = list
        if let source, let sourceName, !list.contains(where: { $0.key == source }) {
            facets.insert(SourceFacet(key: source, displayName: sourceName, count: 0), at: 0)  // gone: pinned, count 0
        }
        let needle = SourceKey.fold(text)
        guard !needle.isEmpty else { return [.anySource] + facets.map(SourcePickerRow.source) }
        return facets.filter { SourceKey.fold($0.displayName).contains(needle) }.map(SourcePickerRow.source)
    }

    /// The list reloaded while the picker is open: rebuild its rows, keeping the highlighted row when it is still there.
    mutating func refreshSourcePicker() {
        guard var picker = sourcePicker else { return }
        let highlighted = picker.highlighted
        picker.rows = sourcePickerRows(matching: picker.narrowText)
        picker.highlightedIndex = highlighted.flatMap { old in picker.rows.firstIndex { $0.id == old.id } }
            ?? (picker.rows.isEmpty ? nil : 0)
        sourcePicker = picker
    }
}
