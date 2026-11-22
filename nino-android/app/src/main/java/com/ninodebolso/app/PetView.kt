package com.ninodebolso.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.SystemClock
import android.view.View
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Nino, drawn with Canvas: a round yellow sprout with big sparkly eyes, blushing cheeks, little feet
 * and a leaf on its head. The view is 160 x 170 "units"; the body is 100 units wide.
 */
class PetView(ctx: Context) : View(ctx) {

    // --------------------------------------------------------------- state set by the owner
    var face = "feliz"
    var talking = false
    var sleeping = false
    var walking = false
    var facing = 1
    var dragging = false
    var airborne = false
    var paused = false
    var level = 1
    var swing = 0f

    private var tempFace: String? = null
    private var tempUntil = 0L
    private var walkPhase = 0f
    private var squash = 0f
    private var blinkUntil = 0L
    private var nextBlink = 0L
    private var lookX = 0f
    private var lookY = 0f
    private var lookTX = 0f
    private var lookTY = 0f
    private var waveUntil = 0L
    private var eatUntil = 0L
    private var foodT0 = 0L
    private var food: String? = null
    private var nextZ = 0L
    private val t0 = SystemClock.uptimeMillis()
    private var lastFrame = t0

    private class Part(
        val kind: Int, var x: Float, var y: Float, var vx: Float, var vy: Float,
        val born: Long, val life: Long, val size: Float, val text: String = "",
    )
    private val parts = ArrayList<Part>()

    // --------------------------------------------------------------- paints and shapes
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val bodyPath = Path().apply {
        moveTo(0f, -86f)
        cubicTo(38f, -86f, 52f, -56f, 51f, -32f)
        cubicTo(50f, -8f, 30f, 0f, 0f, 0f)
        cubicTo(-30f, 0f, -50f, -8f, -51f, -32f)
        cubicTo(-52f, -56f, -38f, -86f, 0f, -86f)
        close()
    }
    private val bodyShader = RadialGradient(
        -16f, -62f, 80f,
        intArrayOf(0xFFFFEBA6.toInt(), 0xFFFFC845.toInt(), 0xFFF29A2E.toInt()),
        floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP,
    )
    private val leafL = Path().apply {
        moveTo(1f, -13f); cubicTo(-6f, -24f, -19f, -25f, -23f, -17f); cubicTo(-14f, -10f, -5f, -9f, 1f, -13f); close()
    }
    private val leafR = Path().apply {
        moveTo(2f, -15f); cubicTo(8f, -30f, 25f, -31f, 29f, -22f); cubicTo(20f, -12f, 8f, -11f, 2f, -15f); close()
    }
    private val tmp = Path()
    private val rect = RectF()

    private val OUTLINE = 0xE6C9741F.toInt()
    private val FOOT = 0xFFF5A93A.toInt()
    private val INK = 0xFF2B1A12.toInt()
    private val MOUTH_IN = 0xFF8E2F35.toInt()
    private val TONGUE = 0xFFFF8A8A.toInt()
    private val CHEEK = 0xFFFF7D92.toInt()
    private val LEAF = 0xFF4CB774.toInt()
    private val LEAF_DARK = 0xFF2E8C55.toInt()
    private val HEART = 0xFFFF4F7B.toInt()
    private val Z_COLOR = 0xFF6C7BFF.toInt()

