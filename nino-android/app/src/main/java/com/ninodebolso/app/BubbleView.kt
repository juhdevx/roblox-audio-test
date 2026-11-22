package com.ninodebolso.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.max

/** A ViewGroup that lays children out in rows and wraps, for the action chips. */
class FlowLayout(ctx: Context) : ViewGroup(ctx) {
    private val gap = ctx.dp(6)

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxW = MeasureSpec.getSize(widthMeasureSpec).let { if (it == 0) Int.MAX_VALUE else it }
        var x = 0
        var y = 0
        var rowH = 0
        var usedW = 0
        for (i in 0 until childCount) {
            val ch = getChildAt(i)
            if (ch.visibility == GONE) continue
            val lp = ch.layoutParams
            val ws = if (lp != null && lp.width > 0) MeasureSpec.makeMeasureSpec(lp.width, MeasureSpec.EXACTLY)
            else MeasureSpec.makeMeasureSpec(maxW, MeasureSpec.AT_MOST)
            val hs = if (lp != null && lp.height > 0) MeasureSpec.makeMeasureSpec(lp.height, MeasureSpec.EXACTLY)
            else MeasureSpec.UNSPECIFIED
            ch.measure(ws, hs)
            if (x > 0 && x + ch.measuredWidth > maxW) { x = 0; y += rowH + gap; rowH = 0 }
            x += ch.measuredWidth + gap
            usedW = max(usedW, x - gap)
            rowH = max(rowH, ch.measuredHeight)
        }
        val w = if (MeasureSpec.getMode(widthMeasureSpec) == MeasureSpec.EXACTLY) MeasureSpec.getSize(widthMeasureSpec) else usedW
        setMeasuredDimension(w, if (childCount == 0) 0 else y + rowH)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val maxW = r - l
        var x = 0
        var y = 0
        var rowH = 0
        for (i in 0 until childCount) {
            val ch = getChildAt(i)
            if (ch.visibility == GONE) continue
            if (x > 0 && x + ch.measuredWidth > maxW) { x = 0; y += rowH + gap; rowH = 0 }
            ch.layout(x, y, x + ch.measuredWidth, y + ch.measuredHeight)
            x += ch.measuredWidth + gap
            rowH = max(rowH, ch.measuredHeight)
        }
    }
}

/** The pet's speech bubble: rounded card with a little tail, typewriter text and optional action chips. */
class BubbleView(ctx: Context) : LinearLayout(ctx) {
    private val p = pal(ctx)
    private val tail = ctx.dpf(9)
    private val radius = ctx.dpf(18)
    private val tv = TextView(ctx)
    private val chips = FlowLayout(ctx)
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = p.bubble }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = ctx.dpf(1.5f)
        color = p.bubbleLine
    }
    private val shape = Path()
    private val box = RectF()
    private var full = ""
    private var shown = 0
    private val typer = object : Runnable {
        override fun run() {
            if (shown >= full.length) { onTyping?.invoke(false); return }
            shown = minOf(full.length, shown + 2)
            render()
            postDelayed(this, 34)
        }
    }

    var tailX = -1f
    var tailDown = true
        set(v) { field = v; applyPadding(); invalidate() }
    var onTyping: ((Boolean) -> Unit)? = null
    var onTapText: (() -> Unit)? = null
    var onOutside: (() -> Unit)? = null

    init {
        orientation = VERTICAL
        setWillNotDraw(false)
        applyPadding()
        tv.setTextColor(p.ink)
        tv.textSize = 15.5f
        tv.setLineSpacing(0f, 1.12f)
        addView(tv, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        addView(chips, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { topMargin = ctx.dp(8) })
        tv.setOnClickListener {
            if (shown < full.length) { shown = full.length; render() } else onTapText?.invoke()
        }
    }

    private fun applyPadding() {
        val h = context.dp(14)
        val v = context.dp(10)
        if (tailDown) setPadding(h, v, h, v + tail.toInt()) else setPadding(h, v + tail.toInt(), h, v)
    }

    fun show(text: String, actions: List<Pair<String, () -> Unit>>, typewriter: Boolean = true) {
        removeCallbacks(typer)
        full = text
        shown = if (typewriter) 0 else text.length
        render()
        chips.removeAllViews()
        actions.forEachIndexed { i, (label, fn) ->
            val b = TextView(context)
            b.text = label
            b.textSize = 13.5f
            b.typeface = Typeface.DEFAULT_BOLD
            b.gravity = Gravity.CENTER
            b.setPadding(context.dp(12), context.dp(7), context.dp(12), context.dp(7))
            b.setTextColor(if (i == 0) p.accentInk else p.accent)
            b.background = rounded(if (i == 0) p.accent else p.accentSoft, context.dpf(99))
            b.setOnClickListener { fn() }
            chips.addView(b)
        }
        chips.visibility = if (actions.isEmpty()) View.GONE else View.VISIBLE
        if (typewriter && text.isNotEmpty()) { onTyping?.invoke(true); post(typer) }
    }

    fun stopTyping() {
        removeCallbacks(typer)
        onTyping?.invoke(false)
    }

    /** Keeps the bubble's size fixed while typing: the rest of the text is laid out but transparent. */
    private fun render() {
        val s = SpannableString(full)
        if (shown < full.length) s.setSpan(ForegroundColorSpan(Color.TRANSPARENT), shown, full.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        tv.text = s
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) { onOutside?.invoke(); return false }
        return super.onTouchEvent(event)
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_OUTSIDE) { onOutside?.invoke(); return false }
        return super.dispatchTouchEvent(ev)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val half = linePaint.strokeWidth / 2
        val top = if (tailDown) half else tail + half
        val bottom = if (tailDown) h - tail - half else h - half
        box.set(half, top, w - half, bottom)
        val tx = (if (tailX < 0) w / 2 else tailX).coerceIn(radius + tail, w - radius - tail)
        shape.reset()
        shape.addRoundRect(box, radius, radius, Path.Direction.CW)
        val t = Path()
        if (tailDown) { t.moveTo(tx - tail, bottom - 1); t.lineTo(tx, h - half); t.lineTo(tx + tail, bottom - 1); t.close() }
        else { t.moveTo(tx - tail, top + 1); t.lineTo(tx, half); t.lineTo(tx + tail, top + 1); t.close() }
        shape.op(t, Path.Op.UNION)
        canvas.drawPath(shape, bgPaint)
        canvas.drawPath(shape, linePaint)
        super.onDraw(canvas)
    }
}
