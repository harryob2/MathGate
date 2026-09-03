package com.mathgate

import java.time.Instant
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.Locale

/**
 * The daily reset time. The "period" for a given instant starts at the most recent reset time
 * (today's if it has passed, otherwise yesterday's) and ends at the next one.
 * Copied from MasterKi's AppBlockingResetTime.
 */
data class ResetTime(
    val hour: Int = DEFAULT_HOUR,
    val minute: Int = DEFAULT_MINUTE,
) {
    fun normalized(): ResetTime = ResetTime(hour.coerceIn(0, 23), minute.coerceIn(0, 59))

    fun label(): String {
        val n = normalized()
        return String.format(Locale.US, "%02d:%02d", n.hour, n.minute)
    }

    fun currentPeriodStartMillis(nowMillis: Long, zoneId: ZoneId = ZoneId.systemDefault()): Long {
        val n = normalized()
        val now = Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDateTime()
        val todayReset = LocalDateTime.of(now.toLocalDate(), LocalTime.of(n.hour, n.minute))
        val periodStart = if (now.isBefore(todayReset)) todayReset.minusDays(1) else todayReset
        return periodStart.atZone(zoneId).toInstant().toEpochMilli()
    }

    fun nextResetMillis(nowMillis: Long, zoneId: ZoneId = ZoneId.systemDefault()): Long {
        val n = normalized()
        val now = Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDateTime()
        val todayReset = LocalDateTime.of(now.toLocalDate(), LocalTime.of(n.hour, n.minute))
        val next = if (now.isBefore(todayReset)) todayReset else todayReset.plusDays(1)
        return next.atZone(zoneId).toInstant().toEpochMilli()
    }

    companion object {
        const val DEFAULT_HOUR = 4
        const val DEFAULT_MINUTE = 0
        val DEFAULT = ResetTime()
    }
}
