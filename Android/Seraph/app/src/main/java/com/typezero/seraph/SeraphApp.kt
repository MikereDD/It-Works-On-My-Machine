package com.typezero.seraph

import android.app.Application
import com.typezero.seraph.di.AppContainer
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SeraphApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        installCrashLogger()
    }

    /**
     * Records the last uncaught exception to filesDir/last_crash.txt so it can be
     * surfaced on the About screen (no adb/logcat needed), then delegates to the
     * platform handler so the normal crash dialog still appears.
     */
    private fun installCrashLogger() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            runCatching {
                val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
                val text = "Seraph crash @ $ts\nthread: ${thread.name}\n\n" +
                    throwable.stackTraceToString()
                File(filesDir, CRASH_FILE).writeText(text)
            }
            previous?.uncaughtException(thread, throwable)
        }
    }

    companion object {
        const val CRASH_FILE = "last_crash.txt"
    }
}
