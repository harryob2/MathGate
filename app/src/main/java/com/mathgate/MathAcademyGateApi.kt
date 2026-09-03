package com.mathgate

import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/** Adapts MathAcademyClient to the GateApi contract, mapping every failure to a blocking status. */
class MathAcademyGateApi(
    private val client: MathAcademyClient,
    private val credentials: () -> Credentials?,
    private val clock: () -> Long = System::currentTimeMillis,
) : GateApi {

    override fun fetch(request: GateRequest): GateStatus {
        val creds = credentials() ?: return GateStatus.AuthFailed("no_credentials (sign in from the MathGate app)")
        return try {
            val tasks = client.fetchRecentTasks(creds, request.zone)
            val summary = TaskSummariser.summarise(tasks, request.periodStartMillis)
            MgLog.d("summary: ${summary.tasksCompleted} tasks, ${summary.xp} XP since period start (of ${tasks.length()} recent)")
            if (summary.isDone) {
                GateStatus.Done(request.nextResetMillis, summary.tasksCompleted, summary.xp)
            } else {
                GateStatus.NotDone(request.periodStartMillis, request.nextResetMillis, clock())
            }
        } catch (e: MathAcademyClient.AuthFailedException) {
            MgLog.w("auth failed: ${e.reason}")
            GateStatus.AuthFailed(e.reason)
        } catch (e: MathAcademyClient.UnexpectedResponseException) {
            MgLog.w("unexpected response: ${e.detail}")
            GateStatus.UnexpectedResponse(e.detail)
        } catch (e: IOException) {
            MgLog.w("offline: ${e.javaClass.simpleName}: ${e.message}")
            GateStatus.Offline(describe(e))
        }
    }

    private fun describe(e: IOException): String = when (e) {
        is UnknownHostException -> "no internet connection (DNS lookup failed)"
        is SocketTimeoutException -> "Math Academy timed out"
        else -> e.message ?: e.javaClass.simpleName
    }
}
