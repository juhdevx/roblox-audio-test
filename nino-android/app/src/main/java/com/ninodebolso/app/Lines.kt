package com.ninodebolso.app

import java.util.Calendar

/** Things the pet says on its own, without the AI. */
object Lines {
    val FOODS = listOf("🍓" to "morango", "🍙" to "bolinho de arroz", "🥕" to "cenoura", "🍪" to "biscoito", "🍉" to "melancia", "🧀" to "queijo", "🍌" to "banana", "🥟" to "pastel", "🍇" to "uva")
    val YUM = listOf("Nham! Que delícia de %s!", "Hmm, %s! Obrigado!", "Nhac nhac... %s é vida.", "%s! Meu favorito... de hoje.")
    val FULL = listOf("Tô cheio! Não cabe mais nada.", "Barriga lotada! Talvez mais tarde.", "Se eu comer mais, eu rolo em vez de andar.")
    val TAP = listOf("Oi! Tô aqui!", "Me chamou?", "Hihi, oi!", "Boop!", "O que vamos fazer?", "Opa! Precisa de mim?")
    val PET = listOf("Hmmm... que gostoso.", "Mais! Mais!", "Eu amo carinho.", "Fico todo vermelhinho assim.", "Ronrom... espera, isso é coisa de gato.")
    val WAKE = listOf("Hã? Já é de manhã?", "Eu tava sonhando com biscoitos...", "Zzz... ah, oi. Acordei.", "Bocejo... tô de pé! Mais ou menos.")
    val DONE = listOf("Boa! Menos uma!", "Mandou bem! Riscado da lista.", "Isso aí! Orgulho de você.", "Tarefa feita, que orgulho!")
    val THROWN = listOf("Wheeee!", "Uaaau, eu voo!", "De novo! De novo!", "Opa! Pousei!")
    val THINK = listOf("Hmm, deixa eu ver...", "Deixa eu dar uma olhadinha...", "Peraí, tô olhando...")
    val HIDE = listOf("Vou ficar aqui no cantinho. Me toca quando precisar!", "Tô de olho daqui, viu?")
    val ZOOM = listOf("Corre corre corre!", "Uhuuul, zoomies!", "Pega eu!")
    val RETURN = listOf("Voltou! Tava com saudade.", "Oi de novo! Senti sua falta.", "Eba, você voltou!")
    private val GENERIC = listOf(
        "Sabia que os polvos têm três corações? Eu só tenho um, mas ele é grandão.",
        "Se precisar de ajuda com alguma coisa, me toca. Sou pequeno, mas sou esperto!",
        "Uma pausa de 5 minutinhos às vezes resolve tudo. Bora alongar?",
        "Já bebeu água hoje? Eu já bebi a minha!",
        "Sabia que dá pra me ensinar? Fala na conversa: quando eu falar “bom dia”, responde “bom dia, flor do dia!”.",
        "Me pergunta “o que é um buraco negro?” que eu pesquiso pra você!",
        "Quer saber o clima? Me pergunta “como tá o tempo em ...” com o nome da sua cidade.",
        "Toca em mim e escolhe “Visual” pra trocar meu chapéu, cabelo e roupa!",
        "Me conta uma coisa legal que aconteceu hoje?",
        "Curiosidade: o mel quase não estraga. Já acharam mel de milhares de anos em tumbas no Egito!",
        "Dica: me toca e escolhe “Olhar a tela” que eu te explico o que tá aparecendo.",
        "Quer que eu te lembre de alguma coisa? É só me pedir na conversa.",
        "Curiosidade: pra botânica, a banana é uma baga e o morango não é. A natureza é doida.",
        "Respira fundo comigo: inspira... segura... solta. Melhor?",
        "Recebeu mensagem pedindo PIX ou código? Me mostra antes que eu dou uma olhada.",
        "Tô de olho em tudo por aqui. Pode contar comigo.",
    )
    private val CURIOSITIES = listOf(
        "Os polvos têm três corações e sangue azul!",
        "O mel quase não estraga: já acharam mel de milhares de anos em tumbas no Egito.",
        "Pra botânica, a banana é uma baga e o morango não é.",
        "Os flamingos ficam rosa por causa do que comem: camarõezinhos e algas.",
        "O coração de uma baleia-azul é do tamanho de um carro pequeno.",
        "As abelhas conseguem reconhecer rostos humanos.",
        "Um dia em Vênus dura mais que um ano em Vênus!",
        "Os cavalos-marinhos machos é que ficam grávidos.",
    )

