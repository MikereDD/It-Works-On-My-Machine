package com.typezero.cloudtv.data

import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.concurrent.Executors

/**
 * A tiny loopback HTTP proxy so LibVLC can stream Google Drive files.
 *
 * Drive's `files.get?alt=media` endpoint requires an `Authorization: Bearer`
 * header on every (ranged) request, which LibVLC can't attach. So the player is
 * pointed at `http://127.0.0.1:<port>/s?id=…&tok=…`; this proxy adds the header,
 * forwards the client's Range, and relays Drive's bytes back.
 *
 * Loopback only. The access token rides in the local URL (never leaves the
 * device). This is the same reason Drive can't be cast — the Chromecast
 * receiver can't reach this proxy or carry the token.
 *
 * NOTE: untested until a real Drive account is available.
 */
class DriveStreamProxy(
    private val http: OkHttpClient = OkHttpClient()
) {
    private var server: ServerSocket? = null
    private val pool = Executors.newCachedThreadPool()

    @Synchronized
    fun ensureStarted(): Int {
        server?.let { if (!it.isClosed) return it.localPort }
        val s = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
        server = s
        pool.execute {
            while (!s.isClosed) {
                val client = try { s.accept() } catch (_: Exception) { break }
                pool.execute { handle(client) }
            }
        }
        return s.localPort
    }

    /** Build the local URL the player should open for [fileId] using [token]. */
    fun urlFor(fileId: String, token: String): String {
        val port = ensureStarted()
        val id = URLEncoder.encode(fileId, "UTF-8")
        val tok = URLEncoder.encode(token, "UTF-8")
        return "http://127.0.0.1:$port/s?id=$id&tok=$tok"
    }

    fun stop() {
        runCatching { server?.close() }
        server = null
    }

    private fun handle(client: Socket) {
        client.use { sock ->
            val reader = BufferedReader(InputStreamReader(sock.getInputStream()))
            val requestLine = reader.readLine() ?: return
            var range: String? = null
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                if (line.startsWith("Range:", ignoreCase = true)) {
                    range = line.substringAfter(":").trim()
                }
            }
            // requestLine = "GET /s?id=…&tok=… HTTP/1.1"
            val path = requestLine.split(" ").getOrNull(1) ?: return
            val query = path.substringAfter("?", "")
            val params = query.split("&").mapNotNull {
                val k = it.substringBefore("=", "")
                val v = it.substringAfter("=", "")
                if (k.isEmpty()) null else k to URLDecoder.decode(v, "UTF-8")
            }.toMap()
            val id = params["id"] ?: return sock.getOutputStream().writeStatus(400)
            val tok = params["tok"] ?: return sock.getOutputStream().writeStatus(401)

            val driveUrl = "https://www.googleapis.com/drive/v3/files/$id?alt=media"
            val reqBuilder = Request.Builder().url(driveUrl)
                .header("Authorization", "Bearer $tok")
            if (range != null) reqBuilder.header("Range", range)

            http.newCall(reqBuilder.build()).execute().use { resp ->
                val body = resp.body ?: return sock.getOutputStream().writeStatus(502)
                val out = sock.getOutputStream()
                val sb = StringBuilder()
                sb.append("HTTP/1.1 ").append(resp.code).append(" ")
                    .append(if (resp.code == 206) "Partial Content" else "OK").append("\r\n")
                resp.header("Content-Type")?.let { sb.append("Content-Type: $it\r\n") }
                resp.header("Content-Length")?.let { sb.append("Content-Length: $it\r\n") }
                resp.header("Content-Range")?.let { sb.append("Content-Range: $it\r\n") }
                sb.append("Accept-Ranges: bytes\r\n")
                sb.append("Connection: close\r\n\r\n")
                out.write(sb.toString().toByteArray(Charsets.US_ASCII))
                body.byteStream().use { input ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                    }
                }
                out.flush()
            }
        }
    }

    private fun OutputStream.writeStatus(code: Int) {
        runCatching {
            write("HTTP/1.1 $code\r\nConnection: close\r\n\r\n".toByteArray(Charsets.US_ASCII))
            flush()
        }
    }
}
