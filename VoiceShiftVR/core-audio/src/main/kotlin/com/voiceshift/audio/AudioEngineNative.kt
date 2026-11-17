package com.voiceshift.audio

/**
 * Abstraction over the native engine so the controller (and everything above it) can be unit
 * tested on the JVM with a fake.
 */
interface AudioEngineNative {
    /** Null when the native engine is usable; otherwise why not (e.g. library failed to load). */
    val unavailableReason: String?

    /** Returns 0 on success, a negative oboe::Result otherwise. Blocks for up to a few hundred ms. */
    fun start(request: EngineRequest): Int
    fun stop()
    fun setParams(values: FloatArray)
    fun setParam(nativeId: Int, value: Float)
    fun setMode(mode: EngineMode)
    fun setBypass(bypass: Boolean)
    fun setMuted(muted: Boolean)
    fun setTestSignal(signal: TestSignal)
    fun setTapEnabled(enabled: Boolean)
    fun readStats(into: DoubleArray): Int
    fun lastError(): String

    // Worker-side queues (see AiBridge.h and the tap in DuplexProcessor.h).
    fun aiAvailable(): Int
    fun aiRead(dst: FloatArray, maxFrames: Int, timestampOut: LongArray): Int
    fun aiWrite(src: FloatArray, frames: Int, timestamp: Long): Int
    fun tapRead(dst: FloatArray, maxFrames: Int): Int
}

/** The real engine: one native OboeEngine instance for the whole process. */
class OboeAudioEngineNative : AudioEngineNative {

    override val unavailableReason: String? = NativeAudioBridge.loadError

    private val handle: Long by lazy {
        check(unavailableReason == null) { "Native audio library unavailable: $unavailableReason" }
        NativeAudioBridge.nativeCreate()
    }

    override fun start(request: EngineRequest): Int = NativeAudioBridge.nativeStart(
        handle,
        request.inputDeviceId,
        request.outputDeviceId,
        request.sampleRate,
        request.quality.fftSize,
        request.micMode.nativeId,
        request.exclusive,
        request.neural?.modelSampleRate ?: 0,
        request.neural?.chunkFrames ?: 0,
    )

    override fun stop() = NativeAudioBridge.nativeStop(handle)

    override fun setParams(values: FloatArray) {
        values.forEachIndexed { id, v -> NativeAudioBridge.nativeSetParam(handle, id, v) }
    }

    override fun setParam(nativeId: Int, value: Float) = NativeAudioBridge.nativeSetParam(handle, nativeId, value)
    override fun setMode(mode: EngineMode) = NativeAudioBridge.nativeSetMode(handle, mode.nativeId)
    override fun setBypass(bypass: Boolean) = NativeAudioBridge.nativeSetBypass(handle, bypass)
    override fun setMuted(muted: Boolean) = NativeAudioBridge.nativeSetMuted(handle, muted)

    override fun setTestSignal(signal: TestSignal) {
        val (freq, level) = when (signal) {
            is TestSignal.Tone -> signal.frequencyHz to signal.levelDb
            else -> 1000f to -18f
        }
        NativeAudioBridge.nativeSetTestSignal(handle, signal.nativeId, freq, level)
    }

    override fun setTapEnabled(enabled: Boolean) = NativeAudioBridge.nativeSetTapEnabled(handle, enabled)
    override fun readStats(into: DoubleArray): Int = NativeAudioBridge.nativeGetStats(handle, into)
    override fun lastError(): String = NativeAudioBridge.nativeGetLastError(handle)
    override fun aiAvailable(): Int = NativeAudioBridge.nativeAiAvailable(handle)
    override fun aiRead(dst: FloatArray, maxFrames: Int, timestampOut: LongArray): Int =
        NativeAudioBridge.nativeAiRead(handle, dst, maxFrames, timestampOut)
    override fun aiWrite(src: FloatArray, frames: Int, timestamp: Long): Int =
        NativeAudioBridge.nativeAiWrite(handle, src, frames, timestamp)
    override fun tapRead(dst: FloatArray, maxFrames: Int): Int = NativeAudioBridge.nativeTapRead(handle, dst, maxFrames)
}
