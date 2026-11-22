package com.ninodebolso.app

import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import java.util.concurrent.CountDownLatch
import kotlin.math.roundToInt

fun now(): Long = System.currentTimeMillis()

fun clamp(v: Double, lo: Double = 0.0, hi: Double = 100.0) = v.coerceIn(lo, hi)

fun newId(): String = java.lang.Long.toString(System.nanoTime() xor (Math.random() * 1e12).toLong(), 36).takeLast(8)

/** Runs work on the main thread. */
object Main {
    val handler = Handler(Looper.getMainLooper())
    fun post(r: () -> Unit) { handler.post(r) }
    fun later(ms: Long, r: () -> Unit) { handler.postDelayed(r, ms) }
    fun isMain() = Looper.myLooper() == Looper.getMainLooper()

    /** Runs [block] on the main thread and waits for its result (call from a worker thread). */
    fun <T> sync(block: () -> T): T {
        if (isMain()) return block()
        val latch = CountDownLatch(1)
        var result: Result<T>? = null
        handler.post {
            result = runCatching(block)
            latch.countDown()
        }
        latch.await()
        return result!!.getOrThrow()
    }
}

fun Context.dp(v: Number): Int = (v.toFloat() * resources.displayMetrics.density).roundToInt()
fun Context.dpf(v: Number): Float = v.toFloat() * resources.displayMetrics.density

fun Context.isNight(): Boolean =
    (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

/** The app's palette, light and dark. */
class Pal(night: Boolean) {
    val bg = if (night) 0xFF0F1228.toInt() else 0xFFEDF0F8.toInt()
    val surface = if (night) 0xFF191D39.toInt() else 0xFFFFFFFF.toInt()
    val surface2 = if (night) 0xFF232847.toInt() else 0xFFF3F5FC.toInt()
    val ink = if (night) 0xFFECEEFA.toInt() else 0xFF1D2340.toInt()
    val muted = if (night) 0xFFA1A8D0.toInt() else 0xFF5A6388.toInt()
    val line = if (night) 0xFF2E345C.toInt() else 0xFFD7DCEC.toInt()
    val accent = if (night) 0xFF93A0FF.toInt() else 0xFF3446D1.toInt()
    val accentInk = if (night) 0xFF0E1230.toInt() else 0xFFFFFFFF.toInt()
    val accentSoft = if (night) 0xFF283066.toInt() else 0xFFE2E6FF.toInt()
    val good = if (night) 0xFF4CC58C.toInt() else 0xFF22905E.toInt()
    val warn = if (night) 0xFFF2B64F.toInt() else 0xFFC98110.toInt()
    val bad = if (night) 0xFFFF7B70.toInt() else 0xFFD2433A.toInt()
    val badSoft = if (night) 0x29FF7B70 else 0x1FD2433A
    val bubble = if (night) 0xFF262C55.toInt() else 0xFFFFFFFF.toInt()
    val bubbleLine = if (night) 0xFF3A4280.toInt() else 0xFFD7DCEC.toInt()
}

fun pal(ctx: Context) = Pal(ctx.isNight())

fun rounded(color: Int, radius: Float, strokeColor: Int = Color.TRANSPARENT, strokeWidth: Int = 0) =
    GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius
        if (strokeWidth > 0) setStroke(strokeWidth, strokeColor)
    }

/**
 * Lays the activity out edge to edge on Android 11+ and pads [root] by the system bars and the keyboard,
 * so nothing hides behind them (Android 15 forces edge to edge for apps that target it).
 */
fun Activity.edgeToEdge(root: View) {
    if (Build.VERSION.SDK_INT < 30) return
    window.setDecorFitsSystemWindows(false)
    @Suppress("DEPRECATION")
    run {
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
    }
    val light = !isNight()
    window.insetsController?.setSystemBarsAppearance(
        if (light) WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS else 0,
        WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
    )
    val base = intArrayOf(root.paddingLeft, root.paddingTop, root.paddingRight, root.paddingBottom)
    root.setOnApplyWindowInsetsListener { v, insets ->
        val sys = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime() or WindowInsets.Type.displayCutout())
        v.setPadding(base[0] + sys.left, base[1] + sys.top, base[2] + sys.right, base[3] + sys.bottom)
        WindowInsets.CONSUMED
    }
}
