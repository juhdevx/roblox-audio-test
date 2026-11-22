package com.ninodebolso.app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.graphics.Point
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/**
 * Keeps Nino on the screen: two overlay windows (the pet and its speech bubble) drawn over other apps,
 * a little physics engine for walking, jumping and being thrown, and the pet's own initiative.
 */
class PetService : Service() {

    companion object {
        const val ACT_START = "start"
        const val ACT_STOP = "stop"
        const val ACT_EYES = "eyes"
        const val ACT_REMIND = "remind"
        const val ACT_TOGGLE = "toggle"
        const val ACT_LOOK = "look"

        var instance: PetService? = null
            private set

        /** The last screenshot the pet took (to attach in the chat). */
        var lastScreen: ByteArray? = null
        var lastScreenAt = 0L

        fun start(ctx: Context, action: String = ACT_START, extras: (Intent) -> Unit = {}) {
            val i = Intent(ctx, PetService::class.java).setAction(action)
            extras(i)
            ctx.startForegroundService(i)
        }
    }

    private enum class Mode { IDLE, WALK, SLEEP, DRAG, AIR, HIDE, ZOOM }

    private lateinit var wm: WindowManager
    private lateinit var pet: PetView
    private lateinit var bubble: BubbleView
    private lateinit var petLp: WindowManager.LayoutParams
    private lateinit var bubbleLp: WindowManager.LayoutParams
    private val h = Handler(Looper.getMainLooper())
    private val choreo by lazy { Choreographer.getInstance() }

    private var petAttached = false
    private var bubbleAttached = false
    private var bubbleShown = false
    private var menuOpen = false
    private var petVisible = true      // false while one of the app's own screens is open
    private var userHidden = false     // hidden from the notification
    private var speakingNow = false
    private var started = false

    // physics, in pixels
    private var x = 0f
    private var y = 0f
    private var vx = 0f
    private var vy = 0f
    private var mode = Mode.IDLE
    private var modeUntil = 0L
    private var targetX = 0f
    private var bounces = 0
    private var thrown = false
    private var laps = 0
    private var screenW = 0
    private var screenH = 0
    private var navBottom = 0
    private var statusTop = 0
    private var petW = 0
    private var petH = 0
    private var groundY = 0f
    private var minX = 0f
    private var maxX = 0f
    private var frameOn = false
    private var lastNanos = 0L

    // touch
    private var grabDX = 0f
    private var grabDY = 0f
    private var downRawX = 0f
    private var downRawY = 0f
    private var lastRawX = 0f
    private var downAt = 0L
    private var moved = false
    private var longPressed = false
    private var lastTapAt = 0L
    private var tracker: VelocityTracker? = null
    private val touchSlop by lazy { ViewConfiguration.get(this).scaledTouchSlop.toFloat() }

    // initiative
    private var screenOn = true
    private var unlockedAt = now()
    private var screenOffAt = 0L
    private var nudged = 0
    private var nightNudgeDay = ""
    private var nextChatAt = now() + 90_000
    private var lastInteract = now()
    private var lastPowerLine = 0L
    private var strokes = 0
    private var lastLevel = 1
    private var lastSize = -1
    private var lastName = ""
    private var thinking = false

    // eyes
    private var eyes: ScreenEyes? = null
    private var glancing = false
    private var nextGlanceAt = 0L
    private var lastGlanceHash = 0L
    private val recentGlances = mutableListOf<String>()

    override fun onBind(intent: Intent?): IBinder? = null

