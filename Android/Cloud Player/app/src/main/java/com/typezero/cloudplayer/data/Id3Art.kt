package com.typezero.cloudplayer.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Pulls embedded cover art (ID3v2 APIC) out of an MP3 by reading just the tag at
 * the front of the file with a ranged GET. LibVLC reliably surfaces embedded art
 * for local files but usually not for network streams, so for pCloud playback this
 * is the dependable source for the now-playing cover.
 *
 * Handles ID3v2.2 (PIC) / 2.3 / 2.4 (APIC), prefers the front-cover picture type,
 * and returns the raw JPEG/PNG bytes (decode with BitmapFactory). Returns null for
 * non-ID3 inputs (e.g. FLAC/M4A) — callers fall back to LibVLC art / placeholder.
 *
 * Not handled: global unsynchronisation (rare; Mp3tag doesn't apply it by default).
 */
object Id3Art {

    private const val MAX_TAG = 6 * 1024 * 1024  // guard against a pathological tag size

    suspend fun fetch(http: OkHttpClient, url: String): ByteArray? = withContext(Dispatchers.IO) {
        try {
            val header = rangeGet(http, url, 0, 9) ?: return@withContext null
            if (header.size < 10) return@withContext null
            if (u8(header, 0) != 'I'.code || u8(header, 1) != 'D'.code || u8(header, 2) != '3'.code)
                return@withContext null
            val major = u8(header, 3)
            val flags = u8(header, 5)
            val tagSize = synchsafe(header, 6)
            if (tagSize <= 0 || tagSize > MAX_TAG) return@withContext null
            val full = rangeGet(http, url, 0, 9 + tagSize) ?: return@withContext null
            extractApic(full, major, flags)
        } catch (e: Exception) {
            null
        }
    }

    private fun rangeGet(http: OkHttpClient, url: String, from: Int, to: Int): ByteArray? {
        val req = Request.Builder().url(url).header("Range", "bytes=$from-$to").build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return null
            return resp.body?.bytes()
        }
    }

    private fun u8(b: ByteArray, i: Int): Int = b[i].toInt() and 0xFF

    private fun synchsafe(b: ByteArray, off: Int): Int =
        (u8(b, off) and 0x7F shl 21) or
            (u8(b, off + 1) and 0x7F shl 14) or
            (u8(b, off + 2) and 0x7F shl 7) or
            (u8(b, off + 3) and 0x7F)

    private fun uint32(b: ByteArray, off: Int): Int =
        (u8(b, off) shl 24) or (u8(b, off + 1) shl 16) or (u8(b, off + 2) shl 8) or u8(b, off + 3)

    private fun extractApic(tag: ByteArray, major: Int, headerFlags: Int): ByteArray? {
        var pos = 10
        // Skip an extended header if present (flag bit 6).
        if (headerFlags and 0x40 != 0 && pos + 4 <= tag.size) {
            val extSize = if (major >= 4) synchsafe(tag, pos) else uint32(tag, pos)
            pos += if (major >= 4) extSize else extSize + 4
        }
        val end = tag.size
        var firstAny: ByteArray? = null
        while (pos + 10 <= end) {
            if (major == 2) {
                if (pos + 6 > end) break
                val id = String(tag, pos, 3, Charsets.ISO_8859_1)
                val size = (u8(tag, pos + 3) shl 16) or (u8(tag, pos + 4) shl 8) or u8(tag, pos + 5)
                pos += 6
                if (size <= 0 || pos + size > end) break
                if (id == "PIC") parsePic22(tag, pos, size)?.let { return it }
                pos += size
            } else {
                val id = String(tag, pos, 4, Charsets.ISO_8859_1)
                val size = if (major >= 4) synchsafe(tag, pos + 4) else uint32(tag, pos + 4)
                pos += 10
                if (size <= 0 || pos + size > end) break
                if (id == "APIC") {
                    val r = parseApic(tag, pos, size)
                    if (r != null) {
                        if (r.second == 3) return r.first        // front cover wins
                        if (firstAny == null) firstAny = r.first
                    }
                }
                pos += size
            }
        }
        return firstAny
    }

    // APIC body: enc(1) | mime(\0) | picType(1) | desc(\0 / \0\0) | image
    private fun parseApic(b: ByteArray, start: Int, size: Int): Pair<ByteArray, Int>? {
        var p = start
        val limit = start + size
        if (p >= limit) return null
        val enc = u8(b, p); p++
        while (p < limit && u8(b, p) != 0) p++            // mime (ISO-8859-1)
        p++
        if (p >= limit) return null
        val picType = u8(b, p); p++
        p = skipDescription(b, p, limit, enc)
        if (p >= limit) return null
        return b.copyOfRange(p, limit) to picType
    }

    // PIC body (v2.2): enc(1) | fmt(3) | picType(1) | desc(\0 / \0\0) | image
    private fun parsePic22(b: ByteArray, start: Int, size: Int): ByteArray? {
        var p = start
        val limit = start + size
        if (p + 5 > limit) return null
        val enc = u8(b, p); p++
        p += 3 // image format
        p += 1 // picture type
        p = skipDescription(b, p, limit, enc)
        if (p >= limit) return null
        return b.copyOfRange(p, limit)
    }

    private fun skipDescription(b: ByteArray, from: Int, limit: Int, enc: Int): Int {
        var p = from
        if (enc == 1 || enc == 2) {                       // UTF-16: double-byte terminator
            while (p + 1 < limit && !(u8(b, p) == 0 && u8(b, p + 1) == 0)) p += 2
            p += 2
        } else {
            while (p < limit && u8(b, p) != 0) p++
            p += 1
        }
        return p
    }
}
