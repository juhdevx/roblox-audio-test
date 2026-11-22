package com.ninodebolso.app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min

/**
 * The pet's eyes: a screen-capture session the person allowed (Android shows its own consent
 * dialog and a "sharing screen" indicator). Frames are only turned into a picture when the pet looks.
 */
class ScreenEyes(private val ctx: Context, private val onStopped: () -> Unit) {
    private val thread = HandlerThread("nino-eyes").apply { start() }
    private val h = Handler(thread.looper)
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var latest: Image? = null
    private val lock = Any()

    val active get() = projection != null

    fun start(resultCode: Int, data: Intent): Boolean {
        val mpm = ctx.getSystemService(MediaProjectionManager::class.java)
        val p = try { mpm.getMediaProjection(resultCode, data) } catch (e: Exception) { null } ?: return false
        projection = p
        p.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                release()
                Main.post(onStopped)
            }
        }, h)

        val wm = ctx.getSystemService(WindowManager::class.java)
        val dm = ctx.resources.displayMetrics
        val (sw, sh) = if (Build.VERSION.SDK_INT >= 30) {
            val b = wm.currentWindowMetrics.bounds
            b.width() to b.height()
        } else {
            val m = DisplayMetrics()
            @Suppress("DEPRECATION") wm.defaultDisplay.getRealMetrics(m)
            m.widthPixels to m.heightPixels
        }
        // Capture at a size good enough to read text, without wasting memory.
        val scale = min(1f, 1440f / max(sw, sh))
        val w = (sw * scale).toInt() and 1.inv()
        val ht = (sh * scale).toInt() and 1.inv()
        val r = ImageReader.newInstance(w, ht, PixelFormat.RGBA_8888, 3)
        r.setOnImageAvailableListener({ ir ->
            val img = try { ir.acquireLatestImage() } catch (e: Exception) { null } ?: return@setOnImageAvailableListener
            synchronized(lock) {
                latest?.close()
                latest = img
            }
        }, h)
        reader = r
        display = try {
            p.createVirtualDisplay("nino-eyes", w, ht, dm.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, r.surface, null, h)
        } catch (e: Exception) {
            release(); null
        }
        return display != null
    }

    /** The most recent frame as JPEG plus a tiny hash to notice when the screen has not changed. */
    fun grab(cb: (ByteArray?, Long) -> Unit) {
        h.post {
            var bmp: Bitmap? = null
            synchronized(lock) {
                val img = latest
                if (img != null) {
                    try {
                        val plane = img.planes[0]
                        val ps = plane.pixelStride
                        val rs = plane.rowStride
                        val padW = rs / ps
                        val raw = Bitmap.createBitmap(padW, img.height, Bitmap.Config.ARGB_8888)
                        plane.buffer.rewind()
                        raw.copyPixelsFromBuffer(plane.buffer)
                        bmp = if (padW != img.width) Bitmap.createBitmap(raw, 0, 0, img.width, img.height).also { raw.recycle() } else raw
                    } catch (e: Exception) {
                        bmp = null
                    }
                }
            }
            val b = bmp
            if (b == null) { Main.post { cb(null, 0) }; return@post }
            val hash = averageHash(b)
            val out = ByteArrayOutputStream()
            b.compress(Bitmap.CompressFormat.JPEG, 78, out)
            b.recycle()
            val bytes = out.toByteArray()
            Main.post { cb(bytes, hash) }
        }
    }

    fun release() {
        synchronized(lock) { latest?.close(); latest = null }
        try { display?.release() } catch (e: Exception) { }
        try { reader?.close() } catch (e: Exception) { }
        display = null
        reader = null
        val p = projection
        projection = null
        try { p?.stop() } catch (e: Exception) { }
    }

    fun shutdown() {
        release()
        thread.quitSafely()
    }

    companion object {
        fun averageHash(b: Bitmap): Long {
            val s = Bitmap.createScaledBitmap(b, 8, 8, true)
            val px = IntArray(64)
            s.getPixels(px, 0, 8, 0, 0, 8, 8)
            if (s != b) s.recycle()
            val lum = px.map { ((it shr 16 and 255) * 3 + (it shr 8 and 255) * 6 + (it and 255)) / 10 }
            val avg = lum.average()
            var hash = 0L
            lum.forEachIndexed { i, v -> if (v > avg) hash = hash or (1L shl i) }
            return hash
        }

        fun similar(a: Long, b: Long) = java.lang.Long.bitCount(a xor b) <= 5
    }
}