    private val frame = object : Runnable {
        override fun run() {
            if (!isAttachedToWindow) return
            if (!paused) invalidate()
            val busy = walking || airborne || dragging || talking || parts.isNotEmpty() || squash > 0.01f ||
                eatUntil > SystemClock.uptimeMillis()
            postOnAnimationDelayed(this, if (paused) 400 else if (busy) 16 else 33)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        removeCallbacks(frame)
        post(frame)
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(frame)
        super.onDetachedFromWindow()
    }

    // --------------------------------------------------------------- API
    fun express(f: String?, ms: Long = 2600) {
        if (f == null) return
        tempFace = f
        tempUntil = SystemClock.uptimeMillis() + ms
    }

    fun currentFace(): String {
        val n = SystemClock.uptimeMillis()
        return when {
            dragging -> "agitado"
            sleeping -> "dormindo"
            eatUntil > n -> "comendo"
            tempFace != null && n < tempUntil -> tempFace!!
            else -> face
        }
    }

    /** Where the eyes look, from -1 to 1 on each axis. */
    fun look(x: Float, y: Float) {
        lookTX = x.coerceIn(-1f, 1f)
        lookTY = y.coerceIn(-1f, 1f)
    }

    fun addWalk(dxPx: Float) {
        val u = width / 160f
        if (u > 0) walkPhase += abs(dxPx) / (9f * u)
    }

    fun land(impact: Float) {
        squash = impact.coerceIn(0.15f, 1f)
        if (impact > 0.25f) dust()
    }

    fun wave() { waveUntil = SystemClock.uptimeMillis() + 1800 }

    fun eat(emoji: String) {
        food = emoji
        foodT0 = SystemClock.uptimeMillis()
        eatUntil = foodT0 + 2100
    }

    fun hearts(n: Int = 4) {
        val now = SystemClock.uptimeMillis()
        repeat(n) { i ->
            parts.add(Part(0, 80f + Random.nextFloat() * 50f - 25f, 60f, Random.nextFloat() * 20f - 10f, -55f - Random.nextFloat() * 25f, now + i * 110L, 1500, 9f + Random.nextFloat() * 5f))
        }
    }

    fun notes() {
        val now = SystemClock.uptimeMillis()
        repeat(2) { i ->
            parts.add(Part(2, 80f + facing * 34f, 70f, facing * 14f, -40f, now + i * 380L, 1700, 13f, if (i % 2 == 0) "♪" else "♫"))
        }
    }

    fun sparkles() {
        val now = SystemClock.uptimeMillis()
        repeat(6) { i ->
            val a = i / 6f * 2 * PI.toFloat()
            parts.add(Part(3, 80f + cos(a) * 40f, 105f + sin(a) * 34f, cos(a) * 24f, sin(a) * 24f - 10f, now + i * 40L, 900, 5f))
        }
    }

    fun sweat() {
        parts.add(Part(4, 80f + 36f, 70f, 6f, 18f, SystemClock.uptimeMillis(), 1300, 4f))
    }

    private fun dust() {
        val now = SystemClock.uptimeMillis()
        repeat(5) { i ->
            val d = if (i % 2 == 0) -1 else 1
            parts.add(Part(5, 80f + d * (20f + i * 4f), 160f, d * (30f + i * 8f), -8f, now, 520, 4f + i))
        }
    }

    // --------------------------------------------------------------- drawing
    override fun onDraw(c: Canvas) {
        val n = SystemClock.uptimeMillis()
        val dt = ((n - lastFrame).coerceIn(0, 100)) / 1000f
        lastFrame = n
        val t = (n - t0) / 1000f
        val u = width / 160f
        if (u <= 0f) return
        val cx = width / 2f
        val gy = height - 7f * u

        if (n > nextBlink) {
            blinkUntil = n + 120
            nextBlink = n + 1800 + Random.nextLong(4200)
        }
        val blink = n < blinkUntil
        val k = min(1f, dt * 8f)
        lookX += (lookTX - lookX) * k
        lookY += (lookTY - lookY) * k
        squash = max(0f, squash - dt * 3.2f)
        val f = currentFace()

        // body motion
        val breath = sin(t * 2.3f)
        var sx = 1f - 0.012f * breath
        var sy = 1f + 0.018f * breath
        var bounce = 0f
        var tilt = 0f
        if (walking) {
            bounce = abs(sin(walkPhase * PI.toFloat())) * 5f * u
            tilt = sin(walkPhase * PI.toFloat()) * 3.5f
        }
        if (f == "animado" && !walking && !airborne) bounce += abs(sin(t * 7f)) * 3f * u
        if (squash > 0f) { sx += 0.30f * squash; sy -= 0.26f * squash }
        if (airborne && !dragging) { sy += 0.07f; sx -= 0.06f }
        if (dragging) { sy += 0.12f; sx -= 0.09f; tilt = swing.coerceIn(-28f, 28f) }
        if (f == "dormindo") { val s = sin(t * 1.4f); sy = 1f + 0.03f * s; sx = 1f - 0.02f * s }

        // shadow
        if (!airborne && !dragging) {
            fill.shader = null
            fill.color = 0x33000000
            rect.set(cx - 40f * u * sx, gy - 5.5f * u, cx + 40f * u * sx, gy + 5.5f * u)
            c.drawOval(rect, fill)
        }

        // feet
        var liftL = 0f
        var liftR = 0f
        var feetDrop = 0f
        if (walking) {
            val s = sin(walkPhase * PI.toFloat())
            liftL = max(0f, s) * 6f
            liftR = max(0f, -s) * 6f
        }
        if (dragging) {
            liftL = (sin(t * 18f) * 0.5f + 0.5f) * 7f
            liftR = (cos(t * 18f) * 0.5f + 0.5f) * 7f
            feetDrop = 6f
        }
        drawFoot(c, cx - 19f * u, gy - (5f + liftL - feetDrop) * u, u)
        drawFoot(c, cx + 19f * u, gy - (5f + liftR - feetDrop) * u, u)

        // everything else in body units: origin at the bottom center of the body
        c.save()
        c.translate(cx, gy - 7f * u - bounce)
        c.rotate(tilt)
        c.scale(sx * u, sy * u)

        drawArms(c, t, f)

        fill.shader = bodyShader
        c.drawPath(bodyPath, fill)
        fill.shader = null
        stroke.color = OUTLINE
        stroke.strokeWidth = 2.4f
        c.drawPath(bodyPath, stroke)

        fill.color = 0x99FFF3C9.toInt()
        rect.set(-31f, -39f, 31f, -5f)
        c.drawOval(rect, fill)

        drawSprout(c, t, f)

        // cheeks
        val blush = when (f) { "carinhoso", "animado", "agitado" -> 220; "triste", "sonolento", "dormindo" -> 90; else -> 150 }
        fill.color = (blush shl 24) or (CHEEK and 0xFFFFFF)
        rect.set(-38f, -45f, -20f, -35f); c.drawOval(rect, fill)
        rect.set(20f, -45f, 38f, -35f); c.drawOval(rect, fill)

        val shift = if (walking) facing * 3f else 0f
        val ex = lookX * 4f + shift
        val ey = lookY * 3f
        drawEyes(c, f, -16f + ex, -50f + ey, 16f + ex, -50f + ey, blink, t)
        drawMouth(c, f, lookX * 2f + shift * 0.7f, -35f + ey * 0.4f, n, t)
        if (f == "dormindo") drawNoseBubble(c, t)
        if (f == "fome" && (n / 1600) % 3 == 0L) {
            fill.color = 0xCC9AD8FF.toInt()
            rect.set(4f, -31f + (n % 1600) / 300f, 7f, -27f + (n % 1600) / 300f)
            c.drawOval(rect, fill)
        }
        c.restore()

        // food flying into the mouth
        val fd = food
        if (fd != null && n < eatUntil) {
            val p = ((n - foodT0) / 600f).coerceIn(0f, 1f)
            if (p < 1f) {
                textPaint.textSize = 20f * u
                textPaint.color = Color.BLACK
                val mouthY = gy - 7f * u - 35f * u * sy
                c.drawText(fd, cx, (6f * u) + (mouthY - 6f * u) * (p * p), textPaint)
            }
        }

        // particles
        if (sleeping && n > nextZ) {
            nextZ = n + 1300
            parts.add(Part(1, 80f + 30f, 58f, 10f, -22f, n, 2400, 11f + Random.nextFloat() * 6f, if (Random.nextBoolean()) "z" else "Z"))
        }
        drawParts(c, n, dt, u)
    }

    private fun drawFoot(c: Canvas, x: Float, y: Float, u: Float) {
        fill.shader = null
        fill.color = FOOT
        rect.set(x - 13f * u, y - 7f * u, x + 13f * u, y + 7f * u)
        c.drawOval(rect, fill)
        stroke.color = OUTLINE
        stroke.strokeWidth = 2.2f * u
        c.drawOval(rect, stroke)
    }

    private fun drawArms(c: Canvas, t: Float, f: String) {
        val n = SystemClock.uptimeMillis()
        var aL = -18f
        var aR = 18f
        var yL = -34f
        var yR = -34f
        when {
            dragging -> { aL = -70f + sin(t * 16f) * 15f; aR = 70f - sin(t * 16f) * 15f; yL = -48f; yR = -48f }
            n < waveUntil -> { aR = -50f + sin(t * 16f) * 28f; yR = -44f }
            f == "animado" -> { aL = -40f + sin(t * 9f) * 12f; aR = 40f - sin(t * 9f) * 12f }
            walking -> { aL = -18f + sin(walkPhase * PI.toFloat()) * 14f; aR = 18f + sin(walkPhase * PI.toFloat()) * 14f }
        }
        drawArm(c, -48f, yL, aL)
        drawArm(c, 48f, yR, aR)
    }

    private fun drawArm(c: Canvas, x: Float, y: Float, angle: Float) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        fill.shader = null
        fill.color = FOOT
        rect.set(-10f, -7.5f, 10f, 7.5f)
        c.drawOval(rect, fill)
        stroke.color = OUTLINE
        stroke.strokeWidth = 2.2f
        c.drawOval(rect, stroke)
        c.restore()
    }

