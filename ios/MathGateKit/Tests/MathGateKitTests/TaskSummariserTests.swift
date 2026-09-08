import XCTest
@testable import MathGateKit

final class TaskSummariserTests: XCTestCase {
    private let periodStart = TaskSummariser.parseInstant("2026-09-03T04:00:00.000Z")!

    private func body(_ json: String) -> Data { Data(json.utf8) }

    func testCountsOnlyTasksInsideThePeriod() throws {
        let tasks = try TaskSummariser.parseArray(body("""
        [
          {"id":1,"type":"Lesson","points":10,"pointsAwarded":9,"completed":"2026-09-03T09:12:00.000Z"},
          {"id":2,"type":"Review","points":5,"pointsAwarded":5,"completed":"2026-09-03T05:00:00.000Z"},
          {"id":3,"type":"Quiz","points":20,"pointsAwarded":18,"completed":"2026-09-02T22:00:00.000Z"}
        ]
        """))
        let summary = TaskSummariser.summarise(tasks, periodStart: periodStart)
        XCTAssertEqual(summary.tasksCompleted, 2)
        XCTAssertEqual(summary.xp, 14)
        XCTAssertEqual(summary.latestCompleted, TaskSummariser.parseInstant("2026-09-03T09:12:00.000Z"))
        XCTAssertTrue(summary.isDone)
    }

    /// The gate rule is "any type counts", so this must not special-case Lesson.
    func testAnyTaskTypeSatisfiesTheGate() throws {
        for type in ["Lesson", "Review", "Multistep", "Quiz", "SomethingNew"] {
            let tasks = try TaskSummariser.parseArray(body(
                #"[{"type":"\#(type)","pointsAwarded":1,"completed":"2026-09-03T06:00:00.000Z"}]"#
            ))
            XCTAssertTrue(
                TaskSummariser.summarise(tasks, periodStart: periodStart).isDone,
                "\(type) should count"
            )
        }
    }

    func testCompletionExactlyAtThePeriodStartCounts() throws {
        let tasks = try TaskSummariser.parseArray(body(
            #"[{"pointsAwarded":3,"completed":"2026-09-03T04:00:00.000Z"}]"#
        ))
        XCTAssertEqual(TaskSummariser.summarise(tasks, periodStart: periodStart).tasksCompleted, 1)
    }

    func testUnfinishedTasksAreIgnored() throws {
        let tasks = try TaskSummariser.parseArray(body("""
        [{"id":1,"type":"Lesson","completed":null},{"id":2,"type":"Lesson"}]
        """))
        XCTAssertEqual(TaskSummariser.summarise(tasks, periodStart: periodStart).tasksCompleted, 0)
        XCTAssertFalse(TaskSummariser.summarise(tasks, periodStart: periodStart).isDone)
    }

    func testFallsBackToPointsWhenPointsAwardedIsMissing() throws {
        let tasks = try TaskSummariser.parseArray(body(
            #"[{"points":7,"completed":"2026-09-03T06:00:00.000Z"}]"#
        ))
        XCTAssertEqual(TaskSummariser.summarise(tasks, periodStart: periodStart).xp, 7)
    }

    func testAcceptsTimestampsWithoutFractionalSeconds() {
        XCTAssertNotNil(TaskSummariser.parseInstant("2026-09-03T06:00:00Z"))
        XCTAssertNotNil(TaskSummariser.parseInstant("2026-09-03T06:00:00.000Z"))
        XCTAssertNil(TaskSummariser.parseInstant("not a date"))
    }

    /// An unfamiliar field or a stray element must not take the gate down; only "this is not an
    /// array" counts as the API having changed.
    func testUnknownFieldsAreIgnoredAndOddElementsSkipped() throws {
        let tasks = try TaskSummariser.parseArray(body("""
        [
          {"newField":{"nested":true},"pointsAwarded":2,"completed":"2026-09-03T06:00:00.000Z"},
          "a bare string",
          12345
        ]
        """))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(TaskSummariser.summarise(tasks, periodStart: periodStart).xp, 2)
    }

    func testHTMLBodyIsReportedAsAnAPIChange() {
        XCTAssertThrowsError(try TaskSummariser.parseArray(body("<html>signed out</html>"))) { error in
            guard case TaskSummariserError.notAJSONArray = error else {
                return XCTFail("got \(error)")
            }
        }
    }

    func testJSONObjectInsteadOfArrayIsReportedAsAnAPIChange() {
        XCTAssertThrowsError(try TaskSummariser.parseArray(body(#"{"tasks":[]}"#))) { error in
            guard case TaskSummariserError.notAJSONArray = error else {
                return XCTFail("got \(error)")
            }
        }
    }
}
