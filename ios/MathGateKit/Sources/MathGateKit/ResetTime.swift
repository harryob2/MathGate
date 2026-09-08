import Foundation

/// The daily reset time. The "period" for a given instant starts at the most recent reset
/// (today's if it has passed, otherwise yesterday's) and ends at the next one.
///
/// Ported from the Android `ResetTime.kt`; the day arithmetic goes through `Calendar` so a
/// 23- or 25-hour DST day still produces exactly one period.
public struct ResetTime: Equatable, Codable, Sendable {
    public static let defaultHour = 4
    public static let defaultMinute = 0
    public static let `default` = ResetTime()

    public var hour: Int
    public var minute: Int

    public init(hour: Int = ResetTime.defaultHour, minute: Int = ResetTime.defaultMinute) {
        self.hour = hour
        self.minute = minute
    }

    public func normalized() -> ResetTime {
        ResetTime(hour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59))
    }

    public var label: String {
        let n = normalized()
        return String(format: "%02d:%02d", n.hour, n.minute)
    }

    public func currentPeriodStart(now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let todayReset = resetOnSameDay(as: now, calendar: calendar)
        guard now < todayReset else { return todayReset }
        return calendar.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset
    }

    public func nextReset(now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let todayReset = resetOnSameDay(as: now, calendar: calendar)
        guard now >= todayReset else { return todayReset }
        return calendar.date(byAdding: .day, value: 1, to: todayReset) ?? todayReset
    }

    private func resetOnSameDay(as date: Date, calendar: Calendar) -> Date {
        let n = normalized()
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = n.hour
        comps.minute = n.minute
        comps.second = 0
        comps.nanosecond = 0
        return calendar.date(from: comps) ?? date
    }
}
