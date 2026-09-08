package com.mathgate

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class BlockingActivity : Activity(), GateStatusCoordinator.Listener {
    private val coordinator by lazy { Gate.coordinator(applicationContext) }
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var tvStatus: TextView
    private lateinit var btnRetry: Button

    private val pollRunnable = object : Runnable {
        override fun run() {
            coordinator.requestRefresh(force = false)
            handler.postDelayed(this, POLL_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
        )
        setContentView(R.layout.activity_blocking)
        tvStatus = findViewById(R.id.tvStatus)
        btnRetry = findViewById(R.id.btnRetry)

        btnRetry.setOnClickListener {
            btnRetry.isEnabled = false
            handler.postDelayed({ btnRetry.isEnabled = true }, 2_000)
            // Only show "checking" if a result is actually coming; otherwise the block screen would
            // hide the real reason it is locked behind a message that never resolves.
            if (coordinator.requestRefresh(force = true)) {
                tvStatus.text = "Checking Math Academy…"
            } else {
                render(coordinator.status())
            }
        }
        val btnOpen = findViewById<Button>(R.id.btnOpenMathAcademy)
        btnOpen.setOnClickListener { openMathAcademy() }
        val browser = PermissionHelper.defaultBrowserPackage(this)
        if (browser == null || browser in Prefs.getBlockedPackages(this)) btnOpen.visibility = View.GONE
        findViewById<Button>(R.id.btnGoHome).setOnClickListener { goHome() }
    }

    override fun onStart() {
        super.onStart()
        coordinator.addListener(this)
    }

    override fun onStop() {
        coordinator.removeListener(this)
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        val status = coordinator.status()
        if (status.allowsAccess) {
            finish()
            return
        }
        render(status)
        handler.postDelayed(pollRunnable, POLL_MS)
    }

    override fun onPause() {
        handler.removeCallbacks(pollRunnable)
        super.onPause()
    }

    override fun onGateStatusChanged(status: GateStatus) {
        if (status.allowsAccess) {
            finish()
        } else {
            render(status)
        }
    }

    private fun render(status: GateStatus) {
        val resetLabel = Prefs.getResetTime(this).label()
        tvStatus.text = when (status) {
            is GateStatus.Done -> "Unlocked."
            is GateStatus.NotDone ->
                "No Math Academy task completed since $resetLabel.\nDo any lesson, review, multistep or quiz, then check again."
            is GateStatus.Offline -> "Offline: ${status.message}.\nApps stay locked until Math Academy can be reached."
            is GateStatus.AuthFailed -> "Math Academy sign-in problem: ${status.reason}.\nOpen MathGate to fix your account details. Apps stay locked."
            is GateStatus.UnexpectedResponse -> "Unexpected response from Math Academy: ${status.detail}.\nApps stay locked. The site may have changed."
            GateStatus.Unknown -> "Checking Math Academy…"
        }
    }

    private fun openMathAcademy() {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PermissionHelper.LEARN_URL)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            finish()
        } catch (e: ActivityNotFoundException) {
            tvStatus.text = "No browser available to open Math Academy."
        }
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            },
        )
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        goHome()
    }

    companion object {
        const val POLL_MS = 30_000L

        fun formatTime(millis: Long, zone: ZoneId = ZoneId.systemDefault()): String =
            DateTimeFormatter.ofPattern("EEE HH:mm").format(Instant.ofEpochMilli(millis).atZone(zone))
    }
}
