package com.typezero.siphon

import android.app.Application
import com.typezero.siphon.di.AppContainer

/** Application entry point; holds the manual DI container. */
class SiphonApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
