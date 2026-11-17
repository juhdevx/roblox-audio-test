package com.voiceshift.dsp

import kotlin.math.log2
import kotlin.math.roundToInt

/** Result of a calibration run: the speaker's measured pitch and the settings that reach the target. */
data class CalibrationResult(
    val medianHz: Float,
    val lowHz: Float,
    val highHz: Float,
    val samples: Int,
    val targetHz: Float,
    val suggestedPitchSemitones: Float,
    val suggestedFormantSemitones: Float,
) {
    /** Expected median speaking pitch after applying the suggested shift. */
    val expectedOutputHz: Float get() = medianHz * PitchMath.semitonesToRatio(suggestedPitchSemitones)
}

/**
 * Collects voiced pitch readings while the user reads aloud and suggests pitch/formant shifts that
 * move their *median speaking pitch* to [targetHz].
 *
 * Typical adult speaking fundamentals: roughly 85-155 Hz for lower voices and 165-255 Hz for higher
 * voices, so 200 Hz is a mid-range feminine target. Shifts are capped at +9 st because larger
 * shifts sound artificial with any real-time method; formants follow at about a third of the pitch
 * shift (≈ +10-20 %), which keeps vowels natural.
 */
class PitchCalibration(val targetHz: Float = DEFAULT_TARGET_HZ) {
    private val readings = ArrayList<Float>()

    val sampleCount: Int get() = readings.size

    /** Adds one reading from the native tracker; unvoiced or low-confidence readings are ignored. */
    fun add(pitchHz: Float, confidence: Float) {
        if (pitchHz in MIN_HZ..MAX_HZ && confidence >= MIN_CONFIDENCE) readings += pitchHz
    }

    fun reset() = readings.clear()

    /** Null until enough voiced speech was heard (about a second of talking). */
    fun result(): CalibrationResult? {
        if (readings.size < MIN_SAMPLES) return null
        val sorted = readings.sorted()
        fun percentile(p: Float) = sorted[((sorted.size - 1) * p).roundToInt()]
        val median = percentile(0.5f)
        val rawShift = 12f * log2(targetHz / median)
        val pitch = roundToHalf(rawShift.coerceIn(0f, MAX_PITCH_SHIFT))
        val formant = roundToHalf((pitch * FORMANT_FRACTION).coerceIn(0f, MAX_FORMANT_SHIFT))
        return CalibrationResult(
            medianHz = median,
            lowHz = percentile(0.1f),
            highHz = percentile(0.9f),
            samples = sorted.size,
            targetHz = targetHz,
            suggestedPitchSemitones = pitch,
            suggestedFormantSemitones = formant,
        )
    }

    private fun roundToHalf(v: Float) = (v * 2f).roundToInt() / 2f

    companion object {
        const val DEFAULT_TARGET_HZ = 200f
        const val MIN_HZ = 60f
        const val MAX_HZ = 600f
        const val MIN_CONFIDENCE = 0.6f
        const val MIN_SAMPLES = 20
        const val MAX_PITCH_SHIFT = 9f
        const val MAX_FORMANT_SHIFT = 3f
        const val FORMANT_FRACTION = 0.35f

        /** Target presets offered in the UI. */
        val TARGETS: List<Pair<String, Float>> = listOf("Lower" to 175f, "Mid" to 200f, "Higher" to 225f)
    }
}
