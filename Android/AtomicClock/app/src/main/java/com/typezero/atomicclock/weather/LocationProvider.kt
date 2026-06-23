package com.typezero.atomicclock.weather

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Looper
import androidx.core.content.ContextCompat
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * Resolves a coarse device location using the platform [LocationManager] only —
 * no Google Play Services dependency. Prefers the most recent cached fix and,
 * on API 30+, falls back to a single live request if nothing is cached.
 */
class LocationProvider(private val context: Context) {

    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    suspend fun current(forceFresh: Boolean = false): Location? {
        if (!hasPermission()) return null
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null

        val providers = listOf(
            LocationManager.NETWORK_PROVIDER,
            LocationManager.GPS_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        ).filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }

        val cached = providers
            .mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }

        // Trust the cached fix only if it is recent. Otherwise it may be from a
        // previous location — that's how stale weather "follows" a moving device
        // (e.g. a Thunderstorm reading persisting from city to city). When stale
        // or missing, ask for a fresh single fix and fall back to the cache.
        if (!forceFresh && cached != null && System.currentTimeMillis() - cached.time <= FRESH_WINDOW_MS) {
            return cached
        }
        return requestSingleFix(lm, providers) ?: cached
    }

    /** One-shot live location, with a path for both API 30+ and 26–29. */
    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private suspend fun requestSingleFix(lm: LocationManager, providers: List<String>): Location? {
        val provider = providers.firstOrNull() ?: return null
        return withTimeoutOrNull(timeMillis = 6_000) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                suspendCancellableCoroutine { cont ->
                    val signal = CancellationSignal()
                    lm.getCurrentLocation(provider, signal, context.mainExecutor) { loc ->
                        if (cont.isActive) cont.resume(loc)
                    }
                    cont.invokeOnCancellation { signal.cancel() }
                }
            } else {
                suspendCancellableCoroutine { cont ->
                    val listener = object : LocationListener {
                        override fun onLocationChanged(location: Location) {
                            lm.removeUpdates(this)
                            if (cont.isActive) cont.resume(location)
                        }

                        override fun onStatusChanged(p: String?, status: Int, extras: Bundle?) {}
                        override fun onProviderEnabled(p: String) {}
                        override fun onProviderDisabled(p: String) {}
                    }
                    lm.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
                    cont.invokeOnCancellation { lm.removeUpdates(listener) }
                }
            }
        }
    }

    private companion object {
        /** Cached fixes older than this trigger a fresh request. */
        const val FRESH_WINDOW_MS = 2 * 60 * 1000L
    }
}
