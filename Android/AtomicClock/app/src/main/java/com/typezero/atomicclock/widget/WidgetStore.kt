package com.typezero.atomicclock.widget

import android.content.Context

/** How opaque the widget's card background should be. */
enum class WidgetBackground { SOLID, TRANSLUCENT, CLEAR }

/** A flat snapshot of everything the widget needs to render, written by the app. */
data class WidgetSnapshot(
    val hasSync: Boolean = false,
    val driftMs: Long = 0L,
    val sourceShort: String = "—",
    val stratum: Int = 0,
    val lastSyncEpoch: Long = 0L,
    val hasWeather: Boolean = false,
    val tempC: Double = 0.0,
    val humidity: Int = -1,
    val label: String = "",
    val iconName: String = "CLOUD",
    val city: String? = null,
    val lastWeatherEpoch: Long = 0L,
    val use24: Boolean = true,
    val fahrenheit: Boolean = false,
    val windMph: Boolean = false,
    val bgLevel: Int = WidgetBackground.TRANSLUCENT.ordinal,
)

/**
 * Bridges app state to the widget. Uses SharedPreferences (not DataStore) so the
 * widget's [android.appwidget.AppWidgetProvider.onUpdate] can read synchronously
 * without a coroutine.
 */
object WidgetStore {
    private const val PREFS = "atomic_widget"

    fun save(context: Context, s: WidgetSnapshot) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            putBoolean("hasSync", s.hasSync)
            putLong("driftMs", s.driftMs)
            putString("sourceShort", s.sourceShort)
            putInt("stratum", s.stratum)
            putLong("lastSyncEpoch", s.lastSyncEpoch)
            putBoolean("hasWeather", s.hasWeather)
            putFloat("tempC", s.tempC.toFloat())
            putInt("humidity", s.humidity)
            putString("label", s.label)
            putString("iconName", s.iconName)
            putString("city", s.city)
            putLong("lastWeatherEpoch", s.lastWeatherEpoch)
            putBoolean("use24", s.use24)
            putBoolean("fahrenheit", s.fahrenheit)
            putBoolean("windMph", s.windMph)
            putInt("bgLevel", s.bgLevel)
            apply()
        }
    }

    fun load(context: Context): WidgetSnapshot {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return WidgetSnapshot(
            hasSync = p.getBoolean("hasSync", false),
            driftMs = p.getLong("driftMs", 0L),
            sourceShort = p.getString("sourceShort", "—") ?: "—",
            stratum = p.getInt("stratum", 0),
            lastSyncEpoch = p.getLong("lastSyncEpoch", 0L),
            hasWeather = p.getBoolean("hasWeather", false),
            tempC = p.getFloat("tempC", 0f).toDouble(),
            humidity = p.getInt("humidity", -1),
            label = p.getString("label", "") ?: "",
            iconName = p.getString("iconName", "CLOUD") ?: "CLOUD",
            city = p.getString("city", null),
            lastWeatherEpoch = p.getLong("lastWeatherEpoch", 0L),
            use24 = p.getBoolean("use24", true),
            fahrenheit = p.getBoolean("fahrenheit", false),
            windMph = p.getBoolean("windMph", false),
            bgLevel = p.getInt("bgLevel", WidgetBackground.TRANSLUCENT.ordinal),
        )
    }
}
