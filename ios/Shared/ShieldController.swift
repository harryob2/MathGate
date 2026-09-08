import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import MathGateKit

/// The bridge between `SharedGateState` (decided in MathGateKit, testable anywhere) and the
/// Screen Time frameworks (only meaningful on a real device with the Family Controls
/// entitlement). Compiled into the app and all three extensions.
enum ShieldController {
    static var store: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(MathGateIDs.managedSettingsStoreName))
    }

    /// What should be shielded right now, or nil when nothing should be. Split out from `apply`
    /// so the decision is testable without a device: `ManagedSettingsStore` writes are inert in
    /// the simulator, but this predicate is the whole safety property.
    static func shieldTargets(_ state: SharedGateState) -> FamilyActivitySelection? {
        guard state.isConfiguredForShielding, state.shouldShieldNow else { return nil }
        return state.familyActivitySelection()
    }

    /// Brings the OS shield in line with the shared state. Safe to call from anywhere, often.
    static func apply(_ state: SharedGateState) {
        guard let selection = shieldTargets(state) else {
            clear()
            return
        }
        let s = store
        s.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        s.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        s.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        s.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
    }

    static func clear() {
        let s = store
        s.shield.applications = nil
        s.shield.webDomains = nil
        s.shield.applicationCategories = nil
        s.shield.webDomainCategories = nil
    }

    static func reconcile(defaults: SharedDefaults = .appGroup) {
        apply(SharedGateStateStore.load(defaults: defaults))
    }
}

extension SharedGateState {
    /// `FamilyActivitySelection` holds opaque, device-bound tokens: MathGate never learns which
    /// apps were chosen, only that they were. It is stored encoded so MathGateKit can carry it
    /// without importing FamilyControls.
    func familyActivitySelection() -> FamilyActivitySelection? {
        guard let selectionData else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
    }

    mutating func setFamilyActivitySelection(_ selection: FamilyActivitySelection) {
        let isEmpty = selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
        selectionData = isEmpty ? nil : try? JSONEncoder().encode(selection)
    }

    var selectedItemCount: Int {
        guard let selection = familyActivitySelection() else { return 0 }
        return selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }
}

/// Registers the daily-reset schedule with the OS so the monitor extension is woken at the
/// reset time even when MathGate has not been opened for days.
enum ScheduleController {
    static func reconcile(_ state: SharedGateState) {
        let center = DeviceActivityCenter()
        let name = DeviceActivityName(MathGateIDs.monitorActivityName)
        guard state.isConfiguredForShielding else {
            center.stopMonitoring([name])
            return
        }
        do {
            try center.startMonitoring(name, during: dailySchedule(state.resetTime))
        } catch {
            MGLog.error("startMonitoring failed: \(error.localizedDescription)")
        }
    }

    /// One interval per day, starting at the reset and ending a minute before the next one, so
    /// `intervalDidStart` fires exactly once per period.
    static func dailySchedule(_ resetTime: ResetTime) -> DeviceActivitySchedule {
        let n = resetTime.normalized()
        let startMinutes = n.hour * 60 + n.minute
        let endMinutes = (startMinutes + (24 * 60) - 1) % (24 * 60)
        return DeviceActivitySchedule(
            intervalStart: DateComponents(hour: n.hour, minute: n.minute),
            intervalEnd: DateComponents(hour: endMinutes / 60, minute: endMinutes % 60),
            repeats: true
        )
    }
}
