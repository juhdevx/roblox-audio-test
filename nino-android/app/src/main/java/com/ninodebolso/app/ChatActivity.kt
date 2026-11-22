package com.ninodebolso.app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.speech.RecognizerIntent
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.ByteArrayOutputStream
import kotlin.math.max

/** The conversation with Nino: type, talk, or show a picture of the screen. */
class ChatActivity : Activity() {
    private lateinit var p: Pal
    private lateinit var root: LinearLayout
    private lateinit var list: LinearLayout
    private lateinit var scroll: ScrollView
    private lateinit var input: EditText
    private lateinit var headPet: PetView
    private lateinit var status: TextView
    private lateinit var attachRow: LinearLayout
    private lateinit var attachThumb: ImageView
    private lateinit var attachText: TextView
    private lateinit var keyBanner: TextView
    private var pending: ByteArray? = null
    private var waiting = false
    private var resumed = false
    private var renderedCount = -1
    private val reqPick = 11
    private val reqSpeech = 12

    private val voiceL: (Boolean) -> Unit = { headPet.talking = it }
    private val storeL: () -> Unit = {
        if (Store.chat.size != renderedCount) render()
        keyBanner.visibility = if (Brain.hasKey()) View.GONE else View.VISIBLE
        headPet.level = Store.level()
        if (headPet.look != Store.look) headPet.look = Store.look
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        p = pal(this)
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(p.bg)
        }
        root.addView(header())
        keyBanner = TextView(this).apply {
            text = "Cérebro próprio ligado: pesquisa na Wikipédia, clima, contas e lembretes. Toque aqui para colocar a chave do Claude e deixar o ${Store.petName} bem mais esperto."
            setTextColor(p.ink)
            textSize = 14f
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = rounded(p.accentSoft, dpf(14))
            setOnClickListener { startActivity(Intent(this@ChatActivity, MainActivity::class.java)) }
        }
        root.addView(keyBanner, LinearLayout.LayoutParams(-1, -2).apply { setMargins(dp(14), 0, dp(14), dp(6)) })
        list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(8), dp(14), dp(12))
        }
        scroll = ScrollView(this).apply {
            isFillViewport = true
            addView(list)
        }
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(attachBar())
        root.addView(composer())
        setContentView(root)
        edgeToEdge(root)
        headPet.level = Store.level()
        render()
        offerScreen()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        PetService.instance?.setOverlayVisible(false)
        Store.listen(storeL)
        Voice.listen(voiceL)
        storeL()
    }

    override fun onPause() {
        resumed = false
        Store.unlisten(storeL)
        Voice.unlisten(voiceL)
        PetService.instance?.setOverlayVisible(true)
        super.onPause()
    }

    // --------------------------------------------------------------- building the screen
    private fun header(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(6), dp(8), dp(6))
        }
        headPet = PetView(this)
        headPet.look = Store.look
        headPet.setOnClickListener { headPet.hearts(3); headPet.express("carinhoso", 2000) }
        row.addView(headPet, LinearLayout.LayoutParams(dp(64), dp(68)))
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        col.addView(TextView(this).apply {
            text = Store.petName
            setTextColor(p.ink)
            textSize = 20f
            typeface = Typeface.DEFAULT_BOLD
        })
        status = TextView(this).apply {
            text = "online, pronto pra ajudar"
            setTextColor(p.muted)
            textSize = 13f
        }
        col.addView(status)
        row.addView(col, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(6) })
        row.addView(iconButton(R.drawable.ic_close, "Fechar", p.ink, 0) { finish() })
        return row
    }

    private fun iconButton(icon: Int, desc: String, tint: Int, bg: Int, onClick: () -> Unit) = ImageView(this).apply {
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(tint)
        contentDescription = desc
        scaleType = ImageView.ScaleType.CENTER
        if (bg != 0) background = rounded(bg, dpf(99))
        layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
        setOnClickListener { onClick() }
    }

    private fun attachBar(): View {
        attachRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(6), dp(6), dp(6))
            background = rounded(p.surface, dpf(14), p.line, dp(1))
            visibility = View.GONE
        }
        attachThumb = ImageView(this).apply { scaleType = ImageView.ScaleType.CENTER_CROP }
        attachRow.addView(attachThumb, LinearLayout.LayoutParams(dp(44), dp(44)))
        attachText = TextView(this).apply { setTextColor(p.ink); textSize = 14f }
        attachRow.addView(attachText, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(10) })
        attachRow.addView(iconButton(R.drawable.ic_close, "Remover imagem", p.muted, 0) { clearAttach() })
        val wrap = LinearLayout(this).apply { setPadding(dp(12), 0, dp(12), dp(6)) }
        wrap.addView(attachRow, LinearLayout.LayoutParams(-1, -2))
        return wrap
    }

    private fun composer(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
            setPadding(dp(6), dp(4), dp(6), dp(4))
            background = rounded(p.surface, dpf(26), p.line, dp(1))
        }
        row.addView(iconButton(R.drawable.ic_image, "Mostrar uma imagem", p.muted, 0) { pickImage() })
        input = EditText(this).apply {
            hint = "Fala com o ${Store.petName}..."
            setHintTextColor(p.muted)
            setTextColor(p.ink)
            textSize = 16f
            background = null
            maxLines = 5
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            imeOptions = EditorInfo.IME_ACTION_SEND
            setPadding(dp(6), dp(10), dp(6), dp(10))
            setOnEditorActionListener { _, action, ev ->
                if (action == EditorInfo.IME_ACTION_SEND || (ev?.keyCode == KeyEvent.KEYCODE_ENTER && ev.action == KeyEvent.ACTION_DOWN && !ev.isShiftPressed)) {
                    send(text.toString()); true
                } else false
            }
        }
        row.addView(input, LinearLayout.LayoutParams(0, -2, 1f))
        if (speechAvailable()) row.addView(iconButton(R.drawable.ic_mic, "Falar", p.muted, 0) { listen() })
        row.addView(iconButton(R.drawable.ic_send, "Enviar", p.accentInk, p.accent) { send(input.text.toString()) })
        val wrap = LinearLayout(this).apply { setPadding(dp(10), 0, dp(10), dp(10)) }
        wrap.addView(row, LinearLayout.LayoutParams(-1, -2))
        return wrap
    }

    // --------------------------------------------------------------- messages
    private fun render() {
        renderedCount = Store.chat.size
        list.removeAllViews()
        if (Store.chat.isEmpty()) {
            list.addView(TextView(this).apply {
                text = "Fala com o ${Store.petName}"
                setTextColor(p.ink); textSize = 19f; typeface = Typeface.DEFAULT_BOLD
            })
            list.addView(TextView(this).apply {
                text = if (Brain.hasKey() && Store.brainMode != "proprio")
                    "Ele conversa, tira dúvidas, pesquisa na internet, escreve mensagens, cria lembretes e olha a sua tela quando você pede. Experimente:"
                else
                    "Com o cérebro próprio ele pesquisa na Wikipédia, vê o clima, faz contas, cria lembretes e aprende o que você ensinar. Experimente:"
                setTextColor(p.muted); textSize = 14.5f
                setPadding(0, dp(6), 0, dp(10))
            })
            val chips = FlowLayout(this)
            listOf(
                "O que é um buraco negro?",
                "Me lembra de beber água daqui 30 minutos",
                "Como tá o tempo em São Paulo?",
                "Quando eu falar bom dia, responde bom dia, flor do dia!",
                "Quanto é 15% de 80?",
                "O que você sabe fazer?",
            ).forEach { s ->
                chips.addView(TextView(this).apply {
                    text = s
                    setTextColor(p.ink); textSize = 14f
                    setPadding(dp(12), dp(8), dp(12), dp(8))
                    background = rounded(p.surface, dpf(99), p.line, dp(1))
                    setOnClickListener { send(s) }
                })
            }
            list.addView(chips)
        }
        val maxW = (resources.displayMetrics.widthPixels * 0.8f).toInt()
        Store.chat.forEach { m -> list.addView(messageView(m, maxW)) }
        if (waiting) {
            list.addView(bubbleFor(false, false, maxW).apply { addView(TextView(this@ChatActivity).apply { text = "..."; setTextColor(p.muted); textSize = 18f }) })
        }
        scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
    }

    private fun bubbleFor(mine: Boolean, note: Boolean, maxW: Int): LinearLayout {
        val b = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = rounded(
                when { mine -> p.accent; note -> p.accentSoft; else -> p.surface }, dpf(18),
                if (mine) p.accent else p.line, if (mine) 0 else dp(1),
            )
        }
        b.layoutParams = LinearLayout.LayoutParams(-2, -2).apply {
            gravity = if (mine) Gravity.END else Gravity.START
            topMargin = dp(8)
        }
        b.minimumWidth = dp(40)
        return b
    }

    private fun messageView(m: ChatMsg, maxW: Int): View {
        val mine = m.role == "u"
        val b = bubbleFor(mine, m.role == "s", maxW)
        val ink = if (mine) p.accentInk else if (m.err) p.bad else p.ink
        if (m.img) b.addView(TextView(this).apply {
            text = "imagem da tela"
            setTextColor(ink); alpha = 0.8f; textSize = 12f; typeface = Typeface.DEFAULT_BOLD
        })
        b.addView(TextView(this).apply {
            text = m.text
            setTextColor(ink)
            textSize = 15.5f
            maxWidth = maxW - dp(24)
            setTextIsSelectable(true)
        })
        if (m.links.isNotEmpty()) {
            val row = FlowLayout(this)
            m.links.forEach { (label, url) ->
                row.addView(TextView(this).apply {
                    text = label
                    textSize = 13.5f
                    typeface = Typeface.DEFAULT_BOLD
                    setPadding(dp(12), dp(6), dp(12), dp(6))
                    setTextColor(p.accent)
                    background = rounded(p.accentSoft, dpf(99))
                    setOnClickListener { openLink(url) }
                })
            }
            b.addView(row, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(8) })
        }
        b.setOnLongClickListener {
            getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Nino", m.text))
            Toast.makeText(this, "Copiado", Toast.LENGTH_SHORT).show()
            true
        }
        return b
    }

    private fun openLink(url: String) {
        try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (e: Exception) {
            Toast.makeText(this, "Não achei um navegador pra abrir.", Toast.LENGTH_SHORT).show()
        }
    }

    // --------------------------------------------------------------- sending
    private fun send(raw: String) {
        val text = raw.trim()
        val img = pending
        if (text.isEmpty() && img == null) return
        if (waiting) { Toast.makeText(this, "Peraí, ainda tô pensando...", Toast.LENGTH_SHORT).show(); return }
        val shown = if (text.isEmpty()) "O que você vê nessa imagem? Me ajuda com isso." else text
        Store.addChat(ChatMsg("u", shown, img = img != null))
        input.setText("")
        clearAttach()
        waiting = true
        status.text = "pensando..."
        headPet.express("pensativo", 120_000)
        render()
        Brain.chat(shown, img) { r ->
            waiting = false
            Store.addChat(ChatMsg("p", r.text, err = r.error, links = r.links))
            status.text = "online, pronto pra ajudar"
            headPet.express(r.emotion ?: "feliz", 4000)
            if (Store.level() > 0) headPet.level = Store.level()
            render()
            if (resumed) {
                if (!r.error) Voice.speak(r.text)
            } else {
                PetService.instance?.say(r.text, r.emotion, speak = !r.error)
            }
        }
    }

    /** Offers the screenshot the pet just took; nothing is attached until the person taps it. */
    private fun offerScreen() {
        val shot = PetService.lastScreen ?: return
        if (now() - PetService.lastScreenAt > 3 * 60_000) return
        attachThumb.setImageBitmap(BitmapFactory.decodeByteArray(shot, 0, shot.size))
        attachText.text = "Quer que eu veja o que estava na tela? Toque aqui para anexar."
        attachText.setTextColor(p.accent)
        attachRow.visibility = View.VISIBLE
        attachRow.setOnClickListener { setAttach(shot, "Tela anexada. Pergunte algo sobre ela, ou só envie.") }
    }

    private fun setAttach(jpeg: ByteArray, label: String) {
        pending = jpeg
        attachThumb.setImageBitmap(BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size))
        attachText.text = label
        attachText.setTextColor(p.ink)
        attachRow.setOnClickListener(null)
        attachRow.visibility = View.VISIBLE
    }

    private fun clearAttach() {
        pending = null
        attachRow.visibility = View.GONE
        attachRow.setOnClickListener(null)
        attachThumb.setImageDrawable(null)
    }

    private fun pickImage() {
        val i = Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
        try { startActivityForResult(i, reqPick) } catch (e: Exception) { Toast.makeText(this, "Não achei um app de fotos.", Toast.LENGTH_SHORT).show() }
    }

    private fun speechIntent() = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-BR")
        .putExtra(RecognizerIntent.EXTRA_PROMPT, "Fala com o ${Store.petName}")

    private fun speechAvailable() = packageManager.queryIntentActivities(speechIntent(), 0).isNotEmpty()

    private fun listen() {
        try { startActivityForResult(speechIntent(), reqSpeech) } catch (e: Exception) { Toast.makeText(this, "O reconhecimento de voz não está disponível.", Toast.LENGTH_SHORT).show() }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK || data == null) return
        when (requestCode) {
            reqSpeech -> {
                val said = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() ?: return
                send(said)
            }
            reqPick -> {
                val uri = data.data ?: return
                Thread {
                    val bytes = loadJpeg(uri)
                    runOnUiThread {
                        if (bytes == null) Toast.makeText(this, "Não consegui abrir essa imagem.", Toast.LENGTH_SHORT).show()
                        else setAttach(bytes, "Imagem pronta. Escreva o que quer saber, ou só envie.")
                    }
                }.start()
            }
        }
    }

    private fun loadJpeg(uri: Uri): ByteArray? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1568) sample *= 2
        val bmp = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
        if (bmp == null) null else {
            val longSide = max(bmp.width, bmp.height)
            val scaled = if (longSide > 1568) Bitmap.createScaledBitmap(bmp, bmp.width * 1568 / longSide, bmp.height * 1568 / longSide, true) else bmp
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
            out.toByteArray()
        }
    } catch (e: Exception) {
        null
    }
}
