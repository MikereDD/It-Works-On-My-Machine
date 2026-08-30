package com.example.tacobros

import android.graphics.Canvas
import android.view.SurfaceHolder

/**
 * Dedicated game loop thread. Targets ~60 FPS using a delta-time step so the
 * game runs at the same speed regardless of device frame rate.
 */
class GameThread(
    private val surfaceHolder: SurfaceHolder,
    private val gameView: GameView
) : Thread() {

    @Volatile
    var running = false

    override fun run() {
        var last = System.nanoTime()
        while (running) {
            val now = System.nanoTime()
            var dt = (now - last) / 1_000_000_000f
            last = now
            // Clamp huge frame gaps (e.g. after a stall) so physics never explodes.
            if (dt > 0.05f) dt = 0.05f

            gameView.update(dt)

            var canvas: Canvas? = null
            try {
                canvas = surfaceHolder.lockCanvas()
                if (canvas != null) {
                    synchronized(surfaceHolder) { gameView.render(canvas) }
                }
            } finally {
                if (canvas != null) {
                    surfaceHolder.unlockCanvasAndPost(canvas)
                }
            }

            val frameMs = (System.nanoTime() - now) / 1_000_000L
            val sleepMs = 16L - frameMs
            if (sleepMs > 0) {
                try {
                    sleep(sleepMs)
                } catch (_: InterruptedException) {
                }
            }
        }
    }
}
