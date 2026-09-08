import Foundation

/// Result of asking "has a Math Academy task been completed in the current period?".
/// Fail closed: only `.done` unlocks.
public enum GateStatus: Equatable, Sendable {
    case done(doneUntil: Date, tasksCompleted: Int, xp: Int)
    case notDone(periodStart: Date, nextReset: Date, checkedAt: Date)
    /// Network unreachable (no connectivity, DNS failure, timeout).
    case offline(String)
    /// No credentials saved, wrong credentials, login backoff active, or Keychain read failure.
    case authFailed(String)
    /// Math Academy answered but not in the shape we expect (API change, HTML instead of JSON).
    case unexpectedResponse(String)
    /// Nothing fetched yet.
    case unknown

    public var allowsAccess: Bool {
        if case .done = self { return true }
        return false
    }
}

public struct Credentials: Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct GateRequest: Equatable, Sendable {
    public let periodStart: Date
    public let nextReset: Date
    public let now: Date

    public init(periodStart: Date, nextReset: Date, now: Date) {
        self.periodStart = periodStart
        self.nextReset = nextReset
        self.now = now
    }
}

public protocol GateAPI: Sendable {
    func fetch(_ request: GateRequest) async -> GateStatus
}