    // ================================================================= lifecycle
    override fun onCreate() {
        super.onCreate()
        instance = this
        Store.init(this)
        wm = getSystemService(WindowManager::class.java)
        pet = PetView(this)
        newBubble()
        measureScreen()
        buildPetWindow()
        x = screenW * 0.62f
        y = groundY
        if (Store.sleeping) { mode = Mode.SLEEP; pet.sleeping = true }
        lastLevel = Store.level()
        pet.level = lastLevel
        pet.setOnTouchListener { _, e -> onPetTouch(e); true }
        Voice.listen(voiceListener)
        Store.listen(storeListener)
        val f = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_BATTERY_LOW)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(sysReceiver, f, Context.RECEIVER_NOT_EXPORTED) else registerReceiver(sysReceiver, f)
        h.postDelayed(thinkLoop, 800)
        h.postDelayed(initiativeLoop, 6000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        goForeground(eyes?.active == true)
        if (!Settings.canDrawOverlays(this)) {
            stopPet()
            return START_NOT_STICKY
        }
        if (intent?.action != ACT_STOP && petVisible && !petAttached && !userHidden) attachPet()
        when (intent?.action) {
            ACT_STOP -> { stopPet(); return START_NOT_STICKY }
            ACT_EYES -> {
                val code = intent.getIntExtra("code", 0)
                val data: Intent? = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra("data", Intent::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra("data")
                if (data != null) startEyes(code, data, intent.getBooleanExtra("look", false))
            }
            ACT_REMIND -> intent.getStringExtra("id")?.let { id -> h.postDelayed({ remind(id) }, 600) }
            ACT_TOGGLE -> toggleHidden()
            ACT_LOOK -> lookAtScreen()
        }
        if (!started) {
            started = true
            Store.petActive = true
            Store.changed()
            if (intent?.action == ACT_START || intent?.action == null) h.postDelayed({ greet() }, 900)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        h.removeCallbacksAndMessages(null)
        if (frameOn) choreo.removeFrameCallback(frameCb)
        try { unregisterReceiver(sysReceiver) } catch (e: Exception) { }
        Voice.unlisten(voiceListener)
        Store.unlisten(storeListener)
        detachBubble()
        detachPet()
        eyes?.shutdown()
        eyes = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        hideBubble()
        newBubble()
        measureScreen()
        if (mode != Mode.HIDE) { x = x.coerceIn(minX, maxX); y = min(y, groundY) }
        if (mode == Mode.IDLE || mode == Mode.WALK || mode == Mode.SLEEP) y = groundY
        moveWindows()
    }

    fun stopPet() {
        Store.petActive = false
        Store.changed()
        Voice.stop()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun goForeground(withEyes: Boolean) {
        val n = notification()
        when {
            Build.VERSION.SDK_INT >= 34 -> {
                var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                if (withEyes) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                startForeground(Notifs.PET_ID, n, type)
            }
            Build.VERSION.SDK_INT >= 29 ->
                @Suppress("DEPRECATION")
                startForeground(Notifs.PET_ID, n, if (withEyes) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION else ServiceInfo.FOREGROUND_SERVICE_TYPE_NONE)
            else -> startForeground(Notifs.PET_ID, n)
        }
    }

    private fun notification(): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), flags)
        val chat = PendingIntent.getActivity(this, 2, Intent(this, ChatActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), flags)
        val toggle = PendingIntent.getService(this, 3, Intent(this, PetService::class.java).setAction(ACT_TOGGLE), flags)
        val stop = PendingIntent.getService(this, 4, Intent(this, PetService::class.java).setAction(ACT_STOP), flags)
        return Notification.Builder(this, Notifs.PET)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("${Store.petName} está na sua tela")
            .setContentText(if (eyes?.active == true) "Ele pode olhar sua tela pra te ajudar." else "Toque nele para conversar.")
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Conversar", chat).build())
            .addAction(Notification.Action.Builder(null, if (userHidden) "Mostrar" else "Esconder", toggle).build())
            .addAction(Notification.Action.Builder(null, "Guardar", stop).build())
            .build()
    }

    private fun refreshNotification() {
        try { getSystemService(NotificationManager::class.java).notify(Notifs.PET_ID, notification()) } catch (e: Exception) { }
    }

    // ================================================================= windows
    private fun overlayParams(w: Int, hgt: Int, extra: Int = 0) = WindowManager.LayoutParams(
        w, hgt,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or extra,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        if (Build.VERSION.SDK_INT >= 28) layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
    }

    private fun bodyDp() = when (Store.size) { 0 -> 56; 2 -> 88; else -> 70 }

    private fun buildPetWindow() {
        lastSize = Store.size
        petW = dp(bodyDp() * 1.6f)
        petH = dp(bodyDp() * 1.7f)
        petLp = overlayParams(petW, petH)
        computeBounds()
    }

    private fun newBubble() {
        val old = if (this::bubble.isInitialized) bubble else null
        if (old != null && bubbleAttached) detachBubble()
        bubble = BubbleView(this)
        bubble.onTyping = { typing -> if (!speakingNow) pet.talking = typing }
        bubble.onOutside = { if (menuOpen) hideBubble() }
        bubble.onTapText = { hideBubble() }
        bubbleLp = overlayParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH)
    }

    private fun attachPet() {
        if (petAttached) return
        petLp.x = x.toInt(); petLp.y = y.toInt()
        try { wm.addView(pet, petLp); petAttached = true } catch (e: Exception) { petAttached = false }
    }

    private fun detachPet() {
        if (!petAttached) return
        try { wm.removeView(pet) } catch (e: Exception) { }
        petAttached = false
    }

    private fun detachBubble() {
        if (!bubbleAttached) return
        try { wm.removeView(bubble) } catch (e: Exception) { }
        bubbleAttached = false
    }

    private fun measureScreen() {
        if (Build.VERSION.SDK_INT >= 30) {
            val m = wm.currentWindowMetrics
            screenW = m.bounds.width()
            screenH = m.bounds.height()
            val ins = m.windowInsets
            navBottom = ins.getInsetsIgnoringVisibility(WindowInsets.Type.navigationBars() or WindowInsets.Type.displayCutout()).bottom
            statusTop = ins.getInsetsIgnoringVisibility(WindowInsets.Type.statusBars() or WindowInsets.Type.displayCutout()).top
        } else {
            val p = Point()
            @Suppress("DEPRECATION") wm.defaultDisplay.getRealSize(p)
            screenW = p.x
            screenH = p.y
            navBottom = sysDimen("navigation_bar_height")
            statusTop = sysDimen("status_bar_height")
        }
        if (this::petLp.isInitialized) computeBounds()
    }

    private fun sysDimen(name: String): Int {
        val id = resources.getIdentifier(name, "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else 0
    }

    private fun computeBounds() {
        val u = petW / 160f
        groundY = screenH - navBottom - (petH - 7f * u) - dp(3)
        minX = -30f * u
        maxX = screenW - petW + 30f * u
    }

    private fun moveWindows() {
        if (petAttached) {
            petLp.x = x.toInt()
            petLp.y = y.toInt()
            try { wm.updateViewLayout(pet, petLp) } catch (e: Exception) { }
        }
        if (bubbleShown) positionBubble()
    }

    private fun positionBubble() {
        val maxW = min(dp(290), screenW - dp(20))
        bubble.measure(
            View.MeasureSpec.makeMeasureSpec(maxW, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(screenH, View.MeasureSpec.AT_MOST),
        )
        val bw = bubble.measuredWidth
        val bh = bubble.measuredHeight
        val pcx = x + petW / 2f
        var by = y + petH * 0.24f - bh
        var down = true
        if (by < statusTop + dp(4)) { by = y + petH - dp(6); down = false }
        val bx = (pcx - bw / 2f).coerceIn(dp(8).toFloat(), max(dp(8), screenW - bw - dp(8)).toFloat())
        bubble.tailX = pcx - bx
        if (bubble.tailDown != down) bubble.tailDown = down
        bubbleLp.x = bx.toInt()
        bubbleLp.y = by.toInt()
        if (bubbleAttached) {
            try { wm.updateViewLayout(bubble, bubbleLp) } catch (e: Exception) { }
        } else {
            try { wm.addView(bubble, bubbleLp); bubbleAttached = true } catch (e: Exception) { }
        }
    }

    /** Hides the pet while one of the app's own screens is open (the chat shows its own Nino). */
    fun setOverlayVisible(v: Boolean) {
        petVisible = v
        if (!v) { hideBubble(); detachPet() }
        else if (!userHidden) { attachPet(); moveWindows() }
    }

    private fun toggleHidden() {
        userHidden = !userHidden
        if (userHidden) { hideBubble(); detachPet() } else if (petVisible) { attachPet(); moveWindows() }
        refreshNotification()
    }

    // ================================================================= speech bubble
    fun say(
        text: String,
        emo: String? = null,
        speak: Boolean = false,
        actions: List<Pair<String, () -> Unit>> = emptyList(),
        holdMs: Long = 0,
        maxChars: Int = 230,
    ) {
        if (!petVisible || userHidden || !petAttached) {
            if (speak) Voice.speak(text)
            return
        }
        if (mode == Mode.WALK || mode == Mode.ZOOM) { pet.walking = false; setIdle(4000) }
        pet.express(emo, 5000)
        var short = text
        var acts = actions
        if (text.length > maxChars) {
            short = text.take(maxChars).substringBeforeLast(' ') + "…"
            if (acts.none { it.first == "Ler tudo" }) acts = acts + ("Ler tudo" to { hideBubble(); openChat(false) })
        }
        speakingNow = speak && Store.voice && Voice.ready
        menuOpen = false
        bubble.show(short, acts)
        bubbleShown = true
        positionBubble()
        if (speakingNow) Voice.speak(text)
        pet.look(0f, -0.3f)
        h.removeCallbacks(hideBubbleR)
        val hold = if (holdMs > 0) holdMs else max(5000L, short.length * 85L) + if (acts.isNotEmpty()) 5000L else 0L
        h.postDelayed(hideBubbleR, hold)
    }

    private val hideBubbleR = Runnable { hideBubble() }

    fun hideBubble() {
        h.removeCallbacks(hideBubbleR)
        if (this::bubble.isInitialized) bubble.stopTyping()
        detachBubble()
        bubbleShown = false
        menuOpen = false
        if (!speakingNow) pet.talking = false
    }

    fun toast(text: String) {
        if (!petVisible) Toast.makeText(this, text, Toast.LENGTH_SHORT).show()
    }

    private val voiceListener: (Boolean) -> Unit = { speaking ->
        if (speakingNow || speaking) pet.talking = speaking
        if (!speaking) speakingNow = false
    }

    private val storeListener: () -> Unit = {
        val lv = Store.level()
        pet.level = lv
        if (lv > lastLevel) {
            h.postDelayed({
                pet.sparkles(); pet.hearts(5); hop()
                say("Subi pro nível $lv! Olha minha folhinha crescendo!", "animado", speak = true)
            }, 1500)
        }
        lastLevel = lv
        if (Store.size != lastSize) {
            val wasAttached = petAttached
            detachPet()
            buildPetWindow()
            y = groundY
            x = x.coerceIn(minX, maxX)
            if (wasAttached) attachPet()
            moveWindows()
        }
        if (Store.petName != lastName) { lastName = Store.petName; refreshNotification() }
    }

    // ================================================================= touch
    private fun onPetTouch(e: MotionEvent) {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                tracker?.recycle()
                tracker = VelocityTracker.obtain().also { it.addMovement(e) }
                downRawX = e.rawX; downRawY = e.rawY; lastRawX = e.rawX
                grabDX = e.rawX - x; grabDY = e.rawY - y
                downAt = now(); moved = false; longPressed = false
                h.postDelayed(longPressR, 600)
            }
            MotionEvent.ACTION_MOVE -> {
                tracker?.addMovement(e)
                if (!moved && hypot(e.rawX - downRawX, e.rawY - downRawY) > touchSlop * 1.5f) {
                    moved = true
                    h.removeCallbacks(longPressR)
                    startDrag()
                }
                if (moved) {
                    pet.swing = pet.swing * 0.7f + (e.rawX - lastRawX) * 1.6f
                    lastRawX = e.rawX
                    x = e.rawX - grabDX
                    y = (e.rawY - grabDY).coerceIn(statusTop - petH * 0.3f, groundY)
                    moveWindows()
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                h.removeCallbacks(longPressR)
                tracker?.addMovement(e)
                if (moved) {
                    tracker?.computeCurrentVelocity(1000)
                    val lim = dp(2800).toFloat()
                    vx = (tracker?.xVelocity ?: 0f).coerceIn(-lim, lim)
                    vy = (tracker?.yVelocity ?: 0f).coerceIn(-lim, lim)
                    thrown = hypot(vx, vy) > dp(900)
                    pet.dragging = false
                    pet.swing = 0f
                    launch()
                } else if (!longPressed && e.actionMasked == MotionEvent.ACTION_UP) {
                    val n = now()
                    if (n - lastTapAt < 320) {
                        h.removeCallbacks(singleTapR)
                        lastTapAt = 0
                        onDoubleTap()
                    } else {
                        lastTapAt = n
                        h.postDelayed(singleTapR, 300)
                    }
                }
                tracker?.recycle()
                tracker = null
            }
        }
    }

    private val longPressR = Runnable {
        longPressed = true
        markInteract()
        pet.express("animado", 1500)
        openChat(true)
    }
    private val singleTapR = Runnable { onSingleTap() }

    private fun startDrag() {
        markInteract()
        hideBubble()
        mode = Mode.DRAG
        pet.walking = false
        pet.airborne = true
        pet.dragging = true
        if (Store.sleeping) { Store.tick(); Store.sleeping = false; pet.sleeping = false; Store.changed() }
    }

    private fun launch() {
        mode = Mode.AIR
        bounces = 0
        pet.airborne = true
        ensureFrames()
    }

    private fun onSingleTap() {
        markInteract()
        when {
            mode == Mode.SLEEP -> wake(true)
            mode == Mode.HIDE -> unhide()
            menuOpen && bubbleShown -> hideBubble()
            else -> { hop(); showMenu() }
        }
    }

    private fun onDoubleTap() {
        markInteract()
        if (mode == Mode.SLEEP) { pet.hearts(1); return }
        strokes++
        Store.bump(joy = 4.0)
        pet.hearts(4)
        pet.express("carinhoso", 2800)
        if (strokes % 3 == 1) say(Lines.PET.random(), "carinhoso")
        if (strokes % 3 == 0) Store.addXp(1)
        Store.changed()
    }

    private fun markInteract() {
        lastInteract = now()
        nextChatAt = max(nextChatAt, lastInteract + chatGap() / 2)
    }

    // ================================================================= movement
    private val frameCb = object : Choreographer.FrameCallback {
        override fun doFrame(nanos: Long) {
            val dt = if (lastNanos == 0L) 0.016f else ((nanos - lastNanos) / 1e9f).coerceIn(0f, 0.05f)
            lastNanos = nanos
            step(dt)
            if (mode == Mode.WALK || mode == Mode.AIR || mode == Mode.ZOOM) choreo.postFrameCallback(this)
            else { frameOn = false; lastNanos = 0L }
        }
    }

    private fun ensureFrames() {
        if (frameOn) return
        frameOn = true
        lastNanos = 0L
        choreo.postFrameCallback(frameCb)
    }

    private fun step(dt: Float) {
        when (mode) {
            Mode.AIR -> {
                vy += dp(2600) * dt
                x += vx * dt
                y += vy * dt
                if (x < minX) { x = minX; vx = abs(vx) * 0.55f }
                if (x > maxX) { x = maxX; vx = -abs(vx) * 0.55f }
                val ceiling = statusTop - petH * 0.3f
                if (y < ceiling) { y = ceiling; vy = abs(vy) * 0.3f }
                if (vx != 0f) pet.facing = if (vx > 0) 1 else -1
                if (y >= groundY) {
                    y = groundY
                    val impact = (vy / dp(1800)).coerceIn(0f, 1f)
                    if (vy > dp(700) && bounces < 2) {
                        vy = -vy * 0.36f
                        vx *= 0.7f
                        bounces++
                        pet.land(impact)
                    } else {
                        vy = 0f; vx = 0f
                        pet.airborne = false
                        pet.land(max(0.25f, impact))
                        setIdle(1400L + Random.nextLong(1500))
                        if (thrown) {
                            thrown = false
                            Store.bump(joy = 3.0)
                            pet.express(if (Random.nextBoolean()) "animado" else "surpreso", 2000)
                            if (Random.nextFloat() < 0.55f) say(Lines.THROWN.random())
                        }
                    }
                }
                moveWindows()
            }
            Mode.WALK, Mode.ZOOM -> {
                val speed = if (mode == Mode.ZOOM) dp(270) else dp(52)
                val dir = if (targetX > x) 1 else -1
                pet.facing = dir
                val dx = dir * speed * dt
                x += dx
                pet.addWalk(dx)
                val arrived = (dir > 0 && x >= targetX) || (dir < 0 && x <= targetX)
                if (arrived) {
                    x = targetX
                    if (mode == Mode.ZOOM && ++laps < 4) {
                        targetX = if (x < (minX + maxX) / 2) maxX else minX
                        if (Random.nextBoolean()) pet.hearts(1)
                    } else {
                        pet.walking = false
                        if (mode == Mode.ZOOM) {
                            pet.hearts(4)
                            Store.bump(joy = 10.0, energy = -4.0)
                            Store.addXp(2)
                            Store.changed()
                            mode = Mode.IDLE
                            say("Ufa! Que divertido!", "animado")
                        }
                        setIdle(2000L + Random.nextLong(4000))
                    }
                }
                moveWindows()
            }
            else -> {}
        }
    }

    private fun setIdle(ms: Long) {
        mode = Mode.IDLE
        modeUntil = now() + ms
        pet.walking = false
    }

    private fun walkTo(tx: Float) {
        targetX = tx.coerceIn(minX, maxX)
        if (abs(targetX - x) < dp(20)) { setIdle(2000); return }
        mode = Mode.WALK
        pet.walking = true
        ensureFrames()
    }

    private fun hop(power: Int = 520) {
        if (mode == Mode.DRAG || mode == Mode.AIR || mode == Mode.HIDE || mode == Mode.SLEEP) return
        pet.walking = false
        vy = -dp(power).toFloat()
        vx = 0f
        launch()
    }

    // ================================================================= the pet's own initiative
    private val thinkLoop = object : Runnable {
        override fun run() {
            think()
            h.postDelayed(this, 700)
        }
    }

    private fun moodFace(): String = when {
        thinking -> "pensativo"
        Store.energy < 15 -> "sonolento"
        Store.food < 18 -> "fome"
        Store.joy < 22 -> "triste"
        else -> "feliz"
    }

    private fun isNight() = Lines.hour().let { it >= 23 || it < 6 }

    private fun think() {
        Store.tick()
        pet.face = moodFace()
        pet.sleeping = mode == Mode.SLEEP
        if (!screenOn || !petVisible || userHidden) return
        val n = now()
        if (mode == Mode.SLEEP) {
            if (Store.energy >= 99 && !isNight()) wake(false)
            return
        }
        if (mode != Mode.IDLE || bubbleShown || n < modeUntil) return
        if (Store.energy < 12 || (isNight() && Store.energy < 40 && n - lastInteract > 15 * 60_000)) { goSleep(); return }
        val r = Random.nextFloat()
        when {
            r < 0.50f -> walkTo(minX + Random.nextFloat() * (maxX - minX))
            r < 0.62f -> { pet.notes(); pet.express("feliz", 2000); setIdle(3000L + Random.nextLong(3000)) }
            r < 0.69f -> hop(480)
            r < 0.75f -> { pet.wave(); setIdle(3000) }
            r < 0.79f && Store.food < 30 -> { pet.sweat(); setIdle(3000) }
            else -> { pet.look(Random.nextFloat() * 2 - 1, Random.nextFloat() * 1.4f - 0.7f); setIdle(2500L + Random.nextLong(4500)) }
        }
    }

    private fun chatGap(): Long = when (Store.chatty) {
        "muito" -> 3 * 60_000L
        "pouco" -> 25 * 60_000L
        "silencio" -> Long.MAX_VALUE / 4
        else -> 8 * 60_000L
    }

    private fun scheduleChat() {
        val g = chatGap()
        nextChatAt = if (g > 24 * 3_600_000L) Long.MAX_VALUE / 2 else now() + (g * (0.7 + Random.nextDouble() * 0.6)).toLong()
    }

    private val initiativeLoop = object : Runnable {
        override fun run() {
            try { initiative() } catch (e: Exception) { android.util.Log.w("Nino", "initiative", e) }
            h.postDelayed(this, 5000)
        }
    }

    private fun today() = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())

    private fun initiative() {
        if (!screenOn || !petVisible || userHidden || !petAttached) return
        if (mode == Mode.DRAG || mode == Mode.AIR || bubbleShown || Brain.busy) return
        val n = now()
        // Long stretches on the phone.
        if (mode != Mode.SLEEP && unlockedAt > 0) {
            val mins = (n - unlockedAt) / 60_000
            if (mins >= 60 && nudged < 1) {
                nudged = 1
                say("Faz uma hora direto no celular. Que tal piscar bem forte, beber água e esticar o corpo?", "carinhoso", speak = true)
                return
            }
            if (mins >= 120 && nudged < 2) {
                nudged = 2
                say("Duas horas de tela! Seus olhos merecem uma pausa. Eu espero aqui.", "pensativo", speak = true)
                return
            }
        }
        // Very late at night.
        val hr = Lines.hour()
        if (hr in 0..4 && mode != Mode.SLEEP && nightNudgeDay != today()) {
            nightNudgeDay = today()
            say("Já passou da meia-noite... que tal descansar? Amanhã eu te ajudo com tudo.", "sonolento", speak = true)
            return
        }
        // Automatic help with what is on the screen.
        if (maybeGlance()) return
        // Small talk.
        if (mode != Mode.SLEEP && n >= nextChatAt) {
            val (line, face) = Lines.idle()
            say(line, face)
            scheduleChat()
        }
    }

    private fun onUnlock() {
        val n = now()
        val away = if (screenOffAt > 0) n - screenOffAt else 0
        unlockedAt = n
        nudged = 0
        if (!petVisible || userHidden) return
        val d = today()
        if (Lines.hour() in 5..11 && Store.morningDay != d) {
            Store.morningDay = d
            Store.changed()
            if (mode == Mode.SLEEP) wakeQuiet()
            h.postDelayed({ pet.wave(); say(Lines.greeting(), "animado", speak = true) }, 1200)
        } else if (away > 2 * 3_600_000L && mode != Mode.SLEEP) {
            h.postDelayed({ say(Lines.RETURN.random(), "animado") }, 1200)
        }
    }

    private val sysReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    screenOn = false
                    screenOffAt = now()
                    unlockedAt = 0
                    pet.paused = true
                    hideBubble()
                    Voice.stop()
                }
                Intent.ACTION_SCREEN_ON -> { screenOn = true; pet.paused = false }
                Intent.ACTION_USER_PRESENT -> { screenOn = true; pet.paused = false; onUnlock() }
                Intent.ACTION_POWER_CONNECTED -> if (now() - lastPowerLine > 30 * 60_000) {
                    lastPowerLine = now()
                    h.postDelayed({ say("Oba, comidinha pro celular!", "animado") }, 800)
                }
                Intent.ACTION_BATTERY_LOW -> say("A bateria tá fraquinha... bora carregar?", "sonolento", speak = true)
            }
        }
    }

    private fun greet() {
        if (Store.chat.isEmpty() && Store.lastSeen == 0L) {
            say(
                "Oi! Eu sou o ${Store.petName}! Vou passear pela sua tela. Me toca pra ver o que sei fazer, toca duas vezes pra fazer carinho e me arrasta pra brincar!",
                "animado", speak = true, holdMs = 12000,
            )
            Store.lastSeen = now()
            Store.changed()
        } else {
            say(Lines.greeting(), "animado", speak = false)
        }
        pet.wave()
    }

    // ================================================================= actions
    private fun showMenu() {
        val sleepLabel = if (mode == Mode.SLEEP) "Acordar" else "Dormir"
        val acts = listOf<Pair<String, () -> Unit>>(
            "Conversar" to { hideBubble(); openChat(true) },
            "Olhar a tela" to { hideBubble(); lookAtScreen() },
            "Comer" to { hideBubble(); feed() },
            "Brincar" to { hideBubble(); zoomies() },
            sleepLabel to { hideBubble(); toggleSleep() },
            "Esconder" to { hideBubble(); hide() },
            "Guardar" to { hideBubble(); goodbye() },
        )
        Store.tick()
        val mood = when {
            Store.food < 30 -> " Tô com fominha..."
            Store.energy < 25 -> " Tô com soninho..."
            Store.joy < 35 -> " Brinca comigo?"
            else -> ""
        }
        say(Lines.TAP.random() + mood, "feliz", actions = acts, holdMs = 10000)
        menuOpen = true
    }

    fun openChat(withScreen: Boolean) {
        markInteract()
        val go = {
            startActivity(Intent(this, ChatActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        if (withScreen && eyes?.active == true) capture { _, _ -> go() } else go()
    }

    private fun openMain() {
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun feed() {
        markInteract()
        if (mode == Mode.SLEEP) { say("Zzz... (tô dormindo, me acorda primeiro)"); return }
        Store.tick()
        if (Store.food > 92) { say(Lines.FULL.random(), "surpreso"); return }
        val (emoji, name) = Lines.FOODS.random()
        setIdle(4500)
        pet.eat(emoji)
        h.postDelayed({
            Store.bump(food = 24.0, joy = 4.0)
            Store.addXp(3)
            Store.changed()
            say(Lines.YUM.random().format(name).replaceFirstChar { it.uppercase() }, "feliz")
        }, 2150)
    }

    private fun zoomies() {
        markInteract()
        if (mode == Mode.SLEEP) wakeQuiet()
        Store.tick()
        if (Store.energy < 12) { say("Tô sem energia pra correr... me deixa cochilar um pouco?", "sonolento"); return }
        say(Lines.ZOOM.random(), "animado", holdMs = 2500)
        laps = 0
        targetX = if (x < (minX + maxX) / 2) maxX else minX
        mode = Mode.ZOOM
        pet.walking = true
        ensureFrames()
    }

    private fun toggleSleep() {
        if (mode == Mode.SLEEP) { wake(false); return }
        Store.tick()
        if (Store.energy > 90) { say("Mas eu nem tô com sono!", "brincalhao"); return }
        goSleep()
    }

    private fun goSleep() {
        Store.tick()
        hideBubble()
        mode = Mode.SLEEP
        pet.walking = false
        pet.sleeping = true
        Store.sleeping = true
        Store.changed()
    }

    private fun wakeQuiet() {
        Store.tick()
        Store.sleeping = false
        Store.changed()
        pet.sleeping = false
        setIdle(2000)
    }

    private fun wake(grumpy: Boolean) {
        wakeQuiet()
        say(if (grumpy) Lines.WAKE.random() else "Bom diaaa! Dormi bem.", if (Store.energy < 50) "sonolento" else "animado")
    }

    private fun hide() {
        markInteract()
        if (mode == Mode.SLEEP) wakeQuiet()
        mode = Mode.HIDE
        pet.walking = false
        pet.airborne = false
        val left = x + petW / 2 < screenW / 2
        x = if (left) -petW * 0.5f else screenW - petW * 0.5f
        y = screenH * 0.42f
        pet.facing = if (left) 1 else -1
        pet.look(if (left) 1f else -1f, 0f)
        moveWindows()
        say(Lines.HIDE.random(), "brincalhao")
    }

    private fun unhide() {
        val left = x < screenW / 2
        vx = if (left) dp(320).toFloat() else -dp(320).toFloat()
        vy = -dp(300).toFloat()
        thrown = false
        launch()
    }

    private fun goodbye() {
        say("Tchau! Me chama quando quiser.", "carinhoso")
        pet.wave()
        h.postDelayed({ stopPet() }, 2200)
    }

    fun cheer() {
        pet.hearts(3)
        pet.sparkles()
        hop()
        say(Lines.DONE.random(), "animado")
    }

    fun remind(id: String) {
        val t = Store.task(id) ?: return
        if (t.done) return
        markInteract()
        if (mode == Mode.SLEEP) wakeQuiet()
        if (mode == Mode.HIDE) { x = x.coerceIn(minX, maxX); y = groundY; setIdle(3000) }
        hop(620)
        pet.wave()
        say(
            "Ei! Hora de: ${t.title}", "surpreso", speak = true, holdMs = 60_000,
            actions = listOf(
                "Feito" to { hideBubble(); if (Store.completeTask(id)) cheer() },
                "Mais 10 min" to {
                    hideBubble()
                    Store.snooze(id, 10)
                    say("Beleza, te lembro de novo em 10 minutos.", "feliz")
                },
            ),
        )
    }

    // ================================================================= eyes
    private fun startEyes(code: Int, data: Intent, look: Boolean) {
        goForeground(true)
        eyes?.shutdown()
        val e = ScreenEyes(this) {
            eyes = null
            goForeground(false)
            refreshNotification()
            say("Parei de olhar sua tela. Se quiser, é só me pedir de novo.", "feliz")
        }
        if (e.start(code, data)) {
            eyes = e
            refreshNotification()
            if (look) h.postDelayed({ lookAtScreen() }, 900)
            else say("Agora eu consigo ver sua tela quando você pedir!", "animado", speak = true)
            nextGlanceAt = now() + Store.autoHelpMin * 60_000L
        } else {
            e.shutdown()
            goForeground(false)
            say("Não consegui abrir meus olhinhos... tenta de novo?", "triste")
        }
    }

    private fun askEyes(look: Boolean) {
        say("Pra eu ver sua tela, o Android vai pedir sua permissão. Escolhe a tela inteira!", "pensativo", holdMs = 4000)
        h.postDelayed({
            startActivity(Intent(this, CaptureActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("look", look))
        }, 1200)
    }

    /** Takes a screenshot without the pet in it. */
    private fun capture(cb: (ByteArray?, Long) -> Unit) {
        val e = eyes
        if (e == null || !e.active) { cb(null, 0); return }
        pet.visibility = View.INVISIBLE
        if (bubbleAttached) bubble.visibility = View.INVISIBLE
        h.postDelayed({
            e.grab { bytes, hash ->
                pet.visibility = View.VISIBLE
                if (bubbleAttached) bubble.visibility = View.VISIBLE
                if (bytes != null) { lastScreen = bytes; lastScreenAt = now() }
                cb(bytes, hash)
            }
        }, 300)
    }

    fun lookAtScreen() {
        markInteract()
        val e = eyes
        if (e == null || !e.active) { askEyes(true); return }
        if (!Brain.hasKey()) {
            say(
                "Pra eu entender a tela, preciso do meu cérebro de IA. Coloca a chave no app do ${Store.petName}!", "triste",
                actions = listOf("Abrir o app" to { hideBubble(); openMain() }),
            )
            return
        }
        if (Brain.busy) { say("Peraí, ainda tô pensando na outra coisa...", "pensativo"); return }
        if (mode == Mode.SLEEP) wakeQuiet()
        capture { jpeg, _ ->
            if (jpeg == null) { say("Não consegui ver nada... tenta de novo?", "triste"); return@capture }
            thinking = true
            pet.face = "pensativo"
            say(Lines.THINK.random(), "pensativo", holdMs = 90_000)
            val q = "Olha minha tela agora: o que tem aqui e como você pode me ajudar com isso?"
            Store.addChat(ChatMsg("u", q, img = true))
            Brain.chat(q, jpeg) { r ->
                thinking = false
                Store.addChat(ChatMsg("p", r.text, err = r.error))
                hideBubble()
                say(
                    r.text, r.emotion ?: "feliz", speak = !r.error,
                    actions = listOf("Responder" to { hideBubble(); openChat(false) }),
                    holdMs = max(9000L, min(30_000L, r.text.length * 90L)),
                )
            }
        }
    }

    private fun maybeGlance(): Boolean {
        val e = eyes ?: return false
        val n = now()
        if (!Store.autoHelp || !e.active || !Brain.hasKey() || Brain.busy || glancing) return false
        if (mode == Mode.SLEEP || mode == Mode.HIDE || bubbleShown || n < nextGlanceAt) return false
        glancing = true
        nextGlanceAt = n + Store.autoHelpMin * 60_000L
        capture { jpeg, hash ->
            if (jpeg == null || (lastGlanceHash != 0L && ScreenEyes.similar(hash, lastGlanceHash))) {
                glancing = false
                return@capture
            }
            lastGlanceHash = hash
            pet.express("pensativo", 4000)
            Brain.glance(jpeg, recentGlances.toList()) { r ->
                glancing = false
                if (r != null && petVisible && mode != Mode.SLEEP) {
                    recentGlances.add(r.text)
                    while (recentGlances.size > 6) recentGlances.removeAt(0)
                    Store.addChat(ChatMsg("p", r.text))
                    say(
                        r.text, r.emotion ?: "feliz", speak = true, holdMs = 15_000,
                        actions = listOf("Conversar" to { hideBubble(); openChat(true) }, "Valeu!" to { hideBubble() }),
                    )
                }
            }
        }
        return true
    }
}
