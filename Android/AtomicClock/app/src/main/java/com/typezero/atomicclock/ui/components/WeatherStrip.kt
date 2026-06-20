package com.typezero.atomicclock.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AcUnit
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.Grain
import androidx.compose.material.icons.rounded.LocationOn
import androidx.compose.material.icons.rounded.Thunderstorm
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.typezero.atomicclock.ui.theme.AtomAmber
import com.typezero.atomicclock.ui.theme.AtomBlue
import com.typezero.atomicclock.ui.theme.AtomTeal
import com.typezero.atomicclock.ui.theme.AtomViolet
import com.typezero.atomicclock.weather.CurrentWeather
import com.typezero.atomicclock.weather.WeatherIcon
import com.typezero.atomicclock.weather.WeatherState
import com.typezero.atomicclock.weather.compass
import com.typezero.atomicclock.weather.dewPointC
import com.typezero.atomicclock.weather.formatDegrees
import com.typezero.atomicclock.weather.formatTemperature
import com.typezero.atomicclock.weather.formatWind
import kotlin.math.abs

@Composable
fun WeatherStrip(
    state: WeatherState,
    fahrenheit: Boolean,
    windMph: Boolean,
    onRequest: () -> Unit,
    onToggleUnit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    when (state) {
        is WeatherState.Available ->
            WeatherContent(state.weather, fahrenheit, windMph, onToggleUnit, modifier)
        is WeatherState.Loading -> Hint("Updating weather…", showIcon = false, modifier = modifier) {}
        is WeatherState.Unavailable -> Hint(
            text = state.message,
            showIcon = state.needsPermission,
            modifier = modifier,
            onClick = onRequest,
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WeatherContent(
    weather: CurrentWeather,
    fahrenheit: Boolean,
    windMph: Boolean,
    onToggleUnit: () -> Unit,
    modifier: Modifier,
) {
    val (icon, tint) = iconFor(weather.icon)
    val sub = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.85f)

    val feels = formatDegrees(weather.apparentC, fahrenheit)
    val showFeels = abs(weather.apparentC - weather.temperatureC) >= 1.0
    val windText = if (weather.windKmh >= 0) buildString {
        append(formatWind(weather.windKmh, windMph))
        if (weather.windDir in 0..360) append(" ${compass(weather.windDir)}")
    } else null
    val dewText = dewPointC(weather.temperatureC, weather.humidity)
        ?.let { "Dew ${formatDegrees(it, fahrenheit)}" }

    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        // Headline: condition icon, temperature (tap to switch °C/°F), label.
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(icon, contentDescription = weather.label, tint = tint, modifier = Modifier.size(22.dp))
            Text(
                text = formatTemperature(weather.temperatureC, fahrenheit),
                style = MaterialTheme.typography.titleMedium.copy(
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 18.sp,
                ),
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClick = onToggleUnit)
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
            Text(
                text = "· ${weather.label}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // Secondary metrics — wraps gracefully and stays centered.
        FlowRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            if (showFeels) Metric("Feels $feels", sub)
            if (weather.humidity in 0..100) {
                Metric("${weather.humidity}%", sub, icon = Icons.Rounded.WaterDrop, iconTint = AtomBlue)
            }
            windText?.let { Metric(it, sub, icon = Icons.Rounded.Air, iconTint = AtomTeal) }
            dewText?.let { Metric(it, sub) }
        }

        weather.city?.let {
            SubText(it, sub.copy(alpha = 0.75f))
        }
    }
}

@Composable
private fun Metric(text: String, color: Color, icon: ImageVector? = null, iconTint: Color = color) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(13.dp))
        }
        SubText(text, color)
    }
}

@Composable
private fun SubText(text: String, color: Color) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 12.sp),
        color = color,
    )
}

@Composable
private fun Hint(
    text: String,
    showIcon: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Row(
        modifier = modifier.clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (showIcon) {
            Icon(
                Icons.Rounded.LocationOn,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(16.dp),
            )
        }
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun iconFor(kind: WeatherIcon): Pair<ImageVector, Color> = when (kind) {
    WeatherIcon.SUN -> Icons.Rounded.WbSunny to AtomAmber
    WeatherIcon.MOON -> Icons.Rounded.DarkMode to AtomBlue
    WeatherIcon.CLOUD -> Icons.Rounded.Cloud to AtomTeal
    WeatherIcon.FOG -> Icons.Rounded.Cloud to AtomTeal
    WeatherIcon.RAIN -> Icons.Rounded.Grain to AtomBlue
    WeatherIcon.SNOW -> Icons.Rounded.AcUnit to AtomTeal
    WeatherIcon.STORM -> Icons.Rounded.Thunderstorm to AtomViolet
}
