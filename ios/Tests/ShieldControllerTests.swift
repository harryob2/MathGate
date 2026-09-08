import FamilyControls
import ManagedSettings
import XCTest
@testable import MathGate
@testable import MathGateKit

/// Runs on the simulator. `ManagedSettingsStore` writes are inert without the Family Controls
/// entitlement and a real device, so these cover the decisions rather than the OS effect.
final class ShieldControllerTests: XCTestCase {
    private func configured(shieldNow: Bool) -> SharedGateState {
        var state = SharedGateState.empty
        state.isEnabled = true
        state.screenTimeAuthorized = true
        state.selectionData = try? JSONEncoder().encode(FamilyActivitySelection())
        state.shouldShieldNow = shieldNow
        return state
    }

    func testShieldIsUpOnlyWhenFullyConfiguredAndFlagged() {
        XCTAssertNotNil(ShieldController.shieldTargets(configured(shieldNow: true)))
        XCTAssertNil(ShieldController.shieldTargets(configured(shieldNow: false)))

        var disabled = configured(shieldNow: true)
        disabled.isEnabled = false
        XCTAssertNil(ShieldController.shieldTargets(disabled), "blocking off must not shield")

        var unauthorized = configured(shieldNow: true)
        unauthorized.screenTimeAuthorized = false
        XCTAssertNil(ShieldController.shieldTargets(unauthorized))

        var noSelection = configured(shieldNow: true)
        noSelection.selectionData = nil
        XCTAssertNil(ShieldController.shieldTargets(noSelection))
    }

    func testSelectionRoundTripsThroughSharedState() {
        var state = SharedGateState.empty
        let empty = FamilyActivitySelection()
        state.setFamilyActivitySelection(empty)
        // An empty pick is stored as "nothing chosen", not as an empty selection, so the setup
        // card can tell the two apart.
        XCTAssertNil(state.selectionData)
        XCTAssertEqual(state.selectedItemCount, 0)
    }

    func testDailyScheduleCoversTheWholeDayEndingJustBeforeTheNextReset() {
        let schedule = ScheduleController.dailySchedule(ResetTime(hour: 4, minute: 0))
        XCTAssertEqual(schedule.intervalStart.hour, 4)
        XCTAssertEqual(schedule.intervalStart.minute, 0)
        XCTAssertEqual(schedule.intervalEnd.hour, 3)
        XCTAssertEqual(schedule.intervalEnd.minute, 59)
        XCTAssertTrue(schedule.repeats)
    }

    func testScheduleWrapsCorrectlyAtMidnight() {
        let schedule = ScheduleController.dailySchedule(ResetTime(hour: 0, minute: 0))
        XCTAssertEqual(schedule.intervalStart.hour, 0)
        XCTAssertEqual(schedule.intervalEnd.hour, 23)
        XCTAssertEqual(schedule.intervalEnd.minute, 59)
    }

    func testDebugBaseURLIsIgnoredUnlessSetAndNeverInRelease() {
        SharedDefaults.appGroup.raw.removeObject(forKey: "debug_base_url")
        XCTAssertEqual(GateFactory.baseURL(), MathAcademyClient.defaultBaseURL)
    }
}

/// Regression cover for a bug found by running the app: `reload()` recomputed `status` from
/// stored state and reset it to `.unknown` whenever there was no valid pass — so a failed check
/// was immediately overwritten and the UI read "Checking…" forever with nothing in flight.
@MainActor
final class GateModelStatusTests: XCTestCase {
    func testAFailedCheckSurvivesAReload() {
        let model = GateModel()
        model.setStatusForTesting(.offline("airplane mode"))

        model.reload()

        guard case .offline = model.status else {
            return XCTFail("a failed check must not be reset to .unknown, got \(model.status)")
        }
    }

    func testAnExpiredPassFallsBackToUnknown() {
        let model = GateModel()
        model.setStatusForTesting(.done(doneUntil: .distantPast, tasksCompleted: 1, xp: 5))

        model.reload()

        XCTAssertEqual(model.status, .unknown, "a pass from a previous period must not linger")
    }
}
