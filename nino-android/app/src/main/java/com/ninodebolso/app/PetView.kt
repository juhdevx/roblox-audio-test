package com.ninodebolso.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
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
 * Nino, drawn with Canvas. It can be a round sprout, a baby or a little human, with hair, hats,
 * glasses and extras. The view is 160 x 170 "units"; drawings use units with the origin at the
 * bottom center of the body.
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
    var look: Look = Look()
        set(v) { field = v; shaders.clear() }

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

    /** Where the face and limbs sit for each kind of pet. */
    private class Geo(
        val eyeY: Float, val eyeDX: Float, val eyeScale: Float, val mouthY: Float,
        val cheekY: Float, val cheekDX: Float, val armX: Float, val armY: Float,
        val footDX: Float, val headX: Float, val headY: Float, val headRX: Float, val headRY: Float,
    )
    private val geoBroto = Geo(-50f, 16f, 1f, -35f, -40f, 29f, 48f, -34f, 19f, 0f, -43f, 51f, 43f)
    private val geoHumano = Geo(-68f, 13f, 0.82f, -56f, -59f, 22f, 27f, -38f, 12f, 0f, -70f, 34f, 31f)
    private val geoBebe = Geo(-58f, 14f, 0.92f, -46f, -49f, 24f, 24f, -31f, 12f, 0f, -60f, 37f, 33f)
    private fun geo() = when (look.species) { "humano" -> geoHumano; "bebe" -> geoBebe; else -> geoBroto }

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
    private val torsoPath = Path().apply {
        moveTo(-16f, -44f); lineTo(16f, -44f); quadTo(23f, -42f, 23f, -32f); lineTo(24f, -14f)
        quadTo(24f, -8f, 18f, -8f); lineTo(-18f, -8f); quadTo(-24f, -8f, -24f, -14f); lineTo(-23f, -32f)
        quadTo(-23f, -42f, -16f, -44f); close()
    }
    private val onesiePath = Path().apply {
        moveTo(-15f, -36f); quadTo(0f, -40f, 15f, -36f); quadTo(27f, -30f, 26f, -15f)
        quadTo(25f, -2f, 0f, -2f); quadTo(-25f, -2f, -26f, -15f); quadTo(-27f, -30f, -15f, -36f); close()
    }
    private val leafL = Path().apply {
        moveTo(1f, -13f); cubicTo(-6f, -24f, -19f, -25f, -23f, -17f); cubicTo(-14f, -10f, -5f, -9f, 1f, -13f); close()
    }
    private val leafR = Path().apply {
        moveTo(2f, -15f); cubicTo(8f, -30f, 25f, -31f, 29f, -22f); cubicTo(20f, -12f, 8f, -11f, 2f, -15f); close()
    }
    private val tmp = Path()
    private val tmp2 = Path()
    private val rect = RectF()
    private val shaders = HashMap<String, Shader>()

    private val INK = 0xFF2B1A12.toInt()
    private val MOUTH_IN = 0xFF8E2F35.toInt()
    private val TONGUE = 0xFFFF8A8A.toInt()
    private val CHEEK = 0xFFFF7D92.toInt()
    private val LEAF = 0xFF4CB774.toInt()
    private val LEAF_DARK = 0xFF2E8C55.toInt()
    private val HEART = 0xFFFF4F7B.toInt()
    private val Z_COLOR = 0xFF6C7BFF.toInt()
    private val GOLD = 0xFFFFD23F.toInt()
    private val GOLD_LINE = 0xFFC99A12.toInt()

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
            parts.add(Part(0, 80f + Random.nextFloat() * 50f - 25f, 52f, Random.nextFloat() * 20f - 10f, -55f - Random.nextFloat() * 25f, now + i * 110L, 1500, 9f + Random.nextFloat() * 5f))
        }
    }

    fun notes() {
        val now = SystemClock.uptimeMillis()
        repeat(2) { i ->
            parts.add(Part(2, 80f + facing * 34f, 66f, facing * 14f, -40f, now + i * 380L, 1700, 13f, if (i % 2 == 0) "♪" else "♫"))
        }
    }

    fun sparkles() {
        val now = SystemClock.uptimeMillis()
        repeat(6) { i ->
            val a = i / 6f * 2 * PI.toFloat()
            parts.add(Part(3, 80f + cos(a) * 42f, 100f + sin(a) * 40f, cos(a) * 24f, sin(a) * 24f - 10f, now + i * 40L, 900, 5f))
        }
    }

    fun sweat() {
        parts.add(Part(4, 80f + 36f, 66f, 6f, 18f, SystemClock.uptimeMillis(), 1300, 4f))
    }

    private fun dust() {
        val now = SystemClock.uptimeMillis()
        repeat(5) { i ->
            val d = if (i % 2 == 0) -1 else 1
            parts.add(Part(5, 80f + d * (20f + i * 4f), 160f, d * (30f + i * 8f), -8f, now, 520, 4f + i))
        }
    }

    private fun gradient(key: String, make: () -> Shader): Shader = shaders.getOrPut(key, make)

    private fun radial(t: Tone, cx: Float, cy: Float, r: Float) =
        gradient("r${t.base}_${cx}_$cy") {
            RadialGradient(cx, cy, r, intArrayOf(t.hi, t.base, t.shade), floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP)
        }

    private fun linear(t: Tone, top: Float, bottom: Float) =
        gradient("l${t.base}_$top") { LinearGradient(0f, top, 0f, bottom, t.hi, t.shade, Shader.TileMode.CLAMP) }

    private fun blend(a: Int, b: Int, f: Float): Int {
        fun ch(s: Int) = (((a shr s) and 255) * (1 - f) + ((b shr s) and 255) * f).toInt() shl s
        return (0xFF shl 24) or ch(16) or ch(8) or ch(0)
    }

    private fun shape(c: Canvas, p: Path, color: Int, line: Int, width: Float = 2.2f, shader: Shader? = null) {
        fill.shader = shader
        fill.color = color
        c.drawPath(p, fill)
        fill.shader = null
        stroke.color = line
        stroke.strokeWidth = width
        c.drawPath(p, stroke)
    }

    private fun oval(c: Canvas, l: Float, t: Float, r: Float, b: Float, color: Int, line: Int, width: Float = 2.2f, shader: Shader? = null) {
        rect.set(l, t, r, b)
        fill.shader = shader
        fill.color = color
        c.drawOval(rect, fill)
        fill.shader = null
        if (width > 0f) {
            stroke.color = line
            stroke.strokeWidth = width
            c.drawOval(rect, stroke)
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
        val g = geo()
        val sp = look.species
        val skin = look.body()
        val cloth = look.outfitTone()

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
            rect.set(cx - 38f * u * sx, gy - 5.5f * u, cx + 38f * u * sx, gy + 5.5f * u)
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
        val (footFill, footLine) = when (sp) {
            "humano" -> 0xFF3B3B4F.toInt() to 0xFF1E1E2A.toInt()
            "bebe" -> cloth.base to cloth.line
            else -> blend(skin.base, skin.shade, 0.5f) to skin.line
        }
        val fw = if (sp == "broto") 13f else 10.5f
        drawFoot(c, cx - g.footDX * u, gy - (5f + liftL - feetDrop) * u, u, fw, footFill, footLine)
        drawFoot(c, cx + g.footDX * u, gy - (5f + liftR - feetDrop) * u, u, fw, footFill, footLine)

        // everything else in body units: origin at the bottom center of the body
        c.save()
        c.translate(cx, gy - 7f * u - bounce)
        c.rotate(tilt)
        c.scale(sx * u, sy * u)

        val shift = if (walking) facing * 3f else 0f
        val ex = lookX * 4f + shift
        val ey = lookY * 3f

        when (sp) {
            "humano" -> drawHuman(c, t, f, skin, cloth)
            "bebe" -> drawBaby(c, t, f, skin, cloth)
            else -> drawSprout(c, t, f, skin)
        }

        // cheeks
        val blush = when (f) { "carinhoso", "animado", "agitado" -> 220; "triste", "sonolento", "dormindo" -> 90; else -> 150 }
        fill.shader = null
        fill.color = (blush shl 24) or (CHEEK and 0xFFFFFF)
        val cw = if (sp == "broto") 9f else 7f
        rect.set(-g.cheekDX - cw, g.cheekY - 5f, -g.cheekDX + cw, g.cheekY + 5f); c.drawOval(rect, fill)
        rect.set(g.cheekDX - cw, g.cheekY - 5f, g.cheekDX + cw, g.cheekY + 5f); c.drawOval(rect, fill)

        drawEyes(c, f, g, -g.eyeDX + ex, g.eyeY + ey, g.eyeDX + ex, g.eyeY + ey, blink, t)
        val mx = lookX * 2f + shift * 0.7f
        val my = g.mouthY + ey * 0.4f
        val pacifier = look.extra == "chupeta" && !talking && f != "comendo" && f != "agitado"
        if (pacifier) drawPacifier(c, mx, my) else drawMouth(c, f, mx, my, n)
        drawGlasses(c, g, -g.eyeDX + ex, g.eyeY + ey, g.eyeDX + ex, g.eyeY + ey)
        if (f == "dormindo" && !pacifier) drawNoseBubble(c, g.eyeDX * 0.6f, g.mouthY - 6f, t)
        if (f == "fome" && (n / 1600) % 3 == 0L) {
            fill.color = 0xCC9AD8FF.toInt()
            rect.set(mx + 4f, my + 4f + (n % 1600) / 300f, mx + 7f, my + 8f + (n % 1600) / 300f)
            c.drawOval(rect, fill)
        }
        drawHat(c, g)
        c.restore()

        // food flying into the mouth
        val fd = food
        if (fd != null && n < eatUntil) {
            val p = ((n - foodT0) / 600f).coerceIn(0f, 1f)
            if (p < 1f) {
                textPaint.textSize = 20f * u
                textPaint.color = Color.BLACK
                val mouthY = gy - 7f * u + g.mouthY * u * sy
                c.drawText(fd, cx, (6f * u) + (mouthY - 6f * u) * (p * p), textPaint)
            }
        }

        if (sleeping && n > nextZ) {
            nextZ = n + 1300
            parts.add(Part(1, 80f + 30f, 54f, 10f, -22f, n, 2400, 11f + Random.nextFloat() * 6f, if (Random.nextBoolean()) "z" else "Z"))
        }
        drawParts(c, n, dt, u)
    }

    private fun drawFoot(c: Canvas, x: Float, y: Float, u: Float, w: Float, color: Int, line: Int) {
        rect.set(x - w * u, y - 6.5f * u, x + w * u, y + 6.5f * u)
        fill.shader = null
        fill.color = color
        c.drawOval(rect, fill)
        stroke.color = line
        stroke.strokeWidth = 2.2f * u
        c.drawOval(rect, stroke)
    }

    // ----- the sprout
    private fun drawSprout(c: Canvas, t: Float, f: String, skin: Tone) {
        val limb = blend(skin.base, skin.shade, 0.5f)
        val (aL, aR, yL, yR) = nubAngles(t, f)
        drawNub(c, -48f, yL, aL, limb, skin.line)
        drawNub(c, 48f, yR, aR, limb, skin.line)
        shape(c, bodyPath, skin.base, skin.line, 2.4f, radial(skin, -16f, -62f, 80f))
        fill.color = (0x99 shl 24) or (blend(skin.hi, Color.WHITE, 0.4f) and 0xFFFFFF)
        rect.set(-31f, -39f, 31f, -5f)
        c.drawOval(rect, fill)
        if (look.hat == "nenhum" || look.hat == "laco") drawLeaf(c, t, f, 0f, -84f)
        else drawLeaf(c, t, f, 0f, -80f)
        drawExtras(c, -24f, 44f)
    }

    private data class Four(val a: Float, val b: Float, val c: Float, val d: Float)

    private fun nubAngles(t: Float, f: String): Four {
        val n = SystemClock.uptimeMillis()
        return when {
            dragging -> Four(-70f + sin(t * 16f) * 15f, 70f - sin(t * 16f) * 15f, -48f, -48f)
            n < waveUntil -> Four(-18f, -50f + sin(t * 16f) * 28f, -34f, -44f)
            f == "animado" -> Four(-40f + sin(t * 9f) * 12f, 40f - sin(t * 9f) * 12f, -34f, -34f)
            walking -> Four(-18f + sin(walkPhase * PI.toFloat()) * 14f, 18f + sin(walkPhase * PI.toFloat()) * 14f, -34f, -34f)
            else -> Four(-18f, 18f, -34f, -34f)
        }
    }

    private fun drawNub(c: Canvas, x: Float, y: Float, angle: Float, color: Int, line: Int) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        oval(c, -10f, -7.5f, 10f, 7.5f, color, line)
        c.restore()
    }

    private fun drawLeaf(c: Canvas, t: Float, f: String, x: Float, y: Float) {
        c.save()
        c.translate(x, y)
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
        shape(c, leafL, LEAF, LEAF_DARK, 1.6f)
        shape(c, leafR, LEAF, LEAF_DARK, 1.6f)
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

    // ----- arms with a sleeve and a hand, for the baby and the human
    private fun armAngles(t: Float, f: String): Pair<Float, Float> {
        val n = SystemClock.uptimeMillis()
        return when {
            dragging -> (160f + sin(t * 16f) * 12f) to (-160f - sin(t * 16f) * 12f)
            n < waveUntil -> 14f to (-150f + sin(t * 16f) * 22f)
            f == "animado" -> (40f + sin(t * 9f) * 14f) to (-40f - sin(t * 9f) * 14f)
            walking -> (12f + sin(walkPhase * PI.toFloat()) * 22f) to (-12f + sin(walkPhase * PI.toFloat()) * 22f)
            else -> 12f to -12f
        }
    }

    private fun drawArm(c: Canvas, x: Float, y: Float, angle: Float, len: Float, skin: Tone, cloth: Tone) {
        c.save()
        c.translate(x, y)
        c.rotate(angle)
        rect.set(-5.5f, -3f, 5.5f, len)
        fill.shader = null
        fill.color = cloth.base
        c.drawRoundRect(rect, 5f, 5f, fill)
        stroke.color = cloth.line
        stroke.strokeWidth = 2f
        c.drawRoundRect(rect, 5f, 5f, stroke)
        oval(c, -5.2f, len - 2f, 5.2f, len + 8.4f, skin.base, skin.line, 2f)
        c.restore()
    }

    private fun drawHead(c: Canvas, g: Geo, skin: Tone) {
        // ears
        oval(c, -g.headRX - 5f, g.headY - 8f, -g.headRX + 7f, g.headY + 7f, skin.base, skin.line)
        oval(c, g.headRX - 7f, g.headY - 8f, g.headRX + 5f, g.headY + 7f, skin.base, skin.line)
        oval(c, -g.headRX, g.headY - g.headRY, g.headRX, g.headY + g.headRY, skin.base, skin.line, 2.4f,
            radial(skin, g.headX - 10f, g.headY - 14f, g.headRX * 1.5f))
    }

    private fun drawHuman(c: Canvas, t: Float, f: String, skin: Tone, cloth: Tone) {
        val g = geoHumano
        // legs
        fill.shader = null
        fill.color = cloth.shade
        rect.set(-14f, -14f, -4f, 2f); c.drawRoundRect(rect, 4f, 4f, fill)
        rect.set(4f, -14f, 14f, 2f); c.drawRoundRect(rect, 4f, 4f, fill)
        drawHair(c, g, back = true)
        shape(c, torsoPath, cloth.base, cloth.line, 2.2f, linear(cloth, -44f, -8f))
        val (aL, aR) = armAngles(t, f)
        drawArm(c, -21f, g.armY, aL, 15f, skin, cloth)
        drawArm(c, 21f, g.armY, aR, 15f, skin, cloth)
        drawHead(c, g, skin)
        drawExtras(c, -37f, 21f)
        drawHair(c, g, back = false)
    }

    private fun drawBaby(c: Canvas, t: Float, f: String, skin: Tone, cloth: Tone) {
        val g = geoBebe
        drawHair(c, g, back = true)
        shape(c, onesiePath, cloth.base, cloth.line, 2.2f, linear(cloth, -38f, -2f))
        fill.color = Color.WHITE
        c.drawCircle(0f, -17f, 2.4f, fill)
        c.drawCircle(0f, -9f, 2.4f, fill)
        val (aL, aR) = armAngles(t, f)
        drawArm(c, -18f, g.armY, aL, 10f, skin, cloth)
        drawArm(c, 18f, g.armY, aR, 10f, skin, cloth)
        drawHead(c, g, skin)
        drawExtras(c, -27f, 19f)
        drawHair(c, g, back = false)
    }

    // ----- hair
    private fun drawHair(c: Canvas, g: Geo, back: Boolean) {
        val h = look.hair
        if (h == "nenhum") return
        val ht = look.hairTone()
        val hx = g.headX
        val hy = g.headY
        val rx = g.headRX
        val ry = g.headRY
        if (back) {
            when (h) {
                "longo" -> {
                    tmp.reset()
                    tmp.moveTo(-rx - 3f, hy - 6f)
                    tmp.lineTo(-rx - 2f, hy + ry * 0.9f)
                    tmp.quadTo(-rx, hy + ry + 12f, -rx + 12f, hy + ry + 10f)
                    tmp.lineTo(rx - 12f, hy + ry + 10f)
                    tmp.quadTo(rx, hy + ry + 12f, rx + 2f, hy + ry * 0.9f)
                    tmp.lineTo(rx + 3f, hy - 6f)
                    tmp.close()
                    shape(c, tmp, ht.base, ht.line, 2.2f, linear(ht, hy - ry, hy + ry + 12f))
                }
                "chiquinhas" -> {
                    oval(c, -rx - 20f, hy - ry * 0.5f - 11f, -rx + 2f, hy - ry * 0.5f + 11f, ht.base, ht.line, 2.2f, radial(ht, -rx - 12f, hy - ry * 0.6f, 16f))
                    oval(c, rx - 2f, hy - ry * 0.5f - 11f, rx + 20f, hy - ry * 0.5f + 11f, ht.base, ht.line, 2.2f, radial(ht, rx + 6f, hy - ry * 0.6f, 16f))
                    val tie = look.hatTone()
                    fill.color = tie.base
                    c.drawCircle(-rx + 1f, hy - ry * 0.5f, 3.5f, fill)
                    c.drawCircle(rx - 1f, hy - ry * 0.5f, 3.5f, fill)
                }
                "coque" -> oval(c, hx - 13f, hy - ry - 20f, hx + 13f, hy - ry + 4f, ht.base, ht.line, 2.2f, radial(ht, hx - 4f, hy - ry - 12f, 18f))
                "afro" -> oval(c, hx - rx - 14f, hy - ry - 22f, hx + rx + 14f, hy + ry * 0.55f, ht.base, ht.line, 2.4f, radial(ht, hx - 12f, hy - ry - 4f, rx + 24f))
            }
            return
        }
        when (h) {
            "curto", "longo", "chiquinhas", "coque" -> {
                tmp.reset()
                tmp.moveTo(-rx - 1f, hy + 2f)
                tmp.cubicTo(-rx - 2f, hy - ry * 1.35f, rx + 2f, hy - ry * 1.35f, rx + 1f, hy + 2f)
                if (h == "curto") {
                    tmp.lineTo(rx * 0.86f, hy - ry * 0.32f)
                    val steps = 4
                    for (i in 0 until steps) {
                        val x0 = rx * 0.86f - (i + 1) * (rx * 1.72f / steps)
                        val xm = x0 + rx * 1.72f / steps / 2f
                        tmp.quadTo(xm, hy - ry * 0.12f, x0, hy - ry * 0.32f)
                    }
                    tmp.lineTo(-rx - 1f, hy + 2f)
                } else {
                    tmp.quadTo(rx * 0.7f, hy - ry * 0.55f, 8f, hy - ry * 0.55f)
                    tmp.quadTo(2f, hy - ry * 0.9f, -4f, hy - ry * 0.5f)
                    tmp.quadTo(-rx * 0.7f, hy - ry * 0.5f, -rx - 1f, hy + 2f)
                }
                tmp.close()
                shape(c, tmp, ht.base, ht.line, 2.2f, radial(ht, hx - 8f, hy - ry, rx * 1.3f))
            }
            "cacheado" -> {
                for (i in 0..8) {
                    val a = (PI + i / 8.0 * PI).toFloat()
                    val px = hx + cos(a) * rx * 0.92f
                    val py = hy - 4f + sin(a) * ry * 0.95f
                    oval(c, px - 11f, py - 11f, px + 11f, py + 11f, ht.base, ht.line, 2f, radial(ht, px - 3f, py - 4f, 14f))
                }
                oval(c, hx - 12f, hy - ry - 8f, hx + 12f, hy - ry + 12f, ht.base, ht.line, 2f, radial(ht, hx - 4f, hy - ry, 14f))
            }
            "moicano" -> {
                val top = hy - ry
                tmp.reset()
                tmp.moveTo(-9f, top + 7f); tmp.lineTo(-7f, top - 8f); tmp.lineTo(-3f, top + 1f); tmp.lineTo(0f, top - 13f)
                tmp.lineTo(3f, top + 1f); tmp.lineTo(7f, top - 8f); tmp.lineTo(9f, top + 7f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 2f)
            }
            "afro" -> {
                tmp.reset()
                tmp.moveTo(-rx, hy - 2f)
                tmp.cubicTo(-rx * 0.8f, hy - ry * 0.9f, rx * 0.8f, hy - ry * 0.9f, rx, hy - 2f)
                tmp.lineTo(rx, hy - ry * 0.9f)
                tmp.lineTo(-rx, hy - ry * 0.9f)
                tmp.close()
                fill.shader = null
                fill.color = ht.base
                c.drawPath(tmp, fill)
            }
            "cachinho" -> {
                stroke.color = ht.base
                stroke.strokeWidth = 4.5f
                tmp.reset()
                tmp.moveTo(hx, hy - ry + 1f)
                tmp.cubicTo(hx - 2f, hy - ry - 10f, hx + 10f, hy - ry - 14f, hx + 9f, hy - ry - 6f)
                tmp.cubicTo(hx + 8f, hy - ry - 1f, hx + 2f, hy - ry - 3f, hx + 4f, hy - ry - 7f)
                c.drawPath(tmp, stroke)
            }
        }
    }

    private fun headTop(g: Geo): Float {
        if (look.species == "broto") return -84f
        return when (look.hair) {
            "afro" -> g.headY - g.headRY - 20f
            "cacheado" -> g.headY - g.headRY - 6f
            "nenhum", "cachinho", "moicano" -> g.headY - g.headRY + 2f
            else -> g.headY - g.headRY - 3f
        }
    }

    // ----- hats
    private fun drawHat(c: Canvas, g: Geo) {
        val hat = look.hat
        if (hat == "nenhum") return
        val w = if (look.species == "broto") 74f else g.headRX * 2f
        val ht = look.hatTone()
        c.save()
        c.translate(0f, headTop(g))
        when (hat) {
            "bone" -> {
                tmp.reset(); tmp.moveTo(-w * 0.47f, 8f); tmp.cubicTo(-w * 0.47f, -15f, w * 0.47f, -15f, w * 0.47f, 8f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 2.2f, linear(ht, -14f, 8f))
                val f = facing.toFloat()
                val x0 = f * w * 0.2f
                val x1 = f * (w * 0.2f + 26f)
                rect.set(min(x0, x1), 3f, max(x0, x1), 10f)
                fill.color = ht.shade; c.drawRoundRect(rect, 4f, 4f, fill)
                stroke.color = ht.line; stroke.strokeWidth = 2f; c.drawRoundRect(rect, 4f, 4f, stroke)
                fill.color = ht.shade; c.drawCircle(0f, -9f, 2.6f, fill)
            }
            "gorro" -> {
                tmp.reset(); tmp.moveTo(-w * 0.48f, 6f); tmp.cubicTo(-w * 0.46f, -24f, w * 0.46f, -24f, w * 0.48f, 6f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 2.2f, linear(ht, -22f, 6f))
                rect.set(-w * 0.5f, 0f, w * 0.5f, 11f)
                fill.color = ht.shade; c.drawRoundRect(rect, 5f, 5f, fill)
                stroke.color = ht.line; stroke.strokeWidth = 2f; c.drawRoundRect(rect, 5f, 5f, stroke)
                oval(c, -7f, -26f, 7f, -12f, Color.WHITE, 0xFFC9C9D2.toInt(), 2f)
            }
            "coroa" -> {
                tmp.reset()
                tmp.moveTo(-w * 0.3f, 7f); tmp.lineTo(-w * 0.33f, -14f); tmp.lineTo(-w * 0.15f, -3f); tmp.lineTo(0f, -19f)
                tmp.lineTo(w * 0.15f, -3f); tmp.lineTo(w * 0.33f, -14f); tmp.lineTo(w * 0.3f, 7f); tmp.close()
                shape(c, tmp, GOLD, GOLD_LINE, 2.2f)
                fill.color = 0xFFFF4F6B.toInt(); c.drawCircle(0f, -4f, 3.2f, fill)
                fill.color = 0xFF4F8BFF.toInt(); c.drawCircle(-w * 0.2f, 1f, 2.4f, fill); c.drawCircle(w * 0.2f, 1f, 2.4f, fill)
            }
            "festa" -> {
                c.save(); c.rotate(-10f)
                tmp.reset(); tmp.moveTo(-13f, 6f); tmp.lineTo(13f, 6f); tmp.lineTo(0f, -34f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 2.2f)
                c.save(); c.clipPath(tmp)
                fill.color = ht.hi
                for (i in 0 until 4) { rect.set(-20f, -30f + i * 10f, 20f, -26f + i * 10f); c.drawRect(rect, fill) }
                c.restore()
                stroke.color = ht.line; stroke.strokeWidth = 2.2f; c.drawPath(tmp, stroke)
                oval(c, -5f, -40f, 5f, -30f, GOLD, GOLD_LINE, 1.6f)
                c.restore()
            }
            "bruxa" -> {
                oval(c, -w * 0.62f, -1f, w * 0.62f, 11f, ht.shade, ht.line)
                tmp.reset()
                tmp.moveTo(-w * 0.28f, 6f); tmp.lineTo(w * 0.28f, 6f); tmp.lineTo(w * 0.06f, -30f)
                tmp.quadTo(w * 0.14f, -42f, w * 0.34f, -40f); tmp.quadTo(w * 0.02f, -50f, -w * 0.08f, -30f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 2.2f, linear(ht, -44f, 6f))
                rect.set(-w * 0.27f, -3f, w * 0.27f, 4f); fill.color = 0xFF2E2E3A.toInt(); c.drawRect(rect, fill)
                rect.set(-4f, -4f, 4f, 5f); fill.color = GOLD; c.drawRect(rect, fill)
            }
            "cartola" -> {
                oval(c, -w * 0.47f, 1f, w * 0.47f, 10f, 0xFF2E2E3A.toInt(), 0xFF111118.toInt())
                rect.set(-w * 0.3f, -30f, w * 0.3f, 6f)
                fill.color = 0xFF2E2E3A.toInt(); c.drawRoundRect(rect, 3f, 3f, fill)
                stroke.color = 0xFF111118.toInt(); stroke.strokeWidth = 2f; c.drawRoundRect(rect, 3f, 3f, stroke)
                rect.set(-w * 0.3f, -6f, w * 0.3f, 0f); fill.color = ht.base; c.drawRect(rect, fill)
            }
            "laco" -> {
                c.save(); c.translate(w * 0.3f, 8f); c.rotate(15f)
                tmp.reset(); tmp.moveTo(0f, 0f); tmp.lineTo(-11f, -8f); tmp.quadTo(-14f, 0f, -11f, 8f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 1.8f)
                tmp.reset(); tmp.moveTo(0f, 0f); tmp.lineTo(11f, -8f); tmp.quadTo(14f, 0f, 11f, 8f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 1.8f)
                oval(c, -3.6f, -3.6f, 3.6f, 3.6f, ht.shade, ht.line, 1.6f)
                c.restore()
            }
            "palha" -> {
                oval(c, -w * 0.66f, -2f, w * 0.66f, 12f, 0xFFE8C26A.toInt(), 0xFFB08A35.toInt())
                tmp.reset(); tmp.moveTo(-w * 0.3f, 5f); tmp.cubicTo(-w * 0.3f, -18f, w * 0.3f, -18f, w * 0.3f, 5f); tmp.close()
                shape(c, tmp, 0xFFF0CF7A.toInt(), 0xFFB08A35.toInt())
                rect.set(-w * 0.3f, -3f, w * 0.3f, 3f); fill.color = ht.base; c.drawRect(rect, fill)
            }
        }
        c.restore()
    }

    // ----- glasses, pacifier and extras
    private fun drawGlasses(c: Canvas, g: Geo, lx: Float, ly: Float, rx: Float, ry: Float) {
        val gl = look.glasses
        if (gl == "nenhum") return
        val s = g.eyeScale
        stroke.color = 0xFF3A2E2A.toInt()
        stroke.strokeWidth = 2.2f
        when (gl) {
            "redondo" -> {
                c.drawCircle(lx, ly, 11f * s, stroke)
                c.drawCircle(rx, ry, 11f * s, stroke)
                c.drawLine(lx + 11f * s, ly, rx - 11f * s, ry, stroke)
            }
            "escuro" -> {
                fill.shader = null
                fill.color = 0xEE1E1E28.toInt()
                rect.set(lx - 12f * s, ly - 8f * s, lx + 12f * s, ly + 8f * s); c.drawRoundRect(rect, 5f, 5f, fill)
                rect.set(rx - 12f * s, ry - 8f * s, rx + 12f * s, ry + 8f * s); c.drawRoundRect(rect, 5f, 5f, fill)
                c.drawLine(lx + 12f * s, ly - 2f, rx - 12f * s, ry - 2f, stroke)
                stroke.color = 0x66FFFFFF; stroke.strokeWidth = 1.6f
                c.drawLine(lx - 7f * s, ly - 3f * s, lx - 2f * s, ly - 6f * s, stroke)
                c.drawLine(rx - 7f * s, ry - 3f * s, rx - 2f * s, ry - 6f * s, stroke)
            }
            "coracao" -> {
                for (x in listOf(lx, rx)) {
                    heartPath(tmp, x, ly + 1f, 1.35f * s)
                    fill.shader = null
                    fill.color = 0x55FF5C8A
                    c.drawPath(tmp, fill)
                    stroke.color = 0xFFE03A70.toInt(); stroke.strokeWidth = 2f
                    c.drawPath(tmp, stroke)
                }
                c.drawLine(lx + 9f * s, ly - 3f, rx - 9f * s, ry - 3f, stroke)
            }
        }
    }

    private fun drawPacifier(c: Canvas, mx: Float, my: Float) {
        oval(c, mx - 8f, my - 2.5f, mx + 8f, my + 5f, 0xFF8FD3FF.toInt(), 0xFF4FA6D9.toInt(), 1.8f)
        stroke.color = 0xFF8FD3FF.toInt(); stroke.strokeWidth = 2.2f
        c.drawCircle(mx, my + 9f, 4.2f, stroke)
        fill.color = Color.WHITE
        c.drawCircle(mx, my + 1.2f, 1.8f, fill)
    }

    /** Scarf or bow tie around the neck at height [y]. */
    private fun drawExtras(c: Canvas, y: Float, halfW: Float) {
        val ht = look.hatTone()
        when (look.extra) {
            "cachecol" -> {
                rect.set(-halfW, y - 4f, halfW, y + 5f)
                fill.shader = null; fill.color = ht.base; c.drawRoundRect(rect, 4.5f, 4.5f, fill)
                stroke.color = ht.line; stroke.strokeWidth = 1.8f; c.drawRoundRect(rect, 4.5f, 4.5f, stroke)
                rect.set(halfW * 0.35f, y, halfW * 0.35f + 7f, y + 16f)
                c.drawRoundRect(rect, 3f, 3f, fill); c.drawRoundRect(rect, 3f, 3f, stroke)
                fill.color = ht.hi
                for (i in 0 until 3) c.drawRect(-halfW + 6f + i * 12f, y - 3f, -halfW + 9f + i * 12f, y + 4f, fill)
            }
            "gravata" -> {
                tmp.reset(); tmp.moveTo(0f, y); tmp.lineTo(-9f, y - 5f); tmp.lineTo(-9f, y + 5f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 1.6f)
                tmp.reset(); tmp.moveTo(0f, y); tmp.lineTo(9f, y - 5f); tmp.lineTo(9f, y + 5f); tmp.close()
                shape(c, tmp, ht.base, ht.line, 1.6f)
                oval(c, -2.8f, y - 2.8f, 2.8f, y + 2.8f, ht.shade, ht.line, 1.4f)
            }
        }
    }

    private fun heartPath(p: Path, x: Float, y: Float, s: Float) {
        p.reset()
        p.moveTo(x, y + 8f * s)
        p.cubicTo(x - 11f * s, y + 1f * s, x - 9f * s, y - 9f * s, x - 4.5f * s, y - 8.5f * s)
        p.cubicTo(x - 1.8f * s, y - 8.2f * s, x, y - 6f * s, x, y - 4f * s)
        p.cubicTo(x, y - 6f * s, x + 1.8f * s, y - 8.2f * s, x + 4.5f * s, y - 8.5f * s)
        p.cubicTo(x + 9f * s, y - 9f * s, x + 11f * s, y + 1f * s, x, y + 8f * s)
        p.close()
    }

    // ----- eyes and mouth
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

    private fun arcEye(c: Canvas, x: Float, y: Float, up: Boolean, s: Float) {
        stroke.color = INK
        stroke.strokeWidth = 3.3f * s
        tmp.reset()
        if (up) { tmp.moveTo(x - 7f * s, y + 2f * s); tmp.quadTo(x, y - 8f * s, x + 7f * s, y + 2f * s) }
        else { tmp.moveTo(x - 7f * s, y - 1f * s); tmp.quadTo(x, y + 6f * s, x + 7f * s, y - 1f * s) }
        c.drawPath(tmp, stroke)
    }

    private fun chevronEye(c: Canvas, x: Float, y: Float, right: Boolean, s: Float) {
        stroke.color = INK
        stroke.strokeWidth = 3.3f * s
        tmp.reset()
        if (right) { tmp.moveTo(x - 6f * s, y - 6f * s); tmp.lineTo(x + 5f * s, y); tmp.lineTo(x - 6f * s, y + 6f * s) }
        else { tmp.moveTo(x + 6f * s, y - 6f * s); tmp.lineTo(x - 5f * s, y); tmp.lineTo(x + 6f * s, y + 6f * s) }
        c.drawPath(tmp, stroke)
    }

    private fun drawEyes(c: Canvas, f: String, g: Geo, lx: Float, ly: Float, rx: Float, ry: Float, blink: Boolean, t: Float) {
        val s = g.eyeScale
        val squeeze = if (blink) 0.08f else 1f
        val by = g.eyeY - 13f * s
        when (f) {
            "animado" -> { openEye(c, lx, ly, 1.08f * s, squeeze, true); openEye(c, rx, ry, 1.08f * s, squeeze, true) }
            "comendo" -> { arcEye(c, lx, ly, true, s); arcEye(c, rx, ry, true, s) }
            "carinhoso" -> {
                val hs = (1f + sin(t * 6f) * 0.06f) * s
                for (x in listOf(lx, rx)) {
                    heartPath(tmp, x, ly, hs)
                    fill.shader = null; fill.color = HEART; c.drawPath(tmp, fill)
                    fill.color = Color.WHITE; c.drawCircle(x - 3.6f * hs, ly - 4.6f * hs, 1.6f * hs, fill)
                }
            }
            "dormindo" -> { arcEye(c, lx, ly, false, s); arcEye(c, rx, ry, false, s) }
            "brincalhao" -> { openEye(c, lx, ly, s, squeeze, true); arcEye(c, rx, ry, true, s) }
            "agitado" -> { chevronEye(c, lx, ly, true, s); chevronEye(c, rx, ry, false, s) }
            "sonolento" -> {
                openEye(c, lx, ly + 2f, s, if (blink) 0.08f else 0.42f, false)
                openEye(c, rx, ry + 2f, s, if (blink) 0.08f else 0.42f, false)
            }
            "surpreso" -> { openEye(c, lx, ly, 1.2f * s, squeeze, false); openEye(c, rx, ry, 1.2f * s, squeeze, false) }
            "pensativo" -> {
                openEye(c, lx - 2f, ly - 2.5f, s, squeeze, false); openEye(c, rx - 2f, ry - 2.5f, s, squeeze, false)
                stroke.color = INK; stroke.strokeWidth = 2.6f * s
                tmp.reset(); tmp.moveTo(g.eyeDX - 7f, by - 2f); tmp.quadTo(g.eyeDX, by - 7f, g.eyeDX + 8f, by - 3f); c.drawPath(tmp, stroke)
            }
            "triste", "fome" -> {
                openEye(c, lx, ly + 1f, 0.95f * s, squeeze, true); openEye(c, rx, ry + 1f, 0.95f * s, squeeze, true)
                stroke.color = INK; stroke.strokeWidth = 2.6f * s
                tmp.reset(); tmp.moveTo(-g.eyeDX - 8f, by + 3f); tmp.lineTo(-g.eyeDX + 6f, by - 1f); c.drawPath(tmp, stroke)
                tmp.reset(); tmp.moveTo(g.eyeDX - 6f, by - 1f); tmp.lineTo(g.eyeDX + 8f, by + 3f); c.drawPath(tmp, stroke)
            }
            else -> { openEye(c, lx, ly, s, squeeze, false); openEye(c, rx, ry, s, squeeze, false) }
        }
    }

    private fun drawMouth(c: Canvas, f: String, mx: Float, my: Float, n: Long) {
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
        val s = if (look.species == "broto") 1f else 0.85f
        stroke.color = INK
        stroke.strokeWidth = 2.5f * s
        fill.shader = null
        tmp.reset()
        when (shape) {
            "omega" -> {
                tmp.moveTo(mx - 6.5f * s, my - 1f); tmp.quadTo(mx - 3.2f * s, my + 4f * s, mx, my - 0.2f)
                tmp.quadTo(mx + 3.2f * s, my + 4f * s, mx + 6.5f * s, my - 1f)
                c.drawPath(tmp, stroke)
            }
            "smile" -> { tmp.moveTo(mx - 6f * s, my - 1f); tmp.quadTo(mx, my + 6f * s, mx + 6f * s, my - 1f); c.drawPath(tmp, stroke) }
            "small" -> { tmp.moveTo(mx - 3f * s, my + 1f); tmp.quadTo(mx, my + 2.8f * s, mx + 3f * s, my + 1f); c.drawPath(tmp, stroke) }
            "flat" -> { tmp.moveTo(mx - 4f * s, my + 1.5f); tmp.quadTo(mx + 1f, my + 0.5f, mx + 4.5f * s, my + 2f); c.drawPath(tmp, stroke) }
            "sad" -> { tmp.moveTo(mx - 5.5f * s, my + 3.5f * s); tmp.quadTo(mx, my - 2.5f * s, mx + 5.5f * s, my + 3.5f * s); c.drawPath(tmp, stroke) }
            "wavy" -> {
                tmp.moveTo(mx - 7f * s, my + 1f); tmp.quadTo(mx - 3.5f * s, my - 2.5f, mx, my + 1f); tmp.quadTo(mx + 3.5f * s, my + 4.5f, mx + 7f * s, my + 1f)
                c.drawPath(tmp, stroke)
            }
            "o" -> {
                rect.set(mx - 3.6f * s, my - 1.5f, mx + 3.6f * s, my + 6f * s)
                fill.color = MOUTH_IN; c.drawOval(rect, fill); c.drawOval(rect, stroke)
            }
            "chompB" -> { tmp.moveTo(mx - 6f * s, my + 1f); tmp.lineTo(mx + 6f * s, my + 1f); c.drawPath(tmp, stroke) }
            else -> {
                val (w0, d0) = when (shape) { "grin" -> 7.5f to 11f; "chompA" -> 8f to 12f; "talkA" -> 6f to 9f; else -> 4.5f to 5f }
                val w = w0 * s
                val d = d0 * s
                tmp.moveTo(mx - w, my - 2f); tmp.quadTo(mx, my + d, mx + w, my - 2f); tmp.quadTo(mx, my + 1f, mx - w, my - 2f); tmp.close()
                fill.color = MOUTH_IN; c.drawPath(tmp, fill)
                if (d0 >= 9f) {
                    fill.color = TONGUE
                    rect.set(mx - 3.2f * s, my + d * 0.32f, mx + 3.2f * s, my + d * 0.32f + 3.6f * s)
                    c.drawOval(rect, fill)
                }
                c.drawPath(tmp, stroke)
            }
        }
    }

    private fun drawNoseBubble(c: Canvas, x: Float, y: Float, t: Float) {
        val r = 2f + 4.5f * (0.5f + 0.5f * sin(t * 1.3f))
        fill.shader = null
        fill.color = 0x66BFE6FF
        c.drawCircle(x + r * 0.6f, y, r, fill)
        stroke.color = 0xAA7FB8E0.toInt()
        stroke.strokeWidth = 1f
        c.drawCircle(x + r * 0.6f, y, r, stroke)
        fill.color = 0xCCFFFFFF.toInt()
        c.drawCircle(x + r * 0.6f - r * 0.35f, y - r * 0.35f, r * 0.22f, fill)
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
                    heartPath(tmp2, x, y, p.size * u / 10f * (0.7f + age * 0.5f))
                    fill.shader = null
                    fill.color = (alpha shl 24) or (HEART and 0xFFFFFF)
                    c.drawPath(tmp2, fill)
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
                    tmp2.reset()
                    tmp2.moveTo(x, y - s); tmp2.lineTo(x + s * 0.3f, y - s * 0.3f); tmp2.lineTo(x + s, y); tmp2.lineTo(x + s * 0.3f, y + s * 0.3f)
                    tmp2.lineTo(x, y + s); tmp2.lineTo(x - s * 0.3f, y + s * 0.3f); tmp2.lineTo(x - s, y); tmp2.lineTo(x - s * 0.3f, y - s * 0.3f); tmp2.close()
                    c.drawPath(tmp2, fill)
                }
                4 -> {
                    fill.shader = null
                    fill.color = (alpha shl 24) or 0x7FC8FF
                    val s = p.size * u
                    tmp2.reset(); tmp2.moveTo(x, y - s * 1.6f); tmp2.quadTo(x + s, y, x, y + s); tmp2.quadTo(x - s, y, x, y - s * 1.6f); tmp2.close()
                    c.drawPath(tmp2, fill)
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
