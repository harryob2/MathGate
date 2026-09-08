import Foundation

/// Math Academy's `/api/previous-tasks/{date}` expects the JavaScript `Date.toString()` shape,
/// e.g. `Thu Sep 03 2026 11:30:00 GMT-0800 (Pacific Standard Time)`, encoded the way
/// `encodeURIComponent` does it. The PST label is fixed regardless of the caller's zone; this
/// mirrors the community mathacademy-stats extension, which is known to work.
public enum MaDateFormat {
    private static let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// `date` is read in `calendar`'s time zone, so the wall-clock components match the user's day.
    public static func format(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let c = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday], from: date
        )
        // Calendar.weekday is 1 = Sunday, matching the array above.
        let dow = days[(c.weekday ?? 1) - 1]
        let month = months[(c.month ?? 1) - 1]
        return String(
            format: "%@ %@ %02d %d %02d:%02d:%02d GMT-0800 (Pacific Standard Time)",
            dow, month, c.day ?? 1, c.year ?? 1970, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    public static func pathSegment(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        encodeURIComponent(format(date, calendar: calendar))
    }

    /// Matches JavaScript's `encodeURIComponent`: everything escaped except these unreserved marks.
    public static func encodeURIComponent(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
