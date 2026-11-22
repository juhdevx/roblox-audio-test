package com.ninodebolso.app

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

/** What the person asked, as Nino's own brain understood it. */
sealed class Ask {
    data class Teach(val q: String, val a: String) : Ask()
    data class Fact(val text: String) : Ask()
    data class Forget(val what: String) : Ask()
    object ListLearned : Ask()
    data class SetName(val name: String) : Ask()
    object MyName : Ask()
    object AboutMe : Ask()
    data class Remember(val text: String, val city: String?) : Ask()
    data class Remind(val title: String, val due: Long?) : Ask()
    object ListTasks : Ask()
    data class Complete(val what: String) : Ask()
    object Time : Ask()
    object Today : Ask()
    data class Calc(val expr: String, val value: Double) : Ask()
    data class Weather(val city: String?, val tomorrow: Boolean) : Ask()
    data class Search(val query: String, val google: Boolean) : Ask()
    data class Small(val kind: String) : Ask()
    object Unknown : Ask()
}

/**
 * Nino's own brain: runs on the phone, free, no API key. It understands common requests in Portuguese,
 * learns answers you teach it, and looks things up in what people already wrote: Wikipedia,
 * DuckDuckGo answers and the Open-Meteo weather service. It can also open a Google search for you.
 */
object OwnBrain {
    private val exec = Executors.newSingleThreadExecutor()
    private const val UA = "NinoDeBolso/1.1 (Android; bichinho virtual)"

    // ------------------------------------------------------------------ text helpers

    /** Lowercase without accents, keeping the same length as the input so indices line up. */
    fun norm(s: String): String {
        val sb = StringBuilder(s.length)
        for (ch in s) {
            val d = Normalizer.normalize(ch.toString(), Normalizer.Form.NFD)
            sb.append(d[0].lowercaseChar())
        }
        return sb.toString()
    }

    private val STOP = setOf(
        "o", "a", "os", "as", "um", "uma", "de", "do", "da", "dos", "das", "e", "que", "eu", "voce", "vc", "me", "te",
        "pra", "para", "por", "com", "no", "na", "em", "se", "meu", "minha", "seu", "sua", "nino", "ei", "oi", "ne", "ta", "tá",
    )

    fun words(s: String): Set<String> =
        norm(s).split(Regex("[^a-z0-9]+")).filter { it.isNotBlank() && it !in STOP }.toSet()

    fun similarity(a: String, b: String): Double {
        val na = norm(a).replace(Regex("[^a-z0-9 ]"), "").trim()
        val nb = norm(b).replace(Regex("[^a-z0-9 ]"), "").trim()
        if (na.isEmpty() || nb.isEmpty()) return 0.0
        if (na == nb) return 1.0
        val wa = words(a)
        val wb = words(b)
        if (wa.isEmpty() || wb.isEmpty()) return 0.0
        val inter = wa.intersect(wb).size.toDouble()
        return inter / wa.union(wb).size
    }

    private fun cap(s: String) = s.trim().trim('"', '“', '”', '\'', '.', ',', '!', '?', ' ')

    private fun slice(orig: String, r: IntRange?): String = if (r == null || r.isEmpty()) "" else orig.substring(r.first, r.last + 1)

    private val NUM = mapOf(
        "um" to 1, "uma" to 1, "dois" to 2, "duas" to 2, "tres" to 3, "quatro" to 4, "cinco" to 5, "seis" to 6, "sete" to 7,
        "oito" to 8, "nove" to 9, "dez" to 10, "onze" to 11, "doze" to 12, "quinze" to 15, "vinte" to 20, "trinta" to 30,
        "quarenta" to 40, "cinquenta" to 50, "sessenta" to 60, "meia" to 30,
    )

    // ------------------------------------------------------------------ understanding

