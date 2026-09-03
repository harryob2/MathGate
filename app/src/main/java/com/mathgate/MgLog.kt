package com.mathgate

import android.util.Log

/** Logging wrapper. Uses Log.e because Log.i/Log.d are hidden in logcat on Android 16 (see CLAUDE.md). */
object MgLog {
    const val TAG = "MathGate"

    fun d(msg: String) {
        Log.e(TAG, msg)
    }

    fun w(msg: String, t: Throwable? = null) {
        Log.e(TAG, msg, t)
    }
}