    private fun drawSprout(c: Canvas, t: Float, f: String) {
        c.save()
        c.translate(0f, -84f)
        var rot = sin(t * 1.6f) * 7f
        if (walking) rot -= facing * 8f
        if (dragging) rot = sin(t * 12f) * 18f
        if (f == "dormindo") rot = 18f + sin(t * 0.8f) * 4f
        c.rotate(rot)
        val grow = 1f + min(level - 1, 10) * 0.05f
        c.scale(grow, grow)
        stroke.color = LEAF_DARK
        stroke.strokeWidth = 3.2f
        tmp.reset(); tmp.moveTo(0f, 0f); tmp.quadTo(-1f, -8f, 2f, -15f)
        c.drawPath(tmp, stroke)
        fill.shader = null
        fill.color = LEAF
        c.drawPath(leafL, fill); c.drawPath(leafR, fill)
        stroke.strokeWidth = 1.6f
        c.drawPath(leafL, stroke); c.drawPath(leafR, stroke)
        if (level >= 5) {
            fill.color = 0xFFFF8FB1.toInt()
            for (i in 0 until 5) {
                val a = i / 5f * 2 * PI.toFloat() - PI.toFloat() / 2
                c.drawCircle(3f + cos(a) * 4.6f, -19f + sin(a) * 4.6f, 3.6f, fill)
            }
            fill.color = 0xFFFFE38F.toInt()
            c.drawCircle(3f, -19f, 3f, fill)
        }
        c.restore()
    }

