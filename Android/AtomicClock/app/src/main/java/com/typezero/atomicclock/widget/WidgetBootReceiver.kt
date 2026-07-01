package com.typezero.atomicclock.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Re-arms widget background refresh after reboot or app update. */
class WidgetBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                WidgetWork.ensureScheduled(context)
                WidgetWork.refreshNow(context)
            }
        }
    }
}
