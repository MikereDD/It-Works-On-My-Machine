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

    /**
     * Foreground/app refresh path.
     *
     * When a real device location is resolved, cache the coordinates and city so
     * the widget worker can later update weather while the app is closed.
     */
    suspend fun fetch(forceFresh: Boolean = false): CurrentWeather? = withContext(Dispatchers.IO) {
        val loc = location.current(forceFresh) ?: return@withContext null
        fetchAt(
            latitude = loc.latitude,
            longitude = loc.longitude,
            cachedCity = null,
            updateLocationCache = true,
        )
    }

    /**
     * Background/widget path.
     *
     * Uses the last good coordinates instead of trying to take a live background
     * location every 15 minutes. This keeps weather current even when Android
     * refuses live background location access.
     */
    suspend fun fetchFromCachedLocation(): CurrentWeather? = withContext(Dispatchers.IO) {
        val cached = LocationCache.load(context) ?: return@withContext null
        fetchAt(
            latitude = cached.latitude,
            longitude = cached.longitude,
            cachedCity = cached.city,
            updateLocationCache = false,
        )
    }

    private fun fetchAt(
        latitude: Double,
        longitude: Double,
        cachedCity: String?,
        updateLocationCache: Boolean,
    ): CurrentWeather? {
        val raw = client.current(latitude, longitude) ?: return null
        val city = cachedCity ?: reverseGeocode(latitude, longitude)
        if (updateLocationCache) {
            LocationCache.save(context, latitude, longitude, city)
        }
        val (label, icon) = resolveCondition(raw.code, raw.isDay, raw.precipitation, raw.cloudCover)
        return CurrentWeather(
            temperatureC = raw.tempC,
            apparentC = raw.apparentC,
            humidity = raw.humidity,
            windKmh = raw.windKmh,
            windDir = raw.windDir,
            code = raw.code,
            isDay = raw.isDay,
            label = label,
            icon = icon,
            city = city,
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