    fun curiosity(): String = "Curiosidade: " + CURIOSITIES.random()

    fun levelUp(level: Int): String = when (Store.look.species) {
        "broto" -> "Subi pro nível $level! Olha minha folhinha crescendo!"
        "bebe" -> "Subi pro nível $level! Tô crescendo, já sei até falar mais coisas!"
        else -> "Subi pro nível $level! Tô ficando cada vez mais esperto!"
    }

    private val HUNGRY = listOf("Minha barriga tá roncando... me dá um lanchinho?", "Fome... me toca e escolhe Comer?")
    private val SLEEPY = listOf("Tô com soninho... me põe pra dormir?", "Bocejo... minha energia tá acabando.")
    private val BORED = listOf("Tô meio entediado... brinca comigo?", "Faz um carinho em mim? Toca duas vezes na minha cabeça.", "Me joga pro alto! Arrasta e solta, é divertido!")

    fun hour() = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)

    private fun timeLines(h: Int) = when (h) {
        in 5..10 -> listOf("Bom dia! Já tomou café? Eu já tomei um raio de sol.", "Manhã é boa pra fazer a tarefa mais chata primeiro. Depois fica leve!")
        in 11..13 -> listOf("Hora do almoço chegando... não esquece de comer, hein!")
        in 14..17 -> listOf("Aquela moleza da tarde... um copo d’água ajuda!", "Tarde produtiva? Se quiser, eu te ajudo a organizar o resto do dia.")
        in 18..22 -> listOf("Fim de dia! Quer me contar como foi?", "Que tal deixar a lista de amanhã pronta? Eu te ajudo.")
        else -> listOf("Tá tarde... que tal guardar o celular e descansar? Eu fico de guarda.", "Essa hora a tela brilha mais que a lua. Bora dormir?")
    }

    /** A line for the pet to say by itself, and the face to make while saying it. */
    fun idle(): Pair<String, String> {
        Store.tick()
        val pool = mutableListOf<Pair<String, String>>()
        if (Store.food < 30) HUNGRY.forEach { pool += it to "fome"; pool += it to "fome" }
        if (Store.energy < 25) SLEEPY.forEach { pool += it to "sonolento"; pool += it to "sonolento" }
        if (Store.joy < 35) BORED.forEach { pool += it to "triste" }
        val open = Store.openTasks()
        val late = open.filter { (it.due ?: Long.MAX_VALUE) < now() }
        if (late.isNotEmpty()) pool += "Ei, “${late[0].title}” já passou da hora. Bora resolver?" to "surpreso"
        else if (open.isNotEmpty()) pool += "Ainda tem “${open.random().title}” na lista. Quer ajuda pra começar?" to "pensativo"
        if (Store.memories.isNotEmpty()) {
            val m = Store.memories.random().text.trim().trimEnd('.')
            pool += (if (m.firstOrNull()?.isLowerCase() == true) "Lembrei que você $m. Tô ligado, viu?" else "Lembrei de uma coisa sua: $m") to "carinhoso"
        }
        if (Store.userName.isBlank()) pool += "Ei, eu ainda não sei seu nome! Me conta na conversa?" to "pensativo"
        timeLines(hour()).forEach { pool += it to "feliz" }
        GENERIC.forEach { pool += it to listOf("feliz", "brincalhao", "pensativo", "feliz").random() }
        return pool.random()
    }

    fun greeting(): String {
        val h = hour()
        val nm = if (Store.userName.isNotBlank()) ", ${Store.userName}" else ""
        val base = when (h) { in 5..11 -> "Bom dia$nm!"; in 12..17 -> "Boa tarde$nm!"; in 18..23 -> "Boa noite$nm!"; else -> "Ainda por aqui a essa hora$nm?" }
        val open = Store.openTasks()
        val today = open.count { it.due != null && fmtDue(it.due!!).startsWith("hoje") }
        val extra = when {
            today > 0 -> " Hoje você tem $today lembrete${if (today > 1) "s" else ""}."
            open.isNotEmpty() -> " Tem ${open.size} coisa${if (open.size > 1) "s" else ""} na sua lista."
            else -> ""
        }
        return base + extra
    }
}
