import Foundation
import MathGateKit

/// One place that wires the object graph, so the app and all three extensions agree on which
/// App Group, Keychain group and base URL they are using.
enum GateFactory {
    static let session: SessionStore = SharedDefaultsSessionStore()
    static let secrets: SecretStore = KeychainSecretStore()

    private static let debugBaseURLKey = "debug_base_url"

    static func makeEngine() -> GateEngine {
        let client = MathAcademyClient(session: session, baseURL: baseURL())
        let api = MathAcademyGateAPI(client: client, secrets: secrets) {
            SharedGateStateStore.load().username
        }
        return GateEngine(api: api)
    }

    /// Debug builds only, and only when explicitly set: points the client at
    /// `tools/fake_mathacademy.py` so the whole flow can be exercised without a real account.
    /// Release builds ignore it entirely, so there is no way to redirect a shipping app.
    static func baseURL() -> URL {
        #if DEBUG
        if let raw = debugBaseURLString(), let url = URL(string: raw) {
            return url
        }
        #endif
        return MathAcademyClient.defaultBaseURL
    }

    static func debugBaseURLString() -> String? {
        #if DEBUG
        let raw = SharedDefaults.appGroup.raw.string(forKey: debugBaseURLKey)
        return (raw?.isEmpty ?? true) ? nil : raw
        #else
        return nil
        #endif
    }

    static func setDebugBaseURL(_ value: String?) {
        #if DEBUG
        SharedDefaults.appGroup.raw.set(value, forKey: debugBaseURLKey)
        #endif
    }
}
