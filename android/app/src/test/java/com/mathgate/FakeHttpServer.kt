package com.mathgate

import java.io.BufferedReader
import java.io.Closeable
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

data class FakeRequest(
    val method: String,
    val path: String,
    val headers: Map<String, String>,
    val body: String,
) {
    fun header(name: String): String? = headers[name.lowercase()]

    /** Parses an application/x-www-form-urlencoded body. */
    fun formParams(): Map<String, String> = body.split('&').filter { it.isNotEmpty() }.associate {
        val idx = it.indexOf('=')
        val k = if (idx >= 0) it.substring(0, idx) else it
        val v = if (idx >= 0) it.substring(idx + 1) else ""
        java.net.URLDecoder.decode(k, "UTF-8") to java.net.URLDecoder.decode(v, "UTF-8")
    }
}

data class FakeResponse(
    val code: Int,
    val headers: List<Pair<String, String>> = emptyList(),
    val body: String = "",
)

/**
 * Minimal HTTP/1.1 server on a loopback port, so MathAcademyClient's real HttpURLConnection code
 * (form POST, Set-Cookie absorption, non-followed redirects, content-type checks) is under test.
 */
class FakeHttpServer(@Volatile private var handler: (FakeRequest) -> FakeResponse) : Closeable {
    private val server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
    @Volatile private var running = true

    val baseUrl: String get() = "http://127.0.0.1:${server.localPort}"

    init {
        thread(isDaemon = true, name = "fake-mathacademy") {
            while (running) {
                val socket = try {
                    server.accept()
                } catch (e: Exception) {
                    break
                }
                try {
                    serve(socket)
                } catch (e: Exception) {
                    // A client that hung up mid-request is not a test failure.
                } finally {
                    runCatching { socket.close() }
                }
            }
        }
    }

    fun setHandler(handler: (FakeRequest) -> FakeResponse) {
        this.handler = handler
    }

    private fun serve(socket: Socket) {
        // ISO-8859-1 keeps one char per byte, so Content-Length stays accurate.
        val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.ISO_8859_1))
        val requestLine = reader.readLine() ?: return
        val parts = requestLine.split(' ')
        val method = parts.getOrElse(0) { "GET" }
        val path = parts.getOrElse(1) { "/" }

        val headers = mutableMapOf<String, String>()
        while (true) {
            val line = reader.readLine() ?: break
            if (line.isEmpty()) break
            val idx = line.indexOf(':')
            if (idx > 0) headers[line.substring(0, idx).trim().lowercase()] = line.substring(idx + 1).trim()
        }

        val length = headers["content-length"]?.toIntOrNull() ?: 0
        val body = if (length > 0) {
            val buf = CharArray(length)
            var read = 0
            while (read < length) {
                val n = reader.read(buf, read, length - read)
                if (n < 0) break
                read += n
            }
            String(buf, 0, read)
        } else {
            ""
        }

        val response = handler(FakeRequest(method, path, headers, body))
        val bodyBytes = response.body.toByteArray(Charsets.UTF_8)
        val head = StringBuilder()
            .append("HTTP/1.1 ${response.code} ${reason(response.code)}\r\n")
            .apply { response.headers.forEach { (k, v) -> append("$k: $v\r\n") } }
            .append("Content-Length: ${bodyBytes.size}\r\n")
            .append("Connection: close\r\n\r\n")
            .toString()

        socket.getOutputStream().apply {
            write(head.toByteArray(Charsets.ISO_8859_1))
            write(bodyBytes)
            flush()
        }
    }

    private fun reason(code: Int): String = when (code) {
        200 -> "OK"
        302 -> "Found"
        401 -> "Unauthorized"
        403 -> "Forbidden"
        404 -> "Not Found"
        500 -> "Internal Server Error"
        else -> "Status"
    }

    override fun close() {
        running = false
        runCatching { server.close() }
    }
}
