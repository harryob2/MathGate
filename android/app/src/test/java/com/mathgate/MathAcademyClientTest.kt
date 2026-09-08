package com.mathgate

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** Drives MathAcademyClient against a loopback fake of mathacademy.com. */
class MathAcademyClientTest {
    private lateinit var server: FakeHttpServer
    private lateinit var client: MathAcademyClient
    private val store = InMemorySessionStore()
    private val zone = ZoneId.of("Europe/London")
    private var now = Instant.parse("2026-09-03T10:00:00Z").toEpochMilli()

    private val creds = Credentials("harry@example.com", "correct-horse")
    private var acceptedPassword = "correct-horse"
    private var validSession = "goodsession"
    private var tasksAlwaysHtml = false

    private var loginCount = 0
    private var tasksCount = 0
    private var lastLoginForm: Map<String, String> = emptyMap()
    private var lastTasksPath: String = ""
    private var lastUserAgent: String? = null

    private val fixture: String by lazy {
        javaClass.classLoader!!.getResource("previous-tasks-fixture.json")!!.readText()
    }

    @Before
    fun setUp() {
        server = FakeHttpServer { request ->
            lastUserAgent = request.header("User-Agent")
            dispatch(request)
        }
        client = MathAcademyClient(store, clock = { now }, baseUrl = server.baseUrl)
    }

    @After
    fun tearDown() {
        server.close()
    }

    private fun dispatch(request: FakeRequest): FakeResponse = when {
        request.path == "/login" -> handleLogin(request)
        request.path.startsWith("/api/previous-tasks/") -> handleTasks(request)
        else -> FakeResponse(404, listOf("Content-Type" to "text/html"), "not found")
    }

    private fun handleLogin(request: FakeRequest): FakeResponse {
        loginCount++
        lastLoginForm = request.formParams()
        if (lastLoginForm["password"] != acceptedPassword) {
            return FakeResponse(
                200,
                listOf("Content-Type" to "text/html; charset=utf-8"),
                "<html><body><form><div id=\"errorMessage\">Invalid username or password.</div></form></body></html>",
            )
        }
        val expires = httpDate(now + THIRTY_DAYS_MS)
        return FakeResponse(
            302,
            listOf(
                "Set-Cookie" to "session=$validSession; path=/; expires=$expires; secure; httponly",
                "Set-Cookie" to "session.sig=sig-1; path=/; expires=$expires; secure; httponly",
                "Location" to "/learn",
            ),
        )
    }

    private fun handleTasks(request: FakeRequest): FakeResponse {
        tasksCount++
        lastTasksPath = request.path
        val cookie = request.header("Cookie") ?: ""
        return when {
            tasksAlwaysHtml ->
                FakeResponse(200, listOf("Content-Type" to "text/html; charset=utf-8"), "<html>please log in</html>")
            cookie.contains("session=$validSession") && cookie.contains("session.sig=") ->
                FakeResponse(200, listOf("Content-Type" to "application/json; charset=utf-8"), fixture)
            else ->
                FakeResponse(302, listOf("Location" to "/session-expired"))
        }
    }

