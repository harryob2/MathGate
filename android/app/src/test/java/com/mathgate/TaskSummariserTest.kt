package com.mathgate

import org.json.JSONArray
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class TaskSummariserTest {
    private val fixture: JSONArray by lazy {
        TaskSummariser.parseArray(javaClass.classLoader!!.getResource("previous-tasks-fixture.json")!!.readText())
    }

    private fun t(iso: String) = Instant.parse(iso).toEpochMilli()

    @Test
    fun fixtureParsesAsArrayOfFourTasks() {
        assertEquals(4, fixture.length())
    }

    @Test
    fun countsOnlyTasksCompletedInPeriod() {
        val s = TaskSummariser.summarise(fixture, t("2025-08-22T00:00:00Z"))
        assertEquals(1, s.tasksCompleted)
        assertEquals(7, s.xp)
        assertEquals(t("2025-08-22T14:05:08Z"), s.latestCompletedMillis)
        assertTrue(s.isDone)
    }

    @Test
    fun sumsXpAcrossAllTaskTypes() {
        val s = TaskSummariser.summarise(fixture, t("2025-08-16T00:00:00Z"))
        assertEquals(4, s.tasksCompleted)
        assertEquals(7 + 6 + 3 + 9, s.xp)
    }

    @Test
    fun nothingInPeriodIsNotDone() {
        val s = TaskSummariser.summarise(fixture, t("2025-08-23T00:00:00Z"))
        assertEquals(0, s.tasksCompleted)
        assertEquals(0, s.xp)
        assertFalse(s.isDone)
    }

    @Test
    fun periodStartBoundaryIsInclusive() {
        val exact = t("2025-08-22T14:05:08Z")
        assertEquals(1, TaskSummariser.summarise(fixture, exact).tasksCompleted)
        assertEquals(0, TaskSummariser.summarise(fixture, exact + 1).tasksCompleted)
    }

    @Test
    fun skipsNullCompletedAndFallsBackToPoints() {
        val tasks = JSONArray(
            """[
              {"type":"Lesson","completed":null,"points":5,"pointsAwarded":5},
              {"type":"Review","completed":"2025-08-22T10:00:00.000Z","points":4,"pointsAwarded":null},
              {"type":"Quiz","started":"2025-08-22T09:00:00.000Z"}
            ]""",
        )
        val s = TaskSummariser.summarise(tasks, t("2025-08-22T00:00:00Z"))
        assertEquals(1, s.tasksCompleted)
        assertEquals(4, s.xp)
    }

    @Test
    fun nonArrayBodiesAreRejected() {
        assertThrows(JSONException::class.java) { TaskSummariser.parseArray("""{"error":"nope"}""") }
        assertThrows(JSONException::class.java) { TaskSummariser.parseArray("<html><body>login</body></html>") }
    }
}
