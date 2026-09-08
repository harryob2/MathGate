import XCTest
@testable import MathGateKit

final class MathAcademyClientTests: XCTestCase {
    private var server: FakeMathAcademy!
    private let creds = Credentials(username: "someone", password: "hunter2")

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    private func makeClient(
        _ session: SessionStore = InMemorySessionStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> MathAcademyClient {
        MathAcademyClient(session: session, baseURL: server.baseURL, now: now)
    }

    private static let cookieExpiry = "Sat, 03 Oct 2026 10:30:42 GMT"

    private static func loginOK() -> FakeMathAcademy.Reply {
        FakeMathAcademy.Reply(
            status: 302,
            headers: [
                ("Location", "/learn"),
                ("Set-Cookie", "session=SESSION-VALUE; path=/; expires=\(cookieExpiry); secure; httponly"),
                ("Set-Cookie", "session.sig=SIG-VALUE; path=/; expires=\(cookieExpiry); secure; httponly"),
            ],
            body: ""
        )
    }

    private static func tasksJSON(completed: [String]) -> String {
        let items = completed.map {
            #"{"id":1,"type":"Lesson","points":10,"pointsAwarded":9,"completed":"\#($0)"}"#
        }
        return "[" + items.joined(separator: ",") + "]"
    }

    // MARK: - Login

    func testSuccessfulLoginStoresBothCookies() async throws {
        server = FakeMathAcademy { req in
            req.path == "/login" ? Self.loginOK() : .html("nope", status: 404)
        }
        try server.start()
        let session = InMemorySessionStore()
        let client = makeClient(session)

        let result = try await client.login(creds)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(session.cookieSession, "SESSION-VALUE")
        XCTAssertEqual(session.cookieSig, "SIG-VALUE")
        XCTAssertNotNil(session.cookieExpires, "expiry drives the proactive re-login")
        XCTAssertTrue(session.hasCookies)
    }

    func testLoginPostsTheFormFieldsTheSiteExpects() async throws {
        server = FakeMathAcademy { _ in Self.loginOK() }
        try server.start()
        _ = try await makeClient().login(Credentials(username: "a b", password: "p+ss&word"))

        let body = server.recordedRequests().first?.body ?? ""
        XCTAssertTrue(body.contains("usernameOrEmail=a+b"), body)
        XCTAssertTrue(body.contains("password=p%2Bss%26word"), "reserved characters must be escaped: \(body)")
        XCTAssertTrue(body.contains("submit=LOGIN"), body)
    }

    func testRedirectBackToLoginIsBadCredentials() async throws {
        server = FakeMathAcademy { _ in
            FakeMathAcademy.Reply(status: 302, headers: [("Location", "/login?error=1")], body: "")
        }
        try server.start()
        let session = InMemorySessionStore()

        let result = try await makeClient(session).login(creds)

        guard case .badCredentials = result else { return XCTFail("expected badCredentials, got \(result)") }
        XCTAssertFalse(session.hasCookies)
    }

    func testLoginPageReturnedIsBadCredentialsWithItsOwnMessage() async throws {
        server = FakeMathAcademy { _ in
            .html("<html><div id=\"errorMessage\">Invalid <b>username</b> or password</div></html>")
        }
        try server.start()

        let result = try await makeClient().login(creds)

        XCTAssertEqual(result, .badCredentials("Invalid username or password"))
    }

    // MARK: - Fetching tasks

    func testFetchLogsInOnceThenReadsTasks() async throws {
        let iso = "2026-09-03T09:00:00.000Z"
        server = FakeMathAcademy { req in
            if req.path == "/login" { return Self.loginOK() }
            if req.path.hasPrefix("/api/previous-tasks/") {
                return .json(Self.tasksJSON(completed: [iso]))
            }
            return .html("nope", status: 404)
        }
        try server.start()

        let tasks = try await makeClient().fetchRecentTasks(creds)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.awardedPoints, 9, "pointsAwarded wins over points")
        XCTAssertEqual(tasks.first?.completed, TaskSummariser.parseInstant(iso))

        let paths = server.recordedRequests().map(\.path)
        XCTAssertEqual(paths.filter { $0 == "/login" }.count, 1)
    }

    func testSendsBothCookiesAndTheFixedUserAgent() async throws {
        server = FakeMathAcademy { req in
            req.path == "/login" ? Self.loginOK() : .json("[]")
        }
        try server.start()

        _ = try await makeClient().fetchRecentTasks(creds)

        let apiRequest = server.recordedRequests().first { $0.path.hasPrefix("/api/") }
        XCTAssertEqual(apiRequest?.headers["cookie"], "session=SESSION-VALUE; session.sig=SIG-VALUE")
        XCTAssertEqual(apiRequest?.headers["user-agent"], MathAcademyClient.userAgent)
        XCTAssertEqual(apiRequest?.headers["accept"], "application/json, text/plain, */*")
    }

