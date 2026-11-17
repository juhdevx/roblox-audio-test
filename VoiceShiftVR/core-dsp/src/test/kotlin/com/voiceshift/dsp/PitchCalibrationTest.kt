package com.voiceshift.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class PitchCalibrationTest {

    @Test
    fun needsEnoughVoicedReadings() {
        val c = PitchCalibration()
        repeat(19) { c.add(120f, 0.9f) }
        assertNull(c.result())
        c.add(0f, 0f)          // unvoiced: ignored
        c.add(120f, 0.3f)      // low confidence: ignored
        assertEquals(19, c.sampleCount)
        c.add(120f, 0.9f)
        assertNotNull(c.result())
    }

    @Test
    fun lowVoiceGetsCappedShiftTowardTarget() {
        val c = PitchCalibration(targetHz = 200f)
        listOf(100f, 105f, 110f, 112f, 115f, 118f, 120f, 125f, 130f, 140f).forEach { hz -> repeat(3) { c.add(hz, 0.9f) } }
        val r = c.result()!!
        assertEquals(118f, r.medianHz, 0.01f)
        // 12*log2(200/118) = 9.13 st -> capped at 9.
        assertEquals(9f, r.suggestedPitchSemitones, 0f)
        assertEquals(3f, r.suggestedFormantSemitones, 0f)
        assertEquals(198.5f, r.expectedOutputHz, 0.5f)
        assertEquals(105f, r.lowHz, 0.01f)
        assertEquals(130f, r.highHz, 0.01f)
    }

    @Test
    fun midVoiceGetsModerateShift() {
        val c = PitchCalibration(targetHz = 200f)
        repeat(40) { c.add(150f, 0.95f) }
        val r = c.result()!!
        // 12*log2(200/150) = 4.98 -> 5.0 st; formant 5*0.35 = 1.75 -> 2.0 (rounded to 0.5).
        assertEquals(5f, r.suggestedPitchSemitones, 0f)
        assertEquals(2f, r.suggestedFormantSemitones, 0f)
    }

    @Test
    fun alreadyHighVoiceIsNotLowered() {
        val c = PitchCalibration(targetHz = 200f)
        repeat(30) { c.add(230f, 0.9f) }
        val r = c.result()!!
        assertEquals(0f, r.suggestedPitchSemitones, 0f)
        assertEquals(0f, r.suggestedFormantSemitones, 0f)
    }
}
