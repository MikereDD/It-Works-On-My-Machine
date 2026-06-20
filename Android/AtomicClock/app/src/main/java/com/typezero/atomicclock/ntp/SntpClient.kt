package com.typezero.atomicclock.ntp

import android.os.SystemClock
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * A small, self-contained SNTP (Simple Network Time Protocol, RFC 4330) client.
 *
 * The algorithm mirrors AOSP's hidden `android.net.SntpClient`: it anchors the
 * resolved time to [SystemClock.elapsedRealtime] (a monotonic counter) rather
 * than the wall clock, so the corrected time stays valid even if the device's
 * `System.currentTimeMillis()` is wrong or later changed by the user.
 *
 * Clock offset and round-trip delay are computed from the four NTP timestamps:
 *   T1 = originate (client transmit)   T2 = server receive
 *   T3 = server transmit               T4 = client receive
 *
 *   offset = ((T2 - T1) + (T3 - T4)) / 2
 *   delay  = (T4 - T1) - (T3 - T2)
 */
class SntpClient(
    private val timeoutMs: Int = 5_000,
) {
    /** Query a single NTP server. Returns null on any network/protocol failure. */
    fun requestTime(host: String): SntpResult? {
        var socket: DatagramSocket? = null
        return try {
            val address = InetAddress.getByName(host)
            socket = DatagramSocket().apply { soTimeout = timeoutMs }

            val buffer = ByteArray(NTP_PACKET_SIZE)
            val request = DatagramPacket(buffer, buffer.size, address, NTP_PORT)

            // Set mode = client (3) and version = 3 in the first byte: 00 011 011.
            buffer[0] = (NTP_MODE_CLIENT or (NTP_VERSION shl 3)).toByte()

            // Anchor points captured as close to send/receive as possible.
            val requestTime = System.currentTimeMillis()
            val requestTicks = SystemClock.elapsedRealtime()
            writeTimeStamp(buffer, TRANSMIT_TIME_OFFSET, requestTime)

            socket.send(request)

            val response = DatagramPacket(buffer, buffer.size)
            socket.receive(response)
            val responseTicks = SystemClock.elapsedRealtime()
            val responseTime = requestTime + (responseTicks - requestTicks)

            val leap = (buffer[0].toInt() shr 6) and 0x3
            val mode = buffer[0].toInt() and 0x7
            val stratum = buffer[1].toInt() and 0xFF

            // Basic sanity checks (RFC 4330 §5, "Kiss-o'-Death" / unsynced rejection).
            if (mode != NTP_MODE_SERVER && mode != NTP_MODE_BROADCAST) return null
            if (leap == NTP_LEAP_NOSYNC || stratum < 1 || stratum > 15) return null

            val originateTime = readTimeStamp(buffer, ORIGINATE_TIME_OFFSET) // T1 echoed
            val receiveTime = readTimeStamp(buffer, RECEIVE_TIME_OFFSET)     // T2
            val transmitTime = readTimeStamp(buffer, TRANSMIT_TIME_OFFSET)   // T3

            val roundTrip = (responseTicks - requestTicks) - (transmitTime - receiveTime)
            val clockOffset = ((receiveTime - originateTime) + (transmitTime - responseTime)) / 2

            SntpResult(
                server = host,
                stratum = stratum,
                ntpTimeMillis = responseTime + clockOffset,
                ntpTimeReferenceMillis = responseTicks,
                clockOffsetMillis = clockOffset,
                roundTripMillis = roundTrip,
            )
        } catch (_: Exception) {
            null
        } finally {
            socket?.close()
        }
    }

    /** Reads an unsigned 32-bit value as a long. */
    private fun read32(buffer: ByteArray, offset: Int): Long {
        val b0 = buffer[offset].toLong() and 0xFF
        val b1 = buffer[offset + 1].toLong() and 0xFF
        val b2 = buffer[offset + 2].toLong() and 0xFF
        val b3 = buffer[offset + 3].toLong() and 0xFF
        return (b0 shl 24) or (b1 shl 16) or (b2 shl 8) or b3
    }

    /** Reads an NTP timestamp (seconds + fraction since 1900) as Unix millis. */
    private fun readTimeStamp(buffer: ByteArray, offset: Int): Long {
        val seconds = read32(buffer, offset)
        val fraction = read32(buffer, offset + 4)
        return (seconds - OFFSET_1900_TO_1970) * 1000L + (fraction * 1000L) / 0x100000000L
    }

    /** Writes Unix millis as an NTP timestamp (seconds + fraction since 1900). */
    private fun writeTimeStamp(buffer: ByteArray, offset: Int, time: Long) {
        var seconds = time / 1000L
        val milliseconds = time - seconds * 1000L
        seconds += OFFSET_1900_TO_1970

        buffer[offset] = (seconds shr 24).toByte()
        buffer[offset + 1] = (seconds shr 16).toByte()
        buffer[offset + 2] = (seconds shr 8).toByte()
        buffer[offset + 3] = seconds.toByte()

        val fraction = milliseconds * 0x100000000L / 1000L
        buffer[offset + 4] = (fraction shr 24).toByte()
        buffer[offset + 5] = (fraction shr 16).toByte()
        buffer[offset + 6] = (fraction shr 8).toByte()
        // Low-order byte randomised to defeat trivial caching, per RFC 4330.
        buffer[offset + 7] = (Math.random() * 255.0).toInt().toByte()
    }

    private companion object {
        const val NTP_PORT = 123
        const val NTP_PACKET_SIZE = 48

        const val NTP_MODE_CLIENT = 3
        const val NTP_MODE_SERVER = 4
        const val NTP_MODE_BROADCAST = 5
        const val NTP_VERSION = 3
        const val NTP_LEAP_NOSYNC = 3

        const val ORIGINATE_TIME_OFFSET = 24
        const val RECEIVE_TIME_OFFSET = 32
        const val TRANSMIT_TIME_OFFSET = 40

        // Seconds between 1900-01-01 (NTP epoch) and 1970-01-01 (Unix epoch).
        const val OFFSET_1900_TO_1970 = 2_208_988_800L
    }
}

/** Raw outcome of a single SNTP exchange with one server. */
data class SntpResult(
    val server: String,
    val stratum: Int,
    /** Corrected UTC time at the moment of sync, in Unix millis. */
    val ntpTimeMillis: Long,
    /** [SystemClock.elapsedRealtime] value captured at sync — the monotonic anchor. */
    val ntpTimeReferenceMillis: Long,
    /** How far the device clock was off: corrected - device (millis). */
    val clockOffsetMillis: Long,
    /** Network round-trip time (millis); accuracy is roughly ±roundTrip/2. */
    val roundTripMillis: Long,
)