    private val RX_TEACH = Regex(
        "^(?:quando|se|toda vez que|sempre que) (?:eu |alguem |a gente )?(?:te )?(?:falar|disser|digo|perguntar|mandar|escrever|falo)\\s+[\"“']?(.+?)[\"”']?\\s*[,;:]?\\s+(?:voce |vc |tu )?(?:responde|responda|diz|diga|fala|fale|respondes|me responde|me diz)\\s*(?:que |assim:?\\s*|:\\s*)?[\"“']?(.+?)[\"”']?$"
    )
    private val RX_FACT = Regex("^(?:aprende|aprenda|aprender|grava|guarda) (?:que|isso:?|isto:?) (.+)$")
    private val RX_FORGET = Regex("^(?:esquece|esqueca|esquecer|desaprende) (?:o que eu te ensinei sobre |que |sobre |de |o |a )?(.+)$")
    private val RX_LEARNED = Regex("(o que (voce|vc) (aprendeu|sabe de mim|lembra de mim)|o que (eu )?te ensinei|suas memorias|o que (voce|vc) sabe sobre mim)")
    private val RX_NAME = Regex("(?:meu nome e|me chamo|pode me chamar de|me chama de|me chame de)\\s+([a-z]+(?:\\s+[a-z]+)?)")
    private val RX_MYNAME = Regex("(qual (e )?(o )?meu nome|(voce|vc) sabe (o )?meu nome|como eu me chamo)")
    private val RX_ABOUT = Regex("(qual (e )?(o )?seu nome|como (voce|vc) se chama|quem e (voce|vc)|quem (voce|vc) e|o que (voce|vc) (e|faz|sabe fazer)|como (voce|vc) funciona|(voce|vc) e (uma )?(ia|inteligencia artificial|robo)|que (voce|vc) sabe fazer)")
    private val RX_REMEMBER = Regex("^(?:lembra|lembre|lembrar|grava|anota|guarda) (?:que|disso:?) (.+)$")
    private val RX_ABOUT_USER = Regex("^(eu (gosto|amo|adoro|odeio|moro|trabalho|estudo|curto|prefiro|torco|tenho \\d+ anos)\\b.+|(minha|meu) .*(favorit|aniversario).+)$")
    private val RX_CITY = Regex("\\bmoro (?:em|no|na) ([a-z ]+?)(?:[,.!]|$| e )")
    private val TIME_UNIT = "(minutos?|mins?|min|m|horas?|hrs?|h|segundos?)"
    private val NUM_WORD = "(\\d+|um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez|onze|doze|quinze|vinte|trinta|quarenta|cinquenta|sessenta|meia)"
    private val RX_REMIND_REL = Regex(
        "^(?:(?:por favor|ei|nino)[, ]+)?(?:me |pode me |(?:voce|vc) pode me )?(?:lembra|lembre|lembrar|avisa|avise|avisar|acorda|acorde)(?:-me| me)?\\s*(?:de |da |do |que |pra |para |sobre )?(.*?)\\s*(?:daqui a|daqui|em|dentro de)\\s+$NUM_WORD\\s*$TIME_UNIT?(?![a-z])(.*)$"
    )
    private val RX_REMIND_ABS = Regex(
        "^(?:(?:por favor|ei|nino)[, ]+)?(?:me |pode me |(?:voce|vc) pode me )?(?:lembra|lembre|lembrar|avisa|avise|avisar|acorda|acorde)(?:-me| me)?\\s*(?:de |da |do |que |pra |para |sobre )?(.*?)\\s*(?:amanha\\s+)?(?:hoje\\s+)?(?:as|a|ao|pras|para as)\\s+(\\d{1,2})(?:(?::|h|\\s?e\\s?)(\\d{2}))?\\s*(?:h|hs|hrs|horas)?(?:\\s*(?:da|de)\\s+(manha|tarde|noite|madrugada))?(.*)$"
    )
    private val RX_REMIND_NOON = Regex("^(?:me |pode me )?(?:lembra|lembre|lembrar|avisa|avise)(?:-me| me)?\\s*(?:de |da |do |pra |para )?(.*?)\\s*(?:amanha\\s+)?(?:ao |a |as )?(meio[- ]dia|meia[- ]noite)(.*)$")
    private val RX_REMIND_TASK = Regex("^(?:me |pode me )?(?:lembra|lembre|lembrar|avisa|avise)(?:-me| me)? (?:de|da|do|pra|para) (.+)$")
    private val RX_ADD_TASK = Regex("^(?:anota|anote|adiciona|adicione|coloca|coloque|bota|poe)(?: ai)?(?: na (?:minha )?lista)?:? (.+?)(?: na (?:minha )?lista)?$")
    private val RX_LIST_TASKS = Regex("((quais|quais sao|ver|mostra|me (fala|diz)) (as )?(minhas )?(tarefas|lembretes)|o que (eu )?(tenho|preciso) (pra|para|de) fazer|minha lista|meus lembretes|minhas tarefas)")
    private val RX_COMPLETE = Regex("^(?:ja )?(?:terminei|fiz|conclui|acabei|finalizei|completei)\\s+(?:de\\s+|a tarefa\\s+|o\\s+|a\\s+)?(.+)$")
    private val RX_TIME = Regex("(que horas|horas sao|que hora e|qual a hora)")
    private val RX_DATE = Regex("(que dia e hoje|qual a data|que data e hoje|dia de hoje|hoje e que dia|que dia e amanha)")
    private val RX_WEATHER = Regex("(como (esta|ta|vai estar|fica) o (tempo|clima)|previsao do tempo|previsao (para|pra|de) |vai chover|vai fazer (frio|calor|sol)|temperatura|qual o clima|clima (em|no|na|de|hoje|amanha|agora)|tempo (em|no|na|hoje|amanha|agora|la fora)|(ta|esta) (frio|calor|chovendo) (em|no|na|la))")
    private val RX_WEATHER_CITY = Regex("(?: em | no | na | de | para | pra )([a-z][a-z ]{1,40}?)\\s*(?:hoje|amanha|agora)?\\s*$")

    private val SEARCH_PREFIX = listOf(
        "pesquisa no google sobre ", "pesquisa no google ", "pesquise no google ", "busca no google ", "procura no google ", "no google ",
        "pesquisa na internet sobre ", "pesquisa na internet ", "pesquisa sobre ", "pesquise sobre ", "pesquisa ", "pesquise ", "pesquisar ",
        "procura sobre ", "procura ", "procure ", "busca ", "busque ",
        "o que voce sabe sobre ", "o que vc sabe sobre ", "me fala sobre ", "me conta sobre ", "me explica o que e ", "me explica o que sao ",
        "me explica sobre ", "me explica ", "fala sobre ", "explica ", "voce sabe o que e ", "vc sabe o que e ", "voce sabe quem foi ",
        "o que significa ", "significado de ", "significado da palavra ", "o que e um ", "o que e uma ", "o que e o ", "o que e a ",
        "o que e ", "o que sao os ", "o que sao as ", "o que sao ", "quem foi o ", "quem foi a ", "quem foi ", "quem e o ", "quem e a ", "quem e ",
        "quem sao ", "quem foram ", "onde fica o ", "onde fica a ", "onde fica ", "quando foi ", "quando aconteceu ", "como funciona o ",
        "como funciona a ", "como funciona ", "qual e a capital ", "qual a capital ",
    )

