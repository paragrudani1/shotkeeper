import Foundation

/// Times for the menu's recent rows and their VoiceOver names. Clock, calendar and locale are injected so tests
/// are deterministic. Words ("Yesterday", "today") are English like the rest of the UI; times and dates follow
/// `locale` ("4:24 PM" in en_US, "16:24" in de_DE).
public struct TimeLabel: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    /// Visible label: "4:24 PM" (today), "Yesterday", "Mon" (this past week), "Nov 14" (this year), "Nov 14, 2025".
    public func short(_ date: Date, now: Date) -> String {
        switch day(of: date, now: now) {
        case .today: return format(date, template: "jmm")
        case .yesterday: return "Yesterday"
        case .thisWeek: return format(date, template: "EEE")
        case .thisYear: return format(date, template: "MMMd")
        case .older: return format(date, template: "yMMMd")
        }
    }

    /// Spoken form with the time always included: "today 4:24 PM", "yesterday 9:05 AM", "Monday 4:24 PM",
    /// "November 14 4:24 PM", "November 14, 2025 4:24 PM".
    public func spoken(_ date: Date, now: Date) -> String {
        let time = format(date, template: "jmm")
        switch day(of: date, now: now) {
        case .today: return "today \(time)"
        case .yesterday: return "yesterday \(time)"
        case .thisWeek: return "\(format(date, template: "EEEE")) \(time)"
        case .thisYear: return "\(format(date, template: "MMMMd")) \(time)"
        case .older: return "\(format(date, template: "yMMMMd")) \(time)"
        }
    }

    /// Time only ("3:42 PM"), or date and time when `date` is not today ("Nov 22, 3:42 PM").
    public func timeOrDateTime(_ date: Date, now: Date) -> String {
        calendar.isDate(date, inSameDayAs: now) ? format(date, template: "jmm") : format(date, template: "MMMdjmm")
    }

    private enum Day { case today, yesterday, thisWeek, thisYear, older }

    private func day(of date: Date, now: Date) -> Day {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        // Dates in the future (clock changes) are treated by calendar day like any other.
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        if days <= 0 { return calendar.isDate(date, inSameDayAs: now) ? .today : .thisYear }
        if days == 1 { return .yesterday }
        if days < 7 { return .thisWeek }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) { return .thisYear }
        return .older
    }

    private func format(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
