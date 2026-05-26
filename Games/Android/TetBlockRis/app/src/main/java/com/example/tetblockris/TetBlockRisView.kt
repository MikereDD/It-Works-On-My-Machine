package com.example.tetblockris

import android.content.Context
import android.graphics.*
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import kotlin.math.min
import kotlin.random.Random

class TetBlockRisView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    // ── Constants ────────────────────────────────────────────────────────────
    private val cols = 10
    private val rows = 20

    // ── Layout values (computed in onSizeChanged) ────────────────────────────
    private var cellSize      = 0f
    private var boardLeft     = 0f   // board origin X
    private var boardTop      = 0f   // board origin Y
    private var previewSize   = 0f   // cell size used for HOLD/NEXT previews
    private var panelWidth    = 0f   // width of a HOLD or NEXT panel
    private var panelHeight   = 0f

    // ── Game state ───────────────────────────────────────────────────────────
    private val game = TetBlockRisGame(cols, rows)
    private val handler = Handler(Looper.getMainLooper())
    var isRunning = false
        private set
    private var dropSpeed = 500L

    // ── Callbacks ────────────────────────────────────────────────────────────
    var onScoreUpdate: ((Int, Int, Int) -> Unit)? = null
    var onGameOver: ((Int) -> Unit)? = null
    var onVictory: ((Int) -> Unit)? = null
    var onHoldUpdate: ((Boolean) -> Unit)? = null

    // ── Animation pools ──────────────────────────────────────────────────────
    private val particles = mutableListOf<Particle>()
    private val lineClearAnims = mutableListOf<LineClearAnim>()

    // ── Paints ───────────────────────────────────────────────────────────────
    private val paint     = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val gridPaint = Paint().apply {
        color = Color.argb(25, 255, 255, 255)
        strokeWidth = 0.8f
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        typeface = Typeface.DEFAULT_BOLD
    }

    private var bgGradient: LinearGradient? = null
    private val blockRect  = RectF()
    private val cornerRad  = 7f

    // ── Gesture detector (swipe-down hard-drop; tap rotate as fallback) ──────
    private val gestureDetector = GestureDetector(context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onFling(e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float): Boolean {
                if (!isRunning) return false
                if (vy > 600) { doHardDrop(); return true }
                return false
            }
        })

    // ── Game loop ────────────────────────────────────────────────────────────
    private val gameLoop = object : Runnable {
        override fun run() {
            if (!isRunning) return
            val result = game.tick()
            when {
                result == -1 -> { gameOver(); return }
                result == -2 -> { victory(); return }
                result > 0   -> { triggerLineClearAnim(result); spawnClearParticles(result) }
            }
            updateScore()
            invalidate()
            handler.postDelayed(this, dropSpeed)
        }
    }

    // ── Public control surface (called by MainActivity buttons) ──────────────
    fun moveLeft()    { if (isRunning) { game.moveLeft();  invalidate() } }
    fun moveRight()   { if (isRunning) { game.moveRight(); invalidate() } }
    fun softDrop()    { if (isRunning) { game.tick();      updateScore(); invalidate() } }
    fun doRotate()    { if (isRunning) { game.rotate();    invalidate() } }
    fun doHardDrop()  {
        if (!isRunning) return
        game.hardDrop()
        spawnDropParticles()
        updateScore()
        invalidate()
    }
    fun doHold() {
        if (!isRunning) return
        game.holdPiece()
        onHoldUpdate?.invoke(game.hasHeldThisTurn)
        invalidate()
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────
    fun startGame() {
        game.reset()
        particles.clear()
        lineClearAnims.clear()
        dropSpeed = 500L
        isRunning = true
        onHoldUpdate?.invoke(false)
        handler.post(gameLoop)
        invalidate()
    }

    fun pauseGame() {
        isRunning = false
        handler.removeCallbacks(gameLoop)
    }

    fun resumeGame() {
        if (isRunning) return
        isRunning = true
        handler.post(gameLoop)
    }

    private fun gameOver() {
        isRunning = false
        onGameOver?.invoke(game.score)
    }

    private fun victory() {
        isRunning = false
        spawnVictoryParticles()
        onVictory?.invoke(game.score)
        invalidate()
    }

    private fun updateScore() {
        onScoreUpdate?.invoke(game.score, game.level, game.linesCleared)
        dropSpeed = game.getDropSpeed()
    }

    // ── Layout ───────────────────────────────────────────────────────────────
    /**
     * Layout strategy:
     *
     *   ┌──────────────────────────────────┐
     *   │  [HOLD panel]   [NEXT panel]     │  ← panel row, height = panelHeight + labelGap
     *   │  ┌────────────────────────────┐  │
     *   │  │                            │  │
     *   │  │       10 × 20 board        │  │  ← remaining height
     *   │  │                            │  │
     *   │  └────────────────────────────┘  │
     *   └──────────────────────────────────┘
     *
     * Both panels sit side-by-side ABOVE the board, centred horizontally.
     * The board is centred below them, sized to fill the remaining space.
     */
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)

        val pw = w.toFloat()
        val ph = h.toFloat()

        // Preview cell: ~18 % of width divided into 5 columns per panel
        previewSize  = pw * 0.09f           // 5 preview cells → 45 % of width per panel
        panelWidth   = previewSize * 5f
        panelHeight  = previewSize * 5f
        val labelGap = previewSize * 1.2f   // space for the label above the box
        val panelRowH = panelHeight + labelGap
        val vPad     = ph * 0.01f           // small gap between panel row and board

        // Board fits in the remaining vertical space
        val boardAvailH = ph - panelRowH - vPad
        val cellByH = boardAvailH / rows
        val cellByW = pw * 0.86f / cols     // 86 % of width leaves margins
        cellSize = min(cellByH, cellByW)

        // Horizontal centre
        val boardW = cols * cellSize
        boardLeft = (pw - boardW) / 2f

        // Board starts just below the panel row
        boardTop = panelRowH + vPad

        bgGradient = LinearGradient(
            0f, 0f, 0f, ph,
            Color.argb(255, 12, 12, 28),
            Color.argb(255, 4, 4, 12),
            Shader.TileMode.CLAMP
        )
    }

    // ── Drawing ──────────────────────────────────────────────────────────────
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        // Background
        paint.shader = bgGradient
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.shader = null

        updateAndDrawParticles(canvas)

        // HOLD and NEXT panels — centred above the board
        val totalPanels   = panelWidth * 2 + previewSize * 2  // two panels + gap
        val panelStartX   = (width - totalPanels) / 2f
        val holdX  = panelStartX
        val nextX  = panelStartX + panelWidth + previewSize * 2
        val panelY = previewSize * 1.1f   // leaves room for label

        drawSidePanel(canvas, holdX, panelY, "HOLD", game.holdPiece, game.hasHeldThisTurn)
        drawSidePanel(canvas, nextX, panelY, "NEXT", game.nextPiece, false)

        drawBoardBackground(canvas)
        drawGrid(canvas)
        drawLineClearAnims(canvas)
        drawBoardBlocks(canvas)
        drawGhost(canvas)
        drawCurrentPiece(canvas)
    }

    private fun drawGrid(canvas: Canvas) {
        for (i in 0..cols) {
            val x = boardLeft + i * cellSize
            canvas.drawLine(x, boardTop, x, boardTop + rows * cellSize, gridPaint)
        }
        for (i in 0..rows) {
            val y = boardTop + i * cellSize
            canvas.drawLine(boardLeft, y, boardLeft + cols * cellSize, y, gridPaint)
        }
    }

    private fun drawBoardBlocks(canvas: Canvas) {
        for (y in 0 until rows) {
            for (x in 0 until cols) {
                game.board[y][x]?.let { color ->
                    drawBlock(canvas,
                        boardLeft + x * cellSize,
                        boardTop  + y * cellSize,
                        cellSize, color, 1f)
                }
            }
        }
    }

    private fun drawGhost(canvas: Canvas) {
        val piece = game.currentPiece ?: return
        val ghostY = game.getGhostY()
        for (block in piece.blocks) {
            val bx = piece.x + block.first
            val by = ghostY + block.second
            if (by >= 0 && by < rows) {
                drawGhostBlock(canvas,
                    boardLeft + bx * cellSize,
                    boardTop  + by * cellSize,
                    cellSize, piece.color)
            }
        }
    }

    private fun drawCurrentPiece(canvas: Canvas) {
        val piece = game.currentPiece ?: return
        for (block in piece.blocks) {
            val bx = piece.x + block.first
            val by = piece.y + block.second
            if (by >= 0) {
                drawBlock(canvas,
                    boardLeft + bx * cellSize,
                    boardTop  + by * cellSize,
                    cellSize, piece.color, 1f, withGlow = true)
            }
        }
    }

    private fun drawBoardBackground(canvas: Canvas) {
        paint.color = Color.argb(45, 255, 255, 255)
        val r = RectF(boardLeft - 4, boardTop - 4,
            boardLeft + cols * cellSize + 4,
            boardTop  + rows * cellSize + 4)
        canvas.drawRoundRect(r, 14f, 14f, paint)

        // Inner board tint
        paint.color = Color.argb(20, 0, 0, 40)
        val inner = RectF(boardLeft, boardTop,
            boardLeft + cols * cellSize,
            boardTop  + rows * cellSize)
        canvas.drawRect(inner, paint)
    }

    // ── Side panels (HOLD / NEXT) ────────────────────────────────────────────
    private fun drawSidePanel(
        canvas: Canvas,
        offsetX: Float, offsetY: Float,
        label: String,
        piece: TetBlockRisPiece?,
        dimmed: Boolean
    ) {
        val boxW = panelWidth
        val boxH = panelHeight

        // Panel background
        paint.color = Color.argb(55, 255, 255, 255)
        val panelRect = RectF(offsetX, offsetY, offsetX + boxW, offsetY + boxH)
        canvas.drawRoundRect(panelRect, 14f, 14f, paint)

        // Panel border
        paint.color = if (dimmed)
            Color.argb(60, 120, 120, 120)
        else
            Color.argb(110, 180, 180, 255)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.5f
        canvas.drawRoundRect(panelRect, 14f, 14f, paint)
        paint.style = Paint.Style.FILL

        // Label above the box
        textPaint.textSize = previewSize * 0.65f
        textPaint.color = if (dimmed) Color.argb(90, 180, 180, 180) else Color.argb(200, 200, 220, 255)
        canvas.drawText(label, offsetX + boxW / 2f, offsetY - previewSize * 0.25f, textPaint)

        // Piece preview
        piece?.let { p ->
            val minBX = p.blocks.minOf { it.first }
            val minBY = p.blocks.minOf { it.second }
            val maxBX = p.blocks.maxOf { it.first }
            val maxBY = p.blocks.maxOf { it.second }
            val pieceW = (maxBX - minBX + 1) * previewSize
            val pieceH = (maxBY - minBY + 1) * previewSize
            val startX = offsetX + (boxW - pieceW) / 2f - minBX * previewSize
            val startY = offsetY + (boxH - pieceH) / 2f - minBY * previewSize

            for (block in p.blocks) {
                val px = startX + block.first  * previewSize
                val py = startY + block.second * previewSize
                drawBlock(canvas, px, py, previewSize, p.color, if (dimmed) 0.35f else 1f)
            }
        }
    }

    // ── Block drawing ────────────────────────────────────────────────────────
    private fun drawBlock(
        canvas: Canvas,
        x: Float, y: Float,
        size: Float, color: Int,
        alpha: Float,
        withGlow: Boolean = false
    ) {
        val pad    = size * 0.07f
        val left   = x + pad
        val top    = y + pad
        val right  = left + size - pad * 2
        val bottom = top  + size - pad * 2

        blockRect.set(left, top, right, bottom)

        if (withGlow) {
            glowPaint.color = color
            glowPaint.alpha = (35 * alpha).toInt()
            glowPaint.maskFilter = BlurMaskFilter(size * 0.35f, BlurMaskFilter.Blur.NORMAL)
            canvas.drawRoundRect(blockRect, cornerRad, cornerRad, glowPaint)
            glowPaint.maskFilter = null
        }

        // Base fill with gradient
        val grad = LinearGradient(left, top, right, bottom,
            lightenColor(color, 1.35f), color, Shader.TileMode.CLAMP)
        paint.shader = grad
        paint.alpha  = (255 * alpha).toInt()
        canvas.drawRoundRect(blockRect, cornerRad, cornerRad, paint)
        paint.shader = null

        // Top-left highlight
        val hlGrad = LinearGradient(left, top, left, top + (bottom - top) * 0.5f,
            Color.argb((110 * alpha).toInt(), 255, 255, 255),
            Color.argb(0, 255, 255, 255),
            Shader.TileMode.CLAMP)
        paint.shader = hlGrad
        canvas.drawRoundRect(
            RectF(left, top, right, top + (bottom - top) * 0.5f),
            cornerRad, cornerRad, paint)
        paint.shader = null

        // Bottom shadow
        paint.color = Color.argb((55 * alpha).toInt(), 0, 0, 0)
        canvas.drawRoundRect(
            RectF(left, bottom - (bottom - top) * 0.28f, right, bottom),
            cornerRad, cornerRad, paint)

        paint.alpha = 255
    }

    private fun drawGhostBlock(canvas: Canvas, x: Float, y: Float, size: Float, color: Int) {
        val pad = size * 0.1f
        val rect = RectF(x + pad, y + pad, x + size - pad, y + size - pad)
        paint.color = color
        paint.alpha = 45
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.8f
        canvas.drawRoundRect(rect, cornerRad, cornerRad, paint)
        paint.style = Paint.Style.FILL
        paint.alpha = 255
    }

    // ── Particles ────────────────────────────────────────────────────────────
    private fun spawnDropParticles() {
        game.currentPiece?.let { piece ->
            for (block in piece.blocks) {
                val bx = piece.x + block.first
                val by = piece.y + block.second
                if (by >= 0) repeat(3) {
                    particles.add(Particle(
                        boardLeft + bx * cellSize + cellSize / 2f,
                        boardTop  + by * cellSize + cellSize / 2f,
                        piece.color))
                }
            }
        }
    }

    private fun spawnClearParticles(cleared: Int) {
        for (y in (rows - cleared) until rows) {
            for (x in 0 until cols) {
                game.board[y][x]?.let { color ->
                    repeat(2) {
                        particles.add(Particle(
                            boardLeft + x * cellSize + cellSize / 2f,
                            boardTop  + y * cellSize + cellSize / 2f,
                            color, speedMultiplier = 2f))
                    }
                }
            }
        }
    }

    private fun spawnVictoryParticles() {
        repeat(60) {
            particles.add(Particle(
                width / 2f, height / 3f,
                listOf(Color.CYAN, Color.MAGENTA, Color.YELLOW, Color.GREEN,
                    0xFFFF6688.toInt(), 0xFF88FFCC.toInt()).random(),
                speedMultiplier = 3.5f, life = 2f))
        }
    }

    private fun updateAndDrawParticles(canvas: Canvas) {
        val it = particles.iterator()
        while (it.hasNext()) {
            val p = it.next()
            p.update()
            if (p.life <= 0) { it.remove(); continue }
            paint.color = p.color
            paint.alpha = (255 * p.life).toInt().coerceIn(0, 255)
            canvas.drawCircle(p.x, p.y, p.size * p.life, paint)
        }
        paint.alpha = 255
        if (particles.isNotEmpty()) invalidate()
    }

    // ── Line clear animation ──────────────────────────────────────────────────
    private fun triggerLineClearAnim(lines: Int) {
        for (i in 0 until lines) lineClearAnims.add(LineClearAnim(rows - 1 - i))
        invalidate()
    }

    private fun drawLineClearAnims(canvas: Canvas) {
        val it = lineClearAnims.iterator()
        while (it.hasNext()) {
            val anim = it.next()
            anim.progress += 0.06f
            if (anim.progress >= 1f) { it.remove(); continue }

            val flashA = (255 * (1f - anim.progress)).toInt()
            paint.color = Color.argb(flashA, 255, 255, 255)
            val y = boardTop + anim.row * cellSize
            canvas.drawRect(boardLeft, y, boardLeft + cols * cellSize, y + cellSize, paint)

            repeat(6) {
                val sx = boardLeft + Random.nextFloat() * cols * cellSize
                val sy = y + Random.nextFloat() * cellSize
                paint.color = Color.argb(flashA, 255, 255, 180)
                canvas.drawCircle(sx, sy, 3.5f * (1f - anim.progress), paint)
            }
        }
        if (lineClearAnims.isNotEmpty()) invalidate()
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private fun lightenColor(color: Int, factor: Float): Int {
        return Color.argb(
            Color.alpha(color),
            min(255, (Color.red(color)   * factor).toInt()),
            min(255, (Color.green(color) * factor).toInt()),
            min(255, (Color.blue(color)  * factor).toInt()))
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        gestureDetector.onTouchEvent(event)
        return true
    }

    // ── Inner classes ────────────────────────────────────────────────────────
    private data class Particle(
        var x: Float, var y: Float,
        val color: Int,
        var vx: Float = Random.nextFloat() * 7f - 3.5f,
        var vy: Float = Random.nextFloat() * -9f - 2f,
        var life: Float = 1f,
        var size: Float = Random.nextFloat() * 7f + 3f,
        val speedMultiplier: Float = 1f
    ) {
        fun update() {
            x  += vx * speedMultiplier
            y  += vy * speedMultiplier
            vy += 0.35f
            life -= 0.022f
        }
    }

    private data class LineClearAnim(val row: Int, var progress: Float = 0f)
}