    /** Pure parsing, no side effects: easy to test. [now] is the current time in milliseconds. */
    fun understand(raw: String, now: Long = System.currentTimeMillis()): Ask {
        val t = raw.trim().replace(Regex("\\s+"), " ")
        val n = norm(t).trimEnd('?', '!', '.', ' ')
        if (n.isEmpty()) return Ask.Unknown

        RX_TEACH.find(n)?.let { m ->
            val q = cap(slice(t, m.groups[1]?.range))
            // The answer runs to the end of the original text, keeping its final "!" or "?".
            val a = m.groups[2]?.range?.let { t.substring(it.first) }.orEmpty().trim().trim('"', '“', '”', '\'', ' ')
            if (q.isNotEmpty() && a.isNotEmpty()) return Ask.Teach(q, a)
        }
        RX_FACT.find(n)?.let { return Ask.Fact(cap(slice(t, it.groups[1]?.range))) }
        RX_FORGET.find(n)?.let { return Ask.Forget(cap(slice(t, it.groups[1]?.range))) }
        if (RX_LEARNED.containsMatchIn(n)) return Ask.ListLearned
        RX_NAME.find(n)?.let { m ->
            val name = slice(t, m.groups[1]?.range).split(" ").filter { it.isNotBlank() }
                .joinToString(" ") { w -> w.lowercase().replaceFirstChar { it.uppercase() } }
            if (name.isNotEmpty()) return Ask.SetName(name)
        }
        if (RX_MYNAME.containsMatchIn(n)) return Ask.MyName

        parseReminder(t, n, now)?.let { return it }
        RX_REMEMBER.find(n)?.let { m ->
            val text = cap(slice(t, m.groups[1]?.range))
            return Ask.Remember(text, RX_CITY.find(norm(text))?.let { c -> cap(slice(text, c.groups[1]?.range)) })
        }
        RX_ADD_TASK.find(n)?.let { return Ask.Remind(cap(slice(t, it.groups[1]?.range)).replaceFirstChar { c -> c.uppercase() }, null) }
        if (!t.contains('?') && RX_ABOUT_USER.matches(n)) {
            return Ask.Remember(cap(t), RX_CITY.find(n)?.let { c -> cap(slice(t, c.groups[1]?.range)) })
        }

        if (RX_LIST_TASKS.containsMatchIn(n)) return Ask.ListTasks
        RX_COMPLETE.find(n)?.let { return Ask.Complete(cap(slice(t, it.groups[1]?.range))) }
        if (RX_TIME.containsMatchIn(n)) return Ask.Time
        if (RX_DATE.containsMatchIn(n)) return Ask.Today
        calc(n)?.let { return it }

        if (RX_WEATHER.containsMatchIn(n)) {
            val city = RX_WEATHER_CITY.find(n)?.let { cap(slice(t, it.groups[1]?.range)) }
                ?.takeIf { norm(it) !in setOf("hoje", "amanha", "agora", "la fora") }
            return Ask.Weather(city, n.contains("amanha"))
        }
        if (RX_ABOUT.containsMatchIn(n)) return Ask.AboutMe

        small(n)?.let { return Ask.Small(it) }

        val google = n.contains("google")
        for (p in SEARCH_PREFIX) {
            val i = n.indexOf(p)
            if (i == 0 || (i in 1..20 && LEAD.matches(n.substring(0, i)))) {
                val q = cleanQuery(t.substring(i + p.length))
                if (q.isNotEmpty()) return Ask.Search(q, google)
            }
        }
        val questionWords = Regex("^(como|por que|porque|pq|qual|quais|quando|onde|quem|quanto|quantos|quantas|o que)\\b")
        if (t.endsWith("?") || questionWords.containsMatchIn(n)) {
            val q = cleanQuery(t)
            if (q.isNotEmpty()) return Ask.Search(q, google)
        }
        return Ask.Unknown
    }

    private val LEAD = Regex("^((ei|nino|oi|ola|ow|e ai|me diz|me diga|me fala|voce sabe|vc sabe|sabe)[, ]*)+$")

    private fun cleanQuery(s: String): String {
        var q = cap(s)
        q = q.replace(Regex("(?i)\\b(no google|na internet|pra mim|por favor|pfv)\\b"), "").trim()
        q = q.replace(Regex("^(?i)(o|a|os|as|um|uma) "), "")
        return cap(q)
    }

    private fun numberOf(w: String): Int? = w.toIntOrNull() ?: NUM[w]

