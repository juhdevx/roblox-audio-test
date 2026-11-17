package com.voiceshift.dsp

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Cross-language contract: the Kotlin parameter table must match the C++ table that the native
 * engine clamps against (core-dsp/cpp/include/voiceshift/dsp/VoiceParams.h).
 */
class VoiceParameterContractTest {

    private val header = File("cpp/include/voiceshift/dsp/VoiceParams.h").readText()

    @Test
    fun enumIdsMatchNativeHeader() {
        val ids = Regex("""k(\w+)\s*=\s*(\d+),""").findAll(header)
            .filter { it.groupValues[1] != "ParamCount" }
            .map { it.groupValues[2].toInt() }
            .toList()
        assertEquals((0 until VoiceParameter.entries.size).toList(), ids)
        val count = Regex("""kParamCount\s*=\s*(\d+)""").find(header)!!.groupValues[1].toInt()
        assertEquals(VoiceParameter.entries.size, count)
    }

    @Test
    fun rangesAndDefaultsMatchNativeHeader() {
        val table = header.substringAfter("kParamSpecs = {{").substringBefore("}};")
        val specs = Regex("""\{\s*(-?[\d.]+)f,\s*(-?[\d.]+)f,\s*(-?[\d.]+)f\s*\}""").findAll(table)
            .map { m -> Triple(m.groupValues[1].toFloat(), m.groupValues[2].toFloat(), m.groupValues[3].toFloat()) }
            .toList()
        assertEquals(VoiceParameter.entries.size, specs.size)
        for (p in VoiceParameter.entries) {
            val (min, max, def) = specs[p.nativeId]
            assertEquals("min of $p", min, p.min, 0f)
            assertEquals("max of $p", max, p.max, 0f)
            assertEquals("default of $p", def, p.default, 0f)
        }
    }

    @Test
    fun nativeIdsAreUniqueAndDense() {
        val ids = VoiceParameter.entries.map { it.nativeId }.sorted()
        assertEquals((0 until ids.size).toList(), ids)
        for (p in VoiceParameter.entries) assertTrue("$p default in range", p.default in p.min..p.max)
    }
}
