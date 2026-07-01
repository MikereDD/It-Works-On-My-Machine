package com.typezero.atomicclock.weather

import android.content.Context

/**
 * Small SharedPreferences cache used by the app UI and widget worker.
 *
 * Android can block live location reads while the app is closed unless the
 * user has granted background location. The widget should still be able to
 * refresh weather periodically from the last known good coordinates.
 */
data class CachedLocation(
    val latitude: Double,
    val longitude: Double,
    val city: String?,
    val savedAtEpoch: Long,
)

object LocationCache {
    private const val PREFS = "atomic_location_cache"
    private const val KEY_HAS = "hasLocation"
    private const val KEY_LAT = "latitude"
    private const val KEY_LON = "longitude"
    private const val KEY_CITY = "city"
    private const val KEY_SAVED_AT = "savedAtEpoch"

    fun save(context: Context, latitude: Double, longitude: Double, city: String?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_HAS, true)
            .putFloat(KEY_LAT, latitude.toFloat())
            .putFloat(KEY_LON, longitude.toFloat())
            .putString(KEY_CITY, city)
            .putLong(KEY_SAVED_AT, System.currentTimeMillis())
            .apply()
    }

    fun load(context: Context): CachedLocation? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_HAS, false)) return null
        return CachedLocation(
            latitude = prefs.getFloat(KEY_LAT, 0f).toDouble(),
            longitude = prefs.getFloat(KEY_LON, 0f).toDouble(),
            city = prefs.getString(KEY_CITY, null),
            savedAtEpoch = prefs.getLong(KEY_SAVED_AT, 0L),
        )
    }
}
