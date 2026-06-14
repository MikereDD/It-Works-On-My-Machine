package com.typezero.siphon.di

import android.content.Context
import com.typezero.siphon.data.MediaStoreVideoRepository
import com.typezero.siphon.engine.OutputResolver
import com.typezero.siphon.engine.LocalFfmpegExtractor
import com.typezero.siphon.engine.YtdlpEngine

/** Manual dependency injection (consistent with the rest of the monorepo). */
class AppContainer(context: Context) {
    private val app = context.applicationContext
    val videoRepository by lazy { MediaStoreVideoRepository(app) }
    val outputResolver by lazy { OutputResolver(app) }
    val engine by lazy { YtdlpEngine(app) }
    val localExtractor by lazy { LocalFfmpegExtractor(app, engine) }
}
