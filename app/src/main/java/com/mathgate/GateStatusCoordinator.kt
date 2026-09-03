package com.mathgate

import java.time.ZoneId
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executor
import java.util.concurrent.Executors

data class GateConfig(val resetTime: ResetTime, val zone: ZoneId)

/**
 * Single source of truth for "may the blocked apps be used right now?".
 *
 * status() is synchronous, O(1) and never touches the network: the accessibility service calls it
 * on the main thread for every window change. Network refreshes run on [ioExecutor], single-flight,
 * and results are broadcast to listeners on the main thread via [mainPoster].
 *
 * Cache rules:
 *  - Done is persisted in [doneStore] keyed by the period start, so it survives process restarts and
 *    automatically stops applying at the next reset time.
 *  - Any non-Done result is held for NOT_DONE_HOLD_MS before the next automatic refresh.
 *  - Unknown (nothing fetched yet) blocks and triggers a refresh. Fail closed.
 */
class GateStatusCoordinator(
    private val api: GateApi,
    private val config: () -> GateConfig,
    private val doneStore: DoneStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val ioExecutor: Executor = Executors.newSingleThreadExecutor(),
    private val mainPoster: (Runnable) -> Unit,
) {
    interface Listener {
        fun onGateStatusChanged(status: GateStatus)
    }

    private val lock = Any()
    private var lastResult: GateStatus? = null
    private var lastFetchedAt: Long? = null
    private var lastAttemptAt: Long? = null
    private var inFlight = false
    private var pendingForce = false
    private val listeners = CopyOnWriteArrayList<Listener>()

    fun status(): GateStatus {
        val now = clock()
        val cfg = config()
        val periodStart = cfg.resetTime.currentPeriodStartMillis(now, cfg.zone)
        synchronized(lock) {
            if (doneStore.donePeriodStartMillis == periodStart && now < doneStore.doneUntilMillis) {
                return GateStatus.Done(doneStore.doneUntilMillis, doneStore.doneTasks, doneStore.doneXp)
            }
            val last = lastResult
            val fetchedAt = lastFetchedAt
            if (last != null && last !is GateStatus.Done && fetchedAt != null && now - fetchedAt < NOT_DONE_HOLD_MS) {
                return last
            }
            // A Done left in memory from a previous period must not grant access.
            val stale = if (last == null || last is GateStatus.Done) GateStatus.Unknown else last
            requestRefreshLocked(now, force = false, bypassGap = false)
            return stale
        }
    }

    /**
     * Kick a refresh. Forced refreshes bypass the hold (used by the block screen's Retry button).
     *
     * Returns true when a listener callback is guaranteed to follow, i.e. a fetch was started or one
     * is already running. Returns false when the request was declined by the rate limit, in which case
     * the caller must not sit waiting for a callback that will never come.
     */
    fun requestRefresh(force: Boolean): Boolean =
        synchronized(lock) { requestRefreshLocked(clock(), force, bypassGap = false) }

    /** Settings or credentials changed: forget everything, including the persisted Done. */
    fun invalidate() {
        synchronized(lock) {
            lastResult = null
            lastFetchedAt = null
            lastAttemptAt = null
            pendingForce = false
            doneStore.clear()
        }
    }

    fun addListener(listener: Listener) {
        listeners.addIfAbsent(listener)
    }

    fun removeListener(listener: Listener) {
        listeners.remove(listener)
    }

    private fun requestRefreshLocked(now: Long, force: Boolean, bypassGap: Boolean): Boolean {
        if (inFlight) {
            if (force) pendingForce = true
            return true // the running fetch, or the forced one queued behind it, will notify listeners
        }
        val attemptedAt = lastAttemptAt
        if (!bypassGap && attemptedAt != null) {
            val minGap = if (force) FORCED_MIN_INTERVAL_MS else MIN_REFRESH_INTERVAL_MS
            if (now - attemptedAt < minGap) return false
        }
        inFlight = true
        lastAttemptAt = now
        val cfg = config()
        val request = GateRequest(
            periodStartMillis = cfg.resetTime.currentPeriodStartMillis(now, cfg.zone),
            nextResetMillis = cfg.resetTime.nextResetMillis(now, cfg.zone),
            zone = cfg.zone,
            forced = force,
        )
        ioExecutor.execute { runFetch(request) }
        return true
    }

    private fun runFetch(request: GateRequest) {
        val result = try {
            api.fetch(request)
        } catch (t: Throwable) {
            MgLog.w("gate fetch crashed", t)
            GateStatus.UnexpectedResponse("fetch crashed: ${t.javaClass.simpleName}: ${t.message}")
        }
        synchronized(lock) {
            val now = clock()
            lastResult = result
            lastFetchedAt = now
            inFlight = false
            if (result is GateStatus.Done) {
                doneStore.donePeriodStartMillis = request.periodStartMillis
                doneStore.doneUntilMillis = request.nextResetMillis
                doneStore.doneTasks = result.tasksCompleted
                doneStore.doneXp = result.xp
            }
            if (pendingForce) {
                // A Retry arrived while this fetch was running: honour it immediately.
                pendingForce = false
                requestRefreshLocked(now, force = true, bypassGap = true)
            }
        }
        MgLog.d("gate status -> $result")
        mainPoster(Runnable { for (l in listeners) l.onGateStatusChanged(result) })
    }

    companion object {
        const val NOT_DONE_HOLD_MS = 15_000L
        const val MIN_REFRESH_INTERVAL_MS = 15_000L
        const val FORCED_MIN_INTERVAL_MS = 3_000L
    }
}
