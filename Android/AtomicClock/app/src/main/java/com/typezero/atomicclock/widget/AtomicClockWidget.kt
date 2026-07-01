package com.typezero.atomicclock.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import com.typezero.atomicclock.MainActivity
import com.typezero.atomicclock.R
import com.typezero.atomicclock.ui.formatOffset
import com.typezero.atomicclock.weather.formatTemperature

/**
 * Home-screen widget.
 *
 * The time is a self-updating TextClock; drift, source, and weather come from
 * the latest [WidgetStore] snapshot written by the app or background worker.
 */
open class AtomicClockWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        WidgetWork.ensureScheduled(context)
        WidgetWork.refreshNow(context)
        ids.forEach { render(context, manager, it) }
    }

    override fun onEnabled(context: Context) {
        WidgetWork.ensureScheduled(context)
        WidgetWork.refreshNow(context)
    }

    override fun onDisabled(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val anyLeft = listOf(
            AtomicClockWidgetSmall::class.java,
            AtomicClockWidgetLarge::class.java,
        ).any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
        if (!anyLeft) WidgetWork.cancel(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle,
    ) {
        WidgetWork.ensureScheduled(context)
        render(context, manager, id)
    }

    companion object {
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val providers = listOf(
                AtomicClockWidgetSmall::class.java,
                AtomicClockWidgetLarge::class.java,
            )
            providers.forEach { cls ->
                manager.getAppWidgetIds(ComponentName(context, cls))
                    .forEach { render(context, manager, it) }
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val options = manager.getAppWidgetOptions(id)
            val minW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val large = minW >= 180 && minH >= 80
            val s = WidgetStore.load(context)
            val views = if (large) buildLarge(context, s) else buildSmall(context, s)
            views.setInt(R.id.widget_root, "setBackgroundResource", backgroundRes(s.bgLevel))
            manager.updateAppWidget(id, views)
        }

        private fun backgroundRes(level: Int): Int = when (level) {
            WidgetBackground.SOLID.ordinal -> R.drawable.widget_bg_solid
            WidgetBackground.CLEAR.ordinal -> R.drawable.widget_bg_clear
            else -> R.drawable.widget_bg_translucent
        }

        private fun buildSmall(context: Context, s: WidgetSnapshot): RemoteViews =
            RemoteViews(context.packageName, R.layout.widget_atomic_small).apply {
                applyClockFormat(this, s.use24)
                setOnClickPendingIntent(R.id.widget_root, launchIntent(context))
                if (s.hasWeather) {
                    setViewVisibility(R.id.widget_cond_icon, View.VISIBLE)
                    setImageViewResource(R.id.widget_cond_icon, condIconRes(s.iconName))
                } else {
                    setViewVisibility(R.id.widget_cond_icon, View.GONE)
                }
                val accent = when {
                    s.hasWeather && s.hasSync -> "${formatTemperature(s.tempC, s.fahrenheit)} · ${formatOffset(s.driftMs)}"
                    s.hasWeather -> formatTemperature(s.tempC, s.fahrenheit)
                    s.hasSync -> formatOffset(s.driftMs)
                    else -> "Open to sync"
                }
                setTextViewText(R.id.widget_accent, accent)
            }

        private fun buildLarge(context: Context, s: WidgetSnapshot): RemoteViews =
            RemoteViews(context.packageName, R.layout.widget_atomic_large).apply {
                applyClockFormat(this, s.use24)
                setOnClickPendingIntent(R.id.widget_root, launchIntent(context))
                if (s.hasWeather) {
                    setViewVisibility(R.id.widget_cond_icon, View.VISIBLE)
                    setImageViewResource(R.id.widget_cond_icon, condIconRes(s.iconName))
                    val main = buildString {
                        append(formatTemperature(s.tempC, s.fahrenheit))
                        if (s.label.isNotEmpty()) append(" · ${s.label}")
                    }
                    setTextViewText(R.id.widget_weather, main)

                    val showDrop = s.humidity in 0..100
                    val rightText = buildString {
                        if (showDrop) append("${s.humidity}%")
                        s.city?.let {
                            if (isNotEmpty()) append(" · ")
                            append(it)
                        }
                    }
                    setViewVisibility(R.id.widget_drop_icon, if (showDrop) View.VISIBLE else View.GONE)
                    if (rightText.isNotEmpty()) {
                        setViewVisibility(R.id.widget_humidity, View.VISIBLE)
                        setTextViewText(R.id.widget_humidity, rightText)
                    } else {
                        setViewVisibility(R.id.widget_humidity, View.GONE)
                    }

                    if (s.lastWeatherEpoch > 0) {
                        setViewVisibility(R.id.widget_weather_updated, View.VISIBLE)
                        setTextViewText(R.id.widget_weather_updated, "Updated ${ago(s.lastWeatherEpoch)}")
                        setTextColor(R.id.widget_weather_updated, weatherAgeColor(s.lastWeatherEpoch))
                    } else {
                        setViewVisibility(R.id.widget_weather_updated, View.GONE)
                    }
                } else {
                    setViewVisibility(R.id.widget_cond_icon, View.GONE)
                    setViewVisibility(R.id.widget_drop_icon, View.GONE)
                    setViewVisibility(R.id.widget_humidity, View.GONE)
                    setViewVisibility(R.id.widget_weather_updated, View.GONE)
                    setTextViewText(R.id.widget_weather, "Weather unavailable")
                }

                val stats = if (s.hasSync) {
                    "Drift ${formatOffset(s.driftMs)} · ${s.sourceShort} S${s.stratum} · ${ago(s.lastSyncEpoch)}"
                } else {
                    "Open the app to sync atomic time"
                }
                setTextViewText(R.id.widget_stats, stats)
            }

        private fun condIconRes(name: String): Int = when (name) {
            "SUN" -> R.drawable.ic_widget_sun
            "MOON" -> R.drawable.ic_widget_moon
            "RAIN" -> R.drawable.ic_widget_rain
            "SNOW" -> R.drawable.ic_widget_snow
            "STORM" -> R.drawable.ic_widget_storm
            else -> R.drawable.ic_widget_cloud
        }

        private fun applyClockFormat(views: RemoteViews, use24: Boolean) {
            val time = if (use24) "HH:mm" else "h:mm"
            views.setCharSequence(R.id.widget_clock, "setFormat12Hour", time)
            views.setCharSequence(R.id.widget_clock, "setFormat24Hour", time)
            views.setCharSequence(R.id.widget_date, "setFormat12Hour", "EEE d MMM")
            views.setCharSequence(R.id.widget_date, "setFormat24Hour", "EEE d MMM")
        }

        private fun launchIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun weatherAgeColor(epoch: Long): Int {
            val mins = ((System.currentTimeMillis() - epoch) / 60_000L).toInt()
            return when {
                mins >= 360 -> 0xFFFF6B6B.toInt()
                mins >= 60 -> 0xFFFFC65C.toInt()
                else -> 0xFF93A0B8.toInt()
            }
        }

        private fun ago(epoch: Long): String {
            if (epoch <= 0) return "—"
            val mins = ((System.currentTimeMillis() - epoch) / 60_000L).toInt()
            return when {
                mins <= 0 -> "just now"
                mins < 60 -> "${mins}m ago"
                else -> "${mins / 60}h ago"
            }
        }
    }
}

class AtomicClockWidgetSmall : AtomicClockWidget()
class AtomicClockWidgetLarge : AtomicClockWidget()