    private fun openEye(c: Canvas, x: Float, y: Float, scale: Float, squeeze: Float, sparkle: Boolean) {
        c.save()
        c.translate(x, y)
        c.scale(scale, scale * squeeze)
        fill.shader = null
        fill.color = INK
        rect.set(-7.8f, -10f, 7.8f, 10f)
        c.drawOval(rect, fill)
        if (squeeze > 0.3f) {
            fill.color = Color.WHITE
            c.drawCircle(2.6f, -3.8f, if (sparkle) 3.8f else 3.2f, fill)
            c.drawCircle(-2.6f, 3.6f, 1.5f, fill)
            if (sparkle) {
                tmp.reset()
                tmp.moveTo(-3.5f, -7.5f); tmp.lineTo(-2.8f, -5.2f); tmp.lineTo(-0.5f, -4.5f); tmp.lineTo(-2.8f, -3.8f)
                tmp.lineTo(-3.5f, -1.5f); tmp.lineTo(-4.2f, -3.8f); tmp.lineTo(-6.5f, -4.5f); tmp.lineTo(-4.2f, -5.2f); tmp.close()
                c.drawPath(tmp, fill)
            }
        }
        c.restore()
    }

    private fun arcEye(c: Canvas, x: Float, y: Float, up: Boolean) {
        stroke.color = INK
        stroke.strokeWidth = 3.3f
        tmp.reset()
        if (up) { tmp.moveTo(x - 7f, y + 2f); tmp.quadTo(x, y - 8f, x + 7f, y + 2f) }
        else { tmp.moveTo(x - 7f, y - 1f); tmp.quadTo(x, y + 6f, x + 7f, y - 1f) }
        c.drawPath(tmp, stroke)
    }

