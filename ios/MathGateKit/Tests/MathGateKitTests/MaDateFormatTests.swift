import XCTest
@testable import MathGateKit

final class MaDateFormatTests: XCTestCase {
    private func london() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h; comps.minute = mi; comps.second = s
        return london().date(from: comps)!
    }

    func testMatchesJavaScriptDateToString() {
        // 3 September 2026 was a Thursday.
        let d = date(2026, 9, 3, 11, 30, 0)
        XCTAssertEqual(
            MaDateFormat.format(d, calendar: london()),
            "Thu Sep 03 2026 11:30:00 GMT-0800 (Pacific Standard Time)"
        )
    }

    func testSingleDigitDayIsZeroPadded() {
        let d = date(2026, 1, 5, 9, 5, 7)
        XCTAssertEqual(
            MaDateFormat.format(d, calendar: london()),
            "Mon Jan 05 2026 09:05:07 GMT-0800 (Pacific Standard Time)"
        )
    }

    func testPathSegmentEscapesLikeEncodeURIComponent() {
        let seg = MaDateFormat.pathSegment(date(2026, 9, 3, 11, 30, 0), calendar: london())
        XCTAssertEqual(
            seg,
            "Thu%20Sep%2003%202026%2011%3A30%3A00%20GMT-0800%20(Pacific%20Standard%20Time)"
        )
        XCTAssertFalse(seg.contains("+"), "encodeURIComponent uses %20, never +")
    }

    func testEncodeURIComponentKeepsUnreservedMarks() {
        XCTAssertEqual(MaDateFormat.encodeURIComponent("a-b_c.d!e~f*g'h(i)j"), "a-b_c.d!e~f*g'h(i)j")
        XCTAssertEqual(MaDateFormat.encodeURIComponent("a b&c=d"), "a%20b%26c%3Dd")
    }
}
