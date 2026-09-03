package com.mathgate

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

data class TaskSummary(val tasksCompleted: Int, val xp: Int, val latestCompletedMillis: Long?) {
    /** The gate rule: at least one task of any type completed in the period. */
    val isDone: Boolean get() = tasksCompleted >= 1
}

object TaskSummariser {
    /** Parses the body of /api/previous-tasks. Throws JSONException if it is not a JSON array. */
    fun parseArray(body: String): JSONArray {
        val parsed = JSONTokener(body).nextValue()
        return parsed as? JSONArray ?: throw JSONException("expected a JSON array, got ${parsed?.javaClass?.simpleName}")
    }

    fun summarise(tasks: JSONArray, periodStartMillis: Long): TaskSummary {
        var count = 0
        var xp = 0
        var latest: Long? = null
        for (i in 0 until tasks.length()) {
            val task = tasks.optJSONObject(i) ?: continue
            val completed = completedMillis(task) ?: continue
            if (completed < periodStartMillis) continue
            count++
            xp += awardedPoints(task)
            latest = maxOf(latest ?: Long.MIN_VALUE, completed)
        }
        return TaskSummary(count, xp, latest)
    }

    fun completedMillis(task: JSONObject): Long? {
        if (!task.has("completed") || task.isNull("completed")) return null
        val raw = task.optString("completed", "")
        if (raw.isBlank()) return null
        return parseInstant(raw)
    }

    private fun awardedPoints(task: JSONObject): Int =
        if (task.has("pointsAwarded") && !task.isNull("pointsAwarded")) task.optInt("pointsAwarded", 0)
        else task.optInt("points", 0)

    fun parseInstant(s: String): Long? = try {
        Instant.parse(s).toEpochMilli()
    } catch (e: DateTimeParseException) {
        try {
            OffsetDateTime.parse(s).toInstant().toEpochMilli()
        } catch (e2: DateTimeParseException) {
            null
        }
    }
}