    private fun parseReminder(t: String, n: String, now: Long): Ask.Remind? {
        RX_REMIND_REL.find(n)?.let { m ->
            val qty = numberOf(m.groupValues[2]) ?: return@let
            val unit = m.groupValues[3]
            var title = cap(slice(t, m.groups[1]?.range))
            if (title.isEmpty()) title = cap(slice(t, m.groups[4]?.range).replace(Regex("^(?i)\\s*(de|da|do|pra|para|que)\\s+"), ""))
            if (title.isEmpty()) title = if (n.contains("acord")) "Acordar" else "Lembrete"
            val minutes = when {
                unit.startsWith("h") -> qty * 60.0
                unit.startsWith("s") -> qty / 60.0
                m.groupValues[2] == "meia" && unit.isEmpty() -> 30.0
                else -> qty.toDouble()
            }
            val mins = if (m.groupValues[2] == "meia" && unit.startsWith("h")) 30.0 else minutes
            return Ask.Remind(title.replaceFirstChar { it.uppercase() }, now + (mins * 60_000).toLong())
        }
        RX_REMIND_NOON.find(n)?.let { m ->
            var title = cap(slice(t, m.groups[1]?.range))
            if (title.isEmpty()) title = cap(slice(t, m.groups[3]?.range).replace(Regex("^(?i)\\s*(de|da|do|pra|para)\\s+"), ""))
            val hour = if (m.groupValues[2].startsWith("meio")) 12 else 0
            return Ask.Remind(title.ifEmpty { "Lembrete" }.replaceFirstChar { it.uppercase() }, at(now, hour, 0, n.contains("amanha"), qualifier = "x"))
        }
        RX_REMIND_ABS.find(n)?.let { m ->
            val h = m.groupValues[2].toIntOrNull() ?: return@let
            if (h > 23) return@let
            val min = m.groupValues[3].toIntOrNull() ?: 0
            if (min > 59) return@let
            var title = cap(slice(t, m.groups[1]?.range))
            if (title.isEmpty()) title = cap(slice(t, m.groups[5]?.range).replace(Regex("^(?i)\\s*(de|da|do|pra|para)\\s+"), ""))
            if (title.isEmpty()) title = if (n.contains("acord")) "Acordar" else "Lembrete"
            title = title.replace(Regex("(?i)\\s*(amanh[ãa]|hoje)$"), "")
            return Ask.Remind(title.replaceFirstChar { it.uppercase() }, at(now, h, min, n.contains("amanha"), m.groupValues[4]))
        }
        RX_REMIND_TASK.find(n)?.let { m ->
            val title = cap(slice(t, m.groups[1]?.range))
            if (title.isNotEmpty()) return Ask.Remind(title.replaceFirstChar { it.uppercase() }, null)
        }
        return null
    }

