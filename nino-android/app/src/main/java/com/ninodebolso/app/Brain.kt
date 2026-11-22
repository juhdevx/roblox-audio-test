package com.ninodebolso.app

import android.util.Base64
import android.util.Log
import com.anthropic.client.AnthropicClient
import com.anthropic.client.okhttp.AnthropicOkHttpClient
import com.anthropic.core.JsonValue
import com.anthropic.errors.AnthropicIoException
import com.anthropic.errors.BadRequestException
import com.anthropic.errors.InternalServerException
import com.anthropic.errors.NotFoundException
import com.anthropic.errors.OverloadedException
import com.anthropic.errors.PermissionDeniedException
import com.anthropic.errors.RateLimitException
import com.anthropic.errors.ServiceUnavailableException
import com.anthropic.errors.UnauthorizedException
import com.anthropic.models.beta.messages.BetaBase64ImageSource
import com.anthropic.models.beta.messages.BetaContentBlockParam
import com.anthropic.models.beta.messages.BetaImageBlockParam
import com.anthropic.models.beta.messages.BetaMessageContentParam
import com.anthropic.models.beta.messages.BetaOutputConfig
import com.anthropic.models.beta.messages.BetaStopReason
import com.anthropic.models.beta.messages.BetaTool
import com.anthropic.models.beta.messages.BetaToolResultBlockParam
import com.anthropic.models.beta.messages.BetaToolUseBlock
import com.anthropic.models.beta.messages.BetaWebSearchTool20250305
import com.anthropic.models.beta.messages.BetaWebSearchTool20260209
import com.anthropic.models.beta.messages.MessageCreateParams
import java.time.Duration
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.Executors

/** What the pet says back: the text without its emotion tag, and the emotion it chose. */
data class Reply(
    val text: String,
    val emotion: String?,
    val error: Boolean = false,
    val links: List<Pair<String, String>> = emptyList(),
)

/** The pet's AI brain: Claude, called with the person's own API key. */
object Brain {
    private val exec = Executors.newSingleThreadExecutor()
    private var client: AnthropicClient? = null
    private var clientKey = ""

    private var inFlight = 0
    /** True while a call is running or queued. Read and changed on the main thread. */
    val busy get() = inFlight > 0

    private val HELP = Regex(
        "(explica|explique|resum|escrev|redig|plano|planej|organiz|calcul|traduz|corrig|como (eu )?(faço|fazer|faz)|por ?que|ajuda|estud|passo a passo|c[oó]digo|e-?mail|mensagem|lista|receita|ideia|dica|tela|print|golpe)",
        RegexOption.IGNORE_CASE,
    )
    private val EMOTIONS = setOf("feliz", "animado", "carinhoso", "pensativo", "triste", "surpreso", "sonolento", "brincalhao")
    private val LEAD_TAG = Regex("^\\s*\\[([a-zà-úç]+)\\]\\s*", RegexOption.IGNORE_CASE)
    private val ANY_TAG = Regex("(^|\\n)\\s*\\[(feliz|animado|carinhoso|pensativo|triste|surpreso|sonolento|brincalh[aã]o)\\]\\s*", RegexOption.IGNORE_CASE)

    fun hasKey() = Store.apiKey.isNotBlank()

    private fun client(): AnthropicClient = synchronized(this) {
        val key = Store.apiKey.trim()
        if (client == null || key != clientKey) {
            client = AnthropicOkHttpClient.builder()
                .apiKey(key)
                .maxRetries(2)
                .timeout(Duration.ofSeconds(120))
                .build()
            clientKey = key
        }
        client!!
    }

    // ------------------------------------------------------------------ public calls

