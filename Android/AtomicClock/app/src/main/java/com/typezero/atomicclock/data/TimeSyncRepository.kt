package com.typezero.atomicclock.data

import com.typezero.atomicclock.ntp.NtpServer
import com.typezero.atomicclock.ntp.SntpClient
import com.typezero.atomicclock.ntp.SntpResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Coordinates SNTP queries off the main thread. To reduce jitter it samples the
 * chosen server a few times and keeps the response with the lowest round-trip
 * delay (the most accurate sample), falling back to other public servers if the
 * preferred one is unreachable.
 */
class TimeSyncRepository(
    private val client: SntpClient = SntpClient(),
) {
    suspend fun sync(preferred: NtpServer, samples: Int = 4): SntpResult? =
        withContext(Dispatchers.IO) {
            bestOf(preferred.host, samples)?.let { return@withContext it }

            // Fallback: try every other server once until one answers.
            for (server in NtpServer.entries) {
                if (server == preferred) continue
                client.requestTime(server.host)?.let { return@withContext it }
            }
            null
        }

    private fun bestOf(host: String, samples: Int): SntpResult? {
        var best: SntpResult? = null
        repeat(samples) {
            val result = client.requestTime(host) ?: return@repeat
            if (best == null || result.roundTripMillis < best!!.roundTripMillis) {
                best = result
            }
        }
        return best
    }
}
