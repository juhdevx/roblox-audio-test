package com.ninodebolso.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

const val MODEL_OPUS = "claude-opus-5-5"
const val MODEL_SONNET = "claude-sonnet-5-5"
const val MODEL_HAIKU = "claude-haiku-5-5"

class Task(
    val id: String,
    var title: String,
    var due: Long?,
    var done: Boolean = false,
    var doneAt: Long? = null,
    var notified: Boolean = false,
    val at: Long = now(),
)

class Memory(val id: String, val text: String, val at: Long = now())

/** role: "u" = you, "p" = the pet, "s" = a note from the pet (reminders). */
class ChatMsg(val role: String, val text: String, val at: Long = now(), val img: Boolean = false, val err: Boolean = false)

/** Everything the pet remembers, kept on the phone in private app storage. Touch it on the main thread. */
object Store {
    private lateinit var app: Context
    private lateinit var prefs: SharedPreferences
    private var loaded = false

    // settings
    var petName = "Nino"
    var userName = ""
    var apiKey = ""
    var model = MODEL_OPUS
    var voice = true
    var chatty = "normal"
    var autoHelp = false
    var autoHelpMin = 5
    var size = 1
    var petActive = false

    // the pet
    var food = 80.0
    var energy = 85.0
    var joy = 75.0
    var statsAt = now()
    var sleeping = false
    var xp = 0
    var lastSeen = 0L
    var morningDay = ""

    val tasks = mutableListOf<Task>()
    val memories = mutableListOf<Memory>()
    val chat = mutableListOf<ChatMsg>()

    private val listeners = LinkedHashSet<() -> Unit>()

    fun init(c: Context) {
        if (loaded) return
        app = c.applicationContext
        prefs = app.getSharedPreferences("nino", Context.MODE_PRIVATE)
        load()
        loaded = true
    }

    fun listen(l: () -> Unit) { listeners.add(l) }
    fun unlisten(l: () -> Unit) { listeners.remove(l) }

    fun changed() {
        save()
        Main.post { listeners.toList().forEach { it() } }
    }

    // ---------------- vitals ----------------
    fun tick() {
        val n = now()
        var h = (n - statsAt) / 3_600_000.0
        statsAt = n
        if (h <= 0) return
        h = min(h, 24.0 * 14)
        food = clamp(food - 6 * h)
        energy = clamp(if (sleeping) energy + 30 * h else energy - 5 * h)
        joy = clamp(joy - ((if (food < 20) 7.0 else 3.5) + (if (energy < 15) 2.0 else 0.0)) * h)
    }

    fun bump(food: Double = 0.0, energy: Double = 0.0, joy: Double = 0.0) {
        tick()
        this.food = clamp(this.food + food)
        this.energy = clamp(this.energy + energy)
        this.joy = clamp(this.joy + joy)
    }

    fun level(): Int = max(1, floor((25 + sqrt(625 + 100.0 * xp)) / 50).toInt())
    fun levelTotal(n: Int) = 25 * n * (n - 1)
    fun levelProgress(): Float {
        val n = level()
        val a = levelTotal(n)
        val b = levelTotal(n + 1)
        return ((xp - a).toFloat() / (b - a)).coerceIn(0f, 1f)
    }

    /** Adds experience; returns the new level if the pet just leveled up. */
    fun addXp(n: Int): Int? {
        val before = level()
        xp += n
        val after = level()
        return if (after > before) after else null
    }

    // ---------------- tasks ----------------
    fun task(id: String) = tasks.firstOrNull { it.id == id }

    fun openTasks(): List<Task> =
        tasks.filter { !it.done }.sortedWith(compareBy<Task>({ it.due ?: Long.MAX_VALUE }, { it.at }))

    fun addTask(title: String, due: Long?): Task {
        val t = Task(newId(), title.trim().take(140), due)
        tasks.add(t)
        Reminders.schedule(app, t)
        changed()
        return t
    }

    fun completeTask(id: String): Boolean {
        val t = task(id) ?: return false
        if (t.done) return false
        t.done = true
        t.doneAt = now()
        Reminders.cancel(app, id)
        bump(joy = 5.0)
        addXp(8)
        val done = tasks.filter { it.done }.sortedByDescending { it.doneAt ?: 0 }
        if (done.size > 25) tasks.removeAll(done.drop(25).toSet())
        changed()
        return true
    }

    fun reopenTask(id: String) {
        val t = task(id) ?: return
        t.done = false
        t.doneAt = null
        if (t.due != null && t.due!! > now()) { t.notified = false; Reminders.schedule(app, t) }
        changed()
    }

    fun snooze(id: String, minutes: Int) {
        val t = task(id) ?: return
        t.due = now() + minutes * 60_000L
        t.notified = false
        t.done = false
        Reminders.schedule(app, t)
        changed()
    }

    fun removeTask(id: String) {
        Reminders.cancel(app, id)
        tasks.removeAll { it.id == id }
        changed()
    }

