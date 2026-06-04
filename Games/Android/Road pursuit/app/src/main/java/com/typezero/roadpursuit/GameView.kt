package com.typezero.roadpursuit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView

class GameView(context: Context) : SurfaceView(context), SurfaceHolder.Callback, Runnable {

    private val sound = SoundManager()
    private val game = Game(context, sound)

    private var thread: Thread? = null
    @Volatile private var running = false

    // low-res offscreen buffer (logical 420x640) upscaled with nearest-neighbor
    private val buffer = Bitmap.createBitmap(Game.W.toInt(), Game.H.toInt(), Bitmap.Config.ARGB_8888)
    private val bufCanvas = Canvas(buffer)
    private val blit = Paint().apply { isAntiAlias = false; isFilterBitmap = false; isDither = false }
    private val dst = RectF(0f, 0f, Game.W, Game.H)

    // device px -> logical mapping
    private var scale = 1f
    private var offX = 0f
    private var offY = 0f

    init {
        holder.addCallback(this)
        isFocusable = true
    }

    override fun surfaceCreated(holder: SurfaceHolder) { startThread() }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        scale = minOf(width / Game.W, height / Game.H)
        offX = (width - Game.W * scale) / 2f
        offY = (height - Game.H * scale) / 2f
        dst.set(offX, offY, offX + Game.W * scale, offY + Game.H * scale)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) { stopThread() }

    fun startThread() {
        if (running) return
        running = true
        thread = Thread(this).also { it.start() }
    }

    fun stopThread() {
        running = false
        try { thread?.join(500) } catch (_: InterruptedException) {}
        thread = null
    }

    fun pauseThread() { game.pause(); stopThread() }
    fun resumeThread() { startThread() }

    override fun run() {
        val frame = 1000L / 60L
        while (running) {
            val start = System.currentTimeMillis()
            val canvas = holder.lockCanvas() ?: continue
            try {
                synchronized(holder) {
                    game.update()
                    // draw the world into the low-res buffer
                    bufCanvas.drawColor(Color.BLACK)
                    game.draw(bufCanvas)
                    // upscale to the screen with hard pixel edges
                    canvas.drawColor(Color.BLACK)
                    canvas.drawBitmap(buffer, null, dst, blit)
                }
            } finally {
                holder.unlockCanvasAndPost(canvas)
            }
            val sleep = frame - (System.currentTimeMillis() - start)
            if (sleep > 0) try { Thread.sleep(sleep) } catch (_: InterruptedException) {}
        }
    }

    private fun toLogical(x: Float, y: Float): Pair<Float, Float> =
        Pair((x - offX) / scale, (y - offY) / scale)

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = event.actionIndex
                val (lx, ly) = toLogical(event.getX(i), event.getY(i))
                game.tap(lx, ly)
            }
        }
        val pts = ArrayList<Pair<Float, Float>>(event.pointerCount)
        if (event.actionMasked != MotionEvent.ACTION_UP &&
            event.actionMasked != MotionEvent.ACTION_CANCEL
        ) {
            for (i in 0 until event.pointerCount) {
                if (event.actionMasked == MotionEvent.ACTION_POINTER_UP && i == event.actionIndex) continue
                pts.add(toLogical(event.getX(i), event.getY(i)))
            }
        }
        game.setHeld(pts)
        return true
    }
}
