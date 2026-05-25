package com.example.tetblockris

import android.graphics.Color

data class TetBlockRisPiece(
    var x: Int,
    var y: Int,
    var blocks: List<Pair<Int, Int>>,
    val color: Int,
    var rotation: Int = 0
) {
    companion object {
        val SHAPES = listOf(
            listOf(
                listOf(Pair(0,0), Pair(1,0), Pair(2,0), Pair(3,0)),
                listOf(Pair(2,0), Pair(2,1), Pair(2,2), Pair(2,3)),
                listOf(Pair(0,2), Pair(1,2), Pair(2,2), Pair(3,2)),
                listOf(Pair(1,0), Pair(1,1), Pair(1,2), Pair(1,3))
            ) to Color.CYAN,

            listOf(
                listOf(Pair(0,0), Pair(1,0), Pair(0,1), Pair(1,1)),
                listOf(Pair(0,0), Pair(1,0), Pair(0,1), Pair(1,1)),
                listOf(Pair(0,0), Pair(1,0), Pair(0,1), Pair(1,1)),
                listOf(Pair(0,0), Pair(1,0), Pair(0,1), Pair(1,1))
            ) to Color.YELLOW,

            listOf(
                listOf(Pair(1,0), Pair(0,1), Pair(1,1), Pair(2,1)),
                listOf(Pair(1,0), Pair(1,1), Pair(2,1), Pair(1,2)),
                listOf(Pair(0,1), Pair(1,1), Pair(2,1), Pair(1,2)),
                listOf(Pair(1,0), Pair(0,1), Pair(1,1), Pair(1,2))
            ) to Color.MAGENTA,

            listOf(
                listOf(Pair(1,0), Pair(2,0), Pair(0,1), Pair(1,1)),
                listOf(Pair(1,0), Pair(1,1), Pair(2,1), Pair(2,2)),
                listOf(Pair(1,1), Pair(2,1), Pair(0,2), Pair(1,2)),
                listOf(Pair(0,0), Pair(0,1), Pair(1,1), Pair(1,2))
            ) to Color.GREEN,

            listOf(
                listOf(Pair(0,0), Pair(1,0), Pair(1,1), Pair(2,1)),
                listOf(Pair(2,0), Pair(1,1), Pair(2,1), Pair(1,2)),
                listOf(Pair(0,1), Pair(1,1), Pair(1,2), Pair(2,2)),
                listOf(Pair(1,0), Pair(0,1), Pair(1,1), Pair(0,2))
            ) to Color.RED,

            listOf(
                listOf(Pair(0,0), Pair(0,1), Pair(1,1), Pair(2,1)),
                listOf(Pair(1,0), Pair(2,0), Pair(1,1), Pair(1,2)),
                listOf(Pair(0,1), Pair(1,1), Pair(2,1), Pair(2,2)),
                listOf(Pair(1,0), Pair(1,1), Pair(0,2), Pair(1,2))
            ) to Color.BLUE,

            listOf(
                listOf(Pair(2,0), Pair(0,1), Pair(1,1), Pair(2,1)),
                listOf(Pair(1,0), Pair(1,1), Pair(1,2), Pair(2,2)),
                listOf(Pair(0,1), Pair(1,1), Pair(2,1), Pair(0,2)),
                listOf(Pair(0,0), Pair(1,0), Pair(1,1), Pair(1,2))
            ) to 0xFFFFA500.toInt()
        )

        fun random(startX: Int, startY: Int): TetBlockRisPiece {
            val (rotations, color) = SHAPES.random()
            return TetBlockRisPiece(startX, startY, rotations[0], color, 0).apply {
                tag = rotations
            }
        }

        fun fromType(rotations: Any?, startX: Int, startY: Int): TetBlockRisPiece {
            val rots = rotations as List<List<Pair<Int, Int>>>
            val color = SHAPES.find { it.first == rots }?.second ?: Color.GRAY
            return TetBlockRisPiece(startX, startY, rots[0], color, 0).apply {
                tag = rots
            }
        }
    }

    var tag: Any? = null

    fun rotated(): TetBlockRisPiece {
        val rotations = tag as List<List<Pair<Int, Int>>>
        val newRotation = (rotation + 1) % 4
        return copy(blocks = rotations[newRotation], rotation = newRotation)
    }
}