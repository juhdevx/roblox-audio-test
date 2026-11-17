package com.voiceshift.dsp

import kotlin.math.log2
import kotlin.math.pow

/**
 * Every voice parameter understood by the native engine.
 *
 * [nativeId], [min], [max] and [default] mirror `kParamSpecs` in
 * `core-dsp/cpp/include/voiceshift/dsp/VoiceParams.h`; `VoiceParameterContractTest` parses that
 * header and fails the build if the two drift apart.
 */
enum class VoiceParameter(
    val nativeId: Int,
    val min: Float,
    val max: Float,
    val default: Float,
    val unit: String,
    val label: String,
) {
    PITCH_SEMITONES(0, -12f, 12f, 0f, "st", "Pitch"),
    FORMANT_SEMITONES(1, -6f, 6f, 0f, "st", "Formant"),
    NOISE_REDUCTION(2, 0f, 1f, 0f, "", "Noise reduction"),
    GATE_THRESHOLD_DB(3, -80f, -20f, -80f, "dB", "Noise gate threshold"),
    AGC_ENABLED(4, 0f, 1f, 0f, "", "Automatic gain"),
    AGC_TARGET_DB(5, -30f, -10f, -20f, "dB", "AGC target level"),
    LOW_CUT_HZ(6, 20f, 300f, 80f, "Hz", "Low cut"),
    BODY_DB(7, -12f, 6f, 0f, "dB", "Body (220 Hz)"),
    PRESENCE_DB(8, -6f, 9f, 0f, "dB", "Presence (3 kHz)"),
    AIR_DB(9, -6f, 9f, 0f, "dB", "Air (8 kHz)"),
    COMPRESSION(10, 0f, 1f, 0f, "", "Compression"),
    BREATHINESS(11, 0f, 1f, 0f, "", "Breathiness"),
    OUTPUT_GAIN_DB(12, -24f, 12f, 0f, "dB", "Output gain");

    fun clamp(value: Float): Float = if (value.isNaN()) default else value.coerceIn(min, max)

    companion object {
        val byNativeId: Map<Int, VoiceParameter> = entries.associateBy { it.nativeId }
    }
}

/** Musical helpers for pitch/formant controls. */
object PitchMath {
    fun semitonesToRatio(semitones: Float): Float = 2.0.pow(semitones / 12.0).toFloat()

    fun ratioToSemitones(ratio: Float): Float {
        require(ratio > 0f) { "ratio must be positive" }
        return (12.0 * log2(ratio.toDouble())).toFloat()
    }

    /** Fundamental frequency after shifting [f0Hz] by [semitones]. */
    fun shiftedFrequency(f0Hz: Float, semitones: Float): Float = f0Hz * semitonesToRatio(semitones)
}

/**
 * STFT size used by the DSP engine. Larger frames resolve the harmonics of low voices (better
 * quality) at the cost of algorithmic latency (= frame length).
 */
enum class DspQuality(val fftSize: Int, val label: String) {
    LOW_LATENCY(1024, "Low latency (21 ms)"),
    QUALITY(2048, "High quality (43 ms)");

    fun algorithmicLatencyMs(sampleRate: Int): Float = fftSize * 1000f / sampleRate
}