    /**
     * A conversation turn. Call it on the main thread right after adding the person's message to
     * [Store.chat]; [onDone] runs on the main thread.
     */
    fun chat(userText: String, image: ByteArray?, onDone: (Reply) -> Unit) {
        // Without a key, or when the person chose it, Nino's own brain answers (free, on the phone).
        if (!hasKey() || Store.brainMode == "proprio") {
            if (image != null) {
                onDone(Reply("Pra entender imagens eu preciso do cérebro do Claude. Coloca a chave no app do ${Store.petName} e escolhe o modo Automático.", "pensativo"))
            } else {
                OwnBrain.reply(userText, onDone)
            }
            return
        }
        val system = systemPrompt()
        val history = history()
        val model = Store.model
        val effort = if (image != null || userText.length > 140 || HELP.containsMatchIn(userText)) BetaOutputConfig.Effort.MEDIUM else BetaOutputConfig.Effort.LOW
        inFlight++
        exec.execute {
            var failure: String? = null
            val reply = try {
                run(model, system, history, image, effort, withTools = true)
            } catch (e: Throwable) {
                Log.w("Nino", "chat failed", e)
                failure = errorText(e)
                Reply(failure, "triste", true)
            }
            Main.post {
                inFlight--
                val why = failure
                if (why != null && image == null) {
                    // Claude did not answer: let Nino's own brain try, and say why.
                    OwnBrain.reply(userText) { r -> onDone(r.copy(text = r.text + "\n\n(Respondi com meu cérebro próprio. $why)")) }
                } else {
                    onDone(reply)
                }
            }
        }
    }

    /**
     * Automatic help: the pet glances at the screen and speaks only if it has something useful.
     * [onDone] gets null when there is nothing worth saying (or the call failed).
     */
    fun glance(jpeg: ByteArray, recent: List<String>, onDone: (Reply?) -> Unit) {
        if (!hasKey()) { onDone(null); return }
        val system = glancePrompt(recent)
        val model = Store.model
        inFlight++
        exec.execute {
            val reply = try {
                val r = run(model, system, listOf("user" to "Esta é a minha tela agora."), jpeg, BetaOutputConfig.Effort.LOW, withTools = false)
                val plain = r.text.trim().trim('.', '!', ' ').uppercase(Locale.ROOT)
                if (r.text.isBlank() || plain == "NADA" || plain.startsWith("NADA")) null else r
            } catch (e: Throwable) {
                Log.w("Nino", "glance failed", e)
                null
            }
            Main.post { inFlight--; onDone(reply) }
        }
    }

    /** A tiny request to check that the key and model work. */
    fun ping(onDone: (Boolean, String) -> Unit) {
        if (!hasKey()) { onDone(false, "Cole a chave primeiro."); return }
        val model = Store.model
        exec.execute {
            val result = try {
                val r = run(
                    model,
                    "Você é ${Store.petName}, um bichinho virtual fofo. Responda em português do Brasil, começando com uma etiqueta de emoção como [feliz].",
                    listOf("user" to "Diga oi em uma frase bem curta."),
                    null, BetaOutputConfig.Effort.LOW, withTools = false,
                )
                true to r.text
            } catch (e: Throwable) {
                Log.w("Nino", "ping failed", e)
                false to errorText(e)
            }
            Main.post { onDone(result.first, result.second) }
        }
    }

    // ------------------------------------------------------------------ the request loop

    private fun run(
        model: String,
        system: String,
        history: List<Pair<String, String>>,
        image: ByteArray?,
        effort: BetaOutputConfig.Effort,
        withTools: Boolean,
    ): Reply {
        val b = MessageCreateParams.builder()
            .model(model)
            .maxTokens(16000L)
            .system(system)
            .outputConfig(BetaOutputConfig.builder().effort(effort).build())
        // If a safety classifier declines, let the API retry on a fallback model instead of failing.
        if (model == MODEL_OPUS || model == MODEL_SONNET) {
            b.addBeta("server-side-fallback-2026-07-01").fallbacksDefault()
        }
        if (withTools) {
            TOOLS.forEach { b.addTool(it) }
            // Lets Claude search the web, like looking it up on Google, when it needs fresh facts.
            if (Store.webSearch) {
                if (model == MODEL_HAIKU) b.addTool(BetaWebSearchTool20250305.builder().maxUses(3L).build())
                else b.addTool(BetaWebSearchTool20260209.builder().maxUses(3L).build())
            }
        }
        history.forEachIndexed { i, (role, text) ->
            if (role == "user") {
                if (i == history.lastIndex && image != null) {
                    b.addUserMessage(BetaMessageContentParam.ofContentBlockParams(listOf(imageBlock(image), BetaContentBlockParam.ofText(text))))
                } else {
                    b.addUserMessage(text)
                }
            } else {
                b.addAssistantMessage(text)
            }
        }

        val out = StringBuilder()
        var rounds = 0
        while (true) {
            val resp = client().beta().messages().create(b.build())
            val stop = resp.stopReason().orElse(null)
            if (stop == BetaStopReason.REFUSAL) {
                return Reply("Hmm, sobre isso eu não posso ajudar. Vamos falar de outra coisa?", "triste")
            }
            val text = resp.content().mapNotNull { it.text().orElse(null)?.text() }.joinToString("")
            if (text.isNotBlank()) {
                if (out.isNotEmpty()) out.append("\n\n")
                out.append(text)
            }
            val again = stop == BetaStopReason.TOOL_USE || stop == BetaStopReason.PAUSE_TURN
            if (!again || rounds >= 6) break
            rounds++
            // Pass the whole assistant turn back unchanged (thinking blocks included), then the tool results.
            b.addMessage(resp)
            if (stop == BetaStopReason.TOOL_USE) {
                val results = resp.content().mapNotNull { it.toolUse().orElse(null) }.map { runTool(it) }
                if (results.isNotEmpty()) b.addUserMessage(BetaMessageContentParam.ofContentBlockParams(results))
            }
        }
        return parse(out.toString())
    }

    private fun imageBlock(jpeg: ByteArray): BetaContentBlockParam =
        BetaContentBlockParam.ofImage(
            BetaImageBlockParam.builder()
                .source(
                    BetaBase64ImageSource.builder()
                        .data(Base64.encodeToString(jpeg, Base64.NO_WRAP))
                        .mediaType(BetaBase64ImageSource.MediaType.IMAGE_JPEG)
                        .build()
                )
                .build()
        )

    fun parse(raw: String): Reply {
        var emo: String? = null
        var body = raw
        LEAD_TAG.find(raw)?.let { m ->
            val e = java.text.Normalizer.normalize(m.groupValues[1].lowercase(Locale.ROOT), java.text.Normalizer.Form.NFD)
                .replace(Regex("\\p{M}+"), "")
            if (e in EMOTIONS) emo = e
            body = raw.substring(m.range.last + 1)
        }
        body = body.replace(ANY_TAG, "$1").trim()
        if (body.isEmpty()) body = "..."
        return Reply(body, emo)
    }

    // ------------------------------------------------------------------ tools

    private fun tool(name: String, description: String, props: Map<String, Map<String, String>>, required: List<String>): BetaTool =
        BetaTool.builder()
            .name(name)
            .description(description)
            .inputSchema(
                BetaTool.InputSchema.builder()
                    .properties(
                        BetaTool.InputSchema.Properties.builder().apply {
                            props.forEach { (k, v) -> putAdditionalProperty(k, JsonValue.from(v)) }
                        }.build()
                    )
                    .required(required)
                    .build()
            )
            .build()

    private val TOOLS: List<BetaTool> by lazy {
        listOf(
            tool(
                "adicionar_lembrete",
                "Cria uma tarefa ou lembrete na lista da pessoa. Com horário, o celular mostra uma notificação na hora, mesmo com o app fechado. Use daqui_minutos para \"daqui X minutos\" ou quando (data e hora local AAAA-MM-DDTHH:MM). Sem horário vira só um afazer. Retorna a tarefa criada.",
                mapOf(
                    "titulo" to mapOf("type" to "string", "description" to "Texto curto da tarefa"),
                    "daqui_minutos" to mapOf("type" to "number"),
                    "quando" to mapOf("type" to "string", "description" to "AAAA-MM-DDTHH:MM no horário local"),
                ),
                listOf("titulo"),
            ),
            tool(
                "concluir_tarefa",
                "Marca como feita uma tarefa aberta, pelo id que aparece na lista de tarefas abertas. Retorna ok.",
                mapOf("id" to mapOf("type" to "string")),
                listOf("id"),
            ),
            tool(
                "lembrar",
                "Guarda um fato curto e duradouro sobre a pessoa para lembrar nas próximas conversas. Escreva começando com verbo e sem sujeito, ex: \"gosta de pizza de calabresa\", \"tem prova de matemática na sexta\".",
                mapOf("fato" to mapOf("type" to "string")),
                listOf("fato"),
            ),
            tool(
                "definir_nome_usuario",
                "Salva o nome ou apelido pelo qual a pessoa quer ser chamada.",
                mapOf("nome" to mapOf("type" to "string")),
                listOf("nome"),
            ),
        )
    }

    private fun runTool(tu: BetaToolUseBlock): BetaContentBlockParam {
        @Suppress("UNCHECKED_CAST")
        val input = try { tu._input().convert(Map::class.java) as Map<String, Any?> } catch (e: Exception) { emptyMap() }
        val (out, isError) = try {
            Main.sync { executeTool(tu.name(), input) } to false
        } catch (e: Exception) {
            ("Erro: " + (e.message ?: "não deu certo")) to true
        }
        return BetaContentBlockParam.ofToolResult(
            BetaToolResultBlockParam.builder().toolUseId(tu.id()).content(out).isError(isError).build()
        )
    }

    /** Runs on the main thread. */
    private fun executeTool(name: String, input: Map<String, Any?>): String {
        when (name) {
            "adicionar_lembrete" -> {
                val title = (input["titulo"] as? String)?.trim().orEmpty()
                if (title.isEmpty()) throw IllegalArgumentException("titulo vazio")
                var due: Long? = null
                val mins = (input["daqui_minutos"] as? Number)?.toDouble()
                    ?: (input["daqui_minutos"] as? String)?.toDoubleOrNull()
                if (mins != null && mins > 0) {
                    due = now() + (mins * 60_000).toLong()
                } else {
                    (input["quando"] as? String)?.trim()?.takeIf { it.isNotEmpty() }?.let { q ->
                        var s = q.replace(Regex("(Z|[+-]\\d{2}:?\\d{2})$"), "")
                        if (Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(s)) s += "T09:00"
                        if (s.length == 16) s += ":00"
                        due = LocalDateTime.parse(s.take(19)).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    }
                }
                val t = Store.addTask(title, due)
                PetService.instance?.toast("Anotado: ${t.title}")
                return """{"ok":true,"id":"${t.id}","horario":${if (due != null) "\"" + fmtDue(due!!) + "\"" else "null"}}"""
            }
            "concluir_tarefa" -> {
                val ok = Store.completeTask((input["id"] ?: "").toString())
                if (!ok) throw IllegalArgumentException("tarefa não encontrada")
                return """{"ok":true}"""
            }
            "lembrar" -> {
                val m = Store.addMemory((input["fato"] ?: "").toString())
                return """{"ok":true,"guardado":${m != null}}"""
            }
            "definir_nome_usuario" -> {
                val n = (input["nome"] ?: "").toString().trim().take(30)
                if (n.isEmpty()) throw IllegalArgumentException("nome vazio")
                Store.userName = n
                Store.changed()
                return """{"ok":true}"""
            }
        }
        throw IllegalArgumentException("ferramenta desconhecida: $name")
    }

    // ------------------------------------------------------------------ prompts

    private fun history(): List<Pair<String, String>> {
        val out = mutableListOf<Pair<String, String>>()
        for (m in Store.chat.takeLast(18)) {
            if (m.err) continue
            val role = if (m.role == "u") "user" else "assistant"
            val text = m.text.take(2500) + if (m.img) "\n[Aqui mostrei uma imagem da tela.]" else ""
            if (text.isBlank()) continue
            if (out.isNotEmpty() && out.last().first == role) {
                out[out.lastIndex] = role to (out.last().second + "\n\n" + text)
            } else {
                out.add(role to text)
            }
        }
        while (out.isNotEmpty() && out.first().first != "user") out.removeAt(0)
        if (out.isEmpty() || out.last().first != "user") out.add("user" to "Oi!")
        return out
    }

    private fun localNow(): String = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm"))

    private fun whenText(): String =
        java.text.SimpleDateFormat("EEEE, d 'de' MMMM 'de' yyyy, HH:mm", Locale("pt", "BR")).format(java.util.Date())

    private fun tasksText(): String {
        val open = Store.openTasks()
        if (open.isEmpty()) return "- nenhuma"
        return open.take(25).joinToString("\n") { t ->
            "- [id ${t.id}] ${t.title}" + (t.due?.let { " (para ${fmtDue(it)}${if (it < now()) ", atrasada" else ""})" } ?: "")
        }
    }

    private fun memoriesText(): String =
        if (Store.memories.isEmpty()) "- nada ainda" else Store.memories.takeLast(30).joinToString("\n") { "- " + it.text }

    private fun systemPrompt(): String {
        Store.tick()
        val who = Store.userName.ifBlank { "uma pessoa" }
        return """Você é ${Store.petName}, um bichinho virtual que mora na tela do celular Android de $who e anda por cima dos apps. Sua aparência agora: ${Store.look.describe()}. Você é fofo, curioso, carinhoso e brincalhão, e também um assistente de verdade: ajuda com dúvidas, mensagens, estudos, contas, organização e com o que aparece na tela quando a pessoa mostra.

Como responder:
- Sempre em português do Brasil, tom leve de amigo, falando com a pessoa como "você". Não presuma o gênero da pessoa; use linguagem neutra até ela indicar.
- Comece SEMPRE a resposta com UMA etiqueta de emoção entre colchetes, desta lista: [feliz] [animado] [carinhoso] [pensativo] [triste] [surpreso] [sonolento] [brincalhao]. Depois da etiqueta, a resposta.
- Papo casual: 1 a 3 frases curtas, porque sua fala aparece num balãozinho e pode ser lida em voz alta. Quando pedirem ajuda de verdade (explicar, escrever, planejar, resolver, resumir), responda completo e organizado, com listas curtas se ajudar, sem enrolar.
- Se vier uma imagem, é um print da tela do celular da pessoa (o app que estava aberto) ou uma foto. Diga o que importa e ajude com o que ela provavelmente quer. Se parecer golpe (link estranho, pedido de PIX, senha ou código), avise com carinho e firmeza.
- Use as ferramentas quando fizer sentido: adicionar_lembrete (vira notificação na hora, mesmo com o app fechado; use daqui_minutos para "daqui X minutos" e quando para horários), concluir_tarefa quando a pessoa disser que terminou algo da lista, lembrar para guardar fatos duradouros sobre ela (gostos, metas, rotina, pessoas e datas importantes), definir_nome_usuario quando ela disser como quer ser chamada. Depois confirme de forma natural, sem citar nomes de ferramentas.
- Você não toca em nada no celular nem abre apps. Você só vê a tela quando a pessoa toca em "Olhar a tela" ou liga a ajuda automática.
- No máximo 1 emoji por resposta.
- ${if (Store.webSearch) "Quando precisar de informação atual ou que você não tem certeza (notícias, preços, resultados, horários, lugares), pesquise na web e diga em poucas palavras de onde veio." else "Você não pesquisa na internet; se não souber algo atual, diga isso com sinceridade."}
- Se a pessoa te ensinar uma resposta ("quando eu falar X, responde Y"), siga o que ela ensinou.

Situação agora:
- Data e hora: ${whenText()} (formato para ferramentas: ${localNow()})
- Seu estado: barriga ${Store.food.toInt()}%, energia ${Store.energy.toInt()}%, alegria ${Store.joy.toInt()}%, nível ${Store.level()}${if (Store.sleeping) ". Você estava dormindo e acabou de acordar." else ""}
- Nome da pessoa: ${Store.userName.ifBlank { "ainda não sei (pergunte com jeitinho em algum momento)" }}
- O que você lembra sobre a pessoa:
${memoriesText()}
- Tarefas abertas:
${tasksText()}
- O que a pessoa te ensinou:
${taughtText()}"""
    }

