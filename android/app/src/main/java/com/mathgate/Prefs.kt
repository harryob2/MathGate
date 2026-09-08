package com.mathgate

import android.content.Context
import android.content.SharedPreferences

object Prefs {
    private const val NAME = "mathgate_prefs"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_BLOCKED_PACKAGES = "blocked_packages"
    private const val KEY_RESET_HOUR = "reset_hour"
    private const val KEY_RESET_MINUTE = "reset_minute"
    private const val KEY_MA_USERNAME = "ma_username"
    private const val KEY_MA_PASSWORD_BLOB = "ma_password_blob"
    private const val KEY_DEBUG_BASE_URL = "debug_base_url"

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun getBlockedPackages(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()

    fun setBlockedPackages(context: Context, packages: Set<String>) {
        prefs(context).edit().putStringSet(KEY_BLOCKED_PACKAGES, packages.toSet()).apply()
    }

    fun getResetTime(context: Context): ResetTime {
        val p = prefs(context)
        return ResetTime(
            hour = p.getInt(KEY_RESET_HOUR, ResetTime.DEFAULT_HOUR),
            minute = p.getInt(KEY_RESET_MINUTE, ResetTime.DEFAULT_MINUTE),
        ).normalized()
    }

    fun setResetTime(context: Context, resetTime: ResetTime) {
        val n = resetTime.normalized()
        prefs(context).edit().putInt(KEY_RESET_HOUR, n.hour).putInt(KEY_RESET_MINUTE, n.minute).apply()
    }

    fun getUsername(context: Context): String? = prefs(context).getString(KEY_MA_USERNAME, null)

    fun hasCredentials(context: Context): Boolean {
        val p = prefs(context)
        return !p.getString(KEY_MA_USERNAME, null).isNullOrEmpty() && !p.getString(KEY_MA_PASSWORD_BLOB, null).isNullOrEmpty()
    }

    /** Null when nothing is saved or the Keystore can no longer decrypt the password. */
    fun getCredentials(context: Context): Credentials? {
        val p = prefs(context)
        val username = p.getString(KEY_MA_USERNAME, null)?.takeIf { it.isNotEmpty() } ?: return null
        val blob = p.getString(KEY_MA_PASSWORD_BLOB, null)?.takeIf { it.isNotEmpty() } ?: return null
        val password = SecretStore.decrypt(blob) ?: return null
        return Credentials(username, password)
    }

    fun setCredentials(context: Context, creds: Credentials) {
        prefs(context).edit()
            .putString(KEY_MA_USERNAME, creds.username)
            .putString(KEY_MA_PASSWORD_BLOB, SecretStore.encrypt(creds.password))
            .apply()
    }

    /**
     * Debug builds only: point the client at a local fake of mathacademy.com. Ignored by release
     * builds, which always use [MathAcademyClient.DEFAULT_BASE_URL].
     */
    fun getDebugBaseUrl(context: Context): String? =
        prefs(context).getString(KEY_DEBUG_BASE_URL, null)?.takeIf { it.isNotBlank() }

    fun clearCredentials(context: Context) {
        prefs(context).edit().remove(KEY_MA_USERNAME).remove(KEY_MA_PASSWORD_BLOB).apply()
    }
}

class PrefsSessionStore(context: Context) : SessionStore {
    private val p = Prefs.prefs(context.applicationContext)

    override var cookieSession: String?
        get() = p.getString("cookie_session", null)
        set(value) = p.edit().putString("cookie_session", value).apply()

    override var cookieSig: String?
        get() = p.getString("cookie_session_sig", null)
        set(value) = p.edit().putString("cookie_session_sig", value).apply()

    override var cookieExpiresMillis: Long
        get() = p.getLong("cookie_expires_millis", 0L)
        set(value) = p.edit().putLong("cookie_expires_millis", value).apply()

    override var loginBackoffUntilMillis: Long
        get() = p.getLong("login_backoff_until_millis", 0L)
        set(value) = p.edit().putLong("login_backoff_until_millis", value).apply()

    override var lastLoginMillis: Long
        get() = p.getLong("last_login_millis", 0L)
        set(value) = p.edit().putLong("last_login_millis", value).apply()
}

class PrefsDoneStore(context: Context) : DoneStore {
    private val p = Prefs.prefs(context.applicationContext)

    override var doneUntilMillis: Long
        get() = p.getLong("done_until_millis", 0L)
        set(value) = p.edit().putLong("done_until_millis", value).apply()

    override var donePeriodStartMillis: Long
        get() = p.getLong("done_period_start_millis", 0L)
        set(value) = p.edit().putLong("done_period_start_millis", value).apply()

    override var doneTasks: Int
        get() = p.getInt("done_tasks", 0)
        set(value) = p.edit().putInt("done_tasks", value).apply()

    override var doneXp: Int
        get() = p.getInt("done_xp", 0)
        set(value) = p.edit().putInt("done_xp", value).apply()
}
