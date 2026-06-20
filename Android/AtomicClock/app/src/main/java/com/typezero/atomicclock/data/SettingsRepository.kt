package com.typezero.atomicclock.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.typezero.atomicclock.ntp.NtpServer
import com.typezero.atomicclock.widget.WidgetBackground
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore("atomic_settings")

/** Persisted user preferences. */
data class AtomicSettings(
    val use24Hour: Boolean = true,
    val showMilliseconds: Boolean = true,
    val server: NtpServer = NtpServer.DEFAULT,
    val fahrenheit: Boolean = false,
    val windMph: Boolean = false,
    val widgetBackground: WidgetBackground = WidgetBackground.TRANSLUCENT,
)

class SettingsRepository(private val context: Context) {

    val settings: Flow<AtomicSettings> = context.dataStore.data.map { prefs ->
        AtomicSettings(
            use24Hour = prefs[KEY_24H] ?: true,
            showMilliseconds = prefs[KEY_MILLIS] ?: true,
            server = NtpServer.fromNameOrDefault(prefs[KEY_SERVER]),
            fahrenheit = prefs[KEY_FAHRENHEIT] ?: defaultFahrenheit(),
            windMph = prefs[KEY_WIND_MPH] ?: defaultWindMph(),
            widgetBackground = runCatching {
                WidgetBackground.valueOf(prefs[KEY_WIDGET_BG] ?: WidgetBackground.TRANSLUCENT.name)
            }.getOrDefault(WidgetBackground.TRANSLUCENT),
        )
    }

    suspend fun setUse24Hour(value: Boolean) =
        context.dataStore.edit { it[KEY_24H] = value }.let {}

    suspend fun setShowMilliseconds(value: Boolean) =
        context.dataStore.edit { it[KEY_MILLIS] = value }.let {}

    suspend fun setServer(server: NtpServer) =
        context.dataStore.edit { it[KEY_SERVER] = server.name }.let {}

    suspend fun setFahrenheit(value: Boolean) =
        context.dataStore.edit { it[KEY_FAHRENHEIT] = value }.let {}

    suspend fun setWindMph(value: Boolean) =
        context.dataStore.edit { it[KEY_WIND_MPH] = value }.let {}

    suspend fun setWidgetBackground(value: WidgetBackground) =
        context.dataStore.edit { it[KEY_WIDGET_BG] = value.name }.let {}

    /** Default to Fahrenheit only in locales that customarily use it. */
    private fun defaultFahrenheit(): Boolean =
        java.util.Locale.getDefault().country in setOf("US", "LR", "MM")

    /** Default to mph in locales that customarily report wind that way. */
    private fun defaultWindMph(): Boolean =
        java.util.Locale.getDefault().country in setOf("US", "GB", "LR", "MM")

    private companion object {
        val KEY_24H = booleanPreferencesKey("use_24_hour")
        val KEY_MILLIS = booleanPreferencesKey("show_milliseconds")
        val KEY_SERVER = stringPreferencesKey("ntp_server")
        val KEY_FAHRENHEIT = booleanPreferencesKey("fahrenheit")
        val KEY_WIND_MPH = booleanPreferencesKey("wind_mph")
        val KEY_WIDGET_BG = stringPreferencesKey("widget_bg")
    }
}
