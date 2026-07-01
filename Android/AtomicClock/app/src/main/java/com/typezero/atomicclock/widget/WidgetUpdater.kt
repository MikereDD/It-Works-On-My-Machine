package com.typezero.atomicclock.widget

import android.content.Context
import com.typezero.atomicclock.data.AtomicSettings
import com.typezero.atomicclock.data.SettingsRepository
import com.typezero.atomicclock.data.TimeSyncRepository
import com.typezero.atomicclock.ntp.SntpResult
import com.typezero.atomicclock.weather.CurrentWeather
import com.typezero.atomicclock.weather.WeatherRepository
import kotlinx.coroutines.flow.first

/**
 * Single place that assembles a [WidgetSnapshot] and refreshes it from scratch.
 *
 * Key rule: a missing new value never erases a good old one. If time sync or
 * weather fetch fails, the previous snapshot is carried forward.
 */
object WidgetUpdater {
    fun buildSnapshot(
        prev: WidgetSnapshot,
        settings: AtomicSettings,
        sync: SntpResult?,
        syncEpoch: Long,
        weather: CurrentWeather?,
    ): WidgetSnapshot = WidgetSnapshot(
        hasSync = sync != null || prev.hasSync,
        driftMs = sync?.clockOffsetMillis ?: prev.driftMs,
        sourceShort = sync?.let { shortSource(it.server) } ?: prev.sourceShort,
        stratum = sync?.stratum ?: prev.stratum,
        lastSyncEpoch = if (sync != null) syncEpoch else prev.lastSyncEpoch,
        hasWeather = weather != null || prev.hasWeather,
        tempC = weather?.temperatureC ?: prev.tempC,
        humidity = weather?.humidity ?: prev.humidity,
        label = weather?.label ?: prev.label,
        iconName = weather?.icon?.name ?: prev.iconName,
        city = weather?.city ?: prev.city,
        lastWeatherEpoch = if (weather != null) System.currentTimeMillis() else prev.lastWeatherEpoch,
        use24 = settings.use24Hour,
        fahrenheit = settings.fahrenheit,
        windMph = settings.windMph,
        bgLevel = settings.widgetBackground.ordinal,
    )

    /**
     * Re-sync time and re-fetch weather without the app being open, then save
     * and re-render.
     *
     * Weather uses cached coordinates first. If the app has background location
     * access, this can still try a fresh location after the cached attempt.
     */
    suspend fun refreshFromBackground(context: Context) {
        val settings = SettingsRepository(context).settings.first()
        val sync = runCatching { TimeSyncRepository().sync(settings.server) }.getOrNull()
        val weatherRepo = WeatherRepository(context)
        val weather = runCatching { weatherRepo.fetchFromCachedLocation() }.getOrNull()
            ?: if (weatherRepo.hasLocationPermission()) {
                runCatching { weatherRepo.fetch(forceFresh = true) }.getOrNull()
            } else {
                null
            }

        val snapshot = buildSnapshot(
            prev = WidgetStore.load(context),
            settings = settings,
            sync = sync,
            syncEpoch = System.currentTimeMillis(),
            weather = weather,
        )
        WidgetStore.save(context, snapshot)
        AtomicClockWidget.refresh(context)
    }

    fun shortSource(host: String): String = host
        .removePrefix("time.")
        .substringBefore('.')
        .replaceFirstChar { it.uppercase() }
}