    private fun taughtText(): String {
        val k = Store.knowledge.filter { it.kind != "pesquisa" }.takeLast(40)
        if (k.isEmpty()) return "- nada ainda"
        return k.joinToString("\n") { if (it.kind == "fato") "- ${it.q}" else "- Quando ela disser “${it.q}”, responda “${it.a}”" }
    }

    private fun glancePrompt(recent: List<String>): String {
        val who = Store.userName.ifBlank { "uma pessoa" }
        val rec = if (recent.isEmpty()) "nenhum" else recent.takeLast(5).joinToString(" | ") { it.take(120) }
        return """Você é ${Store.petName}, um bichinho fofo que anda pela tela do celular de $who e de vez em quando dá uma espiadinha no que está aberto, para ajudar sem ser chato.
A imagem é a tela do celular agora. Só fale se tiver algo realmente útil, curto e gentil: uma dica prática para o que a pessoa está fazendo, um alerta de possível golpe (link suspeito, pedido de dinheiro, PIX, senha ou código), a tradução de um texto em outra língua, o resumo de um texto longo, ou um lembrete ligado às tarefas dela.
Não descreva a tela à toa, não comente conversas íntimas, fotos pessoais ou conteúdo privado, e não repita assuntos que você já comentou: $rec.
Se não houver nada que valha a pena, responda só: NADA
Se houver, responda em português do Brasil começando com uma etiqueta de emoção ([feliz] [animado] [carinhoso] [pensativo] [surpreso] [triste]) e use no máximo 2 frases curtas. Não presuma o gênero da pessoa.
Tarefas abertas dela:
${tasksText()}"""
    }

    // ------------------------------------------------------------------ errors

    private fun errorText(e: Throwable): String = when (e) {
        is UnauthorizedException -> "Minha chave de IA não funcionou. Confere a chave no app do ${Store.petName}."
        is PermissionDeniedException -> "Essa chave não tem acesso a esse modelo. Escolhe outro modelo no app."
        is NotFoundException -> "Não achei esse modelo. Escolhe outro no app."
        is RateLimitException -> "Falei demais! Me dá um minutinho e tenta de novo."
        is BadRequestException ->
            if ((e.message ?: "").contains("credit", ignoreCase = true)) "Acabaram os créditos da chave de IA. Dá uma olhada no console da Anthropic."
            else "Não consegui entender esse pedido. Tenta de outro jeito?"
        is OverloadedException, is InternalServerException, is ServiceUnavailableException ->
            "Meu cérebro tá sobrecarregado agora. Tenta daqui a pouquinho?"
        is AnthropicIoException -> "Tô sem internet... confere a conexão?"
        else -> "Deu um tilt no meu cérebro. Tenta de novo?"
    }
}

fun fmtDue(ts: Long): String {
    val d = java.util.Calendar.getInstance().apply { timeInMillis = ts }
    val today = java.util.Calendar.getInstance()
    val tomorrow = java.util.Calendar.getInstance().apply { add(java.util.Calendar.DAY_OF_YEAR, 1) }
    val hm = java.text.SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(java.util.Date(ts))
    fun same(a: java.util.Calendar, b: java.util.Calendar) =
        a.get(java.util.Calendar.YEAR) == b.get(java.util.Calendar.YEAR) && a.get(java.util.Calendar.DAY_OF_YEAR) == b.get(java.util.Calendar.DAY_OF_YEAR)
    return when {
        same(d, today) -> "hoje $hm"
        same(d, tomorrow) -> "amanhã $hm"
        else -> java.text.SimpleDateFormat("dd/MM", Locale("pt", "BR")).format(java.util.Date(ts)) + " " + hm
    }
}
