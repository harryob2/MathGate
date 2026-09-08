import Foundation

/// Identifiers shared by the app and all three extensions. Changing any of these is a migration:
/// the App Group and Keychain group must also be updated in every `.entitlements` file.
public enum MathGateIDs {
    public static let appGroup = "group.com.harryobrien.mathgate"
    /// An App Group identifier doubles as a keychain access group, which avoids hardcoding a
    /// team prefix — so a fork only has to change this one file plus the `.entitlements`.
    public static var keychainGroup: String { appGroup }

    /// DeviceActivity schedule that fires at the daily reset.
    public static let monitorActivityName = "mathgate.daily-reset"
    /// The ManagedSettingsStore MathGate owns. Namespaced so it never fights MedKi's store.
    public static let managedSettingsStoreName = "MathGateBlocking"
    /// BGAppRefreshTask identifier; must also appear in the app's BGTaskSchedulerPermittedIdentifiers.
    public static let backgroundRefreshTaskID = "com.harryobrien.mathgate.refresh"

    public static let mathAcademyLearnURL = URL(string: "https://www.mathacademy.com/learn")!
}
