import DeviceActivity
import Foundation
import MathGateKit

/// Woken by the OS at the daily reset. This is what makes the gate close again each day without
/// MathGate having been opened, and it is why the iOS build needs no always-running service.
final class MathGateDeviceActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == DeviceActivityName(MathGateIDs.monitorActivityName) else { return }
        MGLog.debug("daily reset: raising the shield")
        GateEngine.applyDailyReset()
        ShieldController.reconcile()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == DeviceActivityName(MathGateIDs.monitorActivityName) else { return }
        // The next interval starts a minute later; just make sure the OS state matches ours.
        ShieldController.reconcile()
    }
}
