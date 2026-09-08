import XCTest
@testable import MathGateKit

/// Pins the one piece of `URLSession` behaviour the client leans on: repeated `Set-Cookie`
/// headers arrive folded into a single comma-separated string, and the `expires` value contains
/// a comma of its own. Getting this wrong loses the session silently.
final class CookieParsingTests: XCTestCase {
    private let folded = [
        "Content-Type": "text/html; charset=utf-8",
        "Set-Cookie": "session=SESSION-VALUE; path=/; expires=Sat, 03 Oct 2026 10:30:42 GMT; secure; httponly,"
            + " session.sig=SIG-VALUE; path=/; expires=Sat, 03 Oct 2026 10:30:42 GMT; secure; httponly",
    ]

    func testFoldedSecureHeaderYieldsBothCookies() {
        let cookies = MathAcademyClient.parseCookies(
            fields: folded, for: URL(string: "https://www.mathacademy.com/login")!
        )
        let byName = Dictionary(uniqueKeysWithValues: cookies.map { ($0.name, $0) })
        XCTAssertEqual(byName["session"]?.value, "SESSION-VALUE")
        XCTAssertEqual(byName["session.sig"]?.value, "SIG-VALUE")
        XCTAssertEqual(
            byName["session"]?.expiresDate,
            SetCookieDateFixture.october3rd2026,
            "the 30-day expiry drives the proactive re-login"
        )
    }

    /// `HTTPCookie` refuses `Secure` cookies from an http URL, which is why the client parses
    /// against an https URL. Without that, every request to the local fake server would look
    /// like a failed sign-in.
    func testSecureCookiesSurviveALoopbackHTTPURL() {
        let cookies = MathAcademyClient.parseCookies(
            fields: folded, for: URL(string: "http://127.0.0.1:8799/login")!
        )
        XCTAssertEqual(Set(cookies.map(\.name)), ["session", "session.sig"])
    }

    func testUnrelatedCookiesAreIgnoredByTheClient() {
        let cookies = MathAcademyClient.parseCookies(
            fields: ["Set-Cookie": "analytics=abc; path=/"],
            for: URL(string: "https://www.mathacademy.com/")!
        )
        XCTAssertEqual(cookies.map(\.name), ["analytics"])
        XCTAssertFalse(cookies.contains { $0.name == "session" })
    }
}

enum SetCookieDateFixture {
    static let october3rd2026: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 3
        comps.hour = 10; comps.minute = 30; comps.second = 42
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: comps)!
    }()
}
