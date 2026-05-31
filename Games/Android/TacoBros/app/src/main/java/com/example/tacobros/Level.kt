package com.example.tacobros

/**
 * Builds the level geometry in world-space pixels from a tile-based layout.
 * Everything is authored in tile units (a tile = one grid square) and scaled
 * by [tile] so the level looks consistent on any screen size.
 *
 * The whole level fits within one screen height, so there is no vertical
 * camera: rows 0 (top) .. 9 (bottom). The ground sits at row 7.
 */
class Level(val tile: Float, screenH: Float) {

    val blocks = ArrayList<Block>()
    val tacos = ArrayList<Taco>()
    val enemies = ArrayList<Enemy>()

    private val groundRow = 7
    val groundTopY = groundRow * tile

    private val widthTiles = 62
    val widthPx = widthTiles * tile

    val startX = 2f * tile
    val startY = groundTopY - tile * 0.95f

    // Goal flag near the end of the final ground segment.
    val goalX = 58f * tile
    val goalTopY = (groundRow - 3) * tile

    init {
        // ---- Ground segments (gaps between them are pits) ----
        addGround(0, 9, screenH)
        addGround(12, 22, screenH)
        addGround(25, 38, screenH)
        addGround(41, 61, screenH)

        // ---- Floating platforms (xTile, row, widthTiles) ----
        addPlatform(5, 5, 3)
        addPlatform(14, 4, 3)
        addPlatform(18, 5, 2)
        addPlatform(28, 4, 4)
        addPlatform(34, 3, 2)
        addPlatform(44, 5, 2)
        addPlatform(48, 4, 3)

        // ---- Tacos ----
        tacoRow(5, 4, 3)
        tacoRow(14, 3, 3)
        tacoAt(10.5f, 6)          // tempting taco over the first pit
        tacoAt(23.5f, 5)          // over the second pit
        tacoRow(28, 3, 4)
        tacoAt(34.5f, 2)          // on the high platform
        tacoAt(39.5f, 5)          // over the third pit
        tacoRow(48, 3, 3)

        // ---- Enemies (xTile, patrolMinTile, patrolMaxTile) ----
        addEnemy(15, 12, 22)
        addEnemy(30, 25, 38)
        addEnemy(45, 41, 56)
    }

    private fun addGround(startTile: Int, endTile: Int, screenH: Float) {
        val x = startTile * tile
        val w = (endTile - startTile + 1) * tile
        // Extend below the screen so the player never sees the bottom edge.
        blocks.add(Block(x, groundTopY, w, screenH - groundTopY + tile))
    }

    private fun addPlatform(xTile: Int, row: Int, wTiles: Int) {
        blocks.add(Block(xTile * tile, row * tile, wTiles * tile, tile * 0.55f))
    }

    private fun tacoAt(xTile: Float, row: Int) {
        tacos.add(Taco(xTile * tile, row * tile, tile * 0.5f))
    }

    private fun tacoRow(startTile: Int, row: Int, count: Int) {
        for (i in 0 until count) tacoAt(startTile + i + 0.25f, row)
    }

    private fun addEnemy(xTile: Int, minTile: Int, maxTile: Int) {
        val size = tile * 0.9f
        enemies.add(
            Enemy(
                x = xTile * tile,
                y = groundTopY - size,
                size = size,
                minX = minTile * tile,
                maxX = (maxTile + 1) * tile,
                speed = tile * 2.2f
            )
        )
    }
}
