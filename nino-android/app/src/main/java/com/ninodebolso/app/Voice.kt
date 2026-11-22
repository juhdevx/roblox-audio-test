package com.ninodebolso.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

class NinoApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Store.init(this)
        Notifs.channels(this)
        Voice.init(this)
    }
}

object Notifs {
    const val PET = "pet"
    const val REMIND = "lembretes"
    const val PET_ID = 1

    fun channels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(PET, "Nino na tela", NotificationManager.IMPORTANCE_MIN).apply {
            description = "Aviso fixo enquanto o Nino passeia pela tela."
            setShowBadge(false)
        })
        nm.createNotificationChannel(NotificationChannel(REMIND, "Lembretes", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Lembretes que você pediu ao Nino."
            enableVibration(true)
        })
    }
}

/** The pet's voice, using the phone's own text-to-speech in Brazilian Portuguese. */
object Voice {
    private var tts: TextToSpeech? = null
    var ready = false
        private set
    private val listeners = LinkedHashSet<(Boolean) -> Unit>()

    fun listen(l: (Boolean) -> Unit) { listeners.add(l) }
    fun unlisten(l: (Boolean) -> Unit) { listeners.remove(l) }

    fun init(ctx: Context) {
        if (tts != null) return
        tts = TextToSpeech(ctx.applicationContext) { status ->
            val t = tts ?: return@TextToSpeech
            if (status != TextToSpeech.SUCCESS) return@TextToSpeech
            val r = t.setLanguage(Locale.forLanguageTag("pt-BR"))
            ready = r != TextToSpeech.LANG_MISSING_DATA && r != TextToSpeech.LANG_NOT_SUPPORTED
            t.setPitch(1.55f)
            t.setSpeechRate(1.05f)
            t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) { Main.post { listeners.toList().forEach { it(true) } } }
                override fun onDone(id: String?) { Main.post { listeners.toList().forEach { it(false) } } }
                @Deprecated("Deprecated in Java")
                override fun onError(id: String?) { Main.post { listeners.toList().forEach { it(false) } } }
                override fun onStop(id: String?, interrupted: Boolean) { Main.post { listeners.toList().forEach { it(false) } } }
            })
        }
    }

    fun speak(text: String) {
        if (!Store.voice || !ready) return
        var s = text.replace(Regex("```[\\s\\S]*?```"), " ").replace(Regex("[*_`#>]"), "").replace(Regex("\\s+"), " ").trim()
        if (s.length > 700) {
            val cut = s.take(700)
            val end = maxOf(cut.lastIndexOf(". "), cut.lastIndexOf("! "), cut.lastIndexOf("? "))
            s = (if (end > 200) cut.take(end + 1) else cut) + " O resto tá escrito na conversa."
        }
        if (s.isEmpty()) return
        tts?.speak(s, TextToSpeech.QUEUE_FLUSH, null, "nino-" + now())
    }

    fun stop() { tts?.stop(); listeners.toList().forEach { it(false) } }
}
