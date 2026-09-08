package com.mathgate

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * Watches window changes and throws up BlockingActivity when a blocked app comes to the front
 * while the gate is not Done. Everything here runs on the main thread, so the decision is a
 * cache read; the network refresh happens asynchronously inside the coordinator.
 */
class MathGateAccessibilityService : AccessibilityService() {
    private val coordinator by lazy { Gate.coordinator(applicationContext) }
    private var blockerShown = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        MgLog.d("accessibility service connected")
        if (Prefs.isEnabled(this)) coordinator.status() // warm the cache / kick a refresh
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // our own block screen; never resets blockerShown
        if (!Prefs.isEnabled(this)) {
            blockerShown = false
            return
        }
        if (pkg !in Prefs.getBlockedPackages(this)) {
            blockerShown = false
            return
        }
        val status = coordinator.status()
        if (status.allowsAccess) {
            blockerShown = false
            return
        }
        if (blockerShown) return
        blockerShown = true
        MgLog.d("blocking $pkg (gate=$status)")
        startActivity(
            Intent(this, BlockingActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
        )
    }

    override fun onInterrupt() {}
}
