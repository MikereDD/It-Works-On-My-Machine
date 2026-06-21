/*
 * file:    ResoundApp.kt
 * author:  Mike Redd (typezero)
 * version: 0.1.0
 * desc:    Application entry; owns the manual DI container.
 */
package com.typezero.resound

import android.app.Application
import com.typezero.resound.di.AppContainer

class ResoundApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(applicationContext)
    }
}