    /// The cursor is tomorrow, and the mis-spelled `minumum` param is omitted, exactly as the
    /// logged-in browser does it.
    func testRequestsTomorrowAndOmitsTheMisspelledParam() async throws {
        server = FakeMathAcademy { req in
            req.path == "/login" ? Self.loginOK() : .json("[]")
        }
        try server.start()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let fixed = cal.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 11, minute: 30))!

        _ = try await makeClient(InMemorySessionStore(), now: { fixed })
            .fetchRecentTasks(creds, calendar: cal)

        let path = server.recordedRequests().first { $0.path.hasPrefix("/api/") }?.path ?? ""
        XCTAssertTrue(path.contains("Fri%20Sep%2004%202026"), "expected tomorrow's date, got \(path)")
        XCTAssertFalse(path.contains("minumum"), path)
    }

    func testHTMLInsteadOfJSONTriggersOneReloginThenFails() async throws {
        server = FakeMathAcademy { req in
            req.path == "/login" ? Self.loginOK() : .html("<html>session expired</html>")
        }
        try server.start()

        do {
            _ = try await makeClient().fetchRecentTasks(creds)
            XCTFail("expected unexpectedResponse")
        } catch let error as MathAcademyClient.ClientError {
            guard case .unexpectedResponse = error else { return XCTFail("got \(error)") }
        }

        let logins = server.recordedRequests().filter { $0.path == "/login" }.count
        XCTAssertEqual(logins, 2, "one initial login plus exactly one re-login")
    }

    func testExpiredSessionIsRetriedOnceAndSucceeds() async throws {
        let attempts = Counter()
        server = FakeMathAcademy { req in
            if req.path == "/login" { return Self.loginOK() }
            // Fail the first API call the way a dead session does, then succeed.
            return attempts.next() == 1
                ? FakeMathAcademy.Reply(status: 302, headers: [("Location", "/session-expired")], body: "")
                : .json(Self.tasksJSON(completed: ["2026-09-03T09:00:00.000Z"]))
        }
        try server.start()

        let tasks = try await makeClient().fetchRecentTasks(creds)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(server.recordedRequests().filter { $0.path == "/login" }.count, 2)
    }

    func testBadCredentialsStartATenMinuteBackoff() async throws {
        server = FakeMathAcademy { _ in .html("<div id=\"errorMessage\">Invalid</div>") }
        try server.start()
        let session = InMemorySessionStore()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let client = makeClient(session, now: { start })

        do {
            _ = try await client.fetchRecentTasks(creds)
            XCTFail("expected authFailed")
        } catch let error as MathAcademyClient.ClientError {
            guard case .authFailed = error else { return XCTFail("got \(error)") }
        }

        XCTAssertEqual(session.loginBackoffUntil, start.addingTimeInterval(600))

        // A second attempt inside the window must not reach the network at all.
        let before = server.recordedRequests().count
        do {
            _ = try await client.fetchRecentTasks(creds)
            XCTFail("expected authFailed")
        } catch let error as MathAcademyClient.ClientError {
            guard case .authFailed(let reason) = error else { return XCTFail("got \(error)") }
            XCTAssertTrue(reason.contains("login_backoff"), reason)
        }
        XCTAssertEqual(server.recordedRequests().count, before, "backoff must suppress the request")
    }

    func testFreshSessionSkipsLoginEntirely() async throws {
        server = FakeMathAcademy { req in
            req.path == "/login" ? Self.loginOK() : .json("[]")
        }
        try server.start()
        let session = InMemorySessionStore()
        session.cookieSession = "SESSION-VALUE"
        session.cookieSig = "SIG-VALUE"
        session.cookieExpires = Date().addingTimeInterval(20 * 24 * 3600)

        _ = try await makeClient(session).fetchRecentTasks(creds)

        XCTAssertTrue(server.recordedRequests().allSatisfy { $0.path != "/login" })
    }

    func testSessionCloseToExpiryIsRefreshedProactively() async throws {
        server = FakeMathAcademy { req in
            req.path == "/login" ? Self.loginOK() : .json("[]")
        }
        try server.start()
        let session = InMemorySessionStore()
        session.cookieSession = "OLD"
        session.cookieSig = "OLD-SIG"
        session.cookieExpires = Date().addingTimeInterval(36 * 3600) // under the 2-day margin

        _ = try await makeClient(session).fetchRecentTasks(creds)

        XCTAssertEqual(server.recordedRequests().filter { $0.path == "/login" }.count, 1)
        XCTAssertEqual(session.cookieSession, "SESSION-VALUE")
    }

    func testUnreachableServerIsOfflineNotAFailure() async throws {
        server = FakeMathAcademy { _ in .json("[]") }
        try server.start()
        let deadURL = server.baseURL
        server.stop()

        let client = MathAcademyClient(session: InMemorySessionStore(), baseURL: deadURL)
        do {
            _ = try await client.fetchRecentTasks(creds)
            XCTFail("expected offline")
        } catch let error as MathAcademyClient.ClientError {
            guard case .offline = error else { return XCTFail("got \(error)") }
        }
    }
}

/// Small thread-safe counter for handlers that must behave differently on each call.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
