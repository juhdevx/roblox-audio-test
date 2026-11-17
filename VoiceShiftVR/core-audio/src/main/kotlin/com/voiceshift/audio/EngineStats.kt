package com.voiceshift.audio

/**
 * Indices of the stats array filled by the native engine (StatIndex in OboeEngine.h).
 * `NativeStatsContractTest` parses the header to keep both sides in sync.
 */
object NativeStats {
    const val STATE = 0
    const val SAMPLE_RATE = 1
    const val FRAMES_PER_BURST = 2
    const val BUFFER_SIZE = 3
    const val INPUT_PEAK_DB = 4
    const val INPUT_RMS_DB = 5
    const val OUTPUT_PEAK_DB = 6
    const val OUTPUT_RMS_DB = 7
    const val OUTPUT_LATENCY_MS = 8
    const val INPUT_LATENCY_MS = 9
    const val DSP_LATENCY_MS = 10
    const val AI_LATENCY_MS = 11
    const val CALLBACK_COUNT = 12
    const val XRUN_COUNT = 13
    const val INPUT_UNDERFLOWS = 14
    const val INPUT_DRAINS = 15
    const val LOAD_AVG_PCT = 16
    const val LOAD_PEAK_PCT = 17
    const val DSP_FAULTS = 18
    const val AI_STATE = 19
    const val AI_UNDERRUNS = 20
    const val AI_OVERFLOWS = 21
    const val PROBE_LATENCY_MS = 22
    const val TONE_DB = 23
    const val TONE_SNR_DB = 24
    const val INPUT_DEVICE_ID = 25
    const val OUTPUT_DEVICE_ID = 26
    const val OUTPUT_EXCLUSIVE = 27
    const val INPUT_EXCLUSIVE = 28
    const val LAST_ERROR = 29
    const val GATE_OPEN = 30
    const val AGC_GAIN_DB = 31
    const val LIMITER_REDUCTION_DB = 32
    const val TAP_OVERFLOWS = 33
    const val AI_DISCONTINUITIES = 34
    const val OUTPUT_CHANNELS = 35
    const val COMPRESSOR_REDUCTION_DB = 36
    const val MODE = 37
    const val BYPASS = 38
    const val FRAMES_PROCESSED = 39
    const val INPUT_PITCH_HZ = 40
    const val PITCH_CONFIDENCE = 41
    const val MONITOR_ACTIVE = 42
    const val MONITOR_UNDERRUNS = 43
    const val MONITOR_DRIFT_CORRECTIONS = 44
    const val MONITOR_DEVICE_ID = 45
    const val COUNT = 46

    fun parse(raw: DoubleArray): EngineStats {
        require(raw.size >= COUNT) { "stats array too small: ${raw.size}" }
        fun f(i: Int) = raw[i].toFloat()
        fun l(i: Int) = raw[i].toLong()
        return EngineStats(
            nativeState = raw[STATE].toInt(),
            sampleRate = raw[SAMPLE_RATE].toInt(),
            framesPerBurst = raw[FRAMES_PER_BURST].toInt(),
            bufferSizeFrames = raw[BUFFER_SIZE].toInt(),
            inputPeakDb = f(INPUT_PEAK_DB),
            inputRmsDb = f(INPUT_RMS_DB),
            outputPeakDb = f(OUTPUT_PEAK_DB),
            outputRmsDb = f(OUTPUT_RMS_DB),
            outputLatencyMs = f(OUTPUT_LATENCY_MS),
            inputLatencyMs = f(INPUT_LATENCY_MS),
            dspLatencyMs = f(DSP_LATENCY_MS),
            aiLatencyMs = f(AI_LATENCY_MS),
            callbackCount = l(CALLBACK_COUNT),
            xRunCount = l(XRUN_COUNT),
            inputUnderflows = l(INPUT_UNDERFLOWS),
            inputDrains = l(INPUT_DRAINS),
            callbackLoadAvgPct = f(LOAD_AVG_PCT),
            callbackLoadPeakPct = f(LOAD_PEAK_PCT),
            dspFaults = l(DSP_FAULTS),
            aiState = AiPathState.fromNative(raw[AI_STATE].toInt()),
            aiUnderruns = l(AI_UNDERRUNS),
            aiOverflows = l(AI_OVERFLOWS),
            probeLatencyMs = f(PROBE_LATENCY_MS),
            toneDb = f(TONE_DB),
            toneSnrDb = f(TONE_SNR_DB),
            inputDeviceId = raw[INPUT_DEVICE_ID].toInt(),
            outputDeviceId = raw[OUTPUT_DEVICE_ID].toInt(),
            outputExclusive = raw[OUTPUT_EXCLUSIVE] > 0.5,
            inputExclusive = raw[INPUT_EXCLUSIVE] > 0.5,
            lastErrorCode = raw[LAST_ERROR].toInt(),
            gateOpen = raw[GATE_OPEN] > 0.5,
            agcGainDb = f(AGC_GAIN_DB),
            limiterReductionDb = f(LIMITER_REDUCTION_DB),
            tapOverflows = l(TAP_OVERFLOWS),
            aiDiscontinuities = l(AI_DISCONTINUITIES),
            outputChannels = raw[OUTPUT_CHANNELS].toInt(),
            compressorReductionDb = f(COMPRESSOR_REDUCTION_DB),
            mode = raw[MODE].toInt(),
            bypass = raw[BYPASS] > 0.5,
            framesProcessed = l(FRAMES_PROCESSED),
            inputPitchHz = f(INPUT_PITCH_HZ),
            pitchConfidence = f(PITCH_CONFIDENCE),
            monitorActive = raw[MONITOR_ACTIVE] > 0.5,
            monitorUnderruns = l(MONITOR_UNDERRUNS),
            monitorDriftCorrections = l(MONITOR_DRIFT_CORRECTIONS),
            monitorDeviceId = raw[MONITOR_DEVICE_ID].toInt(),
        )
    }
}

