package com.mathgate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class GateStatusCoordinatorTest {
    private val zone = ZoneId.of("Europe/London")
    private var now = at(2026, 9, 3, 10, 0)
    private var resetTime = ResetTime.DEFAULT
    private val api = FakeGateApi()
    private val executor = ManualExecutor()
    private val store = InMemoryDoneStore()
    private val received = mutableListOf<GateStatus>()
    private lateinit var coordinator: GateStatusCoordinator

    private val listener = object : GateStatusCoordinator.Listener {
        override fun onGateStatusChanged(status: GateStatus) {
            received += status
        }
    }

    @Before
    fun setUp() {
        coordinator = newCoordinator()
        coordinator.addListener(listener)
    }

    private fun newCoordinator() = GateStatusCoordinator(
        api = api,
        config = { GateConfig(resetTime, zone) },
        doneStore = store,
        clock = { now },
        ioExecutor = executor,
        mainPoster = { it.run() },
    )

    private fun respondNotDone() = api.respond { r -> GateStatus.NotDone(r.periodStartMillis, r.nextResetMillis, now) }
    private fun respondDone() = api.respond { r -> GateStatus.Done(r.nextResetMillis, 2, 14) }

    @Test
    fun firstCallIsUnknownAndSchedulesExactlyOneFetch() {
        respondNotDone()
        assertEquals(GateStatus.Unknown, coordinator.status())
        assertEquals(GateStatus.Unknown, coordinator.status())
        assertEquals(1, executor.pending())
        executor.runAll()
        assertEquals(1, api.calls)
        assertTrue(coordinator.status() is GateStatus.NotDone)
        assertEquals(1, received.size)
        assertEquals(at(2026, 9, 3, 4, 0), api.lastRequest!!.periodStartMillis)
        assertEquals(at(2026, 9, 4, 4, 0), api.lastRequest!!.nextResetMillis)
    }

    @Test
    fun doneIsCachedUntilResetWithoutFurtherFetches() {
        respondDone()
        coordinator.status()
        executor.runAll()
        assertTrue(coordinator.status().allowsAccess)

        now = at(2026, 9, 3, 23, 0)
        assertTrue(coordinator.status().allowsAccess)
        now = at(2026, 9, 4, 3, 59)
        assertTrue(coordinator.status().allowsAccess)
        assertEquals(0, executor.pending())
        assertEquals(1, api.calls)

        now = at(2026, 9, 4, 4, 0)
        val afterReset = coordinator.status()
        assertFalse(afterReset.allowsAccess)
        assertEquals(GateStatus.Unknown, afterReset)
        assertEquals(1, executor.pending())
    }

    @Test
    fun doneSurvivesProcessRestart() {
        respondDone()
        coordinator.status()
        executor.runAll()

        val restarted = newCoordinator()
        val status = restarted.status()
        assertTrue(status is GateStatus.Done)
        assertEquals(2, (status as GateStatus.Done).tasksCompleted)
        assertEquals(0, executor.pending())
    }

    @Test
    fun notDoneIsHeldThenRefetched() {
        respondNotDone()
        coordinator.status()
        executor.runAll()

        now += 10_000
        assertTrue(coordinator.status() is GateStatus.NotDone)
        assertEquals(0, executor.pending())

        now += 6_000
        assertTrue(coordinator.status() is GateStatus.NotDone) // stale answer returned immediately
        assertEquals(1, executor.pending()) // ...and a refresh scheduled
    }

    @Test
    fun offlineBlocksAndRefetchesAfterHold() {
        api.respond { GateStatus.Offline("no internet") }
        coordinator.status()
        executor.runAll()
        assertFalse(coordinator.status().allowsAccess)
        assertEquals(0, executor.pending())
        now += GateStatusCoordinator.NOT_DONE_HOLD_MS + 1
        coordinator.status()
        assertEquals(1, executor.pending())
    }

    @Test
    fun declinedRefreshSaysSoSoTheUiDoesNotWaitForever() {
        // Regression: the UI set "Checking Math Academy..." on every tap. When the rate limit declined
        // the request no fetch ran, no listener fired, and the text stuck permanently.
        respondNotDone()
        coordinator.status()
        executor.runAll()

        now += 1_000
        assertFalse("a rate-limited forced refresh must report that nothing is coming", coordinator.requestRefresh(force = true))
        assertEquals(0, executor.pending())

        now += FORCED_GAP
        assertTrue("once the gap has passed the refresh must actually run", coordinator.requestRefresh(force = true))
        assertEquals(1, executor.pending())
    }

    @Test
    fun refreshRequestedWhileOneIsRunningStillPromisesACallback() {
        respondNotDone()
        coordinator.status()
        assertTrue("a fetch is already in flight, so a callback is guaranteed", coordinator.requestRefresh(force = true))
        assertTrue(coordinator.requestRefresh(force = false))
    }

    @Test
    fun forcedRefreshBypassesHoldButRespectsShortGap() {
        respondNotDone()
        coordinator.status()
        executor.runAll()

        now += 5_000
        coordinator.requestRefresh(force = false)
        assertEquals(0, executor.pending())
        coordinator.requestRefresh(force = true)
        assertEquals(1, executor.pending())
        executor.runAll()

        now += 1_000
        coordinator.requestRefresh(force = true) // within FORCED_MIN_INTERVAL_MS of the last attempt
        assertEquals(0, executor.pending())
    }

    @Test
    fun forcedRefreshWhileInFlightRunsAgainAfterwards() {
        respondNotDone()
        coordinator.status()
        assertEquals(1, executor.pending())
        coordinator.requestRefresh(force = true)
        assertEquals(1, executor.pending())
        executor.runAll()
        assertEquals(1, api.calls)
        assertEquals(1, executor.pending()) // the pending forced refresh was re-queued
        executor.runAll()
        assertEquals(2, api.calls)
        assertTrue(api.lastRequest!!.forced)
    }

    @Test
    fun invalidateForgetsDone() {
        respondDone()
        coordinator.status()
        executor.runAll()
        assertTrue(coordinator.status().allowsAccess)

        coordinator.invalidate()
        assertEquals(GateStatus.Unknown, coordinator.status())
        assertEquals(1, executor.pending())
        assertEquals(0L, store.doneUntilMillis)
    }

    @Test
    fun changingResetTimeMakesStoredDoneStale() {
        respondDone()
        coordinator.status()
        executor.runAll()
        assertTrue(coordinator.status().allowsAccess)

        resetTime = ResetTime(12, 0) // period now started yesterday 12:00, not today 04:00
        val status = coordinator.status()
        assertFalse(status.allowsAccess)
        assertEquals(GateStatus.Unknown, status)
    }

    @Test
    fun apiCrashBecomesUnexpectedResponse() {
        api.respond { throw IllegalStateException("boom") }
        coordinator.status()
        executor.runAll()
        val status = coordinator.status()
        assertTrue(status is GateStatus.UnexpectedResponse)
        assertFalse(status.allowsAccess)
    }

    @Test
    fun removedListenerIsNotNotified() {
        respondNotDone()
        coordinator.removeListener(listener)
        coordinator.status()
        executor.runAll()
        assertEquals(0, received.size)
    }

    private val FORCED_GAP = GateStatusCoordinator.FORCED_MIN_INTERVAL_MS

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int): Long =
        LocalDateTime.of(year, month, day, hour, minute).atZone(zone).toInstant().toEpochMilli()
}
