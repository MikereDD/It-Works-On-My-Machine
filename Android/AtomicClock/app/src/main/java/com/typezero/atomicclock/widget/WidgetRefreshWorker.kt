package com.typezero.atomicclock.widget

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Periodically refreshes the widget snapshot while the app is closed.
 */
class WidgetRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        WidgetUpdater.refreshFromBackground(applicationContext)
        Result.success()
    } catch (_: Throwable) {
        Result.retry()
    }
}

/** Schedules/cancels the periodic [WidgetRefreshWorker]. */
object WidgetWork {
    private const val NAME = "atomic_widget_refresh"
    private const val REFRESH_NOW_NAME = "atomic_widget_refresh_now"

    /**
     * Ensure the periodic refresh is running. Safe to call repeatedly.
     *
     * UPDATE is intentional: it repairs old/stale WorkManager constraints after
     * app updates instead of leaving an older broken schedule untouched.
     */
    fun ensureScheduled(context: Context) {
        val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(
            15,
            TimeUnit.MINUTES,
        ).setConstraints(networkConstraints())
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    /** Queue an immediate one-off refresh, useful after widget placement/update. */
    fun refreshNow(context: Context) {
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .setConstraints(networkConstraints())
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            REFRESH_NOW_NAME,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(NAME)
        WorkManager.getInstance(context).cancelUniqueWork(REFRESH_NOW_NAME)
    }

    private fun networkConstraints(): Constraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()
}
