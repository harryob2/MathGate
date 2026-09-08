package com.mathgate

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.time.ZoneId

/** Process-wide wiring. The accessibility service and the activities share one coordinator. */
object Gate {
    @Volatile
    private var coordinator: GateStatusCoordinator? = null

    fun coordinator(context: Context): GateStatusCoordinator =
        coordinator ?: synchronized(this) {
            coordinator ?: build(context.applicationContext).also { coordinator = it }
        }

    fun client(context: Context): MathAcademyClient {
        val app = context.applicationContext
        val baseUrl = if (BuildConfig.DEBUG) {
            Prefs.getDebugBaseUrl(app) ?: MathAcademyClient.DEFAULT_BASE_URL
        } else {
            MathAcademyClient.DEFAULT_BASE_URL
        }
        return MathAcademyClient(PrefsSessionStore(app), baseUrl = baseUrl)
    }

    private fun build(app: Context): GateStatusCoordinator {
        val api = MathAcademyGateApi(
            client = client(app),
            credentials = { Prefs.getCredentials(app) },
        )
        val handler = Handler(Looper.getMainLooper())
        return GateStatusCoordinator(
            api = api,
            config = { GateConfig(Prefs.getResetTime(app), ZoneId.systemDefault()) },
            doneStore = PrefsDoneStore(app),
            mainPoster = { handler.post(it) },
        )
    }
}
