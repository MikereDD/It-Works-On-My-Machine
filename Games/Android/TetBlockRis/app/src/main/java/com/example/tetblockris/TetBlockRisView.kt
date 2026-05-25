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

    private val cols = 10
    private val rows = 20
    private var cellSize = 0f
    private var boardOffsetX = 0f
    private var boardOffsetY = 0f
    private var previewCellSize = 0f

    private val game = TetBlockRisGame(cols, rows)
    private val handler = Handler(Looper.getMainLooper())
    private var isRunning = false
    private var dropSpeed = 500L

    var onScoreUpdate: ((Int, Int, Int) -> Unit)? = null
    var onGameOver: ((Int) -> Unit)? = null
    var onVictory: ((Int) -> Unit)? = null
    var onHoldUpdate: ((Boolean) -> Unit)? = null

    private val particles = mutableListOf<<Particle>()
    private val lineClearAnimations = mutableListOf<<LineClearAnim>()

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val gridPaint = Paint().apply {
        color = Color.argb(30, 255, 255, 255)
        strokeWidth = 1f
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        typeface = Typeface.DEFAULT_BOLD
    }

    private var bgGradient: LinearGradient? = null
    private val blockRect = RectF()
    private val cornerRadius = 8f

    private val gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onFling(e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float): Boolean {
            if (!isRunning) return false
            when {
                vx > 300 -> game.moveRight()
                vx < -300 -> game.moveLeft()
                vy > 400 -> { game.hardDrop(); spawnDropParticles(); updateScore() }
            }
            invalidate()
            return true
        }

        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            if (!isRunning) return true
            if (e.x < width * 0.2f) {
                game.holdPiece()
                onHoldUpdate?.invoke(game.hasHeldThisTurn)
            } else {
                game.rotate()
            }
            invalidate()
            return true
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            if (isRunning) {
                game.holdPiece()
                onHoldUpdate?.invoke(game.hasHeldThisTurn)
                invalidate()
            }
            return true
        }
    })

    private val gameLoop = object : Runnable {
        override fun run() {
            if (!isRunning) return
            val result = game.tick()
            if (result == -1) {
                gameOver()
                return
            }
            if (result == -2) {
                victory()
                return
            }
            if (result > 0) {
                triggerLineClearAnim(result)
                spawnClearParticles(result)
            }
            updateScore()
            invalidate()
            handler.postDelayed(this, dropSpeed)
        }
    }

    fun startGame() {
        game.reset()
        particles.clear()
        lineClearAnimations.clear()
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

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val minDim = min(w, h)
        cellSize = (minDim * 0.65f) / cols
        previewCellSize = cellSize * 0.75f

        boardOffsetX = (w - cols * cellSize) / 2f
        boardOffsetY = h * 0.15f

        bgGradient = LinearGradient(
            0f, 0f, 0f, h.toFloat(),
            Color.argb(255, 15, 15, 35),
            Color.argb(255, 5, 5, 15),
            Shader.TileMode.CLAMP
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        paint.shader = bgGradient
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.shader = null

        updateAndDrawParticles(canvas)

        drawSidePanel(canvas, boardOffsetX - previewCellSize * 6.5f, boardOffsetY, "HOLD", game.holdPiece, game.hasHeldThisTurn)
        drawSidePanel(canvas, boardOffsetX + cols * cellSize + previewCellSize * 1.5f, boardOffsetY, "NEXT", game.nextPiece, false)

        drawBoardBackground(canvas)

        for (i in 0..cols) {
            val x = boardOffsetX + i * cellSize
            canvas.drawLine(x, boardOffsetY, x, boardOffsetY + rows * cellSize, gridPaint)
        }
        for (i in 0..rows) {
            val y = boardOffsetY + i * cellSize
            canvas.drawLine(boardOffsetX, y, boardOffsetX + cols * cellSize, y, gridPaint)
        }

        drawLineClearAnims(canvas)

        for (y in 0 until rows) {
            for (x in 0 until cols) {
                game.board[y][x]?.let { color ->
                    drawModernBlock(canvas, boardOffsetX + x * cellSize, boardOffsetY + y * cellSize, cellSize, color, 1f)
                }
            }
        }

        game.currentPiece?.let { piece ->
            val ghostY = game.getGhostY()
            for (block in piece.blocks) {
                val bx = piece.x + block.first
                val by = ghostY + block.second
                if (by >= 0 && by < rows) {
                    drawGhostBlock(canvas, boardOffsetX + bx * cellSize, boardOffsetY + by * cellSize, cellSize, piece.color)
                }
            }
        }

        game.currentPiece?.let { piece ->
            for (block in piece.blocks) {
                val bx = piece.x + block.first
                val by = piece.y + block.second
                if (by >= 0) {
                    drawModernBlock(canvas, boardOffsetX + bx * cellSize, boardOffsetY + by * cellSize, cellSize, piece.color, 1f, true)
                }
            }
        }
    }

    private fun drawBoardBackground(canvas: Canvas) {
        paint.color = Color.argb(40, 255, 255, 255)
        val bgRect = RectF(
            boardOffsetX - 4,
            boardOffsetY - 4,
            boardOffsetX + cols * cellSize + 4,
            boardOffsetY + rows * cellSize + 4
        )
        canvas.drawRoundRect(bgRect, 12f, 12f, paint)
    }

    private fun drawSidePanel(canvas: Canvas, offsetX: Float, offsetY: Float, label: String, piece: TetBlockRisPiece?, dimmed: Boolean) {
        val boxWidth = previewCellSize * 5
        val boxHeight = previewCellSize * 5

        paint.color = Color.argb(60, 255, 255, 255)
        val panelRect = RectF(offsetX, offsetY, offsetX + boxWidth, offsetY + boxHeight)
        canvas.drawRoundRect(panelRect, 16f, 16f, paint)

        paint.color = if (dimmed) Color.argb(80, 100, 100, 100) else Color.argb(120, 200, 200, 255)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f
        canvas.drawRoundRect(panelRect, 16f, 16f, paint)
        paint.style = Paint.Style.FILL

        textPaint.textSize = previewCellSize * 0.7f
        textPaint.color = if (dimmed) Color.argb(100, 200, 200, 200) else Color.WHITE
        canvas.drawText(label, offsetX + boxWidth / 2, offsetY - previewCellSize * 0.4f, textPaint)

        piece?.let { p ->
            val pieceWidth = (p.blocks.maxOf { it.first } - p.blocks.minOf { it.first } + 1) * previewCellSize
            val pieceHeight = (p.blocks.maxOf { it.second } - p.blocks.minOf { it.second } + 1) * previewCellSize
            val startX = offsetX + (boxWidth - pieceWidth) / 2
            val startY = offsetY + (boxHeight - pieceHeight) / 2

            for (block in p.blocks) {
                val px = startX + block.first * previewCellSize
                val py = startY + block.second * previewCellSize
                val alpha = if (dimmed) 0.4f else 1f
                drawModernBlock(canvas, px, py, previewCellSize, p.color, alpha)
            }
        }
    }

    private fun drawModernBlock(canvas: Canvas, x: Float, y: Float, size: Float, color: Int, alpha: Float, withGlow: Boolean = false) {
        val padding = size * 0.08f
        val left = x + padding
        val top = y + padding
        val right = left + size - padding * 2
        val bottom = top + size - padding * 2

        blockRect.set(left, top, right, bottom)

        if (withGlow) {
            glowPaint.color = color
            glowPaint.alpha = (40 * alpha).toInt()
            glowPaint.maskFilter = BlurMaskFilter(size * 0.3f, BlurMaskFilter.Blur.NORMAL)
            canvas.drawRoundRect(blockRect, cornerRadius, cornerRadius, glowPaint)
            glowPaint.maskFilter = null
        }

        val blockGradient = LinearGradient(
            left, top, right, bottom,
            lightenColor(color, 1.3f),
            color,
            Shader.TileMode.CLAMP
        )
        paint.shader = blockGradient
        paint.alpha = (255 * alpha).toInt()
        canvas.drawRoundRect(blockRect, cornerRadius, cornerRadius, paint)
        paint.shader = null

        val highlightGradient = LinearGradient(
            left, top, left, top + (bottom - top) * 0.5f,
            Color.argb((100 * alpha).toInt(), 255, 255, 255),
            Color.argb(0, 255, 255, 255),
            Shader.TileMode.CLAMP
        )
        paint.shader = highlightGradient
        val highlightRect = RectF(left, top, right, top + (bottom - top) * 0.5f)
        canvas.drawRoundRect(highlightRect, cornerRadius, cornerRadius, paint)
        paint.shader = null

        paint.color = Color.argb((60 * alpha).toInt(), 0, 0, 0)
        val shadowRect = RectF(left, bottom - (bottom - top) * 0.3f, right, bottom)
        canvas.drawRoundRect(shadowRect, cornerRadius, cornerRadius, paint)

        paint.alpha = 255
    }

    private fun drawGhostBlock(canvas: Canvas, x: Float, y: Float, size: Float, color: Int) {
        val padding = size * 0.15f
        val left = x + padding
        val top = y + padding
        val right = left + size - padding * 2
        val bottom = top + size - padding * 2

        paint.color = color
        paint.alpha = 50
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f
        canvas.drawRoundRect(RectF(left, top, right, bottom), cornerRadius, cornerRadius, paint)
        paint.style = Paint.Style.FILL
        paint.alpha = 255
    }

    private fun spawnDropParticles() {
        game.currentPiece?.let { piece ->
            for (block in piece.blocks) {
                val bx = piece.x + block.first
                val by = piece.y + block.second
                if (by >= 0) {
                    repeat(3) {
                        particles.add(Particle(
                            boardOffsetX + bx * cellSize + cellSize / 2,
                            boardOffsetY + by * cellSize + cellSize / 2,
                            piece.color
                        ))
                    }
                }
            }
        }
    }

    private fun spawnClearParticles(linesCleared: Int) {
        for (y in (rows - linesCleared) until rows) {
            for (x in 0 until cols) {
                game.board[y][x]?.let { color ->
                    repeat(2) {
                        particles.add(Particle(
                            boardOffsetX + x * cellSize + cellSize / 2,
                            boardOffsetY + y * cellSize + cellSize / 2,
                            color,
                            speedMultiplier = 2f
                        ))
                    }
                }
            }
        }
    }

    private fun spawnVictoryParticles() {
        repeat(50) {
            particles.add(Particle(
                width / 2f,
                height / 2f,
                listOf(Color.CYAN, Color.MAGENTA, Color.YELLOW, Color.GREEN).random(),
                speedMultiplier = 3f,
                life = 2f
            ))
        }
    }

    private fun updateAndDrawParticles(canvas: Canvas) {
        val iterator = particles.iterator()
        while (iterator.hasNext()) {
            val p = iterator.next()
            p.update()
            if (p.life <= 0) {
                iterator.remove()
                continue
            }
            paint.color = p.color
            paint.alpha = (255 * p.life).toInt()
            canvas.drawCircle(p.x, p.y, p.size * p.life, paint)
        }
        paint.alpha = 255

        if (particles.isNotEmpty()) {
            invalidate()
        }
    }

    private fun triggerLineClearAnim(lines: Int) {
        for (i in 0 until lines) {
            lineClearAnimations.add(LineClearAnim(rows - 1 - i))
        }
        invalidate()
    }

    private fun drawLineClearAnims(canvas: Canvas) {
        val iterator = lineClearAnimations.iterator()
        while (iterator.hasNext()) {
            val anim = iterator.next()
            anim.progress += 0.05f
            if (anim.progress >= 1f) {
                iterator.remove()
                continue
            }

            val flashAlpha = (255 * (1 - anim.progress)).toInt()
            paint.color = Color.argb(flashAlpha, 255, 255, 255)
            val y = boardOffsetY + anim.row * cellSize
            canvas.drawRect(boardOffsetX, y, boardOffsetX + cols * cellSize, y + cellSize, paint)

            repeat(5) {
                val sparkleX = boardOffsetX + Random.nextFloat() * cols * cellSize
                val sparkleY = y + Random.nextFloat() * cellSize
                paint.color = Color.argb(flashAlpha, 255, 255, 200)
                canvas.drawCircle(sparkleX, sparkleY, 3f * (1 - anim.progress), paint)
            }
        }
        if (lineClearAnimations.isNotEmpty()) {
            invalidate()
        }
    }

    private fun lightenColor(color: Int, factor: Float): Int {
        val a = Color.alpha(color)
        val r = min(255, (Color.red(color) * factor).toInt())
        val g = min(255, (Color.green(color) * factor).toInt())
        val b = min(255, (Color.blue(color) * factor).toInt())
        return Color.argb(a, r, g, b)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        return gestureDetector.onTouchEvent(event) || super.onTouchEvent(event)
    }

    private data class Particle(
        var x: Float, var y: Float, val color: Int,
        var vx: Float = Random.nextFloat() * 6f - 3f,
        var vy: Float = Random.nextFloat() * -8f - 2f,
        var life: Float = 1f,
        var size: Float = Random.nextFloat() * 6f + 3f,
        val speedMultiplier: Float = 1f
    ) {
        fun update() {
            x += vx * speedMultiplier
            y += vy * speedMultiplier
            vy += 0.3f
            life -= 0.02f
        }
    }

    private data class LineClearAnim(var row: Int, var progress: Float = 0f)
}