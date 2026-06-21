package com.typezero.atomicclock

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.typezero.atomicclock.data.AtomicSettings
import com.typezero.atomicclock.data.SettingsRepository
import com.typezero.atomicclock.data.TimeSyncRepository
import com.typezero.atomicclock.ntp.NtpServer
import com.typezero.atomicclock.ntp.SntpResult
import com.typezero.atomicclock.weather.WeatherRepository
import com.typezero.atomicclock.weather.WeatherState
import com.typezero.atomicclock.widget.AtomicClockWidget
import com.typezero.atomicclock.widget.WidgetBackground
import com.typezero.atomicclock.widget.WidgetStore
import com.typezero.atomicclock.widget.WidgetUpdater
import com.typezero.atomicclock.widget.WidgetWork
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Where the most recent sync attempt stands. */
sealed interface SyncState {
    data object Idle : SyncState
    data object Syncing : SyncState
    data class Synced(val result: SntpResult) : SyncState
    data class Failed(val previous: SntpResult?) : SyncState
}

class ClockViewModel(app: Application) : AndroidViewModel(app) {

    private val timeSync = TimeSyncRepository()
    private val settingsRepo = SettingsRepository(app)
    private val weatherRepo = WeatherRepository(app)

    private val _syncState = MutableStateFlow<SyncState>(SyncState.Idle)
    val syncState: StateFlow<SyncState> = _syncState.asStateFlow()

    private val _weatherState = MutableStateFlow<WeatherState>(WeatherState.Loading)
    val weatherState: StateFlow<WeatherState> = _weatherState.asStateFlow()

    val settings: StateFlow<AtomicSettings> = settingsRepo.settings.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = AtomicSettings(),
    )

    /** The result currently driving the displayed time, if any. */
    private val activeResult: SntpResult?
        get() = when (val s = _syncState.value) {
            is SyncState.Synced -> s.result
            is SyncState.Failed -> s.previous
            else -> null
        }

    private var lastSyncAt = 0L

    init {
        WidgetWork.ensureScheduled(app)
        sync()
        refreshWeather()
        viewModelScope.launch {
            while (true) {
                delay(AUTO_RESYNC_INTERVAL_MS)
                sync()
            }
        }
        viewModelScope.launch {
            while (true) {
                delay(WEATHER_REFRESH_INTERVAL_MS)
                refreshWeather()
            }
        }
        // Keep the widget's units/format in step with settings changes.
        settings.onEach { updateWidget() }.launchIn(viewModelScope)
    }

    fun sync() {
        if (_syncState.value is SyncState.Syncing) return
        val previous = activeResult
        _syncState.value = SyncState.Syncing
        viewModelScope.launch {
            val server = settings.value.server
            val result = timeSync.sync(server)
            if (result != null) {
                lastSyncAt = System.currentTimeMillis()
                _syncState.value = SyncState.Synced(result)
            } else {
                _syncState.value = SyncState.Failed(previous)
            }
            updateWidget()
        }
    }

    fun setUse24Hour(value: Boolean) = viewModelScope.launch { settingsRepo.setUse24Hour(value) }
    fun setShowMilliseconds(value: Boolean) =
        viewModelScope.launch { settingsRepo.setShowMilliseconds(value) }

    fun setFahrenheit(value: Boolean) = viewModelScope.launch { settingsRepo.setFahrenheit(value) }

    fun setWindMph(value: Boolean) = viewModelScope.launch { settingsRepo.setWindMph(value) }

    fun setWidgetBackground(value: WidgetBackground) =
        viewModelScope.launch { settingsRepo.setWidgetBackground(value) }

    fun setServer(server: NtpServer) = viewModelScope.launch {
        settingsRepo.setServer(server)
        sync()
    }

    /** Refreshes current conditions. Safe to call before/without location permission. */
    fun refreshWeather() {
        viewModelScope.launch {
            if (!weatherRepo.hasLocationPermission()) {
                _weatherState.value =
                    WeatherState.Unavailable(needsPermission = true, message = "Tap for weather")
                return@launch
            }
            if (_weatherState.value !is WeatherState.Available) {
                _weatherState.value = WeatherState.Loading
            }
            val weather = weatherRepo.fetch()
            _weatherState.value = if (weather != null) {
                WeatherState.Available(weather)
            } else {
                WeatherState.Unavailable(needsPermission = false, message = "Weather unavailable")
            }
            updateWidget()
        }
    }

    /** Writes the current state to the widget store and re-renders placed widgets. */
    private fun updateWidget() {
        val app = getApplication<Application>()
        val weather = (_weatherState.value as? WeatherState.Available)?.weather
        val snapshot = WidgetUpdater.buildSnapshot(
            prev = WidgetStore.load(app),
            settings = settings.value,
            sync = activeResult,
            syncEpoch = lastSyncAt,
            weather = weather,
        )
        WidgetStore.save(app, snapshot)
        AtomicClockWidget.refresh(app)
    }

    /**
     * Corrected UTC time right now, in Unix millis. When synced this is anchored
     * to the monotonic clock; otherwise it gracefully falls back to the device
     * clock so the display always ticks.
     */
    fun correctedTimeMillis(): Long {
        val result = activeResult ?: return System.currentTimeMillis()
        return result.ntpTimeMillis + (SystemClock.elapsedRealtime() - result.ntpTimeReferenceMillis)
    }

    private companion object {
        const val AUTO_RESYNC_INTERVAL_MS = 10 * 60 * 1000L // re-sync every 10 minutes
        const val WEATHER_REFRESH_INTERVAL_MS = 15 * 60 * 1000L // refresh weather every 15 minutes
    }
}
