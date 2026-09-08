import Foundation
import ManagedSettings
import MathGateKit

/// Handles the two buttons on the shield. The primary one is the iOS equivalent of Android's
/// "Retry": it re-checks Math Academy right here, so finishing a task and tapping once is enough.
final class MathGateShieldActionExtension: ShieldActionDelegate {
    /// Shield extensions are given a small time and memory budget, so the check is bounded and
    /// falls back to keeping the shield up. Failing to answer in time must never open the gate.
    private static let checkTimeout: Duration = .seconds(8)

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(
        to action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        // The SDK hands back a plain Objective-C completion block, which Swift 6 cannot see as
        // Sendable. It is called exactly once, from one task, so bridging it is safe.
        let complete = UncheckedBox(completionHandler)
        switch action {
        case .primaryButtonPressed:
            Self.checkThenRespond(complete)
        case .secondaryButtonPressed:
            complete.value(.close)
        @unknown default:
            complete.value(.defer)
        }
    }

    /// Kept out of the `switch` above: the Swift 6 isolation checker cannot yet reason about a
    /// `Task` started inside a switch case over an imported enum.
    private static func checkThenRespond(_ complete: UncheckedBox<(ShieldActionResponse) -> Void>) {
        Task {
            let unlocked = await checkNow()
            complete.value(unlocked ? .none : .defer)
        }
    }

    /// Returns true only when Math Academy positively confirms a completed task.
    private static func checkNow() async -> Bool {
        let engine = GateFactory.makeEngine()
        let status: GateStatus? = await withTaskGroup(of: GateStatus?.self) { group in
            group.addTask { await engine.refresh(force: true) }
            group.addTask {
                try? await Task.sleep(for: checkTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let status, status.allowsAccess else {
            MGLog.debug("shield action: staying shut")
            return false
        }
        ShieldController.reconcile()
        MGLog.debug("shield action: task confirmed, unlocking")
        return true
    }
}
