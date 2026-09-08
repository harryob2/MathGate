import FamilyControls
import MathGateKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: GateModel
    @State private var isPickerPresented = false
    @State private var isResetPickerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusCard(model: model)
                    SetupCard(model: model, isPickerPresented: $isPickerPresented)
                    AccountCard(model: model)
                    ResetCard(model: model, isPresented: $isResetPickerPresented)
                    #if DEBUG
                    DeveloperCard(model: model)
                    #endif
                    Text("Not affiliated with Math Academy.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .background(Color.mgBackground)
            .navigationTitle("MathGate")
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $model.selection)
            .onChange(of: isPickerPresented) { _, presented in
                if !presented { model.commitSelection() }
            }
            .alert("MathGate", isPresented: .constant(model.errorMessage != nil)) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

// MARK: - Status

private struct StatusCard: View {
    @Bindable var model: GateModel

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(.headline)
                Spacer()
                if model.isChecking { ProgressView().controlSize(.small) }
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await model.check(force: true) }
            } label: {
                Text("Check now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mgAccent)
            .disabled(model.isChecking || !model.state.hasUsername)
        }
    }

    private var headline: String {
        switch model.status {
        case .done: return "Unlocked"
        case .notDone: return "Locked"
        case .offline: return "Locked — offline"
        case .authFailed: return "Locked — sign-in failed"
        case .unexpectedResponse: return "Locked — unexpected response"
        case .unknown: return model.state.hasUsername ? "Checking…" : "Not set up"
        }
    }

    private var detail: String {
        switch model.status {
        case .done(let until, let tasks, let xp):
            let time = until.formatted(date: .omitted, time: .shortened)
            return "\(tasks) task\(tasks == 1 ? "" : "s"), \(xp) XP since \(model.state.resetTime.label). "
                + "Apps stay open until \(time)."
        case .notDone:
            return "No Math Academy task since \(model.state.resetTime.label). "
                + "Any lesson, review, multistep or quiz will unlock your apps."
        case .offline(let m):
            return "\(m)\nApps stay locked while MathGate cannot confirm a completed task."
        case .authFailed(let r):
            return "\(r)\nRe-enter your Math Academy details below."
        case .unexpectedResponse(let d):
            return "\(d)\nMath Academy's API may have changed."
        case .unknown:
            return model.state.hasUsername
                ? "Asking Math Academy…"
                : "Add your Math Academy account and choose apps to block."
        }
    }
}

// MARK: - Setup

private struct SetupCard: View {
    @Bindable var model: GateModel
    @Binding var isPickerPresented: Bool

    var body: some View {
        Card {
            Text("Setup").font(.headline)

            Row(title: "Screen Time access", value: model.isScreenTimeAuthorized ? "Granted" : "Missing") {
                if !model.isScreenTimeAuthorized {
                    Button("Allow") { Task { await model.requestScreenTimeAccess() } }
                        .disabled(model.isRequestingPermission)
                }
            }

            Row(
                title: "Blocked apps",
                value: model.state.selectedItemCount == 0
                    ? "None"
                    : "\(model.state.selectedItemCount) selected"
            ) {
                Button("Choose") { isPickerPresented = true }
                    .disabled(!model.isScreenTimeAuthorized)
            }

            Toggle("Blocking enabled", isOn: Binding(
                get: { model.state.isEnabled },
                set: { model.setBlocking($0) }
            ))
            .tint(.mgAccent)

            if let reason = model.missingSetupReason {
                Text(reason).font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Account

private struct AccountCard: View {
    @Bindable var model: GateModel

    var body: some View {
        Card {
            Text("Math Academy account").font(.headline)
            Text("Stored on this iPhone only, in the keychain. MathGate has no server.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Username or email", text: $model.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $model.password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    Task { await model.signIn() }
                } label: {
                    Text("Sign in & test").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mgAccent)
                .disabled(model.isChecking)

                if model.state.hasUsername {
                    Button("Sign out", role: .destructive) { model.signOut() }
                }
            }

            if let message = model.signInMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Reset time

private struct ResetCard: View {
    @Bindable var model: GateModel
    @Binding var isPresented: Bool

    var body: some View {
        Card {
            Text("Daily reset").font(.headline)
            Text("The day rolls over at this time, so a late night still counts as the same day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            DatePicker(
                "Resets at",
                selection: Binding(
                    get: { dateFor(model.state.resetTime) },
                    set: { model.setResetTime(resetTimeFor($0)) }
                ),
                displayedComponents: .hourAndMinute
            )
        }
    }

    private func dateFor(_ resetTime: ResetTime) -> Date {
        let n = resetTime.normalized()
        return Calendar.current.date(
            from: DateComponents(hour: n.hour, minute: n.minute)
        ) ?? Date()
    }

    private func resetTimeFor(_ date: Date) -> ResetTime {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ResetTime(hour: c.hour ?? 4, minute: c.minute ?? 0)
    }
}

// MARK: - Developer

#if DEBUG
/// Never compiled into a release build. Lets the whole flow be exercised against
/// `tools/fake_mathacademy.py` without a Math Academy account.
private struct DeveloperCard: View {
    @Bindable var model: GateModel

    var body: some View {
        Card {
            Text("Developer").font(.headline)
            Text("Debug builds only. Leave empty to use the real mathacademy.com.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // Shows what is *in effect*, not what is typed. Without this it is easy to think a
            // fake server is in use while every request is really going to Math Academy.
            Text("Currently signing in to: \(GateFactory.baseURL().absoluteString)")
                .font(.footnote.monospaced())
                .foregroundStyle(model.isUsingDebugBaseURL ? .green : .orange)
            TextField("http://127.0.0.1:8799", text: $model.debugBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
            Button("Use this base URL") { model.applyDebugBaseURL() }
                .buttonStyle(.bordered)
        }
    }
}
#endif

// MARK: - Shared chrome

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.mgSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    let value: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

extension Color {
    /// Matches the Android build and the website: #0F0F14 / #1A1A24 / #7C4DFF.
    static let mgBackground = Color(red: 0.059, green: 0.059, blue: 0.078)
    static let mgSurface = Color(red: 0.102, green: 0.102, blue: 0.141)
    static let mgAccent = Color(red: 0.486, green: 0.302, blue: 1.0)
}