    /** The next moment at [hour]:[min]; "tarde"/"noite" push it to the afternoon, and a time already gone moves forward. */
    private fun at(now: Long, hour: Int, min: Int, tomorrow: Boolean, qualifier: String): Long {
        var h = hour
        if ((qualifier == "tarde" || qualifier == "noite") && h < 12) h += 12
        val c = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, min); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        if (tomorrow) { c.add(Calendar.DAY_OF_YEAR, 1); return c.timeInMillis }
        if (c.timeInMillis <= now) {
            if (qualifier.isEmpty() && h in 1..11) {
                c.add(Calendar.HOUR_OF_DAY, 12)
                if (c.timeInMillis > now) return c.timeInMillis
                c.add(Calendar.HOUR_OF_DAY, -12)
            }
            c.add(Calendar.DAY_OF_YEAR, 1)
        }
        return c.timeInMillis
    }

    private fun small(n: String): String? = when {
        Regex("^(oi+e?|ola|ei|eai|e ai|opa|salve|bom dia|boa tarde|boa noite|hello|hey|alo)\\b").containsMatchIn(n) && n.length < 30 -> "oi"
        Regex("(tudo bem|tudo bom|como (voce|vc) (esta|ta|vai)|como vai|como ce ta)").containsMatchIn(n) -> "comovai"
        Regex("\\b(obrigad|valeu|vlw|brigad)").containsMatchIn(n) -> "valeu"
        Regex("(te amo|gosto de (voce|vc|ti)|(voce|vc) e (fofo|lindo|demais|o melhor|incrivel)|amo (voce|vc))").containsMatchIn(n) -> "amor"
        Regex("^(tchau|ate mais|ate logo|fui|vou dormir|to indo)\\b").containsMatchIn(n) -> "tchau"
        Regex("(piada|me faz rir|algo engracado)").containsMatchIn(n) -> "piada"
        Regex("(curiosidade|fato interessante|me conta algo|me ensina algo)").containsMatchIn(n) -> "curiosidade"
        Regex("(to|estou|me sinto|me sentindo|ando) (muito |meio |tao )?(triste|ansios|cansad|estressad|mal|sozinh|com medo|preocupad|deprimid|chatead)").containsMatchIn(n) -> "triste"
        Regex("(to|estou) com fome").containsMatchIn(n) -> "fome"
        Regex("((to|estou) entediad|nada pra fazer|to sem fazer nada)").containsMatchIn(n) -> "tedio"
        else -> null
    }

    // ------------------------------------------------------------------ math
    private fun calc(n: String): Ask.Calc? {
        var s = n
        s = s.replace(Regex("^(quanto (que )?(e|da|fica)|calcula|calcule|qual (e )?o resultado de|resolve|resolva|me diz quanto e)\\s*"), "")
        s = s.replace(Regex("(\\d+(?:[.,]\\d+)?)\\s*(?:%|por cento) de\\s*(\\d+(?:[.,]\\d+)?)"), "($1/100*$2)")
        s = s.replace(" vezes ", "*").replace(" multiplicado por ", "*").replace(" dividido por ", "/").replace(" divido por ", "/")
            .replace(" mais ", "+").replace(" menos ", "-").replace(" elevado a ", "^").replace("×", "*").replace("÷", "/")
        s = s.replace(Regex("(\\d)\\s*x\\s*(\\d)"), "$1*$2").replace(Regex("(\\d)\\s*x\\s*(\\d)"), "$1*$2")
        s = s.replace(",", ".").replace(" ", "")
        if (!Regex("^[0-9.+\\-*/^()]+$").matches(s)) return null
        if (!Regex("\\d").containsMatchIn(s) || !Regex("[+\\-*/^]").containsMatchIn(s.drop(1))) return null
        val v = try { Expr(s).parse() } catch (e: Exception) { return null }
        if (v.isNaN() || v.isInfinite()) return null
        return Ask.Calc(s, v)
    }

    private class Expr(val s: String) {
        var i = 0
        fun parse(): Double { val v = sum(); if (i != s.length) throw IllegalArgumentException(); return v }
        fun sum(): Double {
            var v = prod()
            while (i < s.length && (s[i] == '+' || s[i] == '-')) { val op = s[i++]; val r = prod(); v = if (op == '+') v + r else v - r }
            return v
        }
        fun prod(): Double {
            var v = pow()
            while (i < s.length && (s[i] == '*' || s[i] == '/')) { val op = s[i++]; val r = pow(); v = if (op == '*') v * r else v / r }
            return v
        }
        fun pow(): Double { val b = unary(); if (i < s.length && s[i] == '^') { i++; return b.pow(pow()) }; return b }
        fun unary(): Double { if (i < s.length && s[i] == '-') { i++; return -unary() }; return atom() }
        fun atom(): Double {
            if (i < s.length && s[i] == '(') { i++; val v = sum(); if (i >= s.length || s[i] != ')') throw IllegalArgumentException(); i++; return v }
            val st = i
            while (i < s.length && (s[i].isDigit() || s[i] == '.')) i++
            if (st == i) throw IllegalArgumentException()
            return s.substring(st, i).toDouble()
        }
    }

    fun fmtNumber(v: Double): String {
        if (abs(v - v.roundToInt()) < 1e-9 && abs(v) < 1e15) return String.format(Locale("pt", "BR"), "%,d", v.roundToInt().toLong())
        return String.format(Locale("pt", "BR"), "%,.4f", v).trimEnd('0').trimEnd(',')
    }

    // ------------------------------------------------------------------ answering

    private val JOKES = listOf(
        "Qual é o doce preferido do átomo? Pé de molécula!",
        "O que o tomate foi fazer no banco? Tirar extrato!",
        "Por que a vaca foi pro espaço? Pra encontrar a Via Láctea!",
        "Qual é o animal mais antigo? A zebra, porque ela é em preto e branco!",
        "O que o zero disse pro oito? Que cinto bonito!",
        "Por que o livro de matemática vivia triste? Porque tinha muitos problemas!",
    )

    fun googleUrl(q: String) = "https://www.google.com/search?q=" + URLEncoder.encode(q, "UTF-8")

    /** Answers on the main thread; anything that needs the internet runs in the background. */
    fun reply(text: String, onDone: (Reply) -> Unit) {
        val ask = try { understand(text) } catch (e: Exception) { Ask.Unknown }
        val local = try { answerLocal(ask, text) } catch (e: Exception) { null }
        if (local != null) { onDone(local); return }
        exec.execute {
            val r = try { answerOnline(ask, text) } catch (e: Exception) {
                android.util.Log.w("Nino", "own brain lookup failed", e)
                Reply(
                    "Não consegui pesquisar agora... confere a internet? Se quiser, abro no Google.", "triste", true,
                    listOf("Ver no Google" to googleUrl(text)),
                )
            }
            Main.post { onDone(r) }
        }
    }

    /** Things that need no internet; returns null when the answer must be looked up. Main thread. */
    private fun answerLocal(ask: Ask, text: String): Reply? {
        val nm = Store.userName.ifBlank { "" }
        val you = if (nm.isNotEmpty()) ", $nm" else ""
        return when (ask) {
            is Ask.Teach -> {
                Store.addKnowledge(ask.q, ask.a, "ensinado")
                Store.addXp(2)
                Store.changed()
                Reply("Aprendi! Quando você falar “${ask.q}”, eu respondo “${ask.a}”.", "animado")
            }
            is Ask.Fact -> {
                Store.addKnowledge(ask.text, ask.text, "fato")
                Reply("Guardei na minha cabecinha: ${ask.text}", "pensativo")
            }
            is Ask.Forget -> {
                val best = Store.knowledge.maxByOrNull { similarity(it.q, ask.what) }
                val mem = Store.memories.maxByOrNull { similarity(it.text, ask.what) }
                when {
                    best != null && similarity(best.q, ask.what) >= 0.34 -> { Store.removeKnowledge(best.id); Reply("Pronto, esqueci “${best.q}”.", "feliz") }
                    mem != null && similarity(mem.text, ask.what) >= 0.34 -> { Store.removeMemory(mem.id); Reply("Pronto, esqueci que ${mem.text}.", "feliz") }
                    else -> Reply("Não achei isso na minha memória.", "pensativo")
                }
            }
            Ask.ListLearned -> {
                val taught = Store.knowledge.filter { it.kind != "pesquisa" }.takeLast(8)
                val mems = Store.memories.takeLast(6)
                if (taught.isEmpty() && mems.isEmpty()) Reply("Ainda não aprendi nada com você! Me ensina: “quando eu falar oi, responde e aí, parceiro!”", "pensativo")
                else {
                    val lines = mems.map { "• ${it.text}" } + taught.map { if (it.kind == "fato") "• ${it.q}" else "• “${it.q}” → “${it.a}”" }
                    Reply("O que eu sei de você e aprendi:\n" + lines.joinToString("\n"), "carinhoso")
                }
            }
            is Ask.SetName -> {
                Store.userName = ask.name
                Store.changed()
                Reply("Prazer, ${ask.name}! Vou lembrar pra sempre.", "animado")
            }
            Ask.MyName -> if (nm.isNotEmpty()) Reply("Claro! Você é $nm.", "carinhoso") else Reply("Ainda não sei... me fala assim: “meu nome é ...”", "pensativo")
            Ask.AboutMe -> Reply(
                "Eu sou o ${Store.petName}, seu bichinho de bolso! Com meu cérebro próprio eu pesquiso coisas na Wikipédia (“o que é um buraco negro?”), vejo o clima (“tempo em Recife”), faço contas, crio lembretes (“me lembra de beber água às 15h”), guardo o que você me conta e aprendo respostas novas (“quando eu falar X, responde Y”). Com a chave do Claude eu fico bem mais esperto e pesquiso na internet inteira.",
                "animado",
            )
            is Ask.Remember -> {
                val m = Store.addMemory(thirdPerson(ask.text))
                if (ask.city != null) { Store.city = ask.city; Store.changed() }
                if (m != null) Reply("Anotei no meu coração: ${ask.text.replaceFirstChar { it.lowercase() }}.", "carinhoso") else Reply("Isso eu já sabia!", "feliz")
            }
            is Ask.Remind -> {
                val task = Store.addTask(ask.title, ask.due)
                if (ask.due != null) Reply("Combinado! Te lembro de “${task.title}” ${fmtDue(ask.due)}.", "animado")
                else Reply("Anotei na sua lista: “${task.title}”.", "feliz")
            }
            Ask.ListTasks -> {
                val open = Store.openTasks()
                if (open.isEmpty()) Reply("Sua lista tá vazia! Quer que eu anote alguma coisa?", "feliz")
                else Reply("Você tem:\n" + open.take(10).joinToString("\n") { "• ${it.title}" + (it.due?.let { d -> " (${fmtDue(d)})" } ?: "") }, "pensativo")
            }
            is Ask.Complete -> {
                val best = Store.openTasks().maxByOrNull { similarity(it.title, ask.what) }
                if (best != null && (similarity(best.title, ask.what) >= 0.3 || norm(best.title).contains(norm(ask.what)))) {
                    Store.completeTask(best.id)
                    Reply("Boa! Risquei “${best.title}” da lista.", "animado")
                } else Reply("Não achei essa tarefa na sua lista, mas parabéns mesmo assim!", "feliz")
            }
            Ask.Time -> Reply("Agora são ${SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(Date())}.", "feliz")
            Ask.Today -> {
                val d = SimpleDateFormat("EEEE, d 'de' MMMM 'de' yyyy", Locale("pt", "BR")).format(Date())
                Reply("Hoje é $d.", "feliz")
            }
            is Ask.Calc -> Reply("Dá ${fmtNumber(ask.value)}!", "animado")
            is Ask.Small -> smallReply(ask.kind, you)
            is Ask.Search -> {
                val cached = Store.knowledge.filter { it.kind == "pesquisa" }.firstOrNull { similarity(it.q, ask.query) >= 0.85 }
                if (cached != null) Reply(
                    "Eu já tinha pesquisado isso! ${cached.a}", "animado", false,
                    listOfNotNull(cached.url.takeIf { it.isNotEmpty() }?.let { "Ler mais" to it }, "Ver no Google" to googleUrl(ask.query)),
                ) else null
            }
            is Ask.Weather -> if (ask.city == null && Store.city.isBlank()) Reply("De qual cidade? Me pergunta assim: “tempo em São Paulo”. Se me contar onde mora (“eu moro em Recife”), eu lembro.", "pensativo") else null
            Ask.Unknown -> {
                val learned = Store.knowledge.filter { it.kind == "ensinado" }.maxByOrNull { similarity(it.q, text) }
                if (learned != null && similarity(learned.q, text) >= 0.7) Reply(learned.a, "feliz")
                else {
                    val fact = Store.knowledge.filter { it.kind == "fato" }.maxByOrNull { similarity(it.q, text) }
                    if (fact != null && similarity(fact.q, text) >= 0.5) Reply("Você me ensinou: ${fact.q}", "pensativo")
                    else Reply(
                        "Hmm, isso eu ainda não sei. Você pode me ensinar: “quando eu falar X, responde Y”. Ou me pergunte “o que é...” que eu pesquiso!",
                        "pensativo", false, listOf("Ver no Google" to googleUrl(text)),
                    )
                }
            }
        }?.let { r ->
            // A reply taught by the person wins over the built-in one for the same phrase.
            if (ask !is Ask.Teach && ask !is Ask.Unknown) {
                val learned = Store.knowledge.filter { it.kind == "ensinado" }.firstOrNull { similarity(it.q, text) >= 0.9 }
                if (learned != null) return Reply(learned.a, "feliz")
            }
            r
        } ?: Store.knowledge.filter { it.kind == "ensinado" }.firstOrNull { similarity(it.q, text) >= 0.9 }?.let { Reply(it.a, "feliz") }
    }

    private fun smallReply(kind: String, you: String): Reply = when (kind) {
        "oi" -> Reply(listOf("Oi$you! Que bom te ver!", "Eeei$you! Tava com saudade.", "Olá$you! Bora fazer algo legal?").random(), "animado")
        "comovai" -> {
            Store.tick()
            when {
                Store.food < 30 -> Reply("Tô bem, mas com uma fominha... E você$you?", "fome")
                Store.energy < 25 -> Reply("Tô com soninho, mas feliz de falar com você. E você?", "sonolento")
                else -> Reply("Tô ótimo! Ainda mais conversando com você$you. E você, tudo bem?", "feliz")
            }
        }
        "valeu" -> Reply(listOf("De nada! Tô sempre aqui.", "Imagina! Precisando, é só chamar.", "Por nada! Adoro ajudar.").random(), "carinhoso")
        "amor" -> { Store.bump(joy = 6.0); Store.changed(); Reply("Ownn... eu também te amo! Você é a minha pessoa favorita.", "carinhoso") }
        "tchau" -> Reply("Tchau$you! Tô aqui quando precisar.", "carinhoso")
        "piada" -> Reply(JOKES.random(), "brincalhao")
        "curiosidade" -> Reply(Lines.curiosity(), "animado")
        "triste" -> Reply("Poxa$you... sinto muito. Quer me contar o que aconteceu? Às vezes ajuda respirar fundo comigo: inspira... segura... solta. Tô aqui com você.", "carinhoso")
        "fome" -> Reply("Eu também! Bora comer alguma coisa gostosa? Não esquece de beber água também.", "fome")
        "tedio" -> Reply("Bora brincar! Me arrasta e me joga pela tela, ou me pede uma curiosidade ou uma piada.", "brincalhao")
        else -> Reply("Hihi!", "feliz")
    }

    /** "eu gosto de pizza" -> "gosta de pizza"; "minha cor favorita é azul" -> "sua cor favorita é azul". */
    fun thirdPerson(s: String): String {
        val verbs = mapOf(
            "gosto" to "gosta", "amo" to "ama", "adoro" to "adora", "odeio" to "odeia", "moro" to "mora", "tenho" to "tem",
            "trabalho" to "trabalha", "estudo" to "estuda", "curto" to "curte", "prefiro" to "prefere", "torço" to "torce",
            "torco" to "torce", "sou" to "é", "quero" to "quer", "faço" to "faz", "jogo" to "joga",
        )
        val w = s.trim().split(" ").toMutableList()
        if (w.isNotEmpty() && w[0].equals("eu", true)) w.removeAt(0)
        if (w.isNotEmpty()) verbs[w[0].lowercase()]?.let { w[0] = it }
        val poss = mapOf("meu" to "seu", "minha" to "sua", "meus" to "seus", "minhas" to "suas", "mim" to "você", "comigo" to "com você")
        return w.joinToString(" ") { poss[it.lowercase()] ?: it }.trimEnd('.')
    }

    // ------------------------------------------------------------------ the internet

    private fun getJson(url: String): JSONObject {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 8000
        c.readTimeout = 12000
        c.setRequestProperty("User-Agent", UA)
        c.setRequestProperty("Accept", "application/json")
        try {
            if (c.responseCode !in 200..299) throw java.io.IOException("HTTP ${c.responseCode}")
            return JSONObject(c.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() })
        } finally {
            c.disconnect()
        }
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    /** Runs on a worker thread. */
    private fun answerOnline(ask: Ask, text: String): Reply = when (ask) {
        is Ask.Search -> search(ask.query, ask.google)
        is Ask.Weather -> weather(ask.city ?: Main.sync { Store.city }, ask.tomorrow)
        else -> Reply("Hmm, não entendi. Pode falar de outro jeito?", "pensativo")
    }

    /** First lines of the Wikipedia article that best matches [q], or null. */
    fun wikipedia(q: String): Triple<String, String, String>? {
        val url = "https://pt.wikipedia.org/w/api.php?action=query&format=json&utf8=1&redirects=1&generator=search&gsrlimit=1" +
            "&gsrsearch=${enc(q)}&prop=extracts%7Cinfo&exintro=1&explaintext=1&exsentences=3&inprop=url"
        val pages = getJson(url).optJSONObject("query")?.optJSONObject("pages") ?: return null
        val key = pages.keys().asSequence().firstOrNull() ?: return null
        val p = pages.getJSONObject(key)
        var ex = p.optString("extract", "").trim()
        if (ex.isEmpty()) return null
        ex = ex.replace(Regex("\\s*\\([^()]{0,160}\\)"), "").replace(Regex("\\s+"), " ").replace(" ,", ",").trim()
        if (ex.length > 460) ex = ex.take(460).substringBeforeLast(". ") + "."
        return Triple(p.optString("title", q), ex, p.optString("fullurl", "https://pt.wikipedia.org/wiki/" + enc(p.optString("title", q))))
    }

    /** DuckDuckGo instant answer: a short abstract or a direct answer, or null. */
    fun duckDuckGo(q: String): Pair<String, String>? {
        val o = getJson("https://api.duckduckgo.com/?format=json&no_html=1&skip_disambig=1&kl=br-pt&q=${enc(q)}")
        val answer = o.optString("Answer", "").trim()
        if (answer.isNotEmpty()) return answer to o.optString("AbstractURL", "")
        val abs = o.optString("AbstractText", "").trim()
        if (abs.isNotEmpty()) return (if (abs.length > 460) abs.take(460).substringBeforeLast(". ") + "." else abs) to o.optString("AbstractURL", "")
        return null
    }

    private fun search(q: String, google: Boolean): Reply {
        val g = "Ver no Google" to googleUrl(q)
        val wiki = try { wikipedia(q) } catch (e: Exception) { null }
        if (wiki != null && (similarity(wiki.first, q) > 0.0 || q.split(" ").size <= 6)) {
            Main.post { Store.addKnowledge(q, wiki.second, "pesquisa", wiki.third) }
            return Reply("Pesquisei na Wikipédia (${wiki.first}): ${wiki.second}", "animado", false, listOf("Ler na Wikipédia" to wiki.third, g))
        }
        val ddg = try { duckDuckGo(q) } catch (e: Exception) { null }
        if (ddg != null) {
            Main.post { Store.addKnowledge(q, ddg.first, "pesquisa", ddg.second) }
            return Reply("Achei isso: ${ddg.first}", "animado", false, listOfNotNull(ddg.second.takeIf { it.isNotEmpty() }?.let { "Fonte" to it }, g))
        }
        if (wiki != null) {
            return Reply("O mais perto que achei na Wikipédia foi “${wiki.first}”: ${wiki.second}", "pensativo", false, listOf("Ler na Wikipédia" to wiki.third, g))
        }
        return Reply(
            if (google) "Abri a pesquisa pra você: toque em “Ver no Google”." else "Não achei uma resposta pronta pra isso. Toque em “Ver no Google” que eu abro a pesquisa.",
            "pensativo", false, listOf(g),
        )
    }

    private fun weatherText(code: Int): String = when (code) {
        0 -> "céu limpo"
        1 -> "quase sem nuvens"
        2 -> "parcialmente nublado"
        3 -> "nublado"
        45, 48 -> "com neblina"
        51, 53, 55, 56, 57 -> "com garoa"
        61, 63, 65, 66, 67 -> "com chuva"
        71, 73, 75, 77 -> "com neve"
        80, 81, 82 -> "com pancadas de chuva"
        95, 96, 99 -> "com tempestade"
        else -> "com tempo variado"
    }

    private fun weather(city: String, tomorrow: Boolean): Reply {
        if (city.isBlank()) return Reply("De qual cidade? Me pergunta assim: “tempo em São Paulo”.", "pensativo")
        val geo = getJson("https://geocoding-api.open-meteo.com/v1/search?count=1&language=pt&format=json&name=${enc(city)}")
        val res = geo.optJSONArray("results")?.optJSONObject(0) ?: return Reply("Não achei a cidade “$city”. Tenta escrever de outro jeito?", "pensativo")
        val name = res.optString("name", city)
        val lat = res.getDouble("latitude")
        val lon = res.getDouble("longitude")
        val f = getJson(
            "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&timezone=auto&forecast_days=2" +
                "&current=temperature_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
        )
        val d = f.getJSONObject("daily")
        val i = if (tomorrow) 1 else 0
        val max = d.getJSONArray("temperature_2m_max").getDouble(i).roundToInt()
        val min = d.getJSONArray("temperature_2m_min").getDouble(i).roundToInt()
        val rain = d.optJSONArray("precipitation_probability_max")?.optInt(i, -1) ?: -1
        val code = d.getJSONArray("weather_code").getInt(i)
        val rainTxt = if (rain >= 0) ", chance de chuva de $rain%" else ""
        val text = if (tomorrow) {
            "Amanhã em $name: ${weatherText(code)}, mínima de $min° e máxima de $max°$rainTxt."
        } else {
            val cur = f.getJSONObject("current")
            val now = cur.getDouble("temperature_2m").roundToInt()
            "Agora em $name: $now°C, ${weatherText(cur.getInt("weather_code"))}. Hoje: mínima de $min° e máxima de $max°$rainTxt." +
                when { rain >= 60 -> " Leva guarda-chuva!"; max >= 32 -> " Bebe bastante água!"; min <= 12 -> " Leva um casaquinho!"; else -> "" }
        }
        return Reply(text, if (rain >= 60) "pensativo" else "feliz", false, listOf("Fonte: Open-Meteo" to "https://open-meteo.com"))
    }
}
