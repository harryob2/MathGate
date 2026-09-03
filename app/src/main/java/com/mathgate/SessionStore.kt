package com.mathgate

/** Persists the Math Academy session cookies and login throttling state. */
interface SessionStore {
    var cookieSession: String?
    var cookieSig: String?
    /** Epoch millis; 0 = unknown. */
    var cookieExpiresMillis: Long
    var loginBackoffUntilMillis: Long
    var lastLoginMillis: Long

    fun clearCookies() {
        cookieSession = null
        cookieSig = null
        cookieExpiresMillis = 0L
    }

    fun hasCookies(): Boolean = !cookieSession.isNullOrEmpty() && !cookieSig.isNullOrEmpty()
}

/** Persists the "done for the current period" cache so a process restart needs no network. */
interface DoneStore {
    var doneUntilMillis: Long
    var donePeriodStartMillis: Long
    var doneTasks: Int
    var doneXp: Int

    fun clear() {
        doneUntilMillis = 0L
        donePeriodStartMillis = 0L
        doneTasks = 0
        doneXp = 0
    }
}
