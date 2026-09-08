import BackgroundTasks
import MathGateKit
import SwiftUI

@main
struct MathGateApp: App {
    @State private var model = GateModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                if phase == .background { BackgroundRefresh.schedule() }
                return
            }
            Task { await model.onForeground() }
        }
    }
}

/// Opportunistic unlock: iOS grants no always-running service, so completing a task on the web
/// normally unlocks when MathGate is next opened or the shield's own button is tapped. This
/// closes the gap when the OS feels generous. It is a bonus path, never the guarantee.
enum BackgroundRefresh {
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: MathGateIDs.backgroundRefreshTaskID,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
    }

    static func schedule() {
        let state = SharedGateStateStore.load()
        guard state.isConfiguredForShielding else { return }
        let request = BGAppRefreshTaskRequest(identifier: MathGateIDs.backgroundRefreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            MGLog.debug("background refresh not scheduled: \(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule() // always queue the next one first
        let boxed = UncheckedBox(task)
        let work = Task {
            let state = SharedGateStateStore.load()
            guard state.isConfiguredForShielding, !state.hasValidPass(now: Date()) else {
                boxed.value.setTaskCompleted(success: true)
                return
            }
            await GateFactory.makeEngine().refresh()
            ShieldController.reconcile()
            boxed.value.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