/** Snapshot of engine health, refreshed ~20x per second while running. */
data class EngineStats(
    val nativeState: Int = NativeEngineState.STOPPED,
    val sampleRate: Int = 0,
    val framesPerBurst: Int = 0,
    val bufferSizeFrames: Int = 0,
    val inputPeakDb: Float = -120f,
    val inputRmsDb: Float = -120f,
    val outputPeakDb: Float = -120f,
    val outputRmsDb: Float = -120f,
    val outputLatencyMs: Float = -1f,
    val inputLatencyMs: Float = -1f,
    val dspLatencyMs: Float = 0f,
    val aiLatencyMs: Float = 0f,
    val callbackCount: Long = 0,
    val xRunCount: Long = 0,
    val inputUnderflows: Long = 0,
    val inputDrains: Long = 0,
    val callbackLoadAvgPct: Float = 0f,
    val callbackLoadPeakPct: Float = 0f,
    val dspFaults: Long = 0,
    val aiState: AiPathState = AiPathState.OFF,
    val aiUnderruns: Long = 0,
    val aiOverflows: Long = 0,
    val probeLatencyMs: Float = -1f,
    val toneDb: Float = -120f,
    val toneSnrDb: Float = -120f,
    val inputDeviceId: Int = 0,
    val outputDeviceId: Int = 0,
    val outputExclusive: Boolean = false,
    val inputExclusive: Boolean = false,
    val lastErrorCode: Int = 0,
    val gateOpen: Boolean = true,
    val agcGainDb: Float = 0f,
    val limiterReductionDb: Float = 0f,
    val tapOverflows: Long = 0,
    val aiDiscontinuities: Long = 0,
    val outputChannels: Int = 0,
    val compressorReductionDb: Float = 0f,
    val mode: Int = 0,
    val bypass: Boolean = false,
    val framesProcessed: Long = 0,
    /** Median speaking pitch of the microphone signal, 0 when unvoiced/silent. */
    val inputPitchHz: Float = 0f,
    val pitchConfidence: Float = 0f,
    val monitorActive: Boolean = false,
    val monitorUnderruns: Long = 0,
    val monitorDriftCorrections: Long = 0,
    val monitorDeviceId: Int = 0,
) {
    /**
     * Estimated mic-to-speaker latency: platform input + output latency (when the device reports
     * timestamps) plus the algorithmic delay of the active transform. Null when unknown.
     */
    val estimatedEndToEndMs: Float?
        get() {
            if (outputLatencyMs < 0f || inputLatencyMs < 0f) return null
            val transform = when {
                bypass -> 0f
                aiState == AiPathState.ACTIVE -> aiLatencyMs
                else -> dspLatencyMs
            }
            return inputLatencyMs + outputLatencyMs + transform
        }

    /** Rough clipping indicator for the UI (limiter working hard or output at full scale). */
    val outputHot: Boolean get() = outputPeakDb > -1.5f || limiterReductionDb < -6f

    companion object {
        val EMPTY = EngineStats()
    }
}