    private fun heartEye(c: Canvas, x: Float, y: Float, s: Float) {
        tmp.reset()
        tmp.moveTo(x, y + 8f * s)
        tmp.cubicTo(x - 11f * s, y + 1f * s, x - 9f * s, y - 9f * s, x - 4.5f * s, y - 8.5f * s)
        tmp.cubicTo(x - 1.8f * s, y - 8.2f * s, x, y - 6f * s, x, y - 4f * s)
        tmp.cubicTo(x, y - 6f * s, x + 1.8f * s, y - 8.2f * s, x + 4.5f * s, y - 8.5f * s)
        tmp.cubicTo(x + 9f * s, y - 9f * s, x + 11f * s, y + 1f * s, x, y + 8f * s)
        tmp.close()
        fill.shader = null
        fill.color = HEART
        c.drawPath(tmp, fill)
        fill.color = Color.WHITE
        c.drawCircle(x - 3.6f * s, y - 4.6f * s, 1.6f * s, fill)
    }

    private fun chevronEye(c: Canvas, x: Float, y: Float, right: Boolean) {
        stroke.color = INK
        stroke.strokeWidth = 3.3f
        tmp.reset()
        if (right) { tmp.moveTo(x - 6f, y - 6f); tmp.lineTo(x + 5f, y); tmp.lineTo(x - 6f, y + 6f) }
        else { tmp.moveTo(x + 6f, y - 6f); tmp.lineTo(x - 5f, y); tmp.lineTo(x + 6f, y + 6f) }
        c.drawPath(tmp, stroke)
    }

    private fun drawEyes(c: Canvas, f: String, lx: Float, ly: Float, rx: Float, ry: Float, blink: Boolean, t: Float) {
        val squeeze = if (blink) 0.08f else 1f
        when (f) {
            "animado" -> { openEye(c, lx, ly, 1.08f, squeeze, true); openEye(c, rx, ry, 1.08f, squeeze, true) }
            "comendo" -> { arcEye(c, lx, ly, true); arcEye(c, rx, ry, true) }
            "carinhoso" -> { val s = 1f + sin(t * 6f) * 0.06f; heartEye(c, lx, ly, s); heartEye(c, rx, ry, s) }
            "dormindo" -> { arcEye(c, lx, ly, false); arcEye(c, rx, ry, false) }
            "brincalhao" -> { openEye(c, lx, ly, 1f, squeeze, true); arcEye(c, rx, ry, true) }
            "agitado" -> { chevronEye(c, lx, ly, true); chevronEye(c, rx, ry, false) }
            "sonolento" -> { openEye(c, lx, ly + 2f, 1f, if (blink) 0.08f else 0.42f, false); openEye(c, rx, ry + 2f, 1f, if (blink) 0.08f else 0.42f, false) }
            "surpreso" -> { openEye(c, lx, ly, 1.2f, squeeze, false); openEye(c, rx, ry, 1.2f, squeeze, false) }
            "pensativo" -> {
                openEye(c, lx - 2f, ly - 2.5f, 1f, squeeze, false); openEye(c, rx - 2f, ry - 2.5f, 1f, squeeze, false)
                stroke.color = INK; stroke.strokeWidth = 2.6f
                tmp.reset(); tmp.moveTo(9f, -65f); tmp.quadTo(16f, -71f, 24f, -66f); c.drawPath(tmp, stroke)
            }
            "triste", "fome" -> {
                openEye(c, lx, ly + 1f, 0.95f, squeeze, true); openEye(c, rx, ry + 1f, 0.95f, squeeze, true)
                stroke.color = INK; stroke.strokeWidth = 2.6f
                tmp.reset(); tmp.moveTo(-24f, -62f); tmp.lineTo(-10f, -66f); c.drawPath(tmp, stroke)
                tmp.reset(); tmp.moveTo(10f, -66f); tmp.lineTo(24f, -62f); c.drawPath(tmp, stroke)
            }
            else -> { openEye(c, lx, ly, 1f, squeeze, false); openEye(c, rx, ry, 1f, squeeze, false) }
        }
    }

