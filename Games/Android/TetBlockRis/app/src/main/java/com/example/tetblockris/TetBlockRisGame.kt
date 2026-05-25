package com.example.tetblockris

import kotlin.math.min

class TetBlockRisGame(val cols: Int, val rows: Int) {
    val board = Array(rows) { Array<Int?>(cols) { null } }
    var currentPiece: TetBlockRisPiece? = null
    var nextPiece: TetBlockRisPiece? = null
    var holdPiece: TetBlockRisPiece? = null
    var hasHeldThisTurn = false
    var score = 0
        private set
    var linesCleared = 0
        private set
    var level = 1
        private set
    var isVictory = false
        private set

    fun reset() {
        for (y in 0 until rows) {
            for (x in 0 until cols) {
                board[y][x] = null
            }
        }
        score = 0
        linesCleared = 0
        level = 1
        isVictory = false
        holdPiece = null
        hasHeldThisTurn = false
        nextPiece = TetBlockRisPiece.random(cols / 2 - 1, 0)
        spawnPiece()
    }

    fun spawnPiece(): Boolean {
        currentPiece = nextPiece
        nextPiece = TetBlockRisPiece.random(cols / 2 - 1, 0)

        currentPiece?.let {
            if (!isValidPosition(it)) {
                currentPiece = null
                return false
            }
        }
        hasHeldThisTurn = false
        return true
    }

    fun tick(): Int {
        if (isVictory) return -2

        val piece = currentPiece ?: return -1

        if (canMove(piece, 0, 1)) {
            piece.y++
            return 0
        } else {
            lockPiece()
            val lines = clearLines()
            if (!spawnPiece()) return -1
            return lines
        }
    }

    fun holdPiece() {
        if (hasHeldThisTurn || currentPiece == null) return

        val current = currentPiece!!
        val currentType = current.tag

        if (holdPiece == null) {
            holdPiece = TetBlockRisPiece.fromType(currentType, cols / 2 - 1, 0)
            spawnPiece()
        } else {
            val holdType = holdPiece!!.tag
            holdPiece = TetBlockRisPiece.fromType(currentType, cols / 2 - 1, 0)
            currentPiece = TetBlockRisPiece.fromType(holdType, cols / 2 - 1, 0)
        }
        hasHeldThisTurn = true
    }

    fun moveLeft() {
        currentPiece?.let { if (canMove(it, -1, 0)) it.x-- }
    }

    fun moveRight() {
        currentPiece?.let { if (canMove(it, 1, 0)) it.x++ }
    }

    fun rotate() {
        currentPiece?.let { piece ->
            val rotated = piece.rotated()
            if (isValidPosition(rotated)) {
                piece.rotation = (piece.rotation + 1) % 4
                piece.blocks = rotated.blocks
            } else {
                for (offset in listOf(-1, 1, -2, 2)) {
                    val kicked = rotated.copy(x = rotated.x + offset)
                    if (isValidPosition(kicked)) {
                        piece.x += offset
                        piece.rotation = (piece.rotation + 1) % 4
                        piece.blocks = rotated.blocks
                        break
                    }
                }
            }
        }
    }

    fun hardDrop() {
        currentPiece?.let { piece ->
            while (canMove(piece, 0, 1)) {
                piece.y++
                score += 2
            }
        }
    }

    fun getGhostY(): Int {
        val piece = currentPiece ?: return 0
        var ghostY = piece.y
        while (canMoveAt(piece, piece.x, ghostY + 1)) {
            ghostY++
        }
        return ghostY
    }

    private fun canMove(piece: TetBlockRisPiece, dx: Int, dy: Int): Boolean {
        return canMoveAt(piece, piece.x + dx, piece.y + dy)
    }

    private fun canMoveAt(piece: TetBlockRisPiece, newX: Int, newY: Int): Boolean {
        for (block in piece.blocks) {
            val x = newX + block.first
            val y = newY + block.second
            if (x < 0 || x >= cols || y >= rows) return false
            if (y >= 0 && board[y][x] != null) return false
        }
        return true
    }

    private fun isValidPosition(piece: TetBlockRisPiece): Boolean {
        return canMoveAt(piece, piece.x, piece.y)
    }

    private fun lockPiece() {
        currentPiece?.let { piece ->
            for (block in piece.blocks) {
                val x = piece.x + block.first
                val y = piece.y + block.second
                if (y >= 0 && y < rows && x >= 0 && x < cols) {
                    board[y][x] = piece.color
                }
            }
        }
    }

    private fun clearLines(): Int {
        var lines = 0
        var y = rows - 1
        while (y >= 0) {
            if (board[y].all { it != null }) {
                for (moveY in y downTo 1) {
                    board[moveY] = board[moveY - 1].copyOf()
                }
                board[0] = Array(cols) { null }
                lines++
            } else {
                y--
            }
        }

        if (lines > 0) {
            linesCleared += lines
            level = minOf(20, (linesCleared / 10) + 1)

            if (level >= 20 && !isVictory) {
                isVictory = true
            }

            score += when (lines) {
                1 -> 100 * level
                2 -> 300 * level
                3 -> 500 * level
                4 -> 800 * level
                else -> lines * 100 * level
            }
        }
        return lines
    }

    fun getDropSpeed(): Long {
        return when (level) {
            1 -> 500L
            2 -> 450L
            3 -> 400L
            4 -> 350L
            5 -> 300L
            6 -> 250L
            7 -> 200L
            8 -> 150L
            9 -> 100L
            10 -> 80L
            11 -> 70L
            12 -> 60L
            13 -> 50L
            14 -> 45L
            15 -> 40L
            16 -> 35L
            17 -> 30L
            18 -> 25L
            19 -> 20L
            20 -> 15L
            else -> 15L
        }
    }
}