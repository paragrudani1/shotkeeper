import Foundation

/// A row of the in-panel date picker (design §4, "Date picker"), top to bottom.
public enum DatePickerOption: CaseIterable, Hashable, Sendable {
    case anyTime, today, yesterday, last7Days, last30Days, customRange

    public var title: String {
        switch self {
        case .anyTime: return "Any time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        case .customRange: return "Custom range…"
        }
    }

    /// The row that shows `filter` as current (the check mark).
    public init(_ filter: DateFilter?) {
        switch filter {
        case nil: self = .anyTime
        case .today?: self = .today
        case .yesterday?: self = .yesterday
        case .last7Days?: self = .last7Days
        case .last30Days?: self = .last30Days
        case .days?: self = .customRange
        }
    }

    /// The preset this row chooses; nil for "Any time" and for "Custom range…" (which expands instead).
    var preset: DateFilter? {
        switch self {
        case .anyTime, .customRange: return nil
        case .today: return .today
        case .yesterday: return .yesterday
        case .last7Days: return .last7Days
        case .last30Days: return .last30Days
        }
    }
}

/// The open date picker: the keyboard highlight and the custom range being edited. `SearchWindowState.datePicker` is
/// nil while it is closed. The app draws it inside the panel (not a popover or a window), so the panel stays key.
public struct DatePickerState: Equatable, Sendable {
    /// The row ↑/↓ move and ↩ chooses.
    public internal(set) var highlighted: DatePickerOption
    /// "Custom range…" was chosen: the From and To fields and Apply are shown.
    public internal(set) var showsCustomRange: Bool
    /// The custom range fields. They start at the current custom range, else at the last 7 days (6 days ago to today).
    public internal(set) var from: CalendarDay
    public internal(set) var through: CalendarDay

    /// The picker as it opens, for `today` and the current filter.
    public init(today: CalendarDay, current: DateFilter?, calendar: Calendar = Calendar(identifier: .gregorian)) {
        highlighted = DatePickerOption(current)
        if case .days(let from, let through)? = current {
            showsCustomRange = true
            self.from = from
            self.through = through
        } else {
            showsCustomRange = false
            from = today.adding(days: -6, calendar: calendar)
            through = today
        }
    }

    /// The last row's text: "Custom range…" until it is expanded, then "Custom range".
    public var customTitle: String {
        showsCustomRange ? "Custom range" : DatePickerOption.customRange.title
    }

    /// ↑/↓ move the highlight in the list. While the custom range is shown they belong to the focused date field.
    public var takesArrowKeys: Bool { !showsCustomRange }
}

extension SearchWindowState {
    /// ⌘D or a click on the Date pill: opens the picker on the current value, or closes it.
    public mutating func toggleDatePicker() {
        if datePicker != nil {
            datePicker = nil
        } else {
            datePicker = DatePickerState(today: CalendarDay(now, calendar: time.calendar), current: date,
                                         calendar: time.calendar)
        }
    }

    /// Closes the picker without a change (Esc, a click outside it).
    public mutating func closeDatePicker() {
        datePicker = nil
    }

    /// The row with the check mark.
    public var currentDateOption: DatePickerOption { DatePickerOption(date) }

    /// ↑/↓ in the list, clamped to its rows.
    public mutating func moveDateHighlight(by delta: Int) {
        guard let picker = datePicker else { return }
        let options = DatePickerOption.allCases
        let index = options.firstIndex(of: picker.highlighted) ?? 0
        datePicker?.highlighted = options[min(max(index + delta, 0), options.count - 1)]
    }

    /// ↩: Apply while the custom range is shown, else the highlighted row. Returns true when a search must run.
    @discardableResult
    public mutating func chooseHighlightedDate() -> Bool {
        guard let picker = datePicker else { return false }
        return picker.showsCustomRange ? applyCustomRange() : chooseDate(picker.highlighted)
    }

    /// A row was chosen (click or ↩). "Custom range…" expands the picker in place; every other row sets the filter
    /// and closes the picker. Returns true when a search must run.
    @discardableResult
    public mutating func chooseDate(_ option: DatePickerOption) -> Bool {
        guard datePicker != nil else { return false }
        if option == .customRange {
            datePicker?.highlighted = .customRange
            datePicker?.showsCustomRange = true
            return false
        }
        datePicker = nil
        return setDateFilter(option.preset)
    }

    /// The From and To fields changed (not applied yet).
    public mutating func setCustomRange(from: CalendarDay, through: CalendarDay) {
        datePicker?.from = from
        datePicker?.through = through
    }

    /// "Apply": the custom range becomes the filter (a reversed range is swapped when it is resolved).
    @discardableResult
    public mutating func applyCustomRange() -> Bool {
        guard let picker = datePicker else { return false }
        datePicker = nil
        return setDateFilter(.days(from: picker.from, through: picker.through))
    }

    /// ⌫ in the date list: clears the date and closes the picker.
    @discardableResult
    public mutating func clearDateFromPicker() -> Bool {
        datePicker = nil
        return setDateFilter(nil)
    }
}
