package com.mathgate

import org.json.JSONArray
import org.json.JSONException
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.time.ZoneId

/**
 * Minimal Math Academy web client: form login, two session cookies, one JSON endpoint.
 * Never logs cookie values or passwords.
 */
class MathAcademyClient(
    private val session: SessionStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val baseUrl: String = DEFAULT_BASE_URL,
) {
    class AuthFailedException(val reason: String) : Exception(reason)
    class UnexpectedResponseException(val detail: String) : Exception(detail)

    sealed class LoginResult {
        object Success : LoginResult()
        data class BadCredentials(val detail: String) : LoginResult()
    }

    data class Response(val code: Int, val contentType: String?, val location: String?, val body: String)

    /** POSTs the login form. Throws IOException when offline. */
    fun login(creds: Credentials): LoginResult {
        session.clearCookies()
        val form = "usernameOrEmail=" + formEncode(creds.username) +
            "&password=" + formEncode(creds.password) +
            "&submit=LOGIN"
        val resp = request("POST", "/login", form)
        MgLog.d("login -> HTTP ${resp.code} location=${resp.location ?: "-"}")
        if (resp.code in 300..399) {
            val loc = resp.location ?: ""
            if (loc.contains("login", ignoreCase = true) || loc.contains("session-expired", ignoreCase = true)) {
                return LoginResult.BadCredentials("redirected to $loc")
            }
            if (!session.hasCookies()) return LoginResult.BadCredentials("no session cookie after login")
            session.lastLoginMillis = clock()
            return LoginResult.Success
        }
        if (resp.code == 200) {
            return LoginResult.BadCredentials(extractLoginError(resp.body) ?: "login page returned (HTTP 200)")
        }
        throw UnexpectedResponseException("login HTTP ${resp.code}")
    }

    /** Logs in if there is no session or it is about to expire. */
    fun ensureSession(creds: Credentials) {
        val now = clock()
        val exp = session.cookieExpiresMillis
        val fresh = session.hasCookies() && (exp <= 0L || exp - now > RELOGIN_MARGIN_MS)
        if (fresh) return
        loginOrThrow(creds, now)
    }

    /**
     * Fetches the most recent completed tasks. Re-logs in once if the session turns out to be dead.
     * Throws AuthFailedException, UnexpectedResponseException, or IOException (offline).
     */
    fun fetchRecentTasks(creds: Credentials, zone: ZoneId): JSONArray {
        ensureSession(creds)
        val localNow = Instant.ofEpochMilli(clock()).atZone(zone).toLocalDateTime()
        // The site omits the (mis-spelled) "minumum" query param when it wants the default of 25,
        // so this is byte-for-byte the request the logged-in browser makes.
        val path = "/api/previous-tasks/" + MaDateFormat.pathSegment(localNow.plusDays(1))
        var resp = request("GET", path)
        MgLog.d("previous-tasks -> HTTP ${resp.code} type=${resp.contentType ?: "-"}")
        if (looksExpired(resp)) {
            MgLog.d("session looks expired; re-logging in")
            loginOrThrow(creds, clock())
            resp = request("GET", path)
            MgLog.d("previous-tasks (retry) -> HTTP ${resp.code} type=${resp.contentType ?: "-"}")
        }
        if (looksExpired(resp)) {
            throw UnexpectedResponseException("previous-tasks HTTP ${resp.code} (${resp.contentType ?: "no content-type"}) after re-login")
        }
        return try {
            TaskSummariser.parseArray(resp.body)
        } catch (e: JSONException) {
            throw UnexpectedResponseException("previous-tasks is not a JSON array: ${e.message}")
        }
    }

    private fun loginOrThrow(creds: Credentials, now: Long) {
        if (now < session.loginBackoffUntilMillis) {
            val secs = (session.loginBackoffUntilMillis - now) / 1000
            throw AuthFailedException("login_backoff (${secs}s left after a failed sign-in)")
        }
        when (val r = login(creds)) {
            is LoginResult.Success -> session.loginBackoffUntilMillis = 0L
            is LoginResult.BadCredentials -> {
                session.loginBackoffUntilMillis = now + LOGIN_BACKOFF_MS
                throw AuthFailedException("bad_credentials (${r.detail})")
            }
        }
    }

    private fun looksExpired(resp: Response): Boolean {
        if (resp.code in 300..399) return true
        if (resp.code == 401 || resp.code == 403 || resp.code == 404) return true
        val type = resp.contentType ?: ""
        return !type.contains("json", ignoreCase = true)
    }

    private fun request(method: String, path: String, form: String? = null): Response {
        val conn = URL(baseUrl + path).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.instanceFollowRedirects = false
            conn.connectTimeout = CONNECT_TIMEOUT_MS
            conn.readTimeout = READ_TIMEOUT_MS
            conn.setRequestProperty("User-Agent", USER_AGENT)
            conn.setRequestProperty("Accept-Language", "en-GB,en;q=0.9")
            if (path.startsWith("/api/")) {
                conn.setRequestProperty("Accept", "application/json, text/plain, */*")
                conn.setRequestProperty("Referer", "$baseUrl/learn")
            } else {
                conn.setRequestProperty("Accept", "text/html,application/xhtml+xml,*/*;q=0.8")
            }
            cookieHeader()?.let { conn.setRequestProperty("Cookie", it) }
            if (form != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                conn.setRequestProperty("Origin", baseUrl)
                conn.setRequestProperty("Referer", "$baseUrl/login")
                val bytes = form.toByteArray(Charsets.UTF_8)
                conn.setFixedLengthStreamingMode(bytes.size)
                conn.outputStream.use { it.write(bytes) }
            }
            val code = conn.responseCode
            absorbCookies(conn)
            val body = readBody(conn, code)
            return Response(code, conn.contentType, conn.getHeaderField("Location"), body)
        } finally {
            conn.disconnect()
        }
    }

    private fun readBody(conn: HttpURLConnection, code: Int): String {
        val stream: InputStream? = try {
            if (code >= 400) conn.errorStream else conn.inputStream
        } catch (e: IOException) {
            conn.errorStream
        }
        if (stream == null) return ""
        return stream.use { input ->
            val buf = java.io.ByteArrayOutputStream()
            val chunk = ByteArray(16 * 1024)
            var total = 0
            while (true) {
                val n = input.read(chunk)
                if (n < 0) break
                total += n
                if (total > MAX_BODY_BYTES) break
                buf.write(chunk, 0, n)
            }
            buf.toString("UTF-8")
        }
    }

    private fun absorbCookies(conn: HttpURLConnection) {
        val now = clock()
        for ((key, values) in conn.headerFields) {
            if (key == null || !key.equals("Set-Cookie", ignoreCase = true)) continue
            for (header in values) {
                val cookie = SetCookieParser.parse(header, now) ?: continue
                when (cookie.name) {
                    "session" -> {
                        session.cookieSession = cookie.value.ifEmpty { null }
                        cookie.expiresMillis?.let { session.cookieExpiresMillis = it }
                    }
                    "session.sig" -> session.cookieSig = cookie.value.ifEmpty { null }
                }
            }
        }
    }

    private fun cookieHeader(): String? {
        val s = session.cookieSession ?: return null
        val sig = session.cookieSig ?: return null
        if (s.isEmpty() || sig.isEmpty()) return null
        return "session=$s; session.sig=$sig"
    }

    private fun formEncode(s: String): String = URLEncoder.encode(s, "UTF-8")

    private fun extractLoginError(html: String): String? {
        val m = Regex("<div id=\"errorMessage\">(.*?)</div>", RegexOption.DOT_MATCHES_ALL).find(html) ?: return null
        val text = m.groupValues[1].replace(Regex("<[^>]+>"), " ").replace(Regex("\\s+"), " ").trim()
        return text.ifEmpty { null }
    }

    companion object {
        const val DEFAULT_BASE_URL = "https://www.mathacademy.com"
        const val USER_AGENT =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        const val CONNECT_TIMEOUT_MS = 10_000
        const val READ_TIMEOUT_MS = 15_000
        const val MAX_BODY_BYTES = 4 * 1024 * 1024
        const val RELOGIN_MARGIN_MS = 2L * 24 * 60 * 60 * 1000
        const val LOGIN_BACKOFF_MS = 10L * 60 * 1000
    }
}
