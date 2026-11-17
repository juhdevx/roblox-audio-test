package com.voiceshift.audio

import java.io.File
import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Test

/** Keeps the Kotlin stats indices aligned with `enum StatIndex` in OboeEngine.h. */
class NativeStatsContractTest {

    @Test
    fun indicesMatchNativeEnum() {
        val header = File("src/main/cpp/OboeEngine.h").readText()
        val body = header.substringAfter("enum StatIndex : int {").substringBefore("};")
        val nativeNames = Regex("""kStat(\w+)""").findAll(body).map { it.groupValues[1] }.toList()
        val kotlinFields = NativeStats::class.java.declaredFields
            .filter { Modifier.isStatic(it.modifiers) && it.type == Int::class.javaPrimitiveType }
            .associate { it.name.replace("_", "").uppercase() to it.getInt(null) }
        nativeNames.forEachIndexed { index, name ->
            assertEquals("index of kStat$name", index, kotlinFields[name.uppercase()])
        }
        assertEquals(nativeNames.indexOf("Count"), NativeStats.COUNT)
    }

    @Test
    fun parseMapsFields() {
        val raw = DoubleArray(NativeStats.COUNT)
        raw[NativeStats.STATE] = NativeEngineState.RUNNING.toDouble()
        raw[NativeStats.AI_STATE] = 2.0
        raw[NativeStats.OUTPUT_LATENCY_MS] = 12.0
        raw[NativeStats.INPUT_LATENCY_MS] = 8.0
        raw[NativeStats.DSP_LATENCY_MS] = 42.7
        raw[NativeStats.AI_LATENCY_MS] = 150.0
        raw[NativeStats.BYPASS] = 0.0
        val stats = NativeStats.parse(raw)
        assertEquals(AiPathState.ACTIVE, stats.aiState)
        assertEquals(170f, stats.estimatedEndToEndMs!!, 0.01f)
        val dsp = stats.copy(aiState = AiPathState.FALLBACK)
        assertEquals(62.7f, dsp.estimatedEndToEndMs!!, 0.01f)
        assertEquals(20f, dsp.copy(bypass = true).estimatedEndToEndMs!!, 0.01f)
        assertEquals(null, stats.copy(outputLatencyMs = -1f).estimatedEndToEndMs)
    }
}
