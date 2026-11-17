package com.voiceshift.audio

/**
 * Raw JNI entry points of libvoiceshift_audio.so (core-audio/src/main/cpp/jni_bridge.cpp).
 * Use [OboeAudioEngineNative] instead of calling these directly.
 */
object NativeAudioBridge {

    /** Null when the library loaded; otherwise the reason it could not be loaded. */
    val loadError: String? = try {
        System.loadLibrary("voiceshift_audio")
        null
    } catch (e: UnsatisfiedLinkError) {
        // Keep it readable in the UI: drop the (very long) library search path.
        (e.message ?: "UnsatisfiedLinkError").substringBefore(" in java.library.path").take(200)
    }

    @JvmStatic external fun nativeCreate(): Long
    @JvmStatic external fun nativeDestroy(handle: Long)
    @JvmStatic external fun nativeStart(
        handle: Long,
        inputDeviceId: Int,
        outputDeviceId: Int,
        sampleRate: Int,
        fftSize: Int,
        inputPreset: Int,
        exclusive: Boolean,
        aiModelRate: Int,
        aiChunkFrames: Int,
        monitorDeviceId: Int,
    ): Int
    @JvmStatic external fun nativeStop(handle: Long)
    @JvmStatic external fun nativeSetParam(handle: Long, id: Int, value: Float)
    @JvmStatic external fun nativeSetMode(handle: Long, mode: Int)
    @JvmStatic external fun nativeSetBypass(handle: Long, bypass: Boolean)
    @JvmStatic external fun nativeSetMuted(handle: Long, muted: Boolean)
    @JvmStatic external fun nativeSetTestSignal(handle: Long, type: Int, frequencyHz: Float, levelDb: Float)
    @JvmStatic external fun nativeSetTapEnabled(handle: Long, enabled: Boolean)
    @JvmStatic external fun nativeSetMonitorGain(handle: Long, db: Float)
    @JvmStatic external fun nativeGetStats(handle: Long, out: DoubleArray): Int
    @JvmStatic external fun nativeGetLastError(handle: Long): String
    @JvmStatic external fun nativeAiAvailable(handle: Long): Int
    @JvmStatic external fun nativeAiRead(handle: Long, dst: FloatArray, maxFrames: Int, timestampOut: LongArray): Int
    @JvmStatic external fun nativeAiWrite(handle: Long, src: FloatArray, frames: Int, timestamp: Long): Int
    @JvmStatic external fun nativeTapRead(handle: Long, dst: FloatArray, maxFrames: Int): Int
}
