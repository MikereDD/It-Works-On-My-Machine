package com.typezero.atomicclock.ui

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.abs

/** A snapshot of the corrected time split into display-ready pieces. */
data class ClockParts(
    val mainTime: String,   // HH:mm:ss or hh:mm:ss
    val millis: String,     // ".042"
    val amPm: String,       // "" in 24h mode, else "AM"/"PM"
    val date: String,       // "Saturday, 20 Jun 2026"
    val zone: String,       // "BST · UTC+01:00"
)

private val DATE_FORMAT: DateTimeFormatter =
    DateTimeFormatter.ofPattern("EEEE, d MMM yyyy", Locale.getDefault())

fun formatClock(timeMillis: Long, use24Hour: Boolean): ClockParts {
    val zdt = ZonedDateTime.ofInstant(Instant.ofEpochMilli(timeMillis), ZoneId.systemDefault())

    val hour24 = zdt.hour
    val minute = zdt.minute
    val second = zdt.second
    val ms = (timeMillis % 1000L).toInt()

    val main: String
    val amPm: String
    if (use24Hour) {
        main = "%02d:%02d:%02d".format(hour24, minute, second)
        amPm = ""
    } else {
        val h12 = ((hour24 + 11) % 12) + 1
        main = "%d:%02d:%02d".format(h12, minute, second)
        amPm = if (hour24 < 12) "AM" else "PM"
    }

    val zone = zdt.zone
    val shortName = zone.getDisplayName(TextStyle.SHORT, Locale.getDefault())
    val utcOffset = "UTC" + zdt.offset.id.replace("Z", "+00:00")

    return ClockParts(
        mainTime = main,
        millis = ".%03d".format(ms),
        amPm = amPm,
        date = zdt.format(DATE_FORMAT),
        zone = "$shortName · $utcOffset",
    )
}

/** Human-readable signed offset, e.g. "+43 ms" or "-1.20 s". */
fun formatOffset(offsetMillis: Long): String {
    val sign = if (offsetMillis >= 0) "+" else "-"
    val a = abs(offsetMillis)
    return if (a < 1000) "$sign$a ms" else "$sign%.2f s".format(a / 1000.0)
}

/** Estimated accuracy from round-trip delay, e.g. "±18 ms". */
fun formatAccuracy(roundTripMillis: Long): String = "±${abs(roundTripMillis) / 2} ms"
