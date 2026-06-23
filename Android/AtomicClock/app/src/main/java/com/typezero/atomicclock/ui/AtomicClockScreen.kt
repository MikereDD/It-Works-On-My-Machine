package com.typezero.atomicclock.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.core.content.ContextCompat
import com.typezero.atomicclock.ClockViewModel
import com.typezero.atomicclock.SyncState
import com.typezero.atomicclock.ui.components.AboutDialog
import com.typezero.atomicclock.ui.components.ClockFace
import com.typezero.atomicclock.ui.components.SettingsSheet
import com.typezero.atomicclock.ui.components.StatCard
import com.typezero.atomicclock.ui.components.StatusKind
import com.typezero.atomicclock.ui.components.SyncStatusChip
import com.typezero.atomicclock.ui.components.WeatherStrip
import com.typezero.atomicclock.ui.theme.AtomBlue
import com.typezero.atomicclock.ui.theme.AtomTeal
import com.typezero.atomicclock.ui.theme.AtomViolet
import com.typezero.atomicclock.weather.WeatherState
import com.typezero.atomicclock.widget.WidgetBackground

@Composable
fun AtomicClockScreen(vm: ClockViewModel = viewModel()) {
    val syncState by vm.syncState.collectAsState()
    val settings by vm.settings.collectAsState()
    val weatherState by vm.weatherState.collectAsState()
    var showSettings by remember { mutableStateOf(false) }
    var showAbout by remember { mutableStateOf(false) }

    val context = LocalContext.current
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) vm.refreshWeather() }

    val requestWeather: () -> Unit = {
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) vm.refreshWeather()
        else permissionLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
    }
    LaunchedEffect(Unit) { requestWeather() }

    // Re-pull weather each time the app comes back to the foreground, so reopening
    // it after a drive shows current conditions instead of the last fetch.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                val granted = ContextCompat.checkSelfPermission(
                    context, Manifest.permission.ACCESS_COARSE_LOCATION,
                ) == PackageManager.PERMISSION_GRANTED
                if (granted) vm.refreshWeather()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // Drive the display at the frame rate for a perfectly smooth tick.
    val nowMillis by produceState(initialValue = vm.correctedTimeMillis(), syncState) {
        while (true) {
            withFrameMillis { }
            value = vm.correctedTimeMillis()
        }
    }

    val rawParts = formatClock(nowMillis, settings.use24Hour)
    val parts = if (settings.showMilliseconds) rawParts else rawParts.copy(millis = "")
    val fractionOfSecond = (nowMillis % 1000L) / 1000f

    val (statusKind, statusLabel) = statusFor(syncState)
    val accent = MaterialTheme.colorScheme.primary

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        MaterialTheme.colorScheme.background,
                        MaterialTheme.colorScheme.surface,
                    ),
                ),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Top bar: status chip + settings.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                SyncStatusChip(kind = statusKind, label = statusLabel)
                IconButton(onClick = { showSettings = true }) {
                    Icon(
                        Icons.Rounded.Settings,
                        contentDescription = "Settings",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Clock face fills the available middle space.
            ClockFace(
                parts = parts,
                fractionOfSecond = fractionOfSecond,
                accent = accent,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
            )

            // Live conditions.
            WeatherStrip(
                state = weatherState,
                fahrenheit = settings.fahrenheit,
                windMph = settings.windMph,
                onRequest = requestWeather,
                onToggleUnit = { vm.setFahrenheit(!settings.fahrenheit) },
                modifier = Modifier.padding(bottom = 16.dp),
            )

            // Stats row.
            val result = (syncState as? SyncState.Synced)?.result
                ?: (syncState as? SyncState.Failed)?.previous
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                StatCard(
                    label = "Drift",
                    value = result?.let { formatOffset(it.clockOffsetMillis) } ?: "—",
                    accent = AtomBlue,
                )
                StatCard(
                    label = "Accuracy",
                    value = result?.let { formatAccuracy(it.roundTripMillis) } ?: "—",
                    accent = AtomTeal,
                )
                StatCard(
                    label = "Source",
                    value = result?.let { sourceLabel(it.server, it.stratum) } ?: "—",
                    accent = AtomViolet,
                )
            }

            // Refresh button — re-syncs time and pulls fresh weather.
            ResyncButton(
                syncing = syncState is SyncState.Syncing,
                onClick = {
                    vm.sync()
                    val granted = ContextCompat.checkSelfPermission(
                        context, Manifest.permission.ACCESS_COARSE_LOCATION,
                    ) == PackageManager.PERMISSION_GRANTED
                    if (granted) vm.refreshWeather(force = true) else requestWeather()
                },
                modifier = Modifier.padding(vertical = 20.dp),
            )
        }

        if (showSettings) {
            SettingsSheet(
                settings = settings,
                onToggle24Hour = { vm.setUse24Hour(it) },
                onToggleMillis = { vm.setShowMilliseconds(it) },
                onSelectUnit = { vm.setFahrenheit(it) },
                onSelectWind = { vm.setWindMph(it) },
                onSelectWidgetBg = { vm.setWidgetBackground(WidgetBackground.entries[it]) },
                onSelectServer = { vm.setServer(it) },
                onAbout = {
                    showSettings = false
                    showAbout = true
                },
                onDismiss = { showSettings = false },
            )
        }

        if (showAbout) {
            AboutDialog(onDismiss = { showAbout = false })
        }
    }
}

@Composable
private fun ResyncButton(syncing: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val rotation by rememberInfiniteTransition(label = "spin").animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Restart),
        label = "rotation",
    )
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        FilledIconButton(
            onClick = onClick,
            enabled = !syncing,
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                contentColor = MaterialTheme.colorScheme.primary,
            ),
        ) {
            Icon(
                Icons.Rounded.Refresh,
                contentDescription = "Re-sync now",
                modifier = if (syncing) Modifier.rotate(rotation) else Modifier,
            )
        }
    }
}

private fun statusFor(state: SyncState): Pair<StatusKind, String> = when (state) {
    is SyncState.Idle -> StatusKind.SYNCING to "Starting…"
    is SyncState.Syncing -> StatusKind.SYNCING to "Syncing…"
    is SyncState.Synced -> StatusKind.SYNCED to "Atomic time locked"
    is SyncState.Failed ->
        if (state.previous != null) StatusKind.OFFLINE to "Offline · last sync"
        else StatusKind.OFFLINE to "No connection"
}

private fun sourceLabel(server: String, stratum: Int): String {
    val short = server.removePrefix("time.").substringBefore('.').replaceFirstChar { it.uppercase() }
    return "$short · S$stratum"
}
