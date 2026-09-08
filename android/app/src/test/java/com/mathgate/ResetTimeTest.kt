package com.mathgate

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class ResetTimeTest {
    private val zone = ZoneId.of("Europe/London")

    @Test
    fun defaultIsFourAm() {
        assertEquals(4, ResetTime.DEFAULT.hour)
        assertEquals(0, ResetTime.DEFAULT.minute)
        assertEquals("04:00", ResetTime.DEFAULT.label())
    }

    @Test
    fun normalizesOutOfRangeValues() {
        val n = ResetTime(hour = 31, minute = -2).normalized()
        assertEquals(23, n.hour)
        assertEquals(0, n.minute)
        assertEquals("09:05", ResetTime(9, 5).label())
    }

    @Test
    fun nextResetIsTodayWhenStillAhead() {
        assertEquals(millis(2026, 9, 3, 4, 0), ResetTime.DEFAULT.nextResetMillis(millis(2026, 9, 3, 3, 30), zone))
    }

    @Test
    fun nextResetIsTomorrowWhenPassed() {
        assertEquals(millis(2026, 9, 4, 4, 0), ResetTime.DEFAULT.nextResetMillis(millis(2026, 9, 3, 4, 30), zone))
    }

    @Test
    fun periodStartIsYesterdayBeforeReset() {
        assertEquals(millis(2026, 9, 2, 4, 0), ResetTime.DEFAULT.currentPeriodStartMillis(millis(2026, 9, 3, 3, 59), zone))
    }

    @Test
    fun periodStartIsTodayAtAndAfterReset() {
        assertEquals(millis(2026, 9, 3, 4, 0), ResetTime.DEFAULT.currentPeriodStartMillis(millis(2026, 9, 3, 4, 0), zone))
        assertEquals(millis(2026, 9, 3, 4, 0), ResetTime.DEFAULT.currentPeriodStartMillis(millis(2026, 9, 3, 23, 59), zone))
    }

    @Test
    fun customResetTimeIsHonoured() {
        val reset = ResetTime(12, 30)
        assertEquals(millis(2026, 9, 2, 12, 30), reset.currentPeriodStartMillis(millis(2026, 9, 3, 10, 0), zone))
        assertEquals(millis(2026, 9, 3, 12, 30), reset.nextResetMillis(millis(2026, 9, 3, 10, 0), zone))
    }

    @Test
    fun periodSpansTwentyFiveHoursWhenClocksGoBack() {
        // 25 Oct 2026: BST -> GMT at 02:00, so 04:00 Sat -> 04:00 Sun is 25 real hours.
        val now = millis(2026, 10, 24, 10, 0)
        val start = ResetTime.DEFAULT.currentPeriodStartMillis(now, zone)
        val next = ResetTime.DEFAULT.nextResetMillis(now, zone)
        assertEquals(25L * 60 * 60 * 1000, next - start)
    }

    private fun millis(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        LocalDateTime.of(year, month, day, hour, minute).atZone(zone).toInstant().toEpochMilli()
}
