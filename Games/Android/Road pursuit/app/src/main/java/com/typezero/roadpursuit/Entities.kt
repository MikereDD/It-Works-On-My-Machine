package com.typezero.roadpursuit

class Bullet(var x: Float, var y: Float, var vy: Float) {
    var dead = false
}

class Enemy(
    var x: Float, var y: Float,
    var w: Float, var h: Float,
    var vy: Float, var vx: Float,
    var hp: Int, var boss: Boolean
) {
    var spin = 0f
    var dead = false
}

class Civilian(var x: Float, var y: Float, var w: Float, var h: Float, var vy: Float) {
    var dead = false
}

/** type: 0 = oil slick / whirlpool, 1 = barrier / buoy */
class Hazard(var type: Int, var x: Float, var y: Float, var w: Float, var h: Float, var r: Float) {
    var dead = false
}

class Drop(var x: Float, var y: Float, var r: Float, var grow: Float, var life: Int)

/** type: 0 = oil, 1 = smoke, 2 = shield */
class Pickup(var x: Float, var y: Float, var r: Float, var type: Int) {
    var t = 0f
    var dead = false
}

class Van(var x: Float, var y: Float, var w: Float, var h: Float, var vy: Float) {
    var used = false
}

class Particle(
    var x: Float, var y: Float,
    var vx: Float, var vy: Float,
    var life: Int, var max: Int,
    var color: Int, var r: Float,
    var smoke: Boolean
)

class ComboMsg(var x: Float, var y: Float, var text: String, var color: Int, var life: Int)
