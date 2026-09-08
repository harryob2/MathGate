import Foundation

/// The two Math Academy cookies plus the timers around them.
///
/// Lives in the App Group so the shield-action extension can reuse a live session instead of
/// signing in again. Never log these values.
public protocol SessionStore: AnyObject, Sendable {
    var cookieSession: String? { get set }
    var cookieSig: String? { get set }
    var cookieExpires: Date? { get set }
    var lastLogin: Date? { get set }
    var loginBackoffUntil: Date? { get set }

    func clearCookies()
}

extension SessionStore {
    public var hasCookies: Bool {
        guard let s = cookieSession, let sig = cookieSig else { return false }
        return !s.isEmpty && !sig.isEmpty
    }

    public func clearCookies() {
        cookieSession = nil
        cookieSig = nil
        cookieExpires = nil
    }
}

/// App Group-backed store. `UserDefaults` is thread-safe, so this is safe to share.
public final class SharedDefaultsSessionStore: SessionStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: SharedDefaults = .appGroup) {
        self.defaults = defaults.raw
    }

    private enum Key {
        static let session = "ma.cookie.session"
        static let sig = "ma.cookie.sig"
        static let expires = "ma.cookie.expires"
        static let lastLogin = "ma.lastLogin"
        static let backoff = "ma.loginBackoffUntil"
    }

    public var cookieSession: String? {
        get { defaults.string(forKey: Key.session) }
        set { defaults.set(newValue, forKey: Key.session) }
    }

    public var cookieSig: String? {
        get { defaults.string(forKey: Key.sig) }
        set { defaults.set(newValue, forKey: Key.sig) }
    }

    public var cookieExpires: Date? {
        get { defaults.object(forKey: Key.expires) as? Date }
        set { defaults.set(newValue, forKey: Key.expires) }
    }

    public var lastLogin: Date? {
        get { defaults.object(forKey: Key.lastLogin) as? Date }
        set { defaults.set(newValue, forKey: Key.lastLogin) }
    }

    public var loginBackoffUntil: Date? {
        get { defaults.object(forKey: Key.backoff) as? Date }
        set { defaults.set(newValue, forKey: Key.backoff) }
    }
}

/// Test double; also what the previews use.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    public var cookieSession: String?
    public var cookieSig: String?
    public var cookieExpires: Date?
    public var lastLogin: Date?
    public var loginBackoffUntil: Date?

    public init() {}
}

/// `UserDefaults` is documented as thread-safe but is not marked `Sendable`. Asserting that
/// once, here, keeps every other file free of concurrency escape hatches.
public struct SharedDefaults: @unchecked Sendable {
    public let raw: UserDefaults

    public init(_ raw: UserDefaults) { self.raw = raw }

    /// Falls back to `.standard` only when the App Group is missing, which means the entitlement
    /// is not in place — the app surfaces that rather than silently running unshared.
    public static let appGroup = SharedDefaults(
        UserDefaults(suiteName: MathGateIDs.appGroup) ?? .standard
    )

    public static var isAppGroupAvailable: Bool {
        UserDefaults(suiteName: MathGateIDs.appGroup) != nil
    }
}
