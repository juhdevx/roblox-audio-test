package com.voiceshift.audio

import com.voiceshift.dsp.DspQuality

/** Which transform produces the voice. Values are the native EngineMode ids. */
enum class EngineMode(val nativeId: Int) { DSP(0), NEURAL(1) }

/** Android input presets offered to the user (native ids in OboeEngine.cpp mapInputPreset). */
enum class MicMode(val nativeId: Int, val label: String, val description: String) {
    PERFORMANCE(0, "Performance", "Lowest latency, no platform processing (recommended with headphones)."),
    RECOGNITION(1, "Clean", "Unprocessed-style capture tuned for speech."),
    COMMUNICATION(2, "Echo cancel", "Platform echo cancellation / noise suppression. Higher latency; varies by phone."),
    UNPROCESSED(3, "Raw", "Raw microphone where supported."),
}

/** Diagnostic signals the engine can emit instead of the voice. Native TestSignal ids. */
sealed class TestSignal(val nativeId: Int) {
    data object None : TestSignal(0)
    data class Tone(val frequencyHz: Float = 1000f, val levelDb: Float = -18f) : TestSignal(1)
    data object LatencyProbe : TestSignal(2)
}

/** Everything needed to (re)start the duplex engine. */
data class EngineRequest(
    val inputDeviceId: Int = 0,
    val outputDeviceId: Int = 0,
    val sampleRate: Int = 48000,
    val quality: DspQuality = DspQuality.QUALITY,
    val micMode: MicMode = MicMode.PERFORMANCE,
    val exclusive: Boolean = true,
    val neural: NeuralPathConfig? = null,
)

/** Configures the native AI queues for a loaded model (model-rate frames). */
data class NeuralPathConfig(val modelSampleRate: Int, val chunkFrames: Int) {
    init {
        require(modelSampleRate in 8000..96000) { "model sample rate out of range: $modelSampleRate" }
        require(chunkFrames > 0) { "chunk must be positive" }
    }
}

sealed interface EngineState {
    data object Idle : EngineState
    data object Starting : EngineState
    data class Running(val request: EngineRequest) : EngineState
    data class Recovering(val attempt: Int, val reason: String) : EngineState
    data class Failed(val message: String, val code: Int) : EngineState
}

/** Native engine state values (EngineState in OboeEngine.h). */
object NativeEngineState {
    const val STOPPED = 0
    const val RUNNING = 1
    const val ERROR = 2
    const val DISCONNECTED = 3
}

/** Neural path state values (AiState in DuplexProcessor.h). */
enum class AiPathState { OFF, PRIMING, ACTIVE, FALLBACK;
    companion object {
        fun fromNative(v: Int): AiPathState = entries.getOrElse(v) { OFF }
    }
}
