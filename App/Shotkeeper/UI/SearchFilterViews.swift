import AppKit
import ShotkeeperCore
import SwiftUI

// The filter pills at the right end of row 2 and the in-panel pickers they open (design §2 layout A, picker A2; §4).
// Wording and behaviour are core's (`SearchWindowState`, `DatePickerState`); these views only draw them.

/// Where a filter pill is, so its picker can hang under it (right edges aligned, 6 pt below).
struct FilterPillAnchorKey: PreferenceKey {
    static var defaultValue: [SearchFilterKind: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [SearchFilterKind: Anchor<CGRect>], nextValue: () -> [SearchFilterKind: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The filters that have a pill and a picker.
enum SearchFilterKind: Hashable {
    case date, source
}

/// A filter pill: off, the chip style with the filter's name and a chevron; on, the selected-chip indigo with the
/// value and an ✕ that clears only this filter; open, a 2 pt focus ring; disabled, 40% opacity and no chevron, the
/// tooltip saying why (design §4 "Row 2"). A long value truncates at the tail within `maxWidth`.
struct FilterPill: View {
    let symbol: String
    let title: String
    let isOn: Bool
    let isOpen: Bool
    let accessibilityName: String
    let accessibilityValue: String
    let help: String
    let clearName: String
    let clearHelp: String
    let toggle: () -> Void
    let clear: () -> Void
    var maxWidth: CGFloat?
    var isDisabled = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Brand.secondaryText))
                    Text(title)
                        .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !isOn && !isDisabled {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Brand.secondaryText)
                    }
                }
                .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .padding(.leading, 10)
                .padding(.trailing, isOn ? 3 : 10)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue(accessibilityValue)
            .help(help)
            if isOn {
                Button(action: clear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 16, height: 16)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 5)
                .accessibilityLabel(clearName)
                .help(clearHelp)
            }
        }
        .frame(maxWidth: maxWidth)
        .background(Capsule().fill(isOn ? AnyShapeStyle(Brand.indigo) : AnyShapeStyle(Color.primary.opacity(0.07))))
        .opacity(isDisabled ? 0.4 : 1)
        // A disabled button shows no tooltip of its own; the pill's shape keeps the reason on hover.
        .contentShape(Capsule())
        .help(ifSet: isDisabled ? help : nil)
        .overlay {
            if isOpen {
                Capsule().strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2).padding(-2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The Date pill (design §5 "Filter pills").
struct DateFilterPill: View {
    let model: SearchViewModel

    var body: some View {
        let state = model.state
        FilterPill(symbol: "calendar", title: state.datePillTitle, isOn: state.date != nil,
                   isOpen: state.datePicker != nil, accessibilityName: "Date", accessibilityValue: state.datePillValue,
                   help: state.datePillHelp, clearName: "Clear date", clearHelp: "Clear the date",
                   toggle: { model.toggleDatePicker() }, clear: { model.clearDate() })
            .anchorPreference(key: FilterPillAnchorKey.self, value: .bounds) { [.date: $0] }
    }
}

/// A list drawn inside the search panel, under its pill: not a popover and not a window, so the panel keeps key
/// status (design §2, A2). Menu material, radius 10, menu shadow, 0.5 pt border. Snapshots draw it opaque.
struct InPanelPicker<Content: View>: View {
    let width: CGFloat
    let accessibilityName: String
    var opaqueBackground = false
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(5)
            .frame(width: width)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                if opaqueBackground {
                    shape.fill(colorScheme == .dark ? Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255) : .white)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityName)
    }
}

/// A picker row: 28 pt, 13 pt text, a check mark on the current value, the selection tint on the highlight, and an
/// optional count right-aligned in secondary text with tabular figures (source rows).
struct PickerRow: View {
    static let height: CGFloat = 28

    let title: String
    let isCurrent: Bool
    let isHighlighted: Bool
    var count: Int?
    /// VoiceOver label when it differs from the title ("Slack, 64 screenshots").
    var accessibilityLabel: String?
    /// Tooltip (the full name of a source that may be truncated).
    var help: String?
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.indigoText)
                    .opacity(isCurrent ? 1 : 0)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Brand.secondaryText)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: Self.height)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Brand.indigo.opacity(colorScheme == .dark ? 0.34 : 0.14))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .help(ifSet: help)
    }
}

/// The date picker (240 pt): Any time, the four presets, then "Custom range…", which expands in place to From, To
/// and Apply (design §4 "Date picker").
struct DatePickerPanel: View {
    static let width: CGFloat = 240

    let model: SearchViewModel
    let picker: DatePickerState
    var opaqueBackground = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case list, from, through }

    var body: some View {
        InPanelPicker(width: Self.width, accessibilityName: "Date", opaqueBackground: opaqueBackground) {
            ForEach(DatePickerOption.allCases.filter { $0 != .customRange }, id: \.self) { option in
                row(option, title: option.title)
            }
            Divider().padding(.vertical, 4).padding(.horizontal, 6)
            row(.customRange, title: picker.customTitle)
            if picker.showsCustomRange {
                customRange
            }
        }
        // The list takes the keyboard while it is open (the panel's key handler routes ↑/↓/↩/⌫/esc to it), so typed
        // letters don't edit the search text behind it. The search field gets the focus back when it closes.
        .focusable(!picker.showsCustomRange)
        .focusEffectDisabled()
        .focused($focus, equals: .list)
        .onAppear { focus = picker.showsCustomRange ? .from : .list }
        .onChange(of: picker.showsCustomRange) { _, shows in focus = shows ? .from : .list }
    }

    private func row(_ option: DatePickerOption, title: String) -> some View {
        PickerRow(title: title, isCurrent: model.state.currentDateOption == option,
                  isHighlighted: picker.highlighted == option && picker.takesArrowKeys) {
            model.chooseDate(option)
        }
    }

    private var customRange: some View {
        let calendar = model.time.calendar
        return VStack(alignment: .trailing, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("From").font(.system(size: 13)).foregroundStyle(Brand.secondaryText)
                    dayField("From", day: picker.from, focus: .from) {
                        model.setCustomRange(from: $0, through: picker.through)
                    }
                }
                GridRow {
                    Text("To").font(.system(size: 13)).foregroundStyle(Brand.secondaryText)
                    dayField("To", day: picker.through, focus: .through) {
                        model.setCustomRange(from: picker.from, through: $0)
                    }
                }
            }
            Button("Apply") { model.applyCustomRange() }
                .buttonStyle(BrandPrimaryButtonStyle())
                .help("Show screenshots from these days (↩)")
        }
        .padding(.leading, 26)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .environment(\.locale, model.time.locale)
    }

    /// A native `NSDatePicker` text field with stepper: type digits, ↑/↓ change the focused part, Tab moves on.
    private func dayField(_ label: String, day: CalendarDay, focus target: Focus,
                          set: @escaping (CalendarDay) -> Void) -> some View {
        let calendar = model.time.calendar
        return DatePicker(label, selection: Binding(get: { day.start(in: calendar) },
                                                    set: { set(CalendarDay($0, calendar: calendar)) }),
                          displayedComponents: .date)
            .datePickerStyle(.field)
            .labelsHidden()
            .focused($focus, equals: target)
            .accessibilityLabel(label)
    }
}

extension View {
    /// A tooltip only when there is text; no tooltip view at all otherwise (an empty one could cover a child's).
    @ViewBuilder
    func help(ifSet text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}
