import XCTest
@testable import MathGateKit

final class ResetTimeTests: XCTestCase {
    private func london() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }

    private func date(_ iso: String, _ cal: Calendar) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    func testDefaultIsFourAM() {
        XCTAssertEqual(ResetTime.default.hour, 4)
        XCTAssertEqual(ResetTime.default.minute, 0)
        XCTAssertEqual(ResetTime.default.label, "04:00")
    }

    func testOutOfRangeValuesAreClamped() {
        XCTAssertEqual(ResetTime(hour: 99, minute: -3).normalized(), ResetTime(hour: 23, minute: 0))
        XCTAssertEqual(ResetTime(hour: -1, minute: 90).normalized(), ResetTime(hour: 0, minute: 59))
    }

    func testJustBeforeResetBelongsToYesterdaysPeriod() {
        let cal = london()
        let now = date("2026-09-03 03:59:00", cal)
        XCTAssertEqual(
            ResetTime.default.currentPeriodStart(now: now, calendar: cal),
            date("2026-09-02 04:00:00", cal)
        )
        XCTAssertEqual(
            ResetTime.default.nextReset(now: now, calendar: cal),
            date("2026-09-03 04:00:00", cal)
        )
    }

    func testAtResetTheNewPeriodStarts() {
        let cal = london()
        let now = date("2026-09-03 04:00:00", cal)
        XCTAssertEqual(
            ResetTime.default.currentPeriodStart(now: now, calendar: cal),
            date("2026-09-03 04:00:00", cal)
        )
        XCTAssertEqual(
            ResetTime.default.nextReset(now: now, calendar: cal),
            date("2026-09-04 04:00:00", cal)
        )
    }

    /// British Summer Time ends on 25 October 2026, making that a 25-hour day. The period must
    /// still be exactly one day of wall-clock time, not 24 fixed hours.
    func testPeriodSpansTheTwentyFiveHourDSTDay() {
        let cal = london()
        let now = date("2026-10-25 12:00:00", cal)
        let start = ResetTime.default.currentPeriodStart(now: now, calendar: cal)
        let next = ResetTime.default.nextReset(now: now, calendar: cal)
        XCTAssertEqual(start, date("2026-10-25 04:00:00", cal))
        XCTAssertEqual(next, date("2026-10-26 04:00:00", cal))
        XCTAssertEqual(next.timeIntervalSince(start), 24 * 3600, "clocks go back after 04:00 that day")
    }

    func testCustomResetTime() {
        let cal = london()
        let reset = ResetTime(hour: 22, minute: 30)
        let now = date("2026-09-03 22:29:59", cal)
        XCTAssertEqual(reset.currentPeriodStart(now: now, calendar: cal), date("2026-09-02 22:30:00", cal))
        XCTAssertEqual(reset.nextReset(now: now, calendar: cal), date("2026-09-03 22:30:00", cal))
    }
}
