import Foundation
import Security

/// Where the Math Academy password lives.
///
/// The Android side seals it with an Android Keystore key; the iOS equivalent is the Keychain,
/// shared with the extensions through a Keychain access group. Accessibility is
/// `AfterFirstUnlock` rather than `WhenUnlocked` because the DeviceActivity and shield
/// extensions run without the user present.
public protocol SecretStore: AnyObject, Sendable {
    func save(password: String) throws
    func loadPassword() -> String?
    func deletePassword()
}

public enum SecretStoreError: Error, Equatable {
    case keychain(OSStatus)
    case encoding
}

public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service = "com.harryobrien.mathgate.mathacademy"
    private let account = "password"
    private let accessGroup: String?

    public init(accessGroup: String? = MathGateIDs.keychainGroup) {
        self.accessGroup = accessGroup
    }

    private func baseQuery(shared: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared, let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    public func save(password: String) throws {
        guard let data = password.data(using: .utf8) else { throw SecretStoreError.encoding }
        deletePassword()
        var status = errSecSuccess
        for shared in [true, false] {
            var q = baseQuery(shared: shared)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(q as CFDictionary, nil)
            if status == errSecSuccess { return }
            // Only an entitlement problem is worth retrying without the shared group; anything
            // else is a real failure and should surface.
            guard shared, status == errSecMissingEntitlement || status == errSecParam else { break }
            MGLog.error("keychain group unavailable (\(status)); falling back to app-only storage")
        }
        throw SecretStoreError.keychain(status)
    }

    public func loadPassword() -> String? {
        for shared in [true, false] {
            var q = baseQuery(shared: shared)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
               let data = out as? Data,
               let password = String(data: data, encoding: .utf8) {
                return password
            }
        }
        return nil
    }

    public func deletePassword() {
        for shared in [true, false] {
            SecItemDelete(baseQuery(shared: shared) as CFDictionary)
        }
    }
}

/// Test double. Never used in the shipping app.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var password: String?

    public init(password: String? = nil) {
        self.password = password
    }

    public func save(password: String) throws {
        lock.lock(); defer { lock.unlock() }
        self.password = password
    }

    public func loadPassword() -> String? {
        lock.lock(); defer { lock.unlock() }
        return password
    }

    public func deletePassword() {
        lock.lock(); defer { lock.unlock() }
        password = nil
    }
}
