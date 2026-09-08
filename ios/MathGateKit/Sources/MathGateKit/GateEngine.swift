import Foundation

/// Decides whether the shield should be up, and records the day's pass.
///
/// Deliberately knows nothing about FamilyControls: it reports what should happen and writes
/// `SharedGateState`, and the caller (app or extension) applies that to a `ManagedSettingsStore`.
/// That keeps this testable on macOS with no simulator and no entitlements.
public actor GateEngine {
    private let api: GateAPI
    private let defaults: SharedDefaults
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Serialises overlapping refreshes so two entry points (app foreground and a background
    /// task, say) cannot sign in twice at once.
    private var inFlight: Task<GateStatus, Never>?

    public init(
        api: GateAPI,
        defaults: SharedDefaults = .appGroup,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    /// The cached answer, with no network. Cheap enough for any UI or extension entry point.
    public func cachedStatus() -> GateStatus {
        let state = SharedGateStateStore.load(defaults: defaults)
        let t = now()
        if state.hasValidPass(now: t, calendar: calendar), let until = state.doneUntil {
            return .done(doneUntil: until, tasksCompleted: state.doneTasks, xp: state.doneXP)
        }
        return .unknown
    }

    /// Honours an existing pass without touching the network; otherwise asks Math Academy.
    @discardableResult
    public func refresh(force: Bool = false) async -> GateStatus {
        if !force, case .done = cachedStatus() { return cachedStatus() }
        if let inFlight { return await inFlight.value }

        let task = Task<GateStatus, Never> { [api, defaults, calendar, now] in
            let t = now()
            let state = SharedGateStateStore.load(defaults: defaults)
            let periodStart = state.resetTime.currentPeriodStart(now: t, calendar: calendar)
            let nextReset = state.resetTime.nextReset(now: t, calendar: calendar)
            let status = await api.fetch(
                GateRequest(periodStart: periodStart, nextReset: nextReset, now: t)
            )
            Self.record(status, periodStart: periodStart, at: t, defaults: defaults)
            return status
        }
        inFlight = task
        let status = await task.value
        inFlight = nil
        return status
    }

    /// Called at the daily reset. Drops the pass and puts the shield back up.
    public static func applyDailyReset(defaults: SharedDefaults = .appGroup) {
        SharedGateStateStore.mutate(defaults: defaults) { state in
            state.donePeriodStart = nil
            state.doneUntil = nil
            state.doneTasks = 0
            state.doneXP = 0
            state.shouldShieldNow = state.isConfiguredForShielding
        }
    }

    private static func record(
        _ status: GateStatus,
        periodStart: Date,
        at t: Date,
        defaults: SharedDefaults
    ) {
        SharedGateStateStore.mutate(defaults: defaults) { state in
            state.lastCheckedAt = t
            switch status {
            case .done(let until, let tasks, let xp):
                state.donePeriodStart = periodStart
                state.doneUntil = until
                state.doneTasks = tasks
                state.doneXP = xp
                state.shouldShieldNow = false
                state.lastStatusDetail = nil
            case .notDone:
                state.shouldShieldNow = state.isConfiguredForShielding
                state.lastStatusDetail = nil
            case .offline(let m):
                state.shouldShieldNow = state.isConfiguredForShielding
                state.lastStatusDetail = "Offline: \(m)"
            case .authFailed(let r):
                state.shouldShieldNow = state.isConfiguredForShielding
                state.lastStatusDetail = "Sign-in failed: \(r)"
            case .unexpectedResponse(let d):
                state.shouldShieldNow = state.isConfiguredForShielding
                state.lastStatusDetail = "Unexpected response: \(d)"
            case .unknown:
                break
            }
        }
    }
}
