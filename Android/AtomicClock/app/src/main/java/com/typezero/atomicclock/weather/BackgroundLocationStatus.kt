package com.typezero.atomicclock.weather

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

/** User-facing status for automatic widget weather updates while the app is closed. */
data class BackgroundLocationStatus(
    val foregroundGranted: Boolean,
    val backgroundGranted: Boolean,
) {
    val ready: Boolean get() = foregroundGranted && backgroundGranted

    val title: String
        get() = if (ready) "Automatic widget weather is on" else "Enable automatic widget weather"

    val message: String
        get() = when {
            ready -> "Weather and city can refresh while Atomic Clock is closed."
            !foregroundGranted -> "First allow location so the app can find local weather."
            else -> "Android requires Location set to \"Allow all the time\" for weather and city to update while the app is closed."
        }
}

fun backgroundLocationStatus(context: Context): BackgroundLocationStatus {
    val foreground = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_COARSE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_FINE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED

    val background = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_BACKGROUND_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED

    return BackgroundLocationStatus(
        foregroundGranted = foreground,
        backgroundGranted = background,
    )
}
