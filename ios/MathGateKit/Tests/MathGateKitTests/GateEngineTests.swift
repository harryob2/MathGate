import XCTest
@testable import MathGateKit

final class GateEngineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: SharedDefaults!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        suiteName = "mathgate.tests.\(UUID().uuidString)"
        defaults = SharedDefaults(UserDefaults(suiteName: suiteName)!)
        calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "Europe/London")!
            return c
        }()
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour, minute: minute
        ))!
    }

    private func configure(enabled: Bool = true) {
        SharedGateStateStore.mutate(defaults: defaults) { state in
            state.isEnabled = enabled
            state.screenTimeAuthorized = enabled
            state.selectionData = enabled ? Data("selection".utf8) : nil
            state.username = "someone"
            state.resetTime = .default
        }
    }

    private func engine(_ api: FakeGateAPI, now: @escaping @Sendable () -> Date) -> GateEngine {
        GateEngine(api: api, defaults: defaults, calendar: calendar, now: now)
    }

    /// A fixed clock. Built here so the closure captures a `Date`, not the (non-Sendable) test case.
    private func clock(_ day: Int, _ hour: Int, _ minute: Int = 0) -> @Sendable () -> Date {
        let fixed = date(day, hour, minute)
        return { fixed }
    }

    // MARK: -

    func testDoneRecordsThePassAndLowersTheShield() async {
        configure()
        let api = FakeGateAPI(result: .doneWithTwoTasks)
        let status = await engine(api, now: clock(3, 10)).refresh()

        guard case .done(_, let tasks, let xp) = status else { return XCTFail("got \(status)") }
        XCTAssertEqual(tasks, 2)
        XCTAssertEqual(xp, 18)

        let state = SharedGateStateStore.load(defaults: defaults)
        XCTAssertFalse(state.shouldShieldNow)
        XCTAssertEqual(state.donePeriodStart, date(3, 4))
        XCTAssertEqual(state.doneUntil, date(4, 4))
    }

    func testASavedPassIsHonouredWithoutTouchingTheNetwork() async {
        configure()
        let api = FakeGateAPI(result: .doneWithTwoTasks)
        let e = engine(api, now: clock(3, 10))
        await e.refresh()
        XCTAssertEqual(api.callCount, 1)

        // Later the same day: the cached pass answers, nothing is fetched.
        let later = engine(api, now: clock(3, 23))
        let status = await later.refresh()
        guard case .done = status else { return XCTFail("got \(status)") }
        XCTAssertEqual(api.callCount, 1, "a valid pass must not cause another sign-in")
    }

    func testThePassExpiresAtTheNextReset() async {
        configure()
        let api = FakeGateAPI(result: .doneWithTwoTasks)
        await engine(api, now: clock(3, 10)).refresh()

        // 04:01 the next day is a new period, so the pass no longer applies.
        api.result = .notDone
        let status = await engine(api, now: clock(4, 4, 1)).refresh()

        guard case .notDone = status else { return XCTFail("got \(status)") }
        XCTAssertEqual(api.callCount, 2)
        XCTAssertTrue(SharedGateStateStore.load(defaults: defaults).shouldShieldNow)
    }

    func testForcedRefreshIgnoresTheCachedPass() async {
        configure()
        let api = FakeGateAPI(result: .doneWithTwoTasks)
        let e = engine(api, now: clock(3, 10))
        await e.refresh()
        await e.refresh(force: true)
        XCTAssertEqual(api.callCount, 2)
    }

    /// Every failure keeps the shield up. This is the whole safety property.
    func testEveryFailureRaisesTheShield() async {
        let failures: [GateStatus] = [
            .notDone(periodStart: date(3, 4), nextReset: date(4, 4), checkedAt: date(3, 10)),
            .offline("airplane mode"),
            .authFailed("bad_credentials"),
            .unexpectedResponse("html instead of json"),
        ]
        for failure in failures {
            configure()
            let api = FakeGateAPI(result: failure)
            let status = await engine(api, now: clock(3, 10)).refresh()
            XCTAssertFalse(status.allowsAccess, "\(failure) must not unlock")
            XCTAssertTrue(
                SharedGateStateStore.load(defaults: defaults).shouldShieldNow,
                "\(failure) must leave the shield up"
            )
        }
    }

    func testFailureDetailIsSurfacedForTheUI() async {
        configure()
        let api = FakeGateAPI(result: .offline("The Internet connection appears to be offline."))
        await engine(api, now: clock(3, 10)).refresh()
        let detail = SharedGateStateStore.load(defaults: defaults).lastStatusDetail ?? ""
        XCTAssertTrue(detail.hasPrefix("Offline:"), detail)
    }

    /// With blocking switched off, a failed check must not start shielding apps.
    func testShieldStaysDownWhenBlockingIsDisabled() async {
        configure(enabled: false)
        let api = FakeGateAPI(result: .offline("no network"))
        await engine(api, now: clock(3, 10)).refresh()
        XCTAssertFalse(SharedGateStateStore.load(defaults: defaults).shouldShieldNow)
    }

    func testDailyResetDropsThePassAndRaisesTheShield() async {
        configure()
        let api = FakeGateAPI(result: .doneWithTwoTasks)
        await engine(api, now: clock(3, 10)).refresh()
        XCTAssertFalse(SharedGateStateStore.load(defaults: defaults).shouldShieldNow)

        GateEngine.applyDailyReset(defaults: defaults)

        let state = SharedGateStateStore.load(defaults: defaults)
        XCTAssertTrue(state.shouldShieldNow)
        XCTAssertNil(state.donePeriodStart)
        XCTAssertEqual(state.doneTasks, 0)
    }

    func testOverlappingRefreshesShareOneFetch() async {
        configure()
        let api = FakeGateAPI(result: .doneWithTwoTasks, delay: .milliseconds(120))
        let e = engine(api, now: clock(3, 10))

        async let a = e.refresh(force: true)
        async let b = e.refresh(force: true)
        async let c = e.refresh(force: true)
        _ = await (a, b, c)

        XCTAssertEqual(api.callCount, 1, "concurrent callers must not each sign in")
    }

    func testCachedStatusIsUnknownBeforeAnythingIsFetched() async {
        configure()
        let e = engine(FakeGateAPI(result: .notDone), now: clock(3, 10))
        let cached = await e.cachedStatus()
        XCTAssertEqual(cached, .unknown)
        XCTAssertFalse(cached.allowsAccess, "unknown must not unlock")
    }
}

private extension GateStatus {
    static var doneWithTwoTasks: GateStatus {
        .done(doneUntil: .distantFuture, tasksCompleted: 2, xp: 18)
    }
    static var notDone: GateStatus {
        .notDone(periodStart: .distantPast, nextReset: .distantFuture, checkedAt: .distantPast)
    }
}

private final class FakeGateAPI: GateAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: GateStatus
    private var _callCount = 0
    private let delay: Duration?

    init(result: GateStatus, delay: Duration? = nil) {
        self._result = result
        self.delay = delay
    }

    var result: GateStatus {
        get { lock.lock(); defer { lock.unlock() }; return _result }
        set { lock.lock(); _result = newValue; lock.unlock() }
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    func fetch(_ request: GateRequest) async -> GateStatus {
        lock.withLock { _callCount += 1 }
        if let delay { try? await Task.sleep(for: delay) }
        // `.done` needs the real nextReset so the pass lands in the right period.
        if case .done(_, let tasks, let xp) = result {
            return .done(doneUntil: request.nextReset, tasksCompleted: tasks, xp: xp)
        }
        return result
    }
}
