import Foundation

/// Turns a Math Academy fetch into a `GateStatus`. Every failure maps to a non-`.done` case,
/// which is what makes the gate fail closed.
public struct MathAcademyGateAPI: GateAPI {
    private let client: MathAcademyClient
    private let secrets: SecretStore
    private let usernameProvider: @Sendable () -> String?
    private let calendar: Calendar

    public init(
        client: MathAcademyClient,
        secrets: SecretStore,
        calendar: Calendar = .autoupdatingCurrent,
        usernameProvider: @escaping @Sendable () -> String?
    ) {
        self.client = client
        self.secrets = secrets
        self.calendar = calendar
        self.usernameProvider = usernameProvider
    }

    public func fetch(_ request: GateRequest) async -> GateStatus {
        guard let username = usernameProvider(), !username.isEmpty else {
            return .authFailed("no_credentials (add your Math Academy account in MathGate)")
        }
        guard let password = secrets.loadPassword(), !password.isEmpty else {
            return .authFailed("no_password (sign in again in MathGate)")
        }
        let creds = Credentials(username: username, password: password)

        do {
            let tasks = try await client.fetchRecentTasks(creds, calendar: calendar)
            let summary = TaskSummariser.summarise(tasks, periodStart: request.periodStart)
            if summary.isDone {
                return .done(
                    doneUntil: request.nextReset,
                    tasksCompleted: summary.tasksCompleted,
                    xp: summary.xp
                )
            }
            return .notDone(
                periodStart: request.periodStart,
                nextReset: request.nextReset,
                checkedAt: request.now
            )
        } catch let error as MathAcademyClient.ClientError {
            switch error {
            case .authFailed(let reason): return .authFailed(reason)
            case .offline(let message): return .offline(message)
            case .unexpectedResponse(let detail): return .unexpectedResponse(detail)
            }
        } catch {
            return .offline("\(error)")
        }
    }
}
