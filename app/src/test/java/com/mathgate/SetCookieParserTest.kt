package com.mathgate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

class SetCookieParserTest {
    private val now = Instant.parse("2026-09-03T10:30:42Z").toEpochMilli()

    @Test
    fun parsesMathAcademySessionCookie() {
        val c = SetCookieParser.parse("session=EXAMPLE-SESSION-NOT-A-REAL-ONE; path=/; expires=Sat, 03 Oct 2026 10:30:42 GMT; secure; httponly", now)!!
        assertEquals("session", c.name)
        assertEquals("EXAMPLE-SESSION-NOT-A-REAL-ONE", c.value)
        assertEquals(Instant.parse("2026-10-03T10:30:42Z").toEpochMilli(), c.expiresMillis)
    }

    @Test
    fun parsesSignatureCookieNameWithDot() {
        val c = SetCookieParser.parse("session.sig=EXAMPLE-SIGNATURE-NOT-A-REAL-ONE; path=/; expires=Sat, 03 Oct 2026 10:30:42 GMT; secure; httponly", now)!!
        assertEquals("session.sig", c.name)
        assertEquals("EXAMPLE-SIGNATURE-NOT-A-REAL-ONE", c.value)
    }

    @Test
    fun missingExpiryIsNull() {
        assertNull(SetCookieParser.parse("session=abc; path=/; httponly", now)!!.expiresMillis)
    }

    @Test
    fun maxAgeIsRelativeToNow() {
        assertEquals(now + 3_600_000L, SetCookieParser.parse("session=abc; Max-Age=3600; Path=/", now)!!.expiresMillis)
    }

    @Test
    fun emptyValueIsKeptAsEmptyString() {
        assertEquals("", SetCookieParser.parse("session=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT", now)!!.value)
    }

    @Test
    fun garbageIsNull() {
        assertNull(SetCookieParser.parse("garbage", now))
        assertNull(SetCookieParser.parse("=value", now))
    }
}
