package com.typezero.seraph

import android.app.Application
import com.typezero.seraph.di.AppContainer

class SeraphApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
