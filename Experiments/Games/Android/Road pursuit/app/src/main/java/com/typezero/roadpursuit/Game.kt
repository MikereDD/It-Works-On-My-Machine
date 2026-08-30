package com.typezero.roadpursuit

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Road Pursuit — original top-down vehicular-combat game (Spy Hunter genre),
 * rendered in a hand-authored early-'80s pixel-art style. All sprites and the
 * palette are original. Simulation runs in a fixed 420 x 640 logical space.
 */
class Game(context: Context, private val sound: SoundManager) {

    companion object {
        const val W = 420f
        const val H = 640f

        const val START = 0
        const val PLAY = 1
        const val PAUSE = 2
        const val OVER = 3

        // retro palette
        val GRASS1 = 0xFF2E9E3A.toInt()
        val GRASS2 = 0xFF248030.toInt()
        val WATER1 = 0xFF1A56C8.toInt()
        val WATER2 = 0xFF1444A0.toInt()
        val WAVE = 0xFF6FA8FF.toInt()
        val ASPHALT = 0xFF3A3A42.toInt()
        val ASPHALT2 = 0xFF32323A.toInt()
        val LANE = 0xFFF2C400.toInt()
        val SHOULDER_R = 0xFFE0202C.toInt()
        val SHOULDER_W = 0xFFEDEDED.toInt()

        val WHITE = 0xFFEAF6FF.toInt()
        val AMBER = 0xFFFFBE0B.toInt()
        val RED = 0xFFE0202C.toInt()
        val CYAN = 0xFF38E0C8.toInt()
        val INK = 0xFF080810.toInt()

        // ---- sprite grids (12 cols) ----
        // '.' transparent  B body  G glass  S stripe  T tire  A accent(amber)  W foam
        val CAR = arrayOf(
            ".....BB.....",
            "....BBBB....",
            "...BBBBBB...",
            ".T.BBBBBB.T.",
            ".T.BBBBBB.T.",
            "...BBBBBB...",
            "...BSSSSB...",
            "...BGGGGB...",
            "...BGGGGB...",
            "...BBBBBB...",
            "...BBBBBB...",
            "...BGGGGB...",
            "...BSSSSB...",
            ".T.BBBBBB.T.",
            ".T.BBBBBB.T.",
            "...BBBBBB...",
            "....B..B....",
            "....B..B...."
        )
        val BOAT = arrayOf(
            ".....BB.....",
            ".....BB.....",
            "....BBBB....",
            "...BBBBBB...",
            "..BBBBBBBB..",
            "..BBGGGGBB..",
            "..BBGGGGBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "..BBSSSSBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "...BBBBBB...",
            "...BBBBBB...",
            "....BBBB....",
            "....BBBB...."
        )
        val TRUCK = arrayOf(
            "...BBBBBB...",
            "..BBBBBBBB..",
            ".TBBBBBBBBT.",
            ".TBBBBBBBBT.",
            "..BBBBBBBB..",
            "..BGGGGGGB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            "..BBBBBBBB..",
            ".TBBBBBBBBT.",
            ".TBBBBBBBBT.",
            "..BBBBBBBB..",
            "..BAAAAAAB..",
            "..BAAAAAAB..",
            "..BBBBBBBB..",
            ".TBBBBBBBBT."
        )
    }

    var state = START
        private set

    private val prefs = context.getSharedPreferences("road_pursuit", Context.MODE_PRIVATE)

    // ---- core state ----
    private var score = 0
    private var lives = 0
    private var best = prefs.getInt("best", 0)
    private var scroll = 0f
    private var speed = 0f
    private var distance = 0f
    private var stage = 1

    private var roadCenter = W / 2
    private var roadWidth = 250f
    private var targetCenter = W / 2
    private var targetWidth = 250f
    private var roadTimer = 0

    // player
    private var px = W / 2
    private var py = H - 110
    private val pw = 36f
    private val ph = 60f
    private var pvx = 0f
    private var pinv = 0
    private var pspin = 0f

    private val bullets = ArrayList<Bullet>()
    private val enemies = ArrayList<Enemy>()
    private val civilians = ArrayList<Civilian>()
    private val hazards = ArrayList<Hazard>()
    private val drops = ArrayList<Drop>()
    private val pickups = ArrayList<Pickup>()
    private val vans = ArrayList<Van>()
    private val particles = ArrayList<Particle>()
    private val combos = ArrayList<ComboMsg>()

    private var oilAmmo = 3
    private var smokeAmmo = 3
    private var fireCd = 0
    private var oilCd = 0
    private var smokeCd = 0
    private var smokeTimer = 0

    private var spawnTimer = 0
    private var hazardTimer = 0
    private var civTimer = 0
    private var pickupTimer = 0
    private var vanTimer = 0

