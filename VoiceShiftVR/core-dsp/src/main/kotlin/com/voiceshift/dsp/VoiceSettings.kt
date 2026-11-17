package com.voiceshift.dsp

import kotlinx.serialization.Serializable

/**
 * A complete, serialisable set of voice-processing parameters (what a preset stores).
 * Values are always kept inside [VoiceParameter] ranges via [clamped].
 */
@Serializable
data class VoiceSettings(
    val pitchSemitones: Float = VoiceParameter.PITCH_SEMITONES.default,
    val formantSemitones: Float = VoiceParameter.FORMANT_SEMITONES.default,
    val noiseReduction: Float = VoiceParameter.NOISE_REDUCTION.default,
    val gateThresholdDb: Float = VoiceParameter.GATE_THRESHOLD_DB.default,
    val agcEnabled: Boolean = false,
    val agcTargetDb: Float = VoiceParameter.AGC_TARGET_DB.default,
    val lowCutHz: Float = VoiceParameter.LOW_CUT_HZ.default,
    val bodyDb: Float = VoiceParameter.BODY_DB.default,
    val presenceDb: Float = VoiceParameter.PRESENCE_DB.default,
    val airDb: Float = VoiceParameter.AIR_DB.default,
    val compression: Float = VoiceParameter.COMPRESSION.default,
    val breathiness: Float = VoiceParameter.BREATHINESS.default,
    val outputGainDb: Float = VoiceParameter.OUTPUT_GAIN_DB.default,
) {
    operator fun get(parameter: VoiceParameter): Float = when (parameter) {
        VoiceParameter.PITCH_SEMITONES -> pitchSemitones
        VoiceParameter.FORMANT_SEMITONES -> formantSemitones
        VoiceParameter.NOISE_REDUCTION -> noiseReduction
        VoiceParameter.GATE_THRESHOLD_DB -> gateThresholdDb
        VoiceParameter.AGC_ENABLED -> if (agcEnabled) 1f else 0f
        VoiceParameter.AGC_TARGET_DB -> agcTargetDb
        VoiceParameter.LOW_CUT_HZ -> lowCutHz
        VoiceParameter.BODY_DB -> bodyDb
        VoiceParameter.PRESENCE_DB -> presenceDb
        VoiceParameter.AIR_DB -> airDb
        VoiceParameter.COMPRESSION -> compression
        VoiceParameter.BREATHINESS -> breathiness
        VoiceParameter.OUTPUT_GAIN_DB -> outputGainDb
    }

    /** Returns a copy with [parameter] set to [value] (clamped to its range). */
    fun with(parameter: VoiceParameter, value: Float): VoiceSettings {
        val v = parameter.clamp(value)
        return when (parameter) {
            VoiceParameter.PITCH_SEMITONES -> copy(pitchSemitones = v)
            VoiceParameter.FORMANT_SEMITONES -> copy(formantSemitones = v)
            VoiceParameter.NOISE_REDUCTION -> copy(noiseReduction = v)
            VoiceParameter.GATE_THRESHOLD_DB -> copy(gateThresholdDb = v)
            VoiceParameter.AGC_ENABLED -> copy(agcEnabled = v >= 0.5f)
            VoiceParameter.AGC_TARGET_DB -> copy(agcTargetDb = v)
            VoiceParameter.LOW_CUT_HZ -> copy(lowCutHz = v)
            VoiceParameter.BODY_DB -> copy(bodyDb = v)
            VoiceParameter.PRESENCE_DB -> copy(presenceDb = v)
            VoiceParameter.AIR_DB -> copy(airDb = v)
            VoiceParameter.COMPRESSION -> copy(compression = v)
            VoiceParameter.BREATHINESS -> copy(breathiness = v)
            VoiceParameter.OUTPUT_GAIN_DB -> copy(outputGainDb = v)
        }
    }

    fun clamped(): VoiceSettings =
        VoiceParameter.entries.fold(this) { acc, p -> acc.with(p, acc[p]) }

    /** Values indexed by [VoiceParameter.nativeId], ready for the JNI bridge. */
    fun toNativeArray(): FloatArray {
        val out = FloatArray(VoiceParameter.entries.size)
        for (p in VoiceParameter.entries) out[p.nativeId] = p.clamp(this[p])
        return out
    }

    /** Parameters whose value differs from [other] (used to send only changes to the engine). */
    fun diff(other: VoiceSettings): List<VoiceParameter> =
        VoiceParameter.entries.filter { this[it] != other[it] }

    companion object {
        val NEUTRAL = VoiceSettings()
    }
}