    private fun drawMouth(c: Canvas, f: String, mx: Float, my: Float, n: Long, t: Float) {
        val shape = when {
            f == "dormindo" -> "small"
            f == "comendo" -> if ((n / 150) % 2 == 0L) "chompA" else "chompB"
            f == "agitado" -> if ((n / 200) % 2 == 0L) "o" else "talkA"
            talking -> if ((n / 120) % 2 == 0L) "talkA" else "talkB"
            else -> when (f) {
                "animado", "brincalhao" -> "grin"
                "carinhoso" -> "smile"
                "pensativo" -> "flat"
                "triste" -> "sad"
                "surpreso" -> "o"
                "sonolento" -> "small"
                "fome" -> "wavy"
                else -> "omega"
            }
        }
        stroke.color = INK
        stroke.strokeWidth = 2.5f
        fill.shader = null
        tmp.reset()
        when (shape) {
            "omega" -> {
                tmp.moveTo(mx - 6.5f, my - 1f); tmp.quadTo(mx - 3.2f, my + 4f, mx, my - 0.2f); tmp.quadTo(mx + 3.2f, my + 4f, mx + 6.5f, my - 1f)
                c.drawPath(tmp, stroke)
            }
            "smile" -> { tmp.moveTo(mx - 6f, my - 1f); tmp.quadTo(mx, my + 6f, mx + 6f, my - 1f); c.drawPath(tmp, stroke) }
            "small" -> { tmp.moveTo(mx - 3f, my + 1f); tmp.quadTo(mx, my + 2.8f, mx + 3f, my + 1f); c.drawPath(tmp, stroke) }
            "flat" -> { tmp.moveTo(mx - 4f, my + 1.5f); tmp.quadTo(mx + 1f, my + 0.5f, mx + 4.5f, my + 2f); c.drawPath(tmp, stroke) }
            "sad" -> { tmp.moveTo(mx - 5.5f, my + 3.5f); tmp.quadTo(mx, my - 2.5f, mx + 5.5f, my + 3.5f); c.drawPath(tmp, stroke) }
            "wavy" -> {
                tmp.moveTo(mx - 7f, my + 1f); tmp.quadTo(mx - 3.5f, my - 2.5f, mx, my + 1f); tmp.quadTo(mx + 3.5f, my + 4.5f, mx + 7f, my + 1f)
                c.drawPath(tmp, stroke)
            }
            "o" -> {
                rect.set(mx - 3.6f, my - 1.5f, mx + 3.6f, my + 6f)
                fill.color = MOUTH_IN; c.drawOval(rect, fill); c.drawOval(rect, stroke)
            }
            "chompB" -> { tmp.moveTo(mx - 6f, my + 1f); tmp.lineTo(mx + 6f, my + 1f); c.drawPath(tmp, stroke) }
            else -> {
                val (w, d) = when (shape) { "grin" -> 7.5f to 11f; "chompA" -> 8f to 12f; "talkA" -> 6f to 9f; else -> 4.5f to 5f }
                tmp.moveTo(mx - w, my - 2f); tmp.quadTo(mx, my + d, mx + w, my - 2f); tmp.quadTo(mx, my + 1f, mx - w, my - 2f); tmp.close()
                fill.color = MOUTH_IN; c.drawPath(tmp, fill)
                if (d >= 9f) {
                    fill.color = TONGUE
                    rect.set(mx - 3.2f, my + d * 0.32f, mx + 3.2f, my + d * 0.32f + 3.6f)
                    c.drawOval(rect, fill)
                }
                c.drawPath(tmp, stroke)
            }
        }
    }

