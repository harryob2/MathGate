package com.mathgate

import java.util.concurrent.Executor

class InMemorySessionStore : SessionStore {
    override var cookieSession: String? = null
    override var cookieSig: String? = null
    override var cookieExpiresMillis: Long = 0L
    override var loginBackoffUntilMillis: Long = 0L
    override var lastLoginMillis: Long = 0L
}

class InMemoryDoneStore : DoneStore {
    override var doneUntilMillis: Long = 0L
    override var donePeriodStartMillis: Long = 0L
    override var doneTasks: Int = 0
    override var doneXp: Int = 0
}

class FakeGateApi : GateApi {
    var calls = 0
    var lastRequest: GateRequest? = null
    private var responder: (GateRequest) -> GateStatus = { GateStatus.Unknown }

    fun respond(r: (GateRequest) -> GateStatus) {
        responder = r
    }

    override fun fetch(request: GateRequest): GateStatus {
        calls++
        lastRequest = request
        return responder(request)
    }
}

/** Runs only what was queued at the time runAll() is called, so re-queued work stays visible as pending. */
class ManualExecutor : Executor {
    private val queue = ArrayDeque<Runnable>()

    override fun execute(command: Runnable) {
        queue.addLast(command)
    }

    fun pending(): Int = queue.size

    fun runAll() {
        repeat(queue.size) { queue.removeFirst().run() }
    }
}
