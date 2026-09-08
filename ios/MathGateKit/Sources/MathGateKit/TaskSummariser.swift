import Foundation

/// One entry from `/api/previous-tasks`, reduced to the fields the gate needs.
///
/// The Android port passes `JSONObject`s around; here they are decoded into a `Sendable` value
/// so results can cross the client actor's boundary. Unknown fields are ignored on purpose —
/// Math Academy adds them freely and none of them should be able to break the gate.
public struct MathAcademyTask: Equatable, Sendable {
    public let type: String?
    public let completed: Date?
    public let pointsAwarded: Int?
    public let points: Int?

    public var awardedPoints: Int { pointsAwarded ?? points ?? 0 }

    public init(type: String?, completed: Date?, pointsAwarded: Int?, points: Int?) {
        self.type = type
        self.completed = completed
        self.pointsAwarded = pointsAwarded
        self.points = points
    }
}

public struct TaskSummary: Equatable, Sendable {
    public let tasksCompleted: Int
    public let xp: Int
    public let latestCompleted: Date?

    /// The gate rule: at least one task of any type completed in the period.
    public var isDone: Bool { tasksCompleted >= 1 }

    public init(tasksCompleted: Int, xp: Int, latestCompleted: Date?) {
        self.tasksCompleted = tasksCompleted
        self.xp = xp
        self.latestCompleted = latestCompleted
    }
}

public enum TaskSummariserError: Error, Equatable {
    case notAJSONArray(String)
}

public enum TaskSummariser {
    /// Parses the body of `/api/previous-tasks`. A malformed element is skipped rather than
    /// fatal; only "this is not a JSON array at all" is treated as an API change.
    public static func parseArray(_ body: Data) throws -> [MathAcademyTask] {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: body, options: [])
        } catch {
            throw TaskSummariserError.notAJSONArray(error.localizedDescription)
        }
        guard let array = parsed as? [Any] else {
            throw TaskSummariserError.notAJSONArray("expected a JSON array, got \(type(of: parsed))")
        }
        return array.compactMap { element in
            guard let dict = element as? [String: Any] else { return nil }
            return MathAcademyTask(
                type: dict["type"] as? String,
                completed: completedDate(dict),
                pointsAwarded: intValue(dict["pointsAwarded"]),
                points: intValue(dict["points"])
            )
        }
    }

    public static func summarise(_ tasks: [MathAcademyTask], periodStart: Date) -> TaskSummary {
        var count = 0
        var xp = 0
        var latest: Date?
        for task in tasks {
            guard let completed = task.completed, completed >= periodStart else { continue }
            count += 1
            xp += task.awardedPoints
            latest = latest.map { max($0, completed) } ?? completed
        }
        return TaskSummary(tasksCompleted: count, xp: xp, latestCompleted: latest)
    }

    static func completedDate(_ task: [String: Any]) -> Date? {
        guard let raw = task["completed"] as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return parseInstant(raw)
    }

    static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let n as Int: return n
        case let n as Double: return Int(n)
        case let s as String: return Int(s)
        default: return nil
        }
    }

    /// ISO 8601, with and without fractional seconds; the API sends `2025-08-22T14:05:08.000Z`.
    public static func parseInstant(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
