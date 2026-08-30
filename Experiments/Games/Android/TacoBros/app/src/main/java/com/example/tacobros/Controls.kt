package com.example.tacobros

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface

/**
 * On-screen touch controls: left / right pad on the bottom-left, JUMP on the
 * bottom-right. Supports multi-touch (move + jump at the same time).
 */
class Controls(screenW: Float, screenH: Float, tile: Float) {

    enum class Button { LEFT, RIGHT, JUMP, NONE }

    private val size = tile * 1.7f
    private val margin = tile * 0.5f
    private val gap = tile * 0.3f

    val leftRect = RectF(margin, screenH - margin - size, margin + size, screenH - margin)
    val rightRect = RectF(
        leftRect.right + gap, screenH - margin - size,
        leftRect.right + gap + size, screenH - margin
    )
    val jumpRect = RectF(screenW - margin - size, screenH - margin - size, screenW - margin, screenH - margin)

    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        textSize = size * 0.28f
        typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
    }

    fun hit(x: Float, y: Float): Button = when {
        leftRect.contains(x, y) -> Button.LEFT
        rightRect.contains(x, y) -> Button.RIGHT
        jumpRect.contains(x, y) -> Button.JUMP
        else -> Button.NONE
    }

    fun draw(canvas: Canvas, paint: Paint, left: Boolean, right: Boolean, jump: Boolean) {
        drawButton(canvas, paint, leftRect, left)
        drawArrow(canvas, paint, leftRect, pointLeft = true)
        drawButton(canvas, paint, rightRect, right)
        drawArrow(canvas, paint, rightRect, pointLeft = false)
        drawButton(canvas, paint, jumpRect, jump)
        canvas.drawText("JUMP", jumpRect.centerX(), jumpRect.centerY() + labelPaint.textSize * 0.35f, labelPaint)
    }

    private fun drawButton(canvas: Canvas, paint: Paint, r: RectF, pressed: Boolean) {
        val radius = r.width() * 0.25f
        paint.style = Paint.Style.FILL
        paint.color = if (pressed) Color.parseColor("#66FFFFFF") else Color.parseColor("#30FFFFFF")
        canvas.drawRoundRect(r, radius, radius, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = r.width() * 0.04f
        paint.color = Color.parseColor("#88FFFFFF")
        canvas.drawRoundRect(r, radius, radius, paint)
        paint.style = Paint.Style.FILL
    }

    private fun drawArrow(canvas: Canvas, paint: Paint, r: RectF, pointLeft: Boolean) {
        paint.color = Color.WHITE
        val cx = r.centerX()
        val cy = r.centerY()
        val s = r.width() * 0.22f
        val p = Path()
        if (pointLeft) {
            p.moveTo(cx + s, cy - s)
            p.lineTo(cx - s, cy)
            p.lineTo(cx + s, cy + s)
        } else {
            p.moveTo(cx - s, cy - s)
            p.lineTo(cx + s, cy)
            p.lineTo(cx - s, cy + s)
        }
        p.close()
        canvas.drawPath(p, paint)
    }
}
