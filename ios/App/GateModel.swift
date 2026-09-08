import FamilyControls
import Foundation
import MathGateKit
import Observation

@MainActor
@Observable
final class GateModel {
    private(set) var state: SharedGateState = .empty
    private(set) var status: GateStatus = .unknown
    private(set) var isChecking = false
    private(set) var isRequestingPermission = false
    var errorMessage: String?
    var signInMessage: String?

    /// Bound to the picker. Kept separate from `state` so a cancelled picker changes nothing.
    var selection = FamilyActivitySelection()
    var username: String = ""
    var password: String = ""
    var debugBaseURL: String = GateFactory.debugBaseURLString() ?? ""
    private(set) var isUsingDebugBaseURL = GateFactory.debugBaseURLString() != nil

    private let engine = GateFactory.makeEngine()

    init() {
        reload()
    }

    var isScreenTimeAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    var canEnableBlocking: Bool {
        isScreenTimeAuthorized && state.selectedItemCount > 0 && state.hasUsername
    }

    var missingSetupReason: String? {
        if !isScreenTimeAuthorized { return "Allow Screen Time access first." }
        if state.selectedItemCount == 0 { return "Choose at least one app to block." }
        if !state.hasUsername { return "Add your Math Academy account first." }
        return nil
    }

    func reload() {
        var loaded = SharedGateStateStore.load()
        loaded.screenTimeAuthorized = isScreenTimeAuthorized
        SharedGateStateStore.save(loaded)
        state = loaded
        selection = loaded.familyActivitySelection() ?? FamilyActivitySelection()
        username = loaded.username ?? ""
        if loaded.hasValidPass(now: Date()), let until = loaded.doneUntil {
            status = .done(doneUntil: until, tasksCompleted: loaded.doneTasks, xp: loaded.doneXP)
        } else if case .done = status {
            // A recorded pass has expired; fall back to unknown until the next check.
            status = .unknown
        }
        // Any other status is kept. A failed check is information, and overwriting it with
        // .unknown would leave the UI reading "Checking…" forever with nothing in flight.
    }

    func onForeground() async {
        reload()
        guard state.hasUsername else { return }
        await check(force: false)
    }

    func check(force: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        status = await engine.refresh(force: force)
        isChecking = false
        reload()
        ShieldController.apply(state)
    }

    func requestScreenTimeAccess() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            errorMessage = nil
        } catch {
            errorMessage = "Screen Time access was not granted: \(error.localizedDescription)"
        }
        reload()
    }

    func commitSelection() {
        mutate { $0.setFamilyActivitySelection(selection) }
    }

    func setBlocking(_ enabled: Bool) {
        if enabled, !canEnableBlocking {
            errorMessage = missingSetupReason
            return
        }
        errorMessage = nil
        mutate { $0.isEnabled = enabled }
        if enabled {
            // Nothing is known yet this period, so start shut and let a check open it.
            mutate { $0.shouldShieldNow = !$0.hasValidPass(now: Date()) }
            Task { await check(force: true) }
        } else {
            ShieldController.clear()
        }
    }

    func setResetTime(_ resetTime: ResetTime) {
        mutate { $0.resetTime = resetTime }
    }

    /// Signs in once to prove the credentials work, then stores them. The password field is
    /// cleared on success and the plaintext never leaves this method.
    func signIn() async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else {
            signInMessage = "Enter your Math Academy username and password."
            return
        }
        isChecking = true
        defer { isChecking = false }
        do {
            try GateFactory.secrets.save(password: password)
        } catch {
            signInMessage = "Could not save the password to the keychain: \(error)"
            return
        }
        mutate { $0.username = user }

        let result = await engine.refresh(force: true)
        switch result {
        case .done(_, let tasks, let xp):
            password = ""
            signInMessage = "Signed in. \(tasks) task\(tasks == 1 ? "" : "s"), \(xp) XP since \(state.resetTime.label)."
        case .notDone:
            password = ""
            signInMessage = "Signed in. Nothing completed since \(state.resetTime.label) yet."
        case .authFailed(let reason):
            GateFactory.secrets.deletePassword()
            mutate { $0.username = nil }
            signInMessage = "Sign-in failed: \(reason)"
        case .offline(let m):
            signInMessage = "Could not reach Math Academy: \(m)"
        case .unexpectedResponse(let d):
            signInMessage = "Unexpected response from Math Academy: \(d)"
        case .unknown:
            signInMessage = "No answer from Math Academy."
        }
        status = result
        reload()
        ShieldController.apply(state)
    }

    func signOut() {
        GateFactory.secrets.deletePassword()
        GateFactory.session.clearCookies()
        mutate { s in
            s.username = nil
            s.isEnabled = false
            s.shouldShieldNow = false
            s.donePeriodStart = nil
            s.doneUntil = nil
        }
        username = ""
        password = ""
        signInMessage = nil
        status = .unknown
        ShieldController.clear()
    }

    /// Debug builds only. Points the client at `tools/fake_mathacademy.py` so the whole flow can
    /// be exercised without a Math Academy account — and without sending junk logins to the real
    /// site while developing.
    func applyDebugBaseURL() {
        let trimmed = debugBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        GateFactory.setDebugBaseURL(trimmed.isEmpty ? nil : trimmed)
        isUsingDebugBaseURL = !trimmed.isEmpty
        GateFactory.session.clearCookies()
        GateFactory.session.loginBackoffUntil = nil
        status = .unknown
        signInMessage = trimmed.isEmpty
            ? "Using the real mathacademy.com."
            : "Using \(trimmed)."
    }

    #if DEBUG
    /// Test seam. The status is otherwise only set by a real check.
    func setStatusForTesting(_ status: GateStatus) { self.status = status }
    #endif

    private func mutate(_ body: (inout SharedGateState) -> Void) {
        var next = SharedGateStateStore.load()
        body(&next)
        next.screenTimeAuthorized = isScreenTimeAuthorized
        SharedGateStateStore.save(next)
        state = next
        ScheduleController.reconcile(next)
        ShieldController.apply(next)
    }
}
