package com.example.tacobros

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView

/**
 * The whole game: world state, physics, collision, camera and rendering.
 * The [GameThread] drives [update] and [render] roughly 60 times a second.
 */
class GameView(context: Context) : SurfaceView(context), SurfaceHolder.Callback {

    enum class State { PLAYING, WIN, GAME_OVER }

    private var thread: GameThread? = null

    private var screenW = 0
    private var screenH = 0
    private var tile = 0f

    private lateinit var player: Player
    private lateinit var level: Level
    private lateinit var controls: Controls

    private var cameraX = 0f

    @Volatile private var state = State.PLAYING
    @Volatile private var ready = false
    @Volatile private var paused = false

    private var score = 0
    private var lives = 3
    private var elapsed = 0f
    private var invuln = 0f

    // ---- Input (touched from the UI thread, read from the game thread) ----
    @Volatile private var leftPressed = false
    @Volatile private var rightPressed = false
    @Volatile private var jumpHeld = false
    @Volatile private var jumpWasHeld = false
    @Volatile private var jumpRequested = false

    // ---- Physics constants (expressed in tiles/sec, scaled by tile size) ----
    private var gravity = 0f
    private var moveSpeed = 0f
    private var jumpVel = 0f
    private var terminalVy = 0f

    // ---- Paints ----
    private val skyPaint = Paint()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    init {
        holder.addCallback(this)
        isFocusable = true
        textPaint.typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
    }

