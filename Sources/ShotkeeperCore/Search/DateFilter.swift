import Foundation

/// A day on the calendar (year, month, day), not an instant: the custom date range holds two of these, so the range
/// means the same days whatever the clock says.
public struct CalendarDay: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local day of `date` in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The first instant of this day in `calendar` (midnight, or the first hour that exists on a DST change day).
    public func start(in calendar: Calendar) -> Date {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        return calendar.startOfDay(for: noon)
    }

    /// The day `count` days after this one (before it when negative).
    public func adding(days count: Int, calendar: Calendar) -> CalendarDay {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        return CalendarDay(calendar.date(byAdding: .day, value: count, to: noon) ?? noon, calendar: calendar)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// The search window's date filter (spec "Filter model"): which days a screenshot was taken on. The query holds the
/// filter, not instants, so `SearchWindowState.query` stays the same while time passes; "today" is resolved again
/// each time a search runs (`interval(now:calendar:)`).
public enum DateFilter: Hashable, Sendable {
    case today
    case yesterday
    /// Today plus the 6 days before it.
    case last7Days
    /// Today plus the 29 days before it.
    case last30Days
    /// Both days included. A range whose end comes before its start is swapped.
    case days(from: CalendarDay, through: CalendarDay)

    /// The first and last day covered, in order.
    public func dayRange(now: Date, calendar: Calendar) -> ClosedRange<CalendarDay> {
        let today = CalendarDay(now, calendar: calendar)
        switch self {
        case .today: return today...today
        case .yesterday:
            let yesterday = today.adding(days: -1, calendar: calendar)
            return yesterday...yesterday
        case .last7Days: return today.adding(days: -6, calendar: calendar)...today
        case .last30Days: return today.adding(days: -29, calendar: calendar)...today
        case .days(let from, let through): return min(from, through)...max(from, through)
        }
    }

    /// Whole local days as a half-open interval `[start of the first day, start of the day after the last)`.
    public func interval(now: Date, calendar: Calendar) -> Range<Date> {
        let days = dayRange(now: now, calendar: calendar)
        return days.lowerBound.start(in: calendar)..<days.upperBound.adding(days: 1, calendar: calendar).start(in: calendar)
    }

    // MARK: Wording (design §5)

    /// The pill's value: "Today", "Yesterday", "Last 7 days", "Last 30 days", "Oct 3 – 17", "Oct 3".
    public func label(now: Date, time: TimeLabel) -> String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        case .days:
            let days = dayRange(now: now, calendar: time.calendar)
            return time.days(days.lowerBound, days.upperBound, now: now)
        }
    }

    /// The pill's VoiceOver value: "today", "last 7 days", "October 3 to October 17".
    public func spokenValue(now: Date, time: TimeLabel) -> String {
        switch self {
        case .today, .yesterday, .last7Days, .last30Days:
            return label(now: now, time: time).lowercased()
        case .days:
            let days = dayRange(now: now, calendar: time.calendar)
            let first = time.days(days.lowerBound, days.lowerBound, now: now, spelled: true)
            guard days.lowerBound != days.upperBound else { return first }
            return "\(first) to \(time.days(days.upperBound, days.upperBound, now: now, spelled: true))"
        }
    }

    /// The date part of a no-match sentence: "taken today", "taken in the last 7 days", "taken on Oct 3",
    /// "taken between Oct 3 and Oct 17".
    public func takenPhrase(now: Date, time: TimeLabel) -> String {
        switch self {
        case .today: return "taken today"
        case .yesterday: return "taken yesterday"
        case .last7Days: return "taken in the last 7 days"
        case .last30Days: return "taken in the last 30 days"
        case .days:
            let days = dayRange(now: now, calendar: time.calendar)
            let first = time.day(days.lowerBound, now: now, alongside: days.upperBound)
            guard days.lowerBound != days.upperBound else { return "taken on \(first)" }
            return "taken between \(first) and \(time.day(days.upperBound, now: now, alongside: days.lowerBound))"
        }
    }
}
