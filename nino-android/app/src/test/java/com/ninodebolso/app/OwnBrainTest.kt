package com.ninodebolso.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class OwnBrainTest {
    // Saturday 2026-11-21 15:00 local time
    private val now = Calendar.getInstance().apply { set(2026, 10, 21, 15, 0, 0); set(Calendar.MILLISECOND, 0) }.timeInMillis

    private fun hm(ms: Long): String {
        val c = Calendar.getInstance().apply { timeInMillis = ms }
        val day = if (c.get(Calendar.DAY_OF_MONTH) == 21) "hoje" else "dia ${c.get(Calendar.DAY_OF_MONTH)}"
        return "$day %02d:%02d".format(c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
    }

    private fun u(s: String) = OwnBrain.understand(s, now)

    @Test fun teach() {
        assertEquals(Ask.Teach("bom dia", "bom dia, flor do dia!"), u("Quando eu falar bom dia, responde bom dia, flor do dia!"))
        assertEquals(Ask.Teach("oi", "E aí, parceiro!"), u("se eu disser \"oi\" você responde \"E aí, parceiro!\""))
        assertEquals(Ask.Fact("o gato se chama Mingau"), u("Aprende que o gato se chama Mingau"))
        assertEquals(Ask.Forget("bom dia"), u("esquece o que eu te ensinei sobre bom dia"))
    }

    @Test fun reminders() {
        val a = u("me lembra de beber água daqui 30 minutos") as Ask.Remind
        assertEquals("Beber água", a.title); assertEquals(now + 30 * 60_000L, a.due)
        val b = u("Me lembra daqui meia hora de tomar remédio") as Ask.Remind
        assertEquals("Tomar remédio", b.title); assertEquals(now + 30 * 60_000L, b.due)
        val c = u("me lembra de ligar pra minha mãe às 19h") as Ask.Remind
        assertEquals("Ligar pra minha mãe", c.title); assertEquals("hoje 19:00", hm(c.due!!))
        val d = u("me lembra de pagar a conta amanhã às 8:30") as Ask.Remind
        assertEquals("Pagar a conta", d.title); assertEquals("dia 22 08:30", hm(d.due!!))
        val e = u("me lembra de buscar o pão às 7") as Ask.Remind  // 7 already passed at 15h -> 19h
        assertEquals("hoje 19:00", hm(e.due!!))
        val f = u("me acorda às 6 da manhã") as Ask.Remind
        assertEquals("dia 22 06:00", hm(f.due!!))
        val g = u("me lembra de comprar leite") as Ask.Remind
        assertEquals("Comprar leite", g.title); assertEquals(null, g.due)
        val h = u("me lembra de almoçar ao meio-dia") as Ask.Remind
        assertEquals("Almoçar", h.title); assertEquals("dia 22 12:00", hm(h.due!!))
        val i = u("anota comprar arroz") as Ask.Remind
        assertEquals("Comprar arroz", i.title)
        val j = u("me lembra em 2 horas de sair") as Ask.Remind
        assertEquals("Sair", j.title); assertEquals(now + 120 * 60_000L, j.due)
    }

    @Test fun memoryAndName() {
        assertEquals(Ask.SetName("Ana Clara"), u("meu nome é ana clara"))
        assertEquals(Ask.MyName, u("qual é o meu nome?"))
        val r = u("eu moro em São Paulo") as Ask.Remember
        assertEquals("São Paulo", r.city)
        assertTrue(u("lembra que eu odeio cebola") is Ask.Remember)
        assertEquals("gosta de pizza de calabresa", OwnBrain.thirdPerson("eu gosto de pizza de calabresa"))
        assertEquals("sua cor favorita é azul", OwnBrain.thirdPerson("minha cor favorita é azul"))
        assertEquals(Ask.ListLearned, u("o que você aprendeu?"))
    }

    @Test fun tasksTimeMath() {
        assertEquals(Ask.ListTasks, u("quais são minhas tarefas?"))
        assertEquals(Ask.ListTasks, u("o que eu tenho pra fazer hoje"))
        assertEquals(Ask.Complete("lavar a louça"), u("terminei de lavar a louça"))
        assertEquals(Ask.Time, u("que horas são?"))
        assertEquals(Ask.Today, u("que dia é hoje?"))
        assertEquals(12.0, (u("quanto é 15% de 80?") as Ask.Calc).value, 1e-9)
        assertEquals(56.0, (u("quanto é 7 x 8") as Ask.Calc).value, 1e-9)
        assertEquals(14.0, (u("2+3*4") as Ask.Calc).value, 1e-9)
        assertEquals(2.5, (u("calcula 10 dividido por 4") as Ask.Calc).value, 1e-9)
        assertEquals("1.234.567", OwnBrain.fmtNumber(1234567.0))
    }

    @Test fun weatherAndSearch() {
        assertEquals(Ask.Weather("São Paulo", false), u("Como tá o tempo em São Paulo?"))
        assertEquals(Ask.Weather(null, true), u("vai chover amanhã?"))
        assertEquals(Ask.Search("buraco negro", false), u("O que é um buraco negro?"))
        assertEquals(Ask.Search("Santos Dumont", false), u("quem foi Santos Dumont?"))
        assertEquals(Ask.Search("fotossíntese", false), u("oi nino, me explica o que é fotossíntese"))
        assertEquals(Ask.Search("receita de bolo de cenoura", true), u("pesquisa no google receita de bolo de cenoura"))
        assertTrue(u("por que o céu é azul?") is Ask.Search)
    }

    @Test fun smallTalk() {
        assertEquals(Ask.Small("oi"), u("Oi!"))
        assertEquals(Ask.Small("comovai"), u("tudo bem?"))
        assertEquals(Ask.Small("piada"), u("conta uma piada"))
        assertEquals(Ask.Small("triste"), u("tô meio triste hoje"))
        assertEquals(Ask.AboutMe, u("o que você sabe fazer?"))
        assertEquals(Ask.Unknown, u("banana azul voadora"))
    }

    @Test fun similarity() {
        assertTrue(OwnBrain.similarity("bom dia", "Bom dia!") >= 0.9)
        assertTrue(OwnBrain.similarity("qual meu time", "qual é o meu time?") >= 0.7)
    }
}
