package com.mathgate

import java.time.ZoneId

/** Result of asking "has a Math Academy task been completed in the current period?". Fail closed: only Done unlocks. */
sealed class GateStatus {
    abstract val allowsAccess: Boolean

    data class Done(val doneUntilMillis: Long, val tasksCompleted: Int, val xp: Int) : GateStatus() {
        override val allowsAccess = true
    }

    data class NotDone(val periodStartMillis: Long, val nextResetMillis: Long, val checkedAtMillis: Long) : GateStatus() {
        override val allowsAccess = false
    }

    /** Network unreachable (no connectivity, DNS failure, timeout). */
    data class Offline(val message: String) : GateStatus() {
        override val allowsAccess = false
    }

    /** No credentials saved, wrong credentials, login backoff active, or Keystore decrypt failure. */
    data class AuthFailed(val reason: String) : GateStatus() {
        override val allowsAccess = false
    }

    /** Math Academy answered but not in the shape we expect (API change, HTML instead of JSON, ...). */
    data class UnexpectedResponse(val detail: String) : GateStatus() {
        override val allowsAccess = false
    }

    /** Nothing fetched yet. */
    object Unknown : GateStatus() {
        override val allowsAccess = false
        override fun toString() = "Unknown"
    }
}

data class GateRequest(
    val periodStartMillis: Long,
    val nextResetMillis: Long,
    val zone: ZoneId,
    val forced: Boolean,
)

/** Blocking call; only ever invoked on the coordinator's IO executor. */
interface GateApi {
    fun fetch(request: GateRequest): GateStatus
}

data class Credentials(val username: String, val password: String)
