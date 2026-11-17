package com.voiceshift.dsp

import kotlinx.serialization.json.Json
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceSettingsTest {

    @Test
    fun withClampsToRange() {
        val s = VoiceSettings().with(VoiceParameter.PITCH_SEMITONES, 99f)
        assertEquals(12f, s.pitchSemitones, 0f)
        val t = s.with(VoiceParameter.OUTPUT_GAIN_DB, -100f)
        assertEquals(-24f, t.outputGainDb, 0f)
    }

    @Test
    fun nanFallsBackToDefault() {
        val s = VoiceSettings().with(VoiceParameter.FORMANT_SEMITONES, Float.NaN)
        assertEquals(0f, s.formantSemitones, 0f)
    }

    @Test
    fun agcFlagRoundTripsThroughFloat() {
        val on = VoiceSettings().with(VoiceParameter.AGC_ENABLED, 1f)
        assertTrue(on.agcEnabled)
        assertEquals(1f, on[VoiceParameter.AGC_ENABLED], 0f)
        assertFalse(on.with(VoiceParameter.AGC_ENABLED, 0.2f).agcEnabled)
    }

    @Test
    fun nativeArrayIsIndexedByNativeId() {
        val s = VoiceSettings(pitchSemitones = 5f, airDb = 3f, outputGainDb = -6f)
        val arr = s.toNativeArray()
        assertEquals(VoiceParameter.entries.size, arr.size)
        assertEquals(5f, arr[VoiceParameter.PITCH_SEMITONES.nativeId], 0f)
        assertEquals(3f, arr[VoiceParameter.AIR_DB.nativeId], 0f)
        assertEquals(-6f, arr[VoiceParameter.OUTPUT_GAIN_DB.nativeId], 0f)
        assertEquals(80f, arr[VoiceParameter.LOW_CUT_HZ.nativeId], 0f)
    }

    @Test
    fun clampedRepairsOutOfRangeDeserializedValues() {
        val raw = VoiceSettings(pitchSemitones = 50f, lowCutHz = 5f)
        val c = raw.clamped()
        assertEquals(12f, c.pitchSemitones, 0f)
        assertEquals(20f, c.lowCutHz, 0f)
    }

    @Test
    fun diffListsChangedParameters() {
        val a = VoiceSettings()
        val b = a.copy(pitchSemitones = 4f, breathiness = 0.2f)
        assertEquals(setOf(VoiceParameter.PITCH_SEMITONES, VoiceParameter.BREATHINESS), b.diff(a).toSet())
    }

    @Test
    fun jsonRoundTripAndForwardCompatibility() {
        val json = Json { ignoreUnknownKeys = true }
        val s = VoiceSettings(pitchSemitones = 6f, agcEnabled = true)
        assertEquals(s, json.decodeFromString(VoiceSettings.serializer(), json.encodeToString(VoiceSettings.serializer(), s)))
        // Older files without newer fields still load with defaults.
        val partial = json.decodeFromString(VoiceSettings.serializer(), """{"pitchSemitones":3.0,"futureField":1}""")
        assertEquals(3f, partial.pitchSemitones, 0f)
        assertEquals(80f, partial.lowCutHz, 0f)
    }

    @Test
    fun pitchMath() {
        assertEquals(2f, PitchMath.semitonesToRatio(12f), 1e-6f)
        assertEquals(7f, PitchMath.ratioToSemitones(PitchMath.semitonesToRatio(7f)), 1e-4f)
        assertEquals(164.8f, PitchMath.shiftedFrequency(110f, 7f), 0.1f)
        assertArrayEquals(intArrayOf(1024, 2048), DspQuality.entries.map { it.fftSize }.toIntArray())
        assertEquals(42.67f, DspQuality.QUALITY.algorithmicLatencyMs(48000), 0.01f)
    }
}
