package com.typezero.atomicclock.weather

import android.content.Context
import android.location.Geocoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

/** Coordinates location + provider fetch + reverse geocoding into [CurrentWeather]. */
class WeatherRepository(
    private val context: Context,
    private val location: LocationProvider = LocationProvider(context),
    private val client: OpenMeteoClient = OpenMeteoClient(),
) {
    fun hasLocationPermission(): Boolean = location.hasPermission()

    suspend fun fetch(): CurrentWeather? = withContext(Dispatchers.IO) {
        val loc = location.current() ?: return@withContext null
        val raw = client.current(loc.latitude, loc.longitude) ?: return@withContext null
        val (label, icon) = wmoToCondition(raw.code, raw.isDay)
        CurrentWeather(
            temperatureC = raw.tempC,
            apparentC = raw.apparentC,
            humidity = raw.humidity,
            windKmh = raw.windKmh,
            windDir = raw.windDir,
            code = raw.code,
            isDay = raw.isDay,
            label = label,
            icon = icon,
            city = reverseGeocode(loc.latitude, loc.longitude),
        )
    }

    @Suppress("DEPRECATION")
    private fun reverseGeocode(lat: Double, lon: Double): String? = runCatching {
        Geocoder(context, Locale.getDefault())
            .getFromLocation(lat, lon, 1)
            ?.firstOrNull()
            ?.let { it.locality ?: it.subAdminArea ?: it.adminArea }
    }.getOrNull()
}
