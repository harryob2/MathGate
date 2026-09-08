package com.mathgate

import java.net.URLEncoder
import java.time.LocalDateTime
import java.util.Locale

/**
 * Math Academy's /api/previous-tasks/{date} expects the JavaScript Date.toString() shape, e.g.
 * "Thu Sep 03 2026 11:30:00 GMT-0800 (Pacific Standard Time)", URL-encoded the way
 * encodeURIComponent does it. The PST label is fixed regardless of the caller's zone
 * (this mirrors the community mathacademy-stats extension, which is known to work).
 */
object MaDateFormat {
    private val DAYS = arrayOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
    private val MONTHS = arrayOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

    fun format(dt: LocalDateTime): String {
        val dow = DAYS[dt.dayOfWeek.value % 7] // java DayOfWeek: MONDAY=1 .. SUNDAY=7
        return String.format(
            Locale.US,
            "%s %s %02d %d %02d:%02d:%02d GMT-0800 (Pacific Standard Time)",
            dow, MONTHS[dt.monthValue - 1], dt.dayOfMonth, dt.year, dt.hour, dt.minute, dt.second,
        )
    }

    fun pathSegment(dt: LocalDateTime): String = encodeUriComponent(format(dt))

    /** java.net.URLEncoder is form-encoding; undo the differences from JS encodeURIComponent. */
    fun encodeUriComponent(s: String): String =
        URLEncoder.encode(s, "UTF-8")
            .replace("+", "%20")
            .replace("%21", "!")
            .replace("%27", "'")
            .replace("%28", "(")
            .replace("%29", ")")
            .replace("%7E", "~")
}
