package com.mathgate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime

class MaDateFormatTest {
    @Test
    fun matchesJavaScriptDateToString() {
        assertEquals(
            "Thu Sep 03 2026 11:30:00 GMT-0800 (Pacific Standard Time)",
            MaDateFormat.format(LocalDateTime.of(2026, 9, 3, 11, 30, 0)),
        )
    }

    @Test
    fun sundayIsIndexZero() {
        assertTrue(MaDateFormat.format(LocalDateTime.of(2026, 9, 6, 0, 5, 9)).startsWith("Sun Sep 06 2026 00:05:09"))
        assertTrue(MaDateFormat.format(LocalDateTime.of(2026, 9, 7, 0, 0, 0)).startsWith("Mon Sep 07 2026"))
    }

    @Test
    fun pathSegmentEncodesLikeEncodeUriComponent() {
        val seg = MaDateFormat.pathSegment(LocalDateTime.of(2026, 9, 3, 11, 30, 0))
        assertEquals("Thu%20Sep%2003%202026%2011%3A30%3A00%20GMT-0800%20(Pacific%20Standard%20Time)", seg)
        assertFalse(seg.contains("+"))
    }
}
