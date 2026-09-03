package com.mathgate

import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

data class ParsedCookie(val name: String, val value: String, val expiresMillis: Long?)

object SetCookieParser {
    /** Parses one Set-Cookie header value. Returns null if it has no name=value pair. */
    fun parse(header: String, nowMillis: Long): ParsedCookie? {
        val parts = header.split(';').map { it.trim() }
        val nameValue = parts.firstOrNull() ?: return null
        val eq = nameValue.indexOf('=')
        if (eq <= 0) return null
        val name = nameValue.substring(0, eq).trim()
        val value = nameValue.substring(eq + 1).trim()
        var expires: Long? = null
        for (attr in parts.drop(1)) {
            val i = attr.indexOf('=')
            val key = (if (i >= 0) attr.substring(0, i) else attr).trim().lowercase()
            val v = if (i >= 0) attr.substring(i + 1).trim() else ""
            when (key) {
                "expires" -> parseHttpDate(v)?.let { expires = it }
                // Max-Age wins over Expires per RFC 6265.
                "max-age" -> v.toLongOrNull()?.let { expires = nowMillis + it * 1000 }
            }
        }
        return ParsedCookie(name, value, expires)
    }

    fun parseHttpDate(s: String): Long? = try {
        ZonedDateTime.parse(s, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli()
    } catch (e: DateTimeParseException) {
        null
    }
}