    private var shake = 0
    private var flash = 0
    private var banner = ""
    private var bannerTimer = 0

    private var water = false
    private var terrainTimer = 0
    private var terrainFlash = 0

    // ---- input ----
    @Volatile var inLeft = false
    @Volatile var inRight = false
    @Volatile var inUp = false
    @Volatile var inDown = false
    @Volatile var inFire = false
    private var reqOil = false
    private var reqSmoke = false

    // paint (anti-alias OFF for crisp pixels)
    private val p = Paint().apply { isAntiAlias = false; isFilterBitmap = false }
    private val mono = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)

    // control rects (logical)
    val rLeft = RectF(12f, 540f, 92f, 620f)
    val rRight = RectF(100f, 540f, 180f, 620f)
    val rUp = RectF(12f, 452f, 92f, 528f)
    val rDown = RectF(100f, 452f, 180f, 528f)
    val rFire = RectF(328f, 540f, 408f, 620f)
    val rOil = RectF(328f, 452f, 408f, 528f)
    val rSmoke = RectF(236f, 540f, 316f, 620f)
    val rPause = RectF(372f, 8f, 412f, 48f)
    val rMute = RectF(324f, 8f, 364f, 48f)

    init { reset() }

    private fun rnd(a: Float, b: Float) = a + Random.nextFloat() * (b - a)
    private fun clamp(v: Float, a: Float, b: Float) = if (v < a) a else if (v > b) b else v

    private fun reset() {
        score = 0; lives = 3; scroll = 0f; speed = 3.4f; distance = 0f; stage = 1
        roadCenter = W / 2; targetCenter = W / 2; roadWidth = 250f; targetWidth = 250f; roadTimer = 0
        px = W / 2; py = H - 110; pvx = 0f; pinv = 120; pspin = 0f
        bullets.clear(); enemies.clear(); civilians.clear(); hazards.clear()
        drops.clear(); pickups.clear(); vans.clear(); particles.clear(); combos.clear()
        oilAmmo = 3; smokeAmmo = 3; fireCd = 0; oilCd = 0; smokeCd = 0; smokeTimer = 0
        spawnTimer = 80; hazardTimer = 140; civTimer = 300; pickupTimer = 520; vanTimer = 900
        shake = 0; flash = 0; banner = ""; bannerTimer = 0
        water = false; terrainTimer = 1400; terrainFlash = 0
    }

    // ---- input from GameView ----
    fun tap(x: Float, y: Float) {
        when (state) {
            START, OVER -> { startGame(); return }
            PAUSE -> { resume(); return }
            else -> {}
        }
        if (rPause.contains(x, y)) { pause(); return }
        if (rMute.contains(x, y)) { sound.muted = !sound.muted; return }
        if (rOil.contains(x, y)) { reqOil = true; return }
        if (rSmoke.contains(x, y)) { reqSmoke = true; return }
    }

    fun setHeld(points: List<Pair<Float, Float>>) {
        inLeft = false; inRight = false; inUp = false; inDown = false; inFire = false
        if (state != PLAY) return
        for ((x, y) in points) {
            if (rLeft.contains(x, y)) inLeft = true
            if (rRight.contains(x, y)) inRight = true
            if (rUp.contains(x, y)) inUp = true
            if (rDown.contains(x, y)) inDown = true
            if (rFire.contains(x, y)) inFire = true
        }
    }

    private fun startGame() { reset(); state = PLAY }
    fun pause() { if (state == PLAY) state = PAUSE }
    fun resume() { if (state == PAUSE) state = PLAY }
    private fun gameOver() {
        state = OVER
        if (score > best) { best = score; prefs.edit().putInt("best", best).apply() }
    }

    private fun boom(x: Float, y: Float, col: Int, n: Int, sp: Float) {
        for (i in 0 until n) {
            val a = Random.nextFloat() * (Math.PI * 2).toFloat()
            val s = rnd(0.5f, sp)
            particles.add(Particle(x, y, cos(a) * s, sin(a) * s, rnd(18f, 38f).toInt(), 38, col, rnd(2f, 4f), false))
        }
    }
    private fun pop(x: Float, y: Float, t: String, col: Int) = combos.add(ComboMsg(x, y, t, col, 50))
    private fun showBanner(t: String) { banner = t; bannerTimer = 110 }

    private fun roadLeft() = roadCenter - roadWidth / 2
    private fun roadRight() = roadCenter + roadWidth / 2

    private fun updateRoad() {
        roadTimer--
        if (roadTimer <= 0) {
            roadTimer = rnd(80f, 180f).toInt()
            targetCenter = clamp(rnd(W * 0.32f, W * 0.68f), roadWidth / 2 + 18, W - roadWidth / 2 - 18)
            targetWidth = rnd(190f, 270f)
        }
        roadCenter += (targetCenter - roadCenter) * 0.018f
        roadWidth += (targetWidth - roadWidth) * 0.02f
        roadCenter = clamp(roadCenter, roadWidth / 2 + 16, W - roadWidth / 2 - 16)

        terrainTimer--
        if (terrainTimer <= 0) {
            water = !water
            terrainTimer = rnd(1200f, 2200f).toInt()
            terrainFlash = 40
            showBanner(if (water) "~ RIVER CROSSING ~" else "= BACK ON ROAD =")
            sound.splash()
        }
        if (terrainFlash > 0) terrainFlash--
    }

    fun update() {
        if (state != PLAY) return

        distance += speed
        speed = clamp(3.4f + distance / 9000f, 3.4f, 9.5f)
        val ns = 1 + (distance / 1800f).toInt()
        if (ns > stage) { stage = ns; showBanner("STAGE $stage"); sound.stage() }

        var mv = speed
        if (inUp) mv = speed * 1.7f
        if (inDown) mv = speed * 0.45f
        scroll += mv
        updateRoad()

        val accel = 0.7f; val maxv = 5.2f
        if (pspin > 0f) {
            pspin += 0.4f; pvx *= 0.9f
            if (pspin > (Math.PI * 2).toFloat()) pspin = 0f
        } else {
            if (inLeft) pvx -= accel
            if (inRight) pvx += accel
            if (!inLeft && !inRight) pvx *= 0.82f
            pvx = clamp(pvx, -maxv, maxv)
        }
        px += pvx
        py += when {
            inUp -> -1.4f
            inDown -> 1.4f
            else -> (H - 110 - py) * 0.04f
        }
        py = clamp(py, H * 0.45f, H - 90)

        if (pinv > 0) pinv--
        if (fireCd > 0) fireCd--
        if (oilCd > 0) oilCd--
        if (smokeCd > 0) smokeCd--
        if (smokeTimer > 0) smokeTimer--

        if (px < roadLeft() + 12 || px > roadRight() - 12) {
            if (pinv <= 0 && pspin <= 0f) hitPlayer()
            px = clamp(px, roadLeft() + 12, roadRight() - 12)
            pvx *= -0.4f
        }

        if (inFire && fireCd <= 0 && pspin <= 0f) {
            bullets.add(Bullet(px - 9, py - ph / 2, -9f))
            bullets.add(Bullet(px + 9, py - ph / 2, -9f))
            fireCd = 7; sound.shoot()
        }
        if (reqOil) { reqOil = false; if (oilAmmo > 0 && oilCd <= 0) { drops.add(Drop(px, py + ph / 2 + 6, 8f, 0f, 220)); oilAmmo--; oilCd = 20 } }
        if (reqSmoke) {
            reqSmoke = false
            if (smokeAmmo > 0 && smokeCd <= 0) {
                smokeTimer = 120; smokeAmmo--; smokeCd = 30
                for (i in 0 until 16) particles.add(Particle(px + rnd(-8f, 8f), py + ph / 2, rnd(-1.5f, 1.5f), rnd(1f, 3f), 60, 60, 0xFFCFD8E0.toInt(), rnd(6f, 12f), true))
            }
        }

        for (b in bullets) b.y += b.vy
        bullets.removeAll { it.y < -20 || it.y > H + 20 }

        spawnTimer--
        if (spawnTimer <= 0) { spawnEnemy(); spawnTimer = max(24f, 72f - distance / 520f - stage * 2f).toInt() }
        for (e in enemies) {
            e.y += (mv - e.vy)
            if (e.boss) { e.vx += if (px > e.x) 0.06f else -0.06f; e.vx = clamp(e.vx, -1.6f, 1.6f) }
            else { if (abs(px - e.x) > 6) e.vx += if (px > e.x) 0.05f else -0.05f; e.vx = clamp(e.vx, -1.4f, 1.4f) }
            e.x = clamp(e.x + e.vx, roadLeft() + 20, roadRight() - 20)
            if (e.spin > 0f) e.spin += 0.5f
            for (d in drops) if (d.grow > 4f && hypot(e.x - d.x, e.y - d.y) < d.r + e.w / 2 && e.spin <= 0f) { e.spin = 0.01f; e.vx = rnd(-3f, 3f) }
            for (b in bullets) if (abs(b.x - e.x) < e.w / 2 && abs(b.y - e.y) < e.h / 2) {
                b.dead = true; e.hp--; boom(b.x, b.y, AMBER, 6, 2.5f)
                if (e.hp <= 0) { e.dead = true; killEnemy(e) }
            }
            if (pinv <= 0 && pspin <= 0f && hit(px, py, pw, ph, e.x, e.y, e.w, e.h)) {
                if (e.boss) hitPlayer()
                else if (inUp) { killEnemy(e); e.dead = true; score += 50; pop(e.x, e.y, "RAM +50", AMBER) }
                else hitPlayer()
            }
        }
        bullets.removeAll { it.dead }
        enemies.removeAll { it.dead || it.y > H + 90 }

        vanTimer--
        if (vanTimer <= 0 && vans.isEmpty()) { vans.add(Van(roadCenter, -90f, 42f, 80f, 1.3f)); vanTimer = rnd(700f, 1100f).toInt() }
        for (v in vans) {
            v.y += (mv - v.vy)
            v.x += (roadCenter - v.x) * 0.02f
            if (!v.used && abs(px - v.x) < (v.w + pw) / 2 - 4 && abs(py - v.y) < (v.h + ph) / 2 - 2 && py > v.y) {
                v.used = true
                oilAmmo = min(oilAmmo + 3, 9); smokeAmmo = min(smokeAmmo + 3, 9)
                pinv = max(pinv, 90); score += 100
                pop(v.x, v.y, "RESUPPLY +100", 0xFF2BD46A.toInt()); boom(v.x, v.y + v.h / 2, 0xFF2BD46A.toInt(), 14, 3f); sound.van()
            }
        }
        vans.removeAll { it.y > H + 100 }

        civTimer--
        if (civTimer <= 0) { civilians.add(Civilian(rnd(roadLeft() + 30, roadRight() - 30), -70f, 34f, 56f, rnd(0.6f, 1.4f))); civTimer = rnd(260f, 460f).toInt() }
        for (c in civilians) {
            c.y += (mv - c.vy)
            c.x = clamp(c.x, roadLeft() + 20, roadRight() - 20)
            for (b in bullets) if (abs(b.x - c.x) < c.w / 2 && abs(b.y - c.y) < c.h / 2) {
                b.dead = true; c.dead = true; boom(c.x, c.y, 0xFFFF3B3B.toInt(), 16, 4f)
                score = max(0, score - 120); pop(c.x, c.y, "CIVILIAN! -120", 0xFFFF3B3B.toInt()); shake = 10; flash = 8; sound.crash()
            }
            if (!c.dead && pinv <= 0 && pspin <= 0f && hit(px, py, pw, ph, c.x, c.y, c.w, c.h) && !inUp) {
                c.dead = true; score = max(0, score - 80); pop(c.x, c.y, "-80", 0xFFFF7B7B.toInt()); shake = 6
            } else if (c.y > H + 40) score += 15
        }
        civilians.removeAll { it.dead || it.y > H + 60 }
        bullets.removeAll { it.dead }

        hazardTimer--
        if (hazardTimer <= 0) { spawnHazard(); hazardTimer = rnd(90f, 200f).toInt() }
        for (h in hazards) {
            h.y += mv
            if (h.type == 0) {
                if (pinv <= 0 && pspin <= 0f && hypot(px - h.x, py - h.y) < h.r + 12) { pspin = 0.01f; pop(px, py - 40, if (water) "WHIRLPOOL!" else "SLIP!", AMBER); sound.slip() }
            } else {
                if (pinv <= 0 && pspin <= 0f && abs(px - h.x) < h.w / 2 + pw / 2 && abs(py - h.y) < h.h / 2 + ph / 2) { hitPlayer(); h.dead = true }
                for (b in bullets) if (abs(b.x - h.x) < h.w / 2 && abs(b.y - h.y) < h.h / 2) { b.dead = true; boom(b.x, b.y, Color.LTGRAY, 5, 2f) }
            }
        }
        hazards.removeAll { it.dead || it.y > H + 60 }
        bullets.removeAll { it.dead }

        for (d in drops) { d.grow = min(d.grow + 0.4f, 1f); d.r = 8f + d.grow * 14f; d.y += mv; d.life-- }
        drops.removeAll { it.y > H + 40 || it.life <= 0 }

        pickupTimer--
        if (pickupTimer <= 0) { spawnPickup(); pickupTimer = rnd(420f, 720f).toInt() }
        for (pk in pickups) {
            pk.y += mv; pk.t += 0.1f
            if (hypot(px - pk.x, py - pk.y) < pk.r + 16) {
                pk.dead = true; sound.pickup()
                when (pk.type) {
                    0 -> { oilAmmo = min(oilAmmo + 2, 9); pop(pk.x, pk.y, "+OIL", AMBER) }
                    1 -> { smokeAmmo = min(smokeAmmo + 2, 9); pop(pk.x, pk.y, "+SMOKE", 0xFFCFD8E0.toInt()) }
                    else -> { pinv = max(pinv, 180); pop(pk.x, pk.y, "SHIELD", CYAN) }
                }
                boom(pk.x, pk.y, CYAN, 10, 3f)
            }
        }
        pickups.removeAll { it.dead || it.y > H + 40 }

        for (pt in particles) { pt.x += pt.vx; pt.y += pt.vy; pt.vy += if (pt.smoke) -0.02f else 0.06f; pt.life--; if (pt.smoke) pt.r += 0.2f }
        particles.removeAll { it.life <= 0 }
        for (m in combos) { m.y -= 0.6f; m.life-- }
        combos.removeAll { it.life <= 0 }

        if (bannerTimer > 0) bannerTimer--
        if (shake > 0) shake--
        if (flash > 0) flash--
        if (distance.toInt() % 6 == 0) score += 1
    }

    private fun spawnEnemy() {
        val x = rnd(roadLeft() + 30, roadRight() - 30)
        val boss = Random.nextFloat() < min(0.06f + stage * 0.02f, 0.22f)
        enemies.add(
            Enemy(
                x, -70f,
                if (boss) 42f else 34f, if (boss) 66f else 56f,
                if (boss) rnd(0.4f, 1f) else rnd(1.2f, 2.4f), 0f,
                if (boss) 2 + stage / 2 else 1, boss
            )
        )
    }
    private fun spawnHazard() {
        val x = rnd(roadLeft() + 24, roadRight() - 24)
        if (Random.nextFloat() < 0.5f) hazards.add(Hazard(0, x, -40f, 0f, 0f, 22f))
        else hazards.add(Hazard(1, x, -40f, rnd(30f, 60f), 16f, 0f))
    }
    private fun spawnPickup() {
        val ty = Random.nextInt(3)
        pickups.add(Pickup(rnd(roadLeft() + 26, roadRight() - 26), -40f, 13f, ty))
    }

    private fun killEnemy(e: Enemy) {
        boom(e.x, e.y, 0xFFFF7B00.toInt(), if (e.boss) 26 else 16, if (e.boss) 5f else 3.5f)
        val pts = if (e.boss) 200 else 75
        score += pts; pop(e.x, e.y, "+$pts", AMBER); shake = min(shake + 4, 8); sound.boom()
    }
    private fun hit(ax: Float, ay: Float, aw: Float, ah: Float, bx: Float, by: Float, bw: Float, bh: Float) =
        abs(ax - bx) < (aw + bw) / 2 - 6 && abs(ay - by) < (ah + bh) / 2 - 6
    private fun hitPlayer() {
        if (pinv > 0 || pspin > 0f) return
        lives--; pinv = 120; shake = 14; flash = 12
        boom(px, py, RED, 22, 5f); pop(px, py - 50, if (lives > 0) "WRECKED!" else "DOWN", RED); sound.crash()
        if (lives <= 0) gameOver()
    }

    // ============ DRAW ============
    fun draw(c: Canvas) {
        val sx = if (shake > 0) rnd(-shake.toFloat(), shake.toFloat()) * 0.6f else 0f
        val sy = if (shake > 0) rnd(-shake.toFloat(), shake.toFloat()) * 0.6f else 0f
        c.save(); c.translate(sx, sy)
        drawWorld(c)

        // oil / whirlpool blobs (pixel clusters)
        for (d in drops) {
            p.color = if (water) 0xCC123A6A.toInt() else 0xE6101018.toInt()
            blob(c, d.x, d.y, d.r)
        }
        // hazards
        for (h in hazards) {
            if (h.type == 0) { p.color = if (water) 0xE6123A6A.toInt() else 0xE60E0E16.toInt(); blob(c, h.x, h.y, h.r) }
            else { var i = 0f; while (i < h.w) { p.color = if ((i / 8f).toInt() % 2 == 0) AMBER else INK; px(c, h.x - h.w / 2 + i, h.y - h.h / 2, 8f, h.h); i += 8f } }
        }
        // pickups (pixel crate)
        for (pk in pickups) {
            val col = when (pk.type) { 0 -> AMBER; 1 -> 0xFFCFD8E0.toInt(); else -> CYAN }
            val s = pk.r + (if ((pk.t * 4).toInt() % 2 == 0) 1f else 0f)
            p.color = INK; px(c, pk.x - s - 1, pk.y - s - 1, (s + 1) * 2, (s + 1) * 2)
            p.color = col; px(c, pk.x - s, pk.y - s, s * 2, s * 2)
            p.color = INK; p.textAlign = Paint.Align.CENTER; p.typeface = mono; p.textSize = 13f
            c.drawText(if (pk.type == 0) "O" else if (pk.type == 1) "S" else "+", pk.x, pk.y + 5, p)
        }

        for (v in vans) drawTruck(c, v.x, v.y, v.w, v.h, 0xFF2BB24A.toInt(), 0xFF06301A.toInt())
        for (cv in civilians) drawVehicle(c, cv.x, cv.y, cv.w, cv.h, 0xFFB9C2CC.toInt(), 0xFF2A3640.toInt(), 0xFFEFF3F7.toInt(), 0f)
        for (e in enemies) {
            val body = if (e.boss) 0xFFFF9000.toInt() else RED
            val stripe = if (e.boss) 0xFFFFE08A.toInt() else 0xFFFFB0B0.toInt()
            drawVehicle(c, e.x, e.y, e.w, e.h, body, 0xFF200006.toInt(), stripe, e.spin)
            if (e.hp > 1) { p.color = WHITE; for (i in 0 until e.hp) px(c, e.x - e.w / 2 + 4 + i * 7, e.y - e.h / 2 - 7, 5f, 3f) }
        }
        // bullets (tracer dots)
        p.color = AMBER
        for (b in bullets) px(c, b.x - 2, b.y - 7, 4f, 11f)

        drawPlayer(c)

        if (smokeTimer > 0) { p.color = Color.argb((min(0.5f, smokeTimer / 180f) * 255).toInt(), 200, 205, 215); c.drawRect(0f, py - 10, W, H, p) }

        for (pt in particles) { p.color = withAlpha(pt.color, max(0f, pt.life.toFloat() / pt.max)); px(c, pt.x - pt.r / 2, pt.y - pt.r / 2, pt.r, pt.r) }

        p.textAlign = Paint.Align.CENTER; p.typeface = mono; p.textSize = 16f
        for (m in combos) { p.color = withAlpha(m.color, min(1f, m.life / 30f)); c.drawText(m.text, m.x, m.y, p) }

        c.restore()

        if (terrainFlash > 0) { p.color = Color.argb((terrainFlash / 40f * 0.25f * 255).toInt(), 120, 200, 255); c.drawRect(0f, 0f, W, H, p) }
        if (flash > 0) { p.color = Color.argb((flash / 12f * 0.35f * 255).toInt(), 224, 32, 44); c.drawRect(0f, 0f, W, H, p) }

        scanlines(c)

        if (bannerTimer > 0) {
            p.color = withAlpha(AMBER, min(1f, bannerTimer / 30f)); p.textAlign = Paint.Align.CENTER; p.typeface = mono; p.textSize = 20f
            c.drawText(banner, W / 2, H / 2 - 40, p)
        }

        drawHUD(c)
        if (state == PLAY) drawControls(c)
        when (state) {
            START -> drawStart(c)
            PAUSE -> drawPanel(c, "PAUSED", "TAP TO RESUME")
            OVER -> drawOver(c)
        }
    }

    private fun drawWorld(c: Canvas) {
        // side terrain: solid + scrolling mown bands
        p.color = if (water) WATER1 else GRASS1
        c.drawRect(0f, 0f, W, H, p)
        p.color = if (water) WATER2 else GRASS2
        var y = -40f
        while (y < H + 40) {
            val yy = ((y + scroll * 0.6f) % 80f) - 40f
            c.drawRect(0f, yy, W, yy + 40f, p)
            y += 80f
        }

        // channel surface
        if (water) {
            p.color = WATER2; c.drawRect(roadLeft(), 0f, roadRight(), H, p)
            p.color = WAVE
            y = -20f
            while (y < H + 20) {
                val yy = ((y + scroll * 1.4f) % 60f) - 20f
                var xx = roadLeft() + 10
                while (xx < roadRight() - 14) { px(c, xx, yy + (if (((xx / 16).toInt()) % 2 == 0) 0f else 4f), 8f, 3f); xx += 22f }
                y += 60f
            }
            // banks
            p.color = SHOULDER_W; px(c, roadLeft() - 3, 0f, 6f, H); px(c, roadRight() - 3, 0f, 6f, H)
        } else {
            // asphalt with scrolling speckle rows
            p.color = ASPHALT; c.drawRect(roadLeft(), 0f, roadRight(), H, p)
            p.color = ASPHALT2
            y = -16f
            while (y < H + 16) { val yy = ((y + scroll) % 32f) - 16f; c.drawRect(roadLeft(), yy, roadRight(), yy + 4f, p); y += 32f }
            // dashed red/white shoulders
            y = -24f
            while (y < H + 24) {
                val yy = ((y + scroll) % 48f) - 24f
                val red = ((yy / 24f).toInt()) % 2 == 0
                p.color = if (red) SHOULDER_R else SHOULDER_W
                px(c, roadLeft() - 3, yy, 6f, 24f); px(c, roadRight() - 3, yy, 6f, 24f)
            }
            // center lane dashes
            p.color = LANE
            y = -40f
            while (y < H + 40) { val yy = ((y + scroll) % 56f) - 40f; px(c, roadCenter - 3, yy, 6f, 28f); y += 56f }
        }
    }

    // generic sprite blitter (each cell = one pixel block)
    private fun drawSprite(c: Canvas, cx: Float, cy: Float, rows: Array<String>, w: Float, h: Float, body: Int, glass: Int, stripe: Int, accent: Int, spinDeg: Float) {
        val cols = rows[0].length
        val pxw = w / cols
        val pxh = h / rows.size
        c.save(); c.translate(cx, cy); if (spinDeg != 0f) c.rotate(spinDeg)
        val left = -w / 2; val top = -h / 2
        for (r in rows.indices) {
            val row = rows[r]
            for (col in 0 until cols) {
                val col2 = when (row[col]) {
                    'B' -> body
                    'G' -> glass
                    'S' -> stripe
                    'A' -> accent
                    'T' -> 0xFF0B0B12.toInt()
                    'W' -> WHITE
                    else -> 0
                }
                if (col2 != 0) { p.color = col2; c.drawRect(left + col * pxw, top + r * pxh, left + (col + 1) * pxw, top + (r + 1) * pxh, p) }
            }
        }
        c.restore()
    }

    private fun drawVehicle(c: Canvas, x: Float, y: Float, w: Float, h: Float, body: Int, glass: Int, stripe: Int, spin: Float) {
        // drop shadow
        p.color = 0x55000000; c.drawRect(x - w / 2 + 3, y - h / 2 + 4, x + w / 2 + 3, y + h / 2 + 4, p)
        if (water) {
            p.color = 0x66B4E1FF; px(c, x - 4, y + h / 2, 8f, rnd(6f, 14f))
            drawSprite(c, x, y, BOAT, w, h, body, glass, stripe, body, if (spin > 0f) Math.toDegrees(spin.toDouble()).toFloat() else 0f)
        } else {
            drawSprite(c, x, y, CAR, w, h, body, glass, stripe, body, if (spin > 0f) Math.toDegrees(spin.toDouble()).toFloat() else 0f)
        }
    }

    private fun drawPlayer(c: Canvas) {
        if (!(pinv > 0 && (pinv / 4) % 2 == 0)) {
            drawVehicle(c, px, py, pw, ph, 0xFF2E78FF.toInt(), 0xFF0A2030.toInt(), WHITE, pspin)
        }
        // exhaust flame
        p.color = withAlpha(AMBER, 0.6f + 0.3f * Random.nextFloat())
        px(c, px - 8, py + ph / 2, 5f, rnd(4f, 9f)); px(c, px + 3, py + ph / 2, 5f, rnd(4f, 9f))
    }

    private fun drawTruck(c: Canvas, x: Float, y: Float, w: Float, h: Float, body: Int, glass: Int) {
        p.color = 0x66000000; c.drawRect(x - w / 2 + 3, y - h / 2 + 4, x + w / 2 + 3, y + h / 2 + 4, p)
        val pulse = 0.55f + 0.4f * sin(scroll * 0.2f)
        drawSprite(c, x, y, TRUCK, w, h, body, glass, body, withAlpha(AMBER, pulse), 0f)
        p.color = 0xFF04240F.toInt(); p.textAlign = Paint.Align.CENTER; p.typeface = mono; p.textSize = 10f
        c.drawText("AMMO", x, y - h / 2 + 18, p)
    }

    private fun scanlines(c: Canvas) {
        p.color = 0x1E000000
        var y = 0f
        while (y < H) { c.drawRect(0f, y, W, y + 1f, p); y += 3f }
    }

    private fun drawHUD(c: Canvas) {
        p.textAlign = Paint.Align.LEFT; p.typeface = mono
        p.color = AMBER; p.textSize = 12f; c.drawText("SCORE", 12f, 26f, p)
        p.color = WHITE; p.textSize = 18f; c.drawText(score.toString().padStart(6, '0'), 12f, 50f, p)
        p.color = LANE; p.textSize = 11f; c.drawText("STAGE $stage", 12f, 70f, p)

        p.textAlign = Paint.Align.RIGHT; p.color = RED; p.textSize = 11f; c.drawText("CARS", W - 12, 24f, p)
        for (i in 0 until lives) { p.color = 0xFF2E78FF.toInt(); px(c, W - 22 - i * 20, 34f, 12f, 18f) }
        if (sound.muted) { p.color = 0xFF9FCFC0.toInt(); p.textAlign = Paint.Align.RIGHT; p.textSize = 10f; c.drawText("MUTED", W - 12, 92f, p) }

        p.textAlign = Paint.Align.LEFT; p.textSize = 11f
        p.color = AMBER; c.drawText("OIL $oilAmmo", 12f, H - 30, p)
        p.color = 0xFFCFD8E0.toInt(); c.drawText("SMK $smokeAmmo", 12f, H - 14, p)
        p.textAlign = Paint.Align.RIGHT; p.color = WHITE
        c.drawText((if (water) "~ " else "") + "DIST " + (distance / 30f).toInt() + "m", W - 12, H - 14, p)
    }

    private fun drawControls(c: Canvas) {
        ctl(c, rLeft, "<", inLeft); ctl(c, rRight, ">", inRight)
        ctl(c, rUp, "GAS", inUp); ctl(c, rDown, "BRK", inDown)
        ctl(c, rFire, "FIRE", inFire); ctl(c, rOil, "OIL", false); ctl(c, rSmoke, "SMK", false)
        ctl(c, rPause, "II", false); ctl(c, rMute, if (sound.muted) "x" else "o", false)
    }
    private fun ctl(c: Canvas, r: RectF, label: String, pressed: Boolean) {
        p.color = if (pressed) 0x552E78FF else 0x33101018
        c.drawRect(r, p)
        p.color = 0xFF2E78FF.toInt()
        c.drawRect(r.left, r.top, r.right, r.top + 2, p)
        c.drawRect(r.left, r.bottom - 2, r.right, r.bottom, p)
        c.drawRect(r.left, r.top, r.left + 2, r.bottom, p)
        c.drawRect(r.right - 2, r.top, r.right, r.bottom, p)
        p.color = WHITE; p.typeface = mono; p.textAlign = Paint.Align.CENTER
        p.textSize = if (label.length > 2) 12f else 18f
        c.drawText(label, r.centerX(), r.centerY() + 6, p)
    }

    private fun drawStart(c: Canvas) {
        scrim(c)
        p.color = AMBER; p.typeface = mono; p.textAlign = Paint.Align.CENTER; p.textSize = 36f
        c.drawText("ROAD", W / 2, 196f, p); c.drawText("PURSUIT", W / 2, 240f, p)
        p.color = RED; p.textSize = 14f; c.drawText("- VEHICULAR COMBAT -", W / 2, 286f, p)
        p.color = WHITE; p.textSize = 13f
        c.drawText("WRECK THE RED BANDITS", W / 2, 356f, p)
        c.drawText("SPARE THE GREY CIVILIANS", W / 2, 380f, p)
        c.drawText("RAM THE AMMO VAN TO RESUPPLY", W / 2, 404f, p)
        c.drawText("WATCH FOR THE RIVER CROSSINGS", W / 2, 428f, p)
        p.color = LANE; p.textSize = 16f; c.drawText("TAP TO START", W / 2, 510f, p)
    }
    private fun drawOver(c: Canvas) {
        scrim(c)
        p.color = RED; p.typeface = mono; p.textAlign = Paint.Align.CENTER; p.textSize = 30f
        c.drawText("GAME OVER", W / 2, 248f, p)
        p.color = WHITE; p.textSize = 20f
        c.drawText("SCORE  $score", W / 2, 318f, p)
        c.drawText("BEST   $best", W / 2, 350f, p)
        c.drawText("STAGE  $stage", W / 2, 382f, p)
        p.color = LANE; p.textSize = 16f; c.drawText("TAP TO PLAY AGAIN", W / 2, 470f, p)
    }
    private fun drawPanel(c: Canvas, title: String, sub: String) {
        scrim(c)
        p.color = AMBER; p.typeface = mono; p.textAlign = Paint.Align.CENTER; p.textSize = 28f
        c.drawText(title, W / 2, H / 2 - 10, p)
        p.color = WHITE; p.textSize = 15f; c.drawText(sub, W / 2, H / 2 + 30, p)
    }
    private fun scrim(c: Canvas) { p.color = 0xD2080810.toInt(); c.drawRect(0f, 0f, W, H, p) }

    // ---- pixel helpers ----
    private fun px(c: Canvas, x: Float, y: Float, w: Float, h: Float) { c.drawRect(x, y, x + w, y + h, p) }
    private fun blob(c: Canvas, cx: Float, cy: Float, r: Float) {
        px(c, cx - r, cy - r * 0.5f, r * 2, r); px(c, cx - r * 0.6f, cy - r, r * 1.2f, r * 2)
    }
    private fun withAlpha(color: Int, a: Float): Int { val aa = (a.coerceIn(0f, 1f) * 255).toInt(); return (color and 0x00FFFFFF) or (aa shl 24) }
}