    fun clearDone() {
        tasks.removeAll { it.done }
        changed()
    }

    // ---------------- memory & chat ----------------
    fun addMemory(text: String): Memory? {
        val t = text.trim().take(160)
        if (t.isEmpty() || memories.any { it.text.equals(t, ignoreCase = true) }) return null
        val m = Memory(newId(), t)
        memories.add(m)
        while (memories.size > 60) memories.removeAt(0)
        changed()
        return m
    }

    fun removeMemory(id: String) {
        memories.removeAll { it.id == id }
        changed()
    }

    fun addChat(m: ChatMsg) {
        chat.add(ChatMsg(m.role, m.text.take(4000), m.at, m.img, m.err))
        while (chat.size > 60) chat.removeAt(0)
        lastSeen = now()
        changed()
    }

    fun resetAll() {
        tasks.forEach { Reminders.cancel(app, it.id) }
        tasks.clear(); memories.clear(); chat.clear()
        food = 80.0; energy = 85.0; joy = 75.0; statsAt = now(); sleeping = false; xp = 0
        petName = "Nino"; userName = ""
        changed()
    }

    // ---------------- persistence ----------------
    private fun save() {
        val o = JSONObject()
        o.put("petName", petName); o.put("userName", userName); o.put("model", model)
        o.put("voice", voice); o.put("chatty", chatty); o.put("autoHelp", autoHelp); o.put("autoHelpMin", autoHelpMin)
        o.put("size", size); o.put("petActive", petActive)
        o.put("food", food); o.put("energy", energy); o.put("joy", joy); o.put("statsAt", statsAt)
        o.put("sleeping", sleeping); o.put("xp", xp); o.put("lastSeen", lastSeen); o.put("morningDay", morningDay)
        o.put("tasks", JSONArray().apply {
            tasks.forEach { t ->
                put(JSONObject().apply {
                    put("id", t.id); put("title", t.title); put("due", t.due ?: JSONObject.NULL)
                    put("done", t.done); put("doneAt", t.doneAt ?: JSONObject.NULL); put("notified", t.notified); put("at", t.at)
                })
            }
        })
        o.put("memories", JSONArray().apply { memories.forEach { put(JSONObject().put("id", it.id).put("text", it.text).put("at", it.at)) } })
        o.put("chat", JSONArray().apply {
            chat.forEach { put(JSONObject().put("r", it.role).put("t", it.text).put("at", it.at).put("img", it.img).put("err", it.err)) }
        })
        prefs.edit().putString("state", o.toString()).putString("apiKey", apiKey).apply()
    }

    private fun load() {
        apiKey = prefs.getString("apiKey", "") ?: ""
        val raw = prefs.getString("state", null) ?: return
        try {
            val o = JSONObject(raw)
            petName = o.optString("petName", petName).ifBlank { "Nino" }
            userName = o.optString("userName", "")
            model = o.optString("model", model).let { if (it in listOf(MODEL_OPUS, MODEL_SONNET, MODEL_HAIKU)) it else MODEL_OPUS }
            voice = o.optBoolean("voice", true)
            chatty = o.optString("chatty", "normal")
            autoHelp = o.optBoolean("autoHelp", false)
            autoHelpMin = o.optInt("autoHelpMin", 5)
            size = o.optInt("size", 1)
            petActive = o.optBoolean("petActive", false)
            food = o.optDouble("food", 80.0); energy = o.optDouble("energy", 85.0); joy = o.optDouble("joy", 75.0)
            statsAt = o.optLong("statsAt", now()); sleeping = o.optBoolean("sleeping", false); xp = o.optInt("xp", 0)
            lastSeen = o.optLong("lastSeen", 0); morningDay = o.optString("morningDay", "")
            tasks.clear()
            o.optJSONArray("tasks")?.let { a ->
                for (i in 0 until a.length()) {
                    val t = a.getJSONObject(i)
                    tasks.add(Task(
                        t.getString("id"), t.getString("title"),
                        if (t.isNull("due")) null else t.getLong("due"),
                        t.optBoolean("done"), if (t.isNull("doneAt")) null else t.optLong("doneAt"),
                        t.optBoolean("notified"), t.optLong("at", now()),
                    ))
                }
            }
            memories.clear()
            o.optJSONArray("memories")?.let { a ->
                for (i in 0 until a.length()) { val m = a.getJSONObject(i); memories.add(Memory(m.getString("id"), m.getString("text"), m.optLong("at"))) }
            }
            chat.clear()
            o.optJSONArray("chat")?.let { a ->
                for (i in 0 until a.length()) {
                    val m = a.getJSONObject(i)
                    chat.add(ChatMsg(m.getString("r"), m.getString("t"), m.optLong("at"), m.optBoolean("img"), m.optBoolean("err")))
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("Nino", "Could not read saved state", e)
        }
    }
}