    private fun httpDate(millis: Long): String =
        DateTimeFormatter.RFC_1123_DATE_TIME.format(Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC))

    @Test
    fun freshSessionLogsInThenFetches() {
        val tasks = client.fetchRecentTasks(creds, zone)

        assertEquals(4, tasks.length())
        assertEquals(1, loginCount)
        assertEquals(1, tasksCount)
        assertEquals("harry@example.com", lastLoginForm["usernameOrEmail"])
        assertEquals("correct-horse", lastLoginForm["password"])
        assertEquals("LOGIN", lastLoginForm["submit"])
        assertTrue(store.hasCookies())
        assertEquals("goodsession", store.cookieSession)
        assertEquals("sig-1", store.cookieSig)
        assertTrue(Math.abs(store.cookieExpiresMillis - (now + THIRTY_DAYS_MS)) < 1000)
        assertEquals(now, store.lastLoginMillis)
    }

    @Test
    fun requestsTomorrowsLocalDateAsTheCursor() {
        client.fetchRecentTasks(creds, zone)
        // 2026-09-03T10:00Z is 11:00 in London, so the cursor is Friday 4 Sep 11:00.
        assertEquals(
            "/api/previous-tasks/Fri%20Sep%2004%202026%2011%3A00%3A00%20GMT-0800%20(Pacific%20Standard%20Time)",
            lastTasksPath,
        )
    }

    @Test
    fun validCookiesSkipLogin() {
        store.cookieSession = validSession
        store.cookieSig = "sig-1"
        store.cookieExpiresMillis = now + 20L * 24 * 3600 * 1000

        client.fetchRecentTasks(creds, zone)

        assertEquals(0, loginCount)
        assertEquals(1, tasksCount)
    }

    @Test
    fun unknownExpiryIsTreatedAsValid() {
        store.cookieSession = validSession
        store.cookieSig = "sig-1"
        store.cookieExpiresMillis = 0L

        client.fetchRecentTasks(creds, zone)

        assertEquals(0, loginCount)
    }

    @Test
    fun nearExpiryLogsInProactively() {
        store.cookieSession = validSession
        store.cookieSig = "sig-1"
        store.cookieExpiresMillis = now + 24L * 3600 * 1000

        client.fetchRecentTasks(creds, zone)

        assertEquals(1, loginCount)
        assertEquals(1, tasksCount)
    }

    @Test
    fun staleCookiesTriggerSingleReloginAndRetry() {
        store.cookieSession = "stale"
        store.cookieSig = "old-sig"
        store.cookieExpiresMillis = now + 20L * 24 * 3600 * 1000

        val tasks = client.fetchRecentTasks(creds, zone)

        assertEquals(4, tasks.length())
        assertEquals(2, tasksCount)
        assertEquals(1, loginCount)
        assertEquals(validSession, store.cookieSession)
    }

    @Test
    fun badPasswordFailsThenBacksOff() {
        acceptedPassword = "something-else"

        val first = assertThrows(MathAcademyClient.AuthFailedException::class.java) {
            client.fetchRecentTasks(creds, zone)
        }
        assertTrue(first.reason, first.reason.contains("bad_credentials"))
        assertTrue(first.reason, first.reason.contains("Invalid username or password"))
        assertEquals(1, loginCount)
        assertEquals(now + MathAcademyClient.LOGIN_BACKOFF_MS, store.loginBackoffUntilMillis)

        val second = assertThrows(MathAcademyClient.AuthFailedException::class.java) {
            client.fetchRecentTasks(creds, zone)
        }
        assertTrue(second.reason, second.reason.contains("login_backoff"))
        assertEquals(1, loginCount)

        now += MathAcademyClient.LOGIN_BACKOFF_MS + 1
        assertThrows(MathAcademyClient.AuthFailedException::class.java) { client.fetchRecentTasks(creds, zone) }
        assertEquals(2, loginCount)
    }

    @Test
    fun successfulLoginClearsBackoff() {
        store.loginBackoffUntilMillis = now - 1
        client.fetchRecentTasks(creds, zone)
        assertEquals(0L, store.loginBackoffUntilMillis)
    }

    @Test
    fun htmlAfterReloginIsUnexpectedResponse() {
        tasksAlwaysHtml = true

        val e = assertThrows(MathAcademyClient.UnexpectedResponseException::class.java) {
            client.fetchRecentTasks(creds, zone)
        }

        assertTrue(e.detail, e.detail.contains("after re-login"))
        // One initial login, then one re-login attempt because HTML looks like a dead session.
        assertEquals(2, loginCount)
        assertEquals(2, tasksCount)
    }

    @Test
    fun jsonObjectInsteadOfArrayIsUnexpectedResponse() {
        server.setHandler { request ->
            if (request.path == "/login") handleLogin(request)
            else FakeResponse(200, listOf("Content-Type" to "application/json"), """{"error":"nope"}""")
        }

        val e = assertThrows(MathAcademyClient.UnexpectedResponseException::class.java) {
            client.fetchRecentTasks(creds, zone)
        }
        assertTrue(e.detail, e.detail.contains("not a JSON array"))
    }

    @Test
    fun loginReportsBadCredentialsWithoutThrowing() {
        acceptedPassword = "something-else"

        val result = client.login(creds)

        assertTrue(result is MathAcademyClient.LoginResult.BadCredentials)
        assertEquals("Invalid username or password.", (result as MathAcademyClient.LoginResult.BadCredentials).detail)
    }

    @Test
    fun sendsABrowserUserAgent() {
        client.fetchRecentTasks(creds, zone)
        // Math Academy's session cookie records the user agent, so it must stay constant.
        assertEquals(MathAcademyClient.USER_AGENT, lastUserAgent)
    }

    companion object {
        private const val THIRTY_DAYS_MS = 30L * 24 * 3600 * 1000
    }
}
