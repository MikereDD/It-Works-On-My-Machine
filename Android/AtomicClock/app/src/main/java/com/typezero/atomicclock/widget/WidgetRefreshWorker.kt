package com.typezero.atomicclock.widget

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Periodically refreshes the widget snapshot while the app is closed, so the
 * tile keeps a current drift reading and weather without needing to be opened.
 */
class WidgetRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = try {
        WidgetUpdater.refreshFromBackground(applicationContext)
        Result.success()
    } catch (t: Throwable) {
        // Transient (e.g. no network yet) — let WorkManager back off and retry.
        Result.retry()
    }
}

/** Schedules/cancels the periodic [WidgetRefreshWorker]. */
object WidgetWork {
    private const val NAME = "atomic_widget_refresh"

    /**
     * Ensure the periodic refresh is running. Safe to call repeatedly — KEEP
     * leaves an already-scheduled job untouched. 15 minutes is WorkManager's
     * minimum period.
     */
    fun ensureScheduled(context: Context) {
        val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(
            15, TimeUnit.MINUTES,
        ).setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build(),
        ).build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(NAME)
    }
}
