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

/**
 * The real engine: one native OboeEngine instance for the whole process.
 *
 * If libvoiceshift_audio.so cannot be loaded (unsupported ABI, corrupted install), every call
 * becomes a safe no-op and [start] fails with [unavailableReason], so the UI can explain the
 * problem instead of crashing with UnsatisfiedLinkError.
 */
class OboeAudioEngineNative : AudioEngineNative {

    override val unavailableReason: String? = NativeAudioBridge.loadError

    private val available = unavailableReason == null

    private val handle: Long by lazy { NativeAudioBridge.nativeCreate() }

    override fun start(request: EngineRequest): Int {
        if (!available) return UNAVAILABLE
        return NativeAudioBridge.nativeStart(
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
    }

    override fun stop() {
        if (available) NativeAudioBridge.nativeStop(handle)
    }

    override fun setParams(values: FloatArray) {
        values.forEachIndexed { id, v -> setParam(id, v) }
    }

    override fun setParam(nativeId: Int, value: Float) {
        if (available) NativeAudioBridge.nativeSetParam(handle, nativeId, value)
    }

    override fun setMode(mode: EngineMode) {
        if (available) NativeAudioBridge.nativeSetMode(handle, mode.nativeId)
    }

    override fun setBypass(bypass: Boolean) {
        if (available) NativeAudioBridge.nativeSetBypass(handle, bypass)
    }

    override fun setMuted(muted: Boolean) {
        if (available) NativeAudioBridge.nativeSetMuted(handle, muted)
    }

    override fun setTestSignal(signal: TestSignal) {
        if (!available) return
        val (freq, level) = when (signal) {
            is TestSignal.Tone -> signal.frequencyHz to signal.levelDb
            else -> 1000f to -18f
        }
        NativeAudioBridge.nativeSetTestSignal(handle, signal.nativeId, freq, level)
    }

    override fun setTapEnabled(enabled: Boolean) {
        if (available) NativeAudioBridge.nativeSetTapEnabled(handle, enabled)
    }

    override fun readStats(into: DoubleArray): Int {
        if (!available) {
            into.fill(0.0)
            return 0
        }
        return NativeAudioBridge.nativeGetStats(handle, into)
    }

    override fun lastError(): String =
        if (available) NativeAudioBridge.nativeGetLastError(handle) else "Native audio library unavailable: $unavailableReason"

    override fun aiAvailable(): Int = if (available) NativeAudioBridge.nativeAiAvailable(handle) else UNAVAILABLE

    override fun aiRead(dst: FloatArray, maxFrames: Int, timestampOut: LongArray): Int =
        if (available) NativeAudioBridge.nativeAiRead(handle, dst, maxFrames, timestampOut) else UNAVAILABLE

    override fun aiWrite(src: FloatArray, frames: Int, timestamp: Long): Int =
        if (available) NativeAudioBridge.nativeAiWrite(handle, src, frames, timestamp) else UNAVAILABLE

    override fun tapRead(dst: FloatArray, maxFrames: Int): Int =
        if (available) NativeAudioBridge.nativeTapRead(handle, dst, maxFrames) else UNAVAILABLE

    private companion object {
        const val UNAVAILABLE = -1
    }
}
