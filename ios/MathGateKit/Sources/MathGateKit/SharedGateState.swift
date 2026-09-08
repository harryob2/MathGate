import Foundation

/// Everything the extensions need to know, in one App Group value.
///
/// The iOS gate is inverted relative to Android's. There, an accessibility service is asked
/// "may this app open?" every time a window changes. Here the shield is declarative OS state, so
/// `shouldShieldNow` *is* the block: it is set at every daily reset and only cleared by a
/// confirmed Math Academy pass. Failing to check therefore fails closed by construction.
public struct SharedGateState: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var screenTimeAuthorized: Bool
    /// JSON-encoded `FamilyActivitySelection`. Opaque here: MathGateKit must not import
    /// FamilyControls, or it stops building for macOS and the fast test loop goes away.
    public var selectionData: Data?
    public var resetTime: ResetTime
    public var shouldShieldNow: Bool

    public var donePeriodStart: Date?
    public var doneUntil: Date?
    public var doneTasks: Int
    public var doneXP: Int

    public var username: String?
    public var lastCheckedAt: Date?
    public var lastStatusDetail: String?

    public var isConfiguredForShielding: Bool {
        isEnabled && screenTimeAuthorized && selectionData != nil
    }

    public var hasUsername: Bool {
        guard let username else { return false }
        return !username.isEmpty
    }

    public static let empty = SharedGateState(
        isEnabled: false,
        screenTimeAuthorized: false,
        selectionData: nil,
        resetTime: .default,
        shouldShieldNow: false,
        donePeriodStart: nil,
        doneUntil: nil,
        doneTasks: 0,
        doneXP: 0,
        username: nil,
        lastCheckedAt: nil,
        lastStatusDetail: nil
    )

    /// True when a pass recorded earlier still belongs to the period containing `now`.
    public func hasValidPass(now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let donePeriodStart, let doneUntil else { return false }
        let periodStart = resetTime.currentPeriodStart(now: now, calendar: calendar)
        return donePeriodStart == periodStart && now < doneUntil
    }
}

public enum SharedGateStateStore {
    private static let key = "mathgate.sharedState"

    public static func load(defaults: SharedDefaults = .appGroup) -> SharedGateState {
        guard let data = defaults.raw.data(forKey: key),
              let state = try? JSONDecoder().decode(SharedGateState.self, from: data)
        else { return .empty }
        return state
    }

    public static func save(_ state: SharedGateState, defaults: SharedDefaults = .appGroup) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.raw.set(data, forKey: key)
    }

    @discardableResult
    public static func mutate(
        defaults: SharedDefaults = .appGroup,
        _ body: (inout SharedGateState) -> Void
    ) -> SharedGateState {
        var state = load(defaults: defaults)
        body(&state)
        save(state, defaults: defaults)
        return state
    }
}