    private fun drawNoseBubble(c: Canvas, t: Float) {
        val r = 2f + 4.5f * (0.5f + 0.5f * sin(t * 1.3f))
        fill.shader = null
        fill.color = 0x66BFE6FF
        c.drawCircle(9f + r * 0.6f, -41f, r, fill)
        stroke.color = 0xAA7FB8E0.toInt()
        stroke.strokeWidth = 1f
        c.drawCircle(9f + r * 0.6f, -41f, r, stroke)
        fill.color = 0xCCFFFFFF.toInt()
        c.drawCircle(9f + r * 0.6f - r * 0.35f, -41f - r * 0.35f, r * 0.22f, fill)
    }

    private fun drawParts(c: Canvas, n: Long, dt: Float, u: Float) {
        val it = parts.iterator()
        while (it.hasNext()) {
            val p = it.next()
            if (n < p.born) continue
            val age = (n - p.born).toFloat() / p.life
            if (age >= 1f) { it.remove(); continue }
            p.x += p.vx * dt
            p.y += p.vy * dt
            val alpha = ((if (age < 0.15f) age / 0.15f else 1f - (age - 0.15f) / 0.85f) * 255).toInt().coerceIn(0, 255)
            val x = p.x * u
            val y = p.y * u
            when (p.kind) {
                0 -> {
                    val s = p.size * u / 10f * (0.7f + age * 0.5f)
                    tmp.reset()
                    tmp.moveTo(x, y + 8f * s)
                    tmp.cubicTo(x - 11f * s, y + 1f * s, x - 9f * s, y - 9f * s, x - 4.5f * s, y - 8.5f * s)
                    tmp.cubicTo(x - 1.8f * s, y - 8.2f * s, x, y - 6f * s, x, y - 4f * s)
                    tmp.cubicTo(x, y - 6f * s, x + 1.8f * s, y - 8.2f * s, x + 4.5f * s, y - 8.5f * s)
                    tmp.cubicTo(x + 9f * s, y - 9f * s, x + 11f * s, y + 1f * s, x, y + 8f * s)
                    fill.shader = null
                    fill.color = (alpha shl 24) or (HEART and 0xFFFFFF)
                    c.drawPath(tmp, fill)
                }
                1, 2 -> {
                    textPaint.textSize = p.size * u
                    textPaint.color = (alpha shl 24) or ((if (p.kind == 1) Z_COLOR else 0xFF3446D1.toInt()) and 0xFFFFFF)
                    c.drawText(p.text, x, y, textPaint)
                }
                3 -> {
                    fill.shader = null
                    fill.color = (alpha shl 24) or 0xFFD54F
                    val s = p.size * u
                    tmp.reset()
                    tmp.moveTo(x, y - s); tmp.lineTo(x + s * 0.3f, y - s * 0.3f); tmp.lineTo(x + s, y); tmp.lineTo(x + s * 0.3f, y + s * 0.3f)
                    tmp.lineTo(x, y + s); tmp.lineTo(x - s * 0.3f, y + s * 0.3f); tmp.lineTo(x - s, y); tmp.lineTo(x - s * 0.3f, y - s * 0.3f); tmp.close()
                    c.drawPath(tmp, fill)
                }
                4 -> {
                    fill.shader = null
                    fill.color = (alpha shl 24) or 0x7FC8FF
                    val s = p.size * u
                    tmp.reset(); tmp.moveTo(x, y - s * 1.6f); tmp.quadTo(x + s, y, x, y + s); tmp.quadTo(x - s, y, x, y - s * 1.6f); tmp.close()
                    c.drawPath(tmp, fill)
                }
                5 -> {
                    fill.shader = null
                    fill.color = ((alpha * 0.55f).toInt() shl 24) or 0xE8E2D8
                    c.drawCircle(x, y, p.size * u * (0.6f + age), fill)
                }
            }
        }
    }
}
