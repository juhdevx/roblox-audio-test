package com.ninodebolso.app

import android.Manifest
import android.app.Activity
import android.app.TimePickerDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.util.Calendar

/** Home screen: set Nino up, release it onto the screen, and manage its brain, tasks and memories. */
class MainActivity : Activity() {
    private lateinit var p: Pal
    private lateinit var col: LinearLayout
    private lateinit var heroPet: PetView
    private lateinit var title: TextView
    private lateinit var levelText: TextView
    private lateinit var bars: Map<String, Pair<TextView, View>>
    private lateinit var mainBtn: TextView
    private lateinit var setupBox: LinearLayout
    private lateinit var taskBox: LinearLayout
    private lateinit var memBox: LinearLayout
    private lateinit var keyInput: EditText
    private lateinit var keyStatus: TextView
    private var pendingDue: Long? = null
    private var wantStart = false
    private val reqNotif = 21

    private val storeL: () -> Unit = { refresh() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        p = pal(this)
        col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(32))
        }
        val scroll = ScrollView(this).apply {
            setBackgroundColor(p.bg)
            addView(col)
        }
        buildHero()
        buildSetup()
        buildBrain()
        buildPersonality()
        buildTasks()
        buildMemory()
        buildAbout()
        setContentView(scroll)
        edgeToEdge(scroll)
    }

    override fun onResume() {
        super.onResume()
        PetService.instance?.setOverlayVisible(false)
        Store.listen(storeL)
        refresh()
        if (wantStart && Settings.canDrawOverlays(this)) { wantStart = false; release() }
    }

    override fun onPause() {
        Store.unlisten(storeL)
        PetService.instance?.setOverlayVisible(true)
        super.onPause()
    }

    // --------------------------------------------------------------- small builders
    private fun card(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16), dp(14), dp(16), dp(16))
        background = rounded(p.surface, dpf(22))
        col.addView(this, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
    }

    private fun h2(parent: LinearLayout, text: String) = TextView(this).apply {
        this.text = text
        setTextColor(p.ink)
        textSize = 18f
        typeface = Typeface.DEFAULT_BOLD
        parent.addView(this)
    }

    private fun note(parent: LinearLayout, text: String, top: Int = 4) = TextView(this).apply {
        this.text = text
        setTextColor(p.muted)
        textSize = 14f
        setLineSpacing(0f, 1.1f)
        parent.addView(this, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(top) })
    }

    private fun label(parent: LinearLayout, text: String) = TextView(this).apply {
        this.text = text.uppercase()
        setTextColor(p.muted)
        textSize = 11.5f
        letterSpacing = 0.08f
        typeface = Typeface.DEFAULT_BOLD
        parent.addView(this, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
    }

    private fun button(text: String, primary: Boolean, onClick: () -> Unit) = TextView(this).apply {
        this.text = text
        gravity = Gravity.CENTER
        textSize = 15f
        typeface = Typeface.DEFAULT_BOLD
        setPadding(dp(16), dp(11), dp(16), dp(11))
        setTextColor(if (primary) p.accentInk else p.accent)
        background = rounded(if (primary) p.accent else p.accentSoft, dpf(14))
        setOnClickListener { onClick() }
    }

    private fun input(hint: String, value: String, password: Boolean = false) = EditText(this).apply {
        this.hint = hint
        setText(value)
        setTextColor(p.ink)
        setHintTextColor(p.muted)
        textSize = 15f
        setSingleLine()
        if (password) inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        setPadding(dp(12), dp(10), dp(12), dp(10))
        background = rounded(p.surface2, dpf(12), p.line, dp(1))
    }

    private fun segmented(parent: LinearLayout, options: List<Pair<String, String>>, selected: () -> String, onPick: (String) -> Unit) {
        val flow = FlowLayout(this)
        fun paint() {
            for (i in 0 until flow.childCount) {
                val v = flow.getChildAt(i) as TextView
                val on = v.tag == selected()
                v.setTextColor(if (on) p.accentInk else p.ink)
                v.background = rounded(if (on) p.accent else p.surface, dpf(99), if (on) p.accent else p.line, dp(1))
                v.typeface = if (on) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            }
        }
        options.forEach { (value, text) ->
            flow.addView(TextView(this).apply {
                this.text = text
                tag = value
                textSize = 14f
                setPadding(dp(14), dp(8), dp(14), dp(8))
                setOnClickListener { onPick(value); paint() }
            })
        }
        paint()
        parent.addView(flow, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
    }

    private fun switchRow(parent: LinearLayout, text: String, value: Boolean, onChange: (Boolean) -> Unit) {
        val s = Switch(this).apply {
            this.text = text
            setTextColor(p.ink)
            textSize = 15f
            isChecked = value
            setOnCheckedChangeListener { _: CompoundButton, v: Boolean -> onChange(v) }
        }
        parent.addView(s, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
    }

    // --------------------------------------------------------------- sections
    private fun buildHero() {
        val c = card()
        val top = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        heroPet = PetView(this)
        heroPet.setOnClickListener {
            heroPet.hearts(3)
            heroPet.express(listOf("carinhoso", "animado", "brincalhao").random(), 2200)
            heroPet.wave()
        }
        top.addView(heroPet, LinearLayout.LayoutParams(dp(128), dp(136)))
        val info = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        title = TextView(this).apply { setTextColor(p.ink); textSize = 28f; typeface = Typeface.DEFAULT_BOLD }
        levelText = TextView(this).apply { setTextColor(p.muted); textSize = 13f }
        info.addView(title)
        info.addView(levelText)
        val m = mutableMapOf<String, Pair<TextView, View>>()
        listOf("food" to "Barriga", "energy" to "Energia", "joy" to "Alegria").forEach { (k, name) ->
            val row = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            val lbl = TextView(this).apply { text = name; setTextColor(p.muted); textSize = 11.5f; typeface = Typeface.DEFAULT_BOLD }
            val track = LinearLayout(this).apply { background = rounded(p.line, dpf(9)) }
            val fillV = View(this).apply { background = rounded(p.good, dpf(9)) }
            track.addView(fillV, LinearLayout.LayoutParams(0, dp(7)))
            row.addView(lbl)
            row.addView(track, LinearLayout.LayoutParams(-1, dp(7)).apply { topMargin = dp(3) })
            info.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
            m[k] = lbl to fillV
        }
        bars = m
        top.addView(info, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(8) })
        c.addView(top)
        mainBtn = button("", true) {
            if (PetService.instance != null) { PetService.instance?.stopPet(); col.postDelayed({ refresh() }, 700) } else release()
        }
        c.addView(mainBtn, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(button("Conversar", false) { startActivity(Intent(this, ChatActivity::class.java)) }, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(button("Olhar a tela", false) { askEyes() }, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(8) })
        c.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
    }

    private fun buildSetup() {
        val c = card()
        h2(c, "Pra ele ficar com você")
        note(c, "O Nino passeia por cima dos outros apps. Libere estas permissões uma vez:")
        setupBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        c.addView(setupBox)
    }

    private fun setupRow(title: String, desc: String, ok: Boolean, action: String, onClick: () -> Unit) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(10), 0, dp(10))
        }
        val text = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        text.addView(TextView(this).apply { this.text = title; setTextColor(p.ink); textSize = 15f; typeface = Typeface.DEFAULT_BOLD })
        text.addView(TextView(this).apply { this.text = desc; setTextColor(p.muted); textSize = 13f })
        row.addView(text, LinearLayout.LayoutParams(0, -2, 1f))
        if (ok) {
            row.addView(TextView(this).apply {
                this.text = "Pronto"
                setTextColor(p.good); textSize = 13f; typeface = Typeface.DEFAULT_BOLD
                setPadding(dp(10), dp(6), dp(10), dp(6))
            })
        } else {
            row.addView(button(action, true, onClick).apply { textSize = 13f; setPadding(dp(12), dp(7), dp(12), dp(7)) })
        }
        setupBox.addView(row)
    }

    private fun buildBrain() {
        val c = card()
        h2(c, "Cérebro de IA")
        note(c, "Pra conversar, entender sua tela e ajudar de verdade, o Nino usa o Claude com uma chave da API da Anthropic. Crie em console.anthropic.com, em API Keys. O uso é cobrado por mensagem na sua conta da Anthropic. Sem chave, ele ainda brinca, come, dorme e lembra das suas tarefas.")
        label(c, "Chave da API")
        keyInput = input("sk-ant-...", Store.apiKey, password = true)
        c.addView(keyInput, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6) })
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(button("Salvar", true) { saveKey(); Toast.makeText(this, "Chave salva", Toast.LENGTH_SHORT).show() }, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(button("Testar", false) {
            saveKey()
            keyStatus.text = "Testando..."
            Brain.ping { ok, msg -> keyStatus.text = if (ok) "Funcionou! ${Store.petName} diz: $msg" else msg; keyStatus.setTextColor(if (ok) p.good else p.bad) }
        }, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(8) })
        c.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
        keyStatus = note(c, "", 8)
        label(c, "Modelo")
        segmented(c, listOf(MODEL_OPUS to "Opus 5.5 (mais esperto)", MODEL_SONNET to "Sonnet 5.5 (equilibrado)", MODEL_HAIKU to "Haiku 5.5 (mais barato)"), { Store.model }) {
            Store.model = it; Store.changed()
        }
        note(c, "A chave fica só neste celular, guardada no app.", 10)
    }

    private fun saveKey() {
        Store.apiKey = keyInput.text.toString().trim()
        Store.changed()
    }

    private fun buildPersonality() {
        val c = card()
        h2(c, "Jeito do Nino")
        label(c, "Nome do pet")
        val pet = input("Nino", Store.petName)
        c.addView(pet, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6) })
        label(c, "Como ele te chama")
        val you = input("Seu nome ou apelido", Store.userName)
        c.addView(you, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6) })
        c.addView(button("Salvar nomes", false) {
            Store.petName = pet.text.toString().trim().take(20).ifBlank { "Nino" }
            Store.userName = you.text.toString().trim().take(30)
            Store.changed()
            Toast.makeText(this, "Salvo", Toast.LENGTH_SHORT).show()
        }, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(8) })
        label(c, "Tamanho na tela")
        segmented(c, listOf("0" to "Pequeno", "1" to "Médio", "2" to "Grande"), { Store.size.toString() }) {
            Store.size = it.toInt(); Store.changed()
        }
        label(c, "Puxar assunto sozinho")
        segmented(c, listOf("muito" to "Muito", "normal" to "Normal", "pouco" to "Pouco", "silencio" to "Silêncio"), { Store.chatty }) {
            Store.chatty = it; Store.changed()
        }
        switchRow(c, "Falar em voz alta", Store.voice) { Store.voice = it; Store.changed(); if (!it) Voice.stop() }
        label(c, "Ajuda automática com a tela")
        switchRow(c, "Dar uma espiada de vez em quando", Store.autoHelp) { Store.autoHelp = it; Store.changed() }
        segmented(c, listOf("2" to "A cada 2 min", "5" to "5 min", "10" to "10 min", "20" to "20 min"), { Store.autoHelpMin.toString() }) {
            Store.autoHelpMin = it.toInt(); Store.changed()
        }
        note(c, "Com “Olhar a tela” ligado, o Nino espia a tela nesse intervalo (só quando ela mudou) e fala apenas se tiver algo útil: um golpe suspeito, uma tradução, um resumo, uma dica. Cada espiada envia uma imagem da tela para a IA e usa sua chave. Apps protegidos, como os de banco, aparecem pretos pra ele.", 8)
    }

    private fun buildTasks() {
        val c = card()
        h2(c, "Lembretes e tarefas")
        note(c, "Também dá pra pedir na conversa: “me lembra de ligar pra minha mãe às 19h”.")
        val title = input("Nova tarefa ou lembrete", "")
        c.addView(title, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(10) })
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        lateinit var whenBtn: TextView
        whenBtn = button("Sem horário", false) {
            val cal = Calendar.getInstance()
            TimePickerDialog(this, { _, hh, mm ->
                val due = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, hh); set(Calendar.MINUTE, mm); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
                }.timeInMillis
                pendingDue = due
                whenBtn.text = fmtDue(due)
            }, cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE), true).show()
        }
        row.addView(whenBtn, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(button("Adicionar", true) {
            val t = title.text.toString().trim()
            if (t.isEmpty()) return@button
            Store.addTask(t, pendingDue)
            title.setText("")
            pendingDue = null
            whenBtn.text = "Sem horário"
        }, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(8) })
        c.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
        taskBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        c.addView(taskBox, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
    }

    private fun buildMemory() {
        val c = card()
        h2(c, "O que o Nino sabe sobre você")
        note(c, "Ele guarda aqui o que aprende nas conversas. Você pode apagar qualquer coisa.")
        val add = input("Ex: gosta de pizza de calabresa", "")
        c.addView(add, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(10) })
        c.addView(button("Guardar", false) {
            if (Store.addMemory(add.text.toString()) != null) add.setText("")
        }, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(8) })
        memBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        c.addView(memBox, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
    }

    private fun buildAbout() {
        val c = card()
        h2(c, "Privacidade")
        note(c, "Conversas, tarefas e memórias ficam neste celular. O que você escreve e as imagens da tela vão para a IA da Anthropic só quando o Nino responde ou espia a tela. Ele só vê a tela depois que você permite no aviso do Android, e para quando você toca em “Parar” no aviso de compartilhamento.")
        note(c, "Se o celular fechar o Nino sozinho, libere o app em “Bateria” (às vezes chamado de “sem restrições”).", 8)
        val reset = button("Apagar tudo e recomeçar", false) {}
        reset.setTextColor(p.bad)
        reset.background = rounded(p.badSoft, dpf(14))
        var armed = false
        reset.setOnClickListener {
            if (!armed) { armed = true; reset.text = "Toque de novo para apagar tudo"; return@setOnClickListener }
            Store.resetAll()
            armed = false
            reset.text = "Apagar tudo e recomeçar"
            Toast.makeText(this, "Tudo apagado. Prazer de novo!", Toast.LENGTH_SHORT).show()
        }
        c.addView(reset, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
    }

    // --------------------------------------------------------------- refresh
    private fun refresh() {
        Store.tick()
        title.text = Store.petName
        levelText.text = "Nível ${Store.level()} · ${(Store.levelProgress() * 100).toInt()}% pro próximo"
        heroPet.level = Store.level()
        heroPet.sleeping = Store.sleeping
        heroPet.face = when { Store.energy < 15 -> "sonolento"; Store.food < 18 -> "fome"; Store.joy < 22 -> "triste"; else -> "feliz" }
        val vals = mapOf("food" to Store.food, "energy" to Store.energy, "joy" to Store.joy)
        val names = mapOf("food" to "Barriga", "energy" to "Energia", "joy" to "Alegria")
        bars.forEach { (k, pair) ->
            val v = vals[k]!!.toInt()
            pair.first.text = "${names[k]} $v%"
            val fillV = pair.second
            val track = fillV.parent as View
            track.post {
                fillV.layoutParams = (fillV.layoutParams as LinearLayout.LayoutParams).apply { width = track.width * v / 100 }
                fillV.background = rounded(if (v < 25) p.bad else if (v < 50) p.warn else p.good, dpf(9))
            }
        }
        val running = PetService.instance != null
        mainBtn.text = if (running) "Guardar o ${Store.petName}" else "Soltar o ${Store.petName} na tela"

        setupBox.removeAllViews()
        setupRow("Aparecer sobre outros apps", "Pra ele andar pela sua tela.", Settings.canDrawOverlays(this), "Permitir") {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
        if (Build.VERSION.SDK_INT >= 33) {
            val ok = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            setupRow("Notificações", "Pros lembretes tocarem mesmo com o app fechado.", ok, "Permitir") {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), reqNotif)
            }
        }
        if (!Reminders.canExact(this)) {
            setupRow("Lembretes na hora exata", "Sem isso o Android pode atrasar os lembretes.", false, "Permitir") {
                Reminders.exactAlarmSettings(this)?.let { startActivity(it) }
            }
        }
        setupRow("Cérebro de IA", if (Brain.hasKey()) "Chave configurada." else "Coloque a chave abaixo.", Brain.hasKey(), "Configurar") {
            keyInput.requestFocus()
        }
        val pm = getSystemService(PowerManager::class.java)
        setupRow("Não deixar o celular fechar o Nino", "Opcional. Ajuda em celulares que economizam bateria demais.", pm.isIgnoringBatteryOptimizations(packageName), "Abrir") {
            try { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) } catch (e: Exception) { }
        }

        taskBox.removeAllViews()
        val open = Store.openTasks()
        if (open.isEmpty()) note(taskBox, "Nada pendente.", 6)
        open.forEach { t -> taskBox.addView(taskRow(t)) }
        val done = Store.tasks.filter { it.done }.sortedByDescending { it.doneAt ?: 0 }
        if (done.isNotEmpty()) {
            label(taskBox, "Feitas")
            done.take(8).forEach { t -> taskBox.addView(taskRow(t)) }
            taskBox.addView(button("Limpar feitas", false) { Store.clearDone() }, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(8) })
        }

        memBox.removeAllViews()
        if (Store.memories.isEmpty()) note(memBox, "Ainda nada. Conte seus gostos e metas na conversa.", 6)
        Store.memories.reversed().forEach { m ->
            memBox.addView(itemRow(m.text, null, false, null) { Store.removeMemory(m.id) })
        }
    }

    private fun taskRow(t: Task): View {
        val late = !t.done && (t.due ?: Long.MAX_VALUE) < now()
        val sub = t.due?.let { (if (late) "atrasada · " else "") + fmtDue(it) }
        return itemRow(t.title, sub, t.done, { if (t.done) Store.reopenTask(t.id) else if (Store.completeTask(t.id)) PetService.instance?.cheer() }) {
            Store.removeTask(t.id)
        }.also { if (late) (it.findViewWithTag<TextView>("sub"))?.setTextColor(p.bad) }
    }

    private fun itemRow(text: String, sub: String?, done: Boolean, onCheck: (() -> Unit)?, onDelete: () -> Unit): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), 0, dp(8))
        }
        if (onCheck != null) {
            row.addView(TextView(this).apply {
                this.text = if (done) "✓" else ""
                gravity = Gravity.CENTER
                setTextColor(p.accentInk)
                typeface = Typeface.DEFAULT_BOLD
                background = rounded(if (done) p.accent else 0, dpf(9), p.accent, dp(2))
                setOnClickListener { onCheck() }
                contentDescription = if (done) "Desmarcar" else "Concluir"
            }, LinearLayout.LayoutParams(dp(28), dp(28)).apply { rightMargin = dp(12) })
        }
        val texts = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        texts.addView(TextView(this).apply {
            this.text = text
            setTextColor(if (done) p.muted else p.ink)
            textSize = 15f
            if (done) paintFlags = paintFlags or android.graphics.Paint.STRIKE_THRU_TEXT_FLAG
        })
        if (sub != null) texts.addView(TextView(this).apply { this.text = sub; tag = "sub"; setTextColor(p.muted); textSize = 12.5f })
        row.addView(texts, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(TextView(this).apply {
            this.text = "Apagar"
            setTextColor(p.muted)
            textSize = 12.5f
            setPadding(dp(10), dp(6), dp(4), dp(6))
            setOnClickListener { onDelete() }
        })
        return row
    }

    // --------------------------------------------------------------- actions
    private fun release() {
        if (!Settings.canDrawOverlays(this)) {
            wantStart = true
            Toast.makeText(this, "Ative “${getString(R.string.app_name)}” na lista e volte aqui.", Toast.LENGTH_LONG).show()
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
            return
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), reqNotif)
        }
        Store.petActive = true
        Store.changed()
        PetService.start(this)
        // Go to the home screen so the pet can be seen walking around.
        moveTaskToBack(true)
    }

    private fun askEyes() {
        if (!Settings.canDrawOverlays(this)) { release(); return }
        startActivity(Intent(this, CaptureActivity::class.java).putExtra("look", false))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refresh()
    }
}
