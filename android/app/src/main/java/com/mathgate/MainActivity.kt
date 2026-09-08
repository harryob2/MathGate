package com.mathgate

import android.app.Activity
import android.app.TimePickerDialog
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.io.IOException
import java.time.ZoneId
import java.util.concurrent.Executors

class MainActivity : Activity(), GateStatusCoordinator.Listener {
    private val coordinator by lazy { Gate.coordinator(applicationContext) }
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private lateinit var tvStatus: TextView
    private lateinit var switchEnabled: Switch
    private lateinit var btnAccessibility: Button
    private lateinit var btnBattery: Button
    private lateinit var tvBlockedApps: TextView
    private lateinit var tvBrowserWarning: TextView
    private lateinit var tvAccountStatus: TextView
    private lateinit var etUsername: EditText
    private lateinit var etPassword: EditText
    private lateinit var btnSignIn: Button
    private lateinit var btnSignOut: Button
    private lateinit var btnResetTime: Button

    /** Transient result of the last sign-in attempt, shown until the next refresh of account state. */
    private var accountMessage: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        tvStatus = findViewById(R.id.tvStatus)
        switchEnabled = findViewById(R.id.switchEnabled)
        btnAccessibility = findViewById(R.id.btnAccessibility)
        btnBattery = findViewById(R.id.btnBattery)
        tvBlockedApps = findViewById(R.id.tvBlockedApps)
        tvBrowserWarning = findViewById(R.id.tvBrowserWarning)
        tvAccountStatus = findViewById(R.id.tvAccountStatus)
        etUsername = findViewById(R.id.etUsername)
        etPassword = findViewById(R.id.etPassword)
        btnSignIn = findViewById(R.id.btnSignIn)
        btnSignOut = findViewById(R.id.btnSignOut)
        btnResetTime = findViewById(R.id.btnResetTime)

        findViewById<Button>(R.id.btnCheckNow).setOnClickListener {
            // Only show "checking" if a result is actually coming; otherwise the text would stick forever.
            if (coordinator.requestRefresh(force = true)) {
                tvStatus.text = "Checking Math Academy…"
            } else {
                renderStatus(coordinator.status())
            }
        }
        switchEnabled.setOnCheckedChangeListener { _, checked -> onEnabledToggled(checked) }
        btnAccessibility.setOnClickListener { PermissionHelper.openAccessibilitySettings(this) }
        btnBattery.setOnClickListener { PermissionHelper.requestIgnoreBatteryOptimizations(this) }
        findViewById<Button>(R.id.btnSelectApps).setOnClickListener {
            startActivity(Intent(this, AppSelectionActivity::class.java))
        }
        btnSignIn.setOnClickListener { signIn() }
        btnSignOut.setOnClickListener { signOut() }
        btnResetTime.setOnClickListener { pickResetTime() }

        val btnDump = findViewById<Button>(R.id.btnDumpTasks)
        if (BuildConfig.DEBUG) {
            btnDump.visibility = View.VISIBLE
            btnDump.setOnClickListener { dumpTasks() }
        }

