package com.example.tacobros

/**
 * Small data holders for the game world. Positions are in world-space pixels.
 * (x, y) is always the top-left corner.
 */

/** The hero. Width/height are derived from the tile size. */
class Player(startX: Float, startY: Float, tile: Float) {
    val w = tile * 0.7f
    val h = tile * 0.9f
    var x = startX
    var y = startY
    var vx = 0f
    var vy = 0f
    var onGround = false
    var facingRight = true
}

/** A solid rectangle the player and enemies collide with (ground & platforms). */
class Block(val x: Float, val y: Float, val w: Float, val h: Float)

/** A collectible taco. */
class Taco(val x: Float, val y: Float, val size: Float) {
    var collected = false
}

/** A patrolling enemy that walks between minX and maxX and reverses at the edges. */
class Enemy(
    var x: Float,
    val y: Float,
    val size: Float,
    private val minX: Float,
    private val maxX: Float,
    speed: Float
) {
    private var vx = -speed
    var alive = true

    fun update(dt: Float) {
        if (!alive) return
        x += vx * dt
        if (x < minX) {
            x = minX
            vx = -vx
        }
        if (x + size > maxX) {
            x = maxX - size
            vx = -vx
        }
    }
}
