package com.typezero.atomicclock.weather

import kotlin.math.ln
import kotlin.math.roundToInt

/** Which glyph to show for a condition (mapped to Material icons in the UI). */
enum class WeatherIcon { SUN, MOON, CLOUD, FOG, RAIN, SNOW, STORM }

/** Minimal parsed payload from the weather provider. */
data class RawWeather(
    val tempC: Double,
    val apparentC: Double,
    val humidity: Int,
    val windKmh: Double,
    val windDir: Int,
    val code: Int,
    val isDay: Boolean,
    val cloudCover: Int = -1,
    val precipitation: Double = 0.0,
)

/** Fully resolved current conditions for display. */
data class CurrentWeather(
    val temperatureC: Double,
    val apparentC: Double,
    val humidity: Int,
    val windKmh: Double,
    val windDir: Int,
    val code: Int,
    val isDay: Boolean,
    val label: String,
    val icon: WeatherIcon,
    val city: String?,
)

/** Where the weather panel stands right now. */
sealed interface WeatherState {
    data object Loading : WeatherState
    data class Unavailable(val needsPermission: Boolean, val message: String) : WeatherState
    data class Available(val weather: CurrentWeather) : WeatherState
}

/** Maps a WMO weather code (Open-Meteo) to a human label and an icon. */
fun wmoToCondition(code: Int, isDay: Boolean): Pair<String, WeatherIcon> {
    val clearIcon = if (isDay) WeatherIcon.SUN else WeatherIcon.MOON
    return when (code) {
        0 -> "Clear" to clearIcon
        1 -> "Mainly clear" to clearIcon
        2 -> "Partly cloudy" to WeatherIcon.CLOUD
        3 -> "Overcast" to WeatherIcon.CLOUD
        45, 48 -> "Fog" to WeatherIcon.FOG
        51, 53, 55 -> "Drizzle" to WeatherIcon.RAIN
        56, 57 -> "Freezing drizzle" to WeatherIcon.RAIN
        61, 63, 65 -> "Rain" to WeatherIcon.RAIN
        66, 67 -> "Freezing rain" to WeatherIcon.RAIN
        71, 73, 75, 77 -> "Snow" to WeatherIcon.SNOW
        80, 81, 82 -> "Rain showers" to WeatherIcon.RAIN
        85, 86 -> "Snow showers" to WeatherIcon.SNOW
        95 -> "Thunderstorm" to WeatherIcon.STORM
        96, 99 -> "Thunderstorm" to WeatherIcon.STORM
        else -> "—" to WeatherIcon.CLOUD
    }
}

/**
 * Resolves the condition to display *now*. Open-Meteo's [code] is the forecast
 * for the whole grid cell over the current hour, so it can announce a
 * "Thunderstorm" while nothing is actually falling and the sky is merely cloudy.
 * When there's no current precipitation we describe the observed sky from
 * [cloudCover] instead, which tracks what you can see far more honestly. When it
 * really is precipitating, the WMO mapping (drizzle/rain/snow/storm) stands.
 */
fun resolveCondition(
    code: Int,
    isDay: Boolean,
    precipitationMm: Double,
    cloudCover: Int,
): Pair<String, WeatherIcon> {
    val isPrecipForecast = code >= 51 // drizzle, rain, snow, showers, thunderstorm
    if (isPrecipForecast && precipitationMm <= 0.0 && cloudCover >= 0) {
        return skyFromCloudCover(cloudCover, isDay)
    }
    return wmoToCondition(code, isDay)
}

/** Describes the sky purely from cloud-cover percentage. */
private fun skyFromCloudCover(cloudCover: Int, isDay: Boolean): Pair<String, WeatherIcon> {
    val clearIcon = if (isDay) WeatherIcon.SUN else WeatherIcon.MOON
    return when {
        cloudCover < 12 -> "Clear" to clearIcon
        cloudCover < 50 -> "Partly cloudy" to clearIcon
        cloudCover < 85 -> "Cloudy" to WeatherIcon.CLOUD
        else -> "Overcast" to WeatherIcon.CLOUD
    }
}

/** Celsius → display string in the chosen unit, e.g. "23°C" or "73°F". */
fun formatTemperature(celsius: Double, fahrenheit: Boolean): String {
    val value = if (fahrenheit) celsius * 9.0 / 5.0 + 32.0 else celsius
    val unit = if (fahrenheit) "F" else "C"
    return "${value.roundToInt()}°$unit"
}

/** Compact degrees only, e.g. "21°" (used for "feels like" and dew point). */
fun formatDegrees(celsius: Double, fahrenheit: Boolean): String {
    val value = if (fahrenheit) celsius * 9.0 / 5.0 + 32.0 else celsius
    return "${value.roundToInt()}°"
}

/** Dew point in Celsius via the Magnus formula; null if humidity is unusable. */
fun dewPointC(tempC: Double, humidity: Int): Double? {
    if (humidity !in 1..100) return null
    val a = 17.625
    val b = 243.04
    val alpha = ln(humidity / 100.0) + a * tempC / (b + tempC)
    return b * alpha / (a - alpha)
}

/** Wind speed in the chosen unit, e.g. "12 km/h" or "8 mph". */
fun formatWind(kmh: Double, mph: Boolean): String =
    if (mph) "${(kmh * 0.621371).roundToInt()} mph" else "${kmh.roundToInt()} km/h"

private val COMPASS = listOf(
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
)

/** Bearing in degrees → 16-point compass label, e.g. 315 → "NW". */
fun compass(degrees: Int): String =
    COMPASS[Math.floorMod((degrees / 22.5).roundToInt(), 16)]