        Prefs.getUsername(this)?.let { etUsername.setText(it) }
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
        refreshUi()
    }

    override fun onGateStatusChanged(status: GateStatus) {
        renderStatus(status)
    }

    private fun refreshUi() {
        val a11y = PermissionHelper.hasAccessibilityPermission(this)
        val battery = PermissionHelper.isIgnoringBatteryOptimizations(this)
        val hasCreds = Prefs.hasCredentials(this)
        val blocked = Prefs.getBlockedPackages(this)

        btnAccessibility.text = if (a11y) "Accessibility service: granted" else "Accessibility service: MISSING"
        btnBattery.text = if (battery) "Battery: unrestricted" else "Battery: optimised (tap to allow)"

        tvBlockedApps.text = if (blocked.isEmpty()) {
            "No blocked apps selected."
        } else {
            "Blocked apps:\n" + blocked.map { appLabel(it) }.sorted().joinToString("\n") { "  - $it" }
        }
        val browser = PermissionHelper.defaultBrowserPackage(this)
        tvBrowserWarning.visibility = if (browser != null && browser in blocked) View.VISIBLE else View.GONE

        tvAccountStatus.text = accountMessage
            ?: if (hasCreds) "Signed in as ${Prefs.getUsername(this)}. Password stored encrypted on this device." else "Not signed in."
        btnSignOut.visibility = if (hasCreds) View.VISIBLE else View.GONE

        btnResetTime.text = "Reset time: ${Prefs.getResetTime(this).label()}"

        // Reflect persisted state without firing the listener.
        switchEnabled.setOnCheckedChangeListener(null)
        switchEnabled.isChecked = Prefs.isEnabled(this)
        switchEnabled.setOnCheckedChangeListener { _, checked -> onEnabledToggled(checked) }

        renderStatus(coordinator.status())
    }

    private fun renderStatus(status: GateStatus) {
        val resetLabel = Prefs.getResetTime(this).label()
        val prefix = when {
            !Prefs.isEnabled(this) -> "Blocking is OFF.\n"
            !PermissionHelper.hasAccessibilityPermission(this) -> "Accessibility service is OFF, so nothing is being blocked.\n"
            else -> ""
        }
        tvStatus.text = prefix + when (status) {
            is GateStatus.Done ->
                "Unlocked until ${BlockingActivity.formatTime(status.doneUntilMillis)} — " +
                    "${status.tasksCompleted} task(s), ${status.xp} XP since $resetLabel."
            is GateStatus.NotDone -> "LOCKED — no Math Academy task completed since $resetLabel."
            is GateStatus.Offline -> "Offline: ${status.message}.\nApps stay locked."
            is GateStatus.AuthFailed -> "Math Academy sign-in problem: ${status.reason}.\nApps stay locked."
            is GateStatus.UnexpectedResponse ->
                "Unexpected response from Math Academy: ${status.detail}.\nApps stay locked; the site may have changed."
            GateStatus.Unknown -> "Checking Math Academy…"
        }
    }

    private fun onEnabledToggled(checked: Boolean) {
        if (!checked) {
            Prefs.setEnabled(this, false)
            renderStatus(coordinator.status())
            return
        }
        val missing = mutableListOf<String>()
        if (!PermissionHelper.hasAccessibilityPermission(this)) missing += "accessibility service"
        if (!Prefs.hasCredentials(this)) missing += "Math Academy sign-in"
        if (Prefs.getBlockedPackages(this).isEmpty()) missing += "at least one blocked app"
        if (missing.isNotEmpty()) {
            Toast.makeText(this, "Missing: ${missing.joinToString(", ")}", Toast.LENGTH_LONG).show()
            switchEnabled.isChecked = false
            return
        }
        Prefs.setEnabled(this, true)
        renderStatus(coordinator.status()) // status() also kicks a refresh if nothing is cached
    }

    private fun signIn() {
        val username = etUsername.text.toString().trim()
        val password = etPassword.text.toString()
        if (username.isEmpty() || password.isEmpty()) {
            Toast.makeText(this, "Enter your Math Academy username and password", Toast.LENGTH_SHORT).show()
            return
        }
        btnSignIn.isEnabled = false
        accountMessage = "Signing in…"
        tvAccountStatus.text = accountMessage
        val creds = Credentials(username, password)
        val client = Gate.client(this)
        val zone = ZoneId.systemDefault()
        val resetTime = Prefs.getResetTime(this)
        io.execute {
            var loginOk = false
            val message: String = try {
                when (val result = client.login(creds)) {
                    is MathAcademyClient.LoginResult.Success -> {
                        loginOk = true
                        val tasks = client.fetchRecentTasks(creds, zone)
                        val periodStart = resetTime.currentPeriodStartMillis(System.currentTimeMillis(), zone)
                        val summary = TaskSummariser.summarise(tasks, periodStart)
                        "Signed in as $username. ${summary.tasksCompleted} task(s), ${summary.xp} XP since ${resetTime.label()}."
                    }
                    is MathAcademyClient.LoginResult.BadCredentials -> "Sign-in failed: ${result.detail}"
                }
            } catch (e: MathAcademyClient.UnexpectedResponseException) {
                "Signed in, but Math Academy answered unexpectedly: ${e.detail}"
            } catch (e: MathAcademyClient.AuthFailedException) {
                "Sign-in failed: ${e.reason}"
            } catch (e: IOException) {
                "Offline: ${e.message ?: e.javaClass.simpleName}"
            }
            main.post {
                if (loginOk) {
                    Prefs.setCredentials(this, creds)
                    etPassword.setText("")
                    coordinator.invalidate()
                }
                accountMessage = message
                btnSignIn.isEnabled = true
                refreshUi()
            }
        }
    }

    private fun signOut() {
        Prefs.clearCredentials(this)
        PrefsSessionStore(this).clearCookies()
        Prefs.setEnabled(this, false)
        coordinator.invalidate()
        accountMessage = null
        etPassword.setText("")
        refreshUi()
    }

    private fun pickResetTime() {
        val current = Prefs.getResetTime(this)
        TimePickerDialog(
            this,
            { _, hour, minute ->
                Prefs.setResetTime(this, ResetTime(hour, minute))
                coordinator.invalidate()
                refreshUi()
            },
            current.hour,
            current.minute,
            true,
        ).show()
    }

    private fun dumpTasks() {
        val creds = Prefs.getCredentials(this)
        if (creds == null) {
            Toast.makeText(this, "Sign in first", Toast.LENGTH_SHORT).show()
            return
        }
        val client = Gate.client(this)
        io.execute {
            try {
                val tasks = client.fetchRecentTasks(creds, ZoneId.systemDefault())
                MgLog.d("raw previous-tasks: ${tasks.length()} items")
                for (i in 0 until minOf(3, tasks.length())) MgLog.d("task[$i] = ${tasks.optJSONObject(i)}")
                main.post { Toast.makeText(this, "Dumped ${tasks.length()} tasks to logcat", Toast.LENGTH_SHORT).show() }
            } catch (e: Exception) {
                MgLog.w("dump failed", e)
                main.post { Toast.makeText(this, "Dump failed: ${e.message}", Toast.LENGTH_LONG).show() }
            }
        }
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }
}