    // ---------------------------------------------------------------- lifecycle
    override fun surfaceCreated(holder: SurfaceHolder) {
        if (thread == null) {
            thread = GameThread(holder, this).also {
                it.running = true
                it.start()
            }
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        synchronized(holder) {
            screenW = width
            screenH = height
            tile = screenH / 9f
            setupPhysics()
            controls = Controls(screenW.toFloat(), screenH.toFloat(), tile)
            skyPaint.shader = LinearGradient(
                0f, 0f, 0f, screenH.toFloat(),
                Color.parseColor("#6FC6E8"), Color.parseColor("#FBE3C2"),
                Shader.TileMode.CLAMP
            )
            startLevel(resetProgress = true)
            ready = true
        }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        stopThread()
    }

    fun resume() { paused = false }

    fun pause() { paused = true }

    private fun stopThread() {
        val t = thread ?: return
        t.running = false
        while (true) {
            try {
                t.join()
                break
            } catch (_: InterruptedException) {
            }
        }
        thread = null
    }

    private fun setupPhysics() {
        gravity = 38f * tile
        moveSpeed = 6.2f * tile
        jumpVel = 15.5f * tile
        terminalVy = 30f * tile
    }

    private fun startLevel(resetProgress: Boolean) {
        level = Level(tile, screenH.toFloat())
        player = Player(level.startX, level.startY, tile)
        cameraX = 0f
        state = State.PLAYING
        elapsed = 0f
        invuln = 0f
        if (resetProgress) {
            score = 0
            lives = 3
        }
        leftPressed = false
        rightPressed = false
        jumpHeld = false
        jumpWasHeld = false
        jumpRequested = false
    }

    fun restart() {
        synchronized(holder) { startLevel(resetProgress = true) }
    }

    // ------------------------------------------------------------------- update
    fun update(dt: Float) {
        if (!ready || paused) return
        if (state == State.PLAYING) updatePlaying(dt)
    }

    private fun updatePlaying(dt: Float) {
        elapsed += dt
        if (invuln > 0f) invuln -= dt

        // Horizontal movement from input.
        player.vx = when {
            leftPressed && !rightPressed -> -moveSpeed
            rightPressed && !leftPressed -> moveSpeed
            else -> 0f
        }
        if (player.vx < 0f) player.facingRight = false
        if (player.vx > 0f) player.facingRight = true

        // Jump (edge-triggered, only from the ground).
        if (jumpRequested && player.onGround) {
            player.vy = -jumpVel
            player.onGround = false
        }
        jumpRequested = false

        // Gravity.
        player.vy += gravity * dt
        if (player.vy > terminalVy) player.vy = terminalVy

        // Move and resolve collisions one axis at a time.
        player.x += player.vx * dt
        resolveHorizontal()

        player.y += player.vy * dt
        player.onGround = false
        resolveVertical()

        // Keep the player from walking off the left edge of the world.
        if (player.x < 0f) player.x = 0f

        // Enemies.
        for (e in level.enemies) e.update(dt)
        handleEnemyCollisions()

        // Tacos.
        for (c in level.tacos) {
            if (c.collected) continue
            if (intersects(player.x, player.y, player.w, player.h, c.x, c.y, c.size, c.size)) {
                c.collected = true
                score += 10
            }
        }

        // Fell into a pit.
        if (player.y > screenH + tile) {
            loseLife(respawn = true)
        }

        // Reached the goal.
        if (state == State.PLAYING && player.x + player.w >= level.goalX) {
            state = State.WIN
        }

        updateCamera()
    }

    private fun resolveHorizontal() {
        for (b in level.blocks) {
            if (!intersects(player.x, player.y, player.w, player.h, b.x, b.y, b.w, b.h)) continue
            if (player.vx > 0f) {
                player.x = b.x - player.w
            } else if (player.vx < 0f) {
                player.x = b.x + b.w
            }
            player.vx = 0f
        }
    }

    private fun resolveVertical() {
        for (b in level.blocks) {
            if (!intersects(player.x, player.y, player.w, player.h, b.x, b.y, b.w, b.h)) continue
            if (player.vy > 0f) {
                // Landing on top of a block.
                player.y = b.y - player.h
                player.onGround = true
            } else if (player.vy < 0f) {
                // Bumping head on the underside.
                player.y = b.y + b.h
            }
            player.vy = 0f
        }
    }

    private fun handleEnemyCollisions() {
        for (e in level.enemies) {
            if (!e.alive) continue
            if (!intersects(player.x, player.y, player.w, player.h, e.x, e.y, e.size, e.size)) continue

            val playerBottom = player.y + player.h
            val stomping = player.vy > 0f && (playerBottom - e.y) < tile * 0.6f
            if (stomping) {
                e.alive = false
                player.vy = -jumpVel * 0.6f
                score += 20
            } else if (invuln <= 0f) {
                loseLife(respawn = false)
            }
        }
    }

    private fun loseLife(respawn: Boolean) {
        lives -= 1
        if (lives <= 0) {
            state = State.GAME_OVER
            return
        }
        invuln = 1.5f
        if (respawn) {
            player.x = level.startX
            player.y = level.startY
            player.vx = 0f
            player.vy = 0f
            cameraX = 0f
        } else {
            // Knock the player back and up a little.
            player.vy = -jumpVel * 0.5f
            player.x += if (player.facingRight) -tile else tile
            if (player.x < 0f) player.x = 0f
        }
    }

    private fun updateCamera() {
        cameraX = player.x + player.w / 2f - screenW / 3f
        val maxCam = (level.widthPx - screenW).coerceAtLeast(0f)
        cameraX = cameraX.coerceIn(0f, maxCam)
    }

    private fun intersects(
        ax: Float, ay: Float, aw: Float, ah: Float,
        bx: Float, by: Float, bw: Float, bh: Float
    ): Boolean = ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by

    // ------------------------------------------------------------------- render
    fun render(canvas: Canvas) {
        if (!ready) {
            canvas.drawColor(Color.BLACK)
            return
        }
        drawBackground(canvas)
        canvas.save()
        canvas.translate(-cameraX, 0f)
        drawLevel(canvas)
        drawTacos(canvas)
        drawEnemies(canvas)
        drawPlayer(canvas)
        canvas.restore()
        drawHud(canvas)
        if (state == State.PLAYING) controls.draw(canvas, paint, leftPressed, rightPressed, jumpHeld)
        if (state != State.PLAYING) drawOverlay(canvas)
    }

    private fun drawBackground(canvas: Canvas) {
        canvas.drawRect(0f, 0f, screenW.toFloat(), screenH.toFloat(), skyPaint)

        // Sun.
        paint.color = Color.parseColor("#FFF3C4")
        canvas.drawCircle(screenW * 0.82f, screenH * 0.22f, tile * 1.2f, paint)

        // Far hills (slow parallax).
        paint.color = Color.parseColor("#9BD79A")
        drawHillRow(canvas, factor = 0.3f, spacing = tile * 8f, baseY = screenH * 0.80f, radius = tile * 3.2f)

        // Near hills (faster parallax).
        paint.color = Color.parseColor("#7CC178")
        drawHillRow(canvas, factor = 0.5f, spacing = tile * 6f, baseY = screenH * 0.92f, radius = tile * 2.4f)
    }

    private fun drawHillRow(canvas: Canvas, factor: Float, spacing: Float, baseY: Float, radius: Float) {
        val offset = (cameraX * factor) % spacing
        var hx = -offset - spacing
        while (hx < screenW + spacing) {
            canvas.drawCircle(hx, baseY, radius, paint)
            hx += spacing
        }
    }

    private fun drawLevel(canvas: Canvas) {
        val left = cameraX
        val right = cameraX + screenW
        for (b in level.blocks) {
            if (b.x + b.w < left || b.x > right) continue
            // Dirt body.
            paint.color = Color.parseColor("#B5793E")
            canvas.drawRect(b.x, b.y, b.x + b.w, b.y + b.h, paint)
            // Grass cap (a thin band on top, never taller than the block).
            paint.color = Color.parseColor("#5BB14F")
            val grass = (tile * 0.25f).coerceAtMost(b.h)
            canvas.drawRect(b.x, b.y, b.x + b.w, b.y + grass, paint)
        }
        drawGoal(canvas)
    }

    private fun drawGoal(canvas: Canvas) {
        val gx = level.goalX
        val topY = level.goalTopY
        // Pole.
        paint.color = Color.parseColor("#E0E0E0")
        canvas.drawRect(gx, topY, gx + tile * 0.12f, level.groundTopY, paint)
        // Ball on top.
        paint.color = Color.parseColor("#F2C14E")
        canvas.drawCircle(gx + tile * 0.06f, topY, tile * 0.16f, paint)
        // Triangular flag.
        paint.color = Color.parseColor("#E8503A")
        val flag = Path()
        flag.moveTo(gx + tile * 0.12f, topY + tile * 0.05f)
        flag.lineTo(gx + tile * 1.05f, topY + tile * 0.35f)
        flag.lineTo(gx + tile * 0.12f, topY + tile * 0.65f)
        flag.close()
        canvas.drawPath(flag, paint)
    }

    private fun drawTacos(canvas: Canvas) {
        val left = cameraX
        val right = cameraX + screenW
        for (c in level.tacos) {
            if (c.collected) continue
            if (c.x + c.size < left || c.x > right) continue
            val cx = c.x + c.size / 2f
            val cy = c.y + c.size / 2f
            val r = c.size * 0.5f

            // Taco shell: a yellow half-disc (flat side up) forming the U shape.
            paint.color = Color.parseColor("#F4B73E")
            val shell = RectF(cx - r, cy - r * 0.55f, cx + r, cy + r * 1.25f)
            canvas.drawArc(shell, 0f, 180f, true, paint)

            // Lettuce poking out of the top.
            paint.color = Color.parseColor("#5BB14F")
            canvas.drawRect(cx - r * 0.8f, cy - r * 0.18f, cx + r * 0.8f, cy + r * 0.12f, paint)

            // Tomato / filling bits.
            paint.color = Color.parseColor("#E8503A")
            canvas.drawCircle(cx - r * 0.35f, cy + r * 0.05f, r * 0.16f, paint)
            canvas.drawCircle(cx + r * 0.4f, cy, r * 0.14f, paint)

            // Meat layer just under the lettuce.
            paint.color = Color.parseColor("#8B5A2B")
            canvas.drawRect(cx - r * 0.7f, cy + r * 0.18f, cx + r * 0.7f, cy + r * 0.4f, paint)

            // Shell outline for a little definition.
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = r * 0.1f
            paint.color = Color.parseColor("#D99A22")
            canvas.drawArc(shell, 0f, 180f, true, paint)
            paint.style = Paint.Style.FILL
        }
    }

    private fun drawEnemies(canvas: Canvas) {
        val left = cameraX
        val right = cameraX + screenW
        for (e in level.enemies) {
            if (!e.alive) continue
            if (e.x + e.size < left || e.x > right) continue
            val cx = e.x + e.size / 2f
            // Body.
            paint.color = Color.parseColor("#9B5DE5")
            canvas.drawRoundRect(RectF(e.x, e.y, e.x + e.size, e.y + e.size), e.size * 0.4f, e.size * 0.4f, paint)
            // Eyes.
            paint.color = Color.WHITE
            canvas.drawCircle(cx - e.size * 0.18f, e.y + e.size * 0.42f, e.size * 0.12f, paint)
            canvas.drawCircle(cx + e.size * 0.18f, e.y + e.size * 0.42f, e.size * 0.12f, paint)
            paint.color = Color.parseColor("#10303A")
            canvas.drawCircle(cx - e.size * 0.18f, e.y + e.size * 0.42f, e.size * 0.06f, paint)
            canvas.drawCircle(cx + e.size * 0.18f, e.y + e.size * 0.42f, e.size * 0.06f, paint)
            // Feet.
            paint.color = Color.parseColor("#6A3FB0")
            canvas.drawRect(e.x + e.size * 0.1f, e.y + e.size * 0.85f, e.x + e.size * 0.4f, e.y + e.size, paint)
            canvas.drawRect(e.x + e.size * 0.6f, e.y + e.size * 0.85f, e.x + e.size * 0.9f, e.y + e.size, paint)
        }
    }

    /** Draws Miguel, the hero. */
    private fun drawPlayer(canvas: Canvas) {
        // Flicker while invulnerable.
        if (invuln > 0f && ((invuln * 10).toInt() % 2 == 0)) return

        val x = player.x
        val y = player.y
        val w = player.w
        val h = player.h
        val cx = x + w / 2f
        val look = if (player.facingRight) w * 0.05f else -w * 0.05f

        // Legs.
        paint.color = Color.parseColor("#2F4858")
        canvas.drawRect(x + w * 0.2f, y + h * 0.82f, x + w * 0.45f, y + h, paint)
        canvas.drawRect(x + w * 0.55f, y + h * 0.82f, x + w * 0.8f, y + h, paint)

        // Shirt / body.
        paint.color = Color.parseColor("#2EC4B6")
        canvas.drawRoundRect(
            RectF(x + w * 0.12f, y + h * 0.45f, x + w * 0.88f, y + h * 0.86f),
            w * 0.18f, w * 0.18f, paint
        )

        // Arms.
        paint.color = Color.parseColor("#C68642")
        canvas.drawRoundRect(RectF(x, y + h * 0.48f, x + w * 0.16f, y + h * 0.78f), w * 0.08f, w * 0.08f, paint)
        canvas.drawRoundRect(RectF(x + w * 0.84f, y + h * 0.48f, x + w, y + h * 0.78f), w * 0.08f, w * 0.08f, paint)

        // Head.
        paint.color = Color.parseColor("#D69A63")
        canvas.drawRoundRect(
            RectF(x + w * 0.18f, y + h * 0.1f, x + w * 0.82f, y + h * 0.5f),
            w * 0.22f, w * 0.22f, paint
        )

        // Hair.
        paint.color = Color.parseColor("#2B1A12")
        canvas.drawRoundRect(
            RectF(x + w * 0.16f, y + h * 0.07f, x + w * 0.84f, y + h * 0.24f),
            w * 0.2f, w * 0.2f, paint
        )

        // Eyes.
        val eyeY = y + h * 0.30f
        val eyeDX = w * 0.16f
        paint.color = Color.WHITE
        canvas.drawCircle(cx - eyeDX, eyeY, w * 0.1f, paint)
        canvas.drawCircle(cx + eyeDX, eyeY, w * 0.1f, paint)
        paint.color = Color.parseColor("#10303A")
        canvas.drawCircle(cx - eyeDX + look, eyeY, w * 0.05f, paint)
        canvas.drawCircle(cx + eyeDX + look, eyeY, w * 0.05f, paint)

        // Friendly smile.
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = w * 0.04f
        paint.color = Color.parseColor("#7A3B1E")
        val mouth = RectF(cx - w * 0.12f, y + h * 0.34f, cx + w * 0.12f, y + h * 0.46f)
        canvas.drawArc(mouth, 20f, 140f, false, paint)
        paint.style = Paint.Style.FILL
    }

    private fun drawHud(canvas: Canvas) {
        textPaint.setShadowLayer(tile * 0.06f, tile * 0.03f, tile * 0.03f, Color.parseColor("#66000000"))
        textPaint.color = Color.WHITE
        textPaint.textSize = tile * 0.5f
        textPaint.textAlign = Paint.Align.LEFT
        canvas.drawText("TACOS  $score", tile * 0.4f, tile * 0.7f, textPaint)
        canvas.drawText("LIVES  $lives", tile * 0.4f, tile * 1.35f, textPaint)
        textPaint.textAlign = Paint.Align.RIGHT
        canvas.drawText("TIME  ${elapsed.toInt()}", screenW - tile * 0.4f, tile * 0.7f, textPaint)
        textPaint.textAlign = Paint.Align.LEFT
        textPaint.clearShadowLayer()
    }

    private fun drawOverlay(canvas: Canvas) {
        paint.color = Color.parseColor("#AA000000")
        canvas.drawRect(0f, 0f, screenW.toFloat(), screenH.toFloat(), paint)

        textPaint.textAlign = Paint.Align.CENTER
        textPaint.color = Color.WHITE
        textPaint.textSize = tile * 1.1f
        val title = if (state == State.WIN) "Level Complete!" else "Game Over"
        canvas.drawText(title, screenW / 2f, screenH / 2f - tile * 0.4f, textPaint)

        textPaint.textSize = tile * 0.5f
        canvas.drawText("Tacos $score    Time ${elapsed.toInt()}s", screenW / 2f, screenH / 2f + tile * 0.4f, textPaint)
        canvas.drawText("Tap to play again", screenW / 2f, screenH / 2f + tile * 1.3f, textPaint)
        textPaint.textAlign = Paint.Align.LEFT
    }

    // -------------------------------------------------------------------- input
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!ready) return true
        val action = event.actionMasked

        if (state != State.PLAYING) {
            if (action == MotionEvent.ACTION_DOWN) restart()
            return true
        }

        var left = false
        var right = false
        var jump = false

        if (action != MotionEvent.ACTION_UP && action != MotionEvent.ACTION_CANCEL) {
            for (i in 0 until event.pointerCount) {
                // Ignore the pointer that is lifting in a multi-touch up event.
                if (action == MotionEvent.ACTION_POINTER_UP && i == event.actionIndex) continue
                when (controls.hit(event.getX(i), event.getY(i))) {
                    Controls.Button.LEFT -> left = true
                    Controls.Button.RIGHT -> right = true
                    Controls.Button.JUMP -> jump = true
                    Controls.Button.NONE -> {}
                }
            }
        }

        leftPressed = left
        rightPressed = right
        if (jump && !jumpWasHeld) jumpRequested = true
        jumpWasHeld = jump
        jumpHeld = jump
        return true
    }
}
