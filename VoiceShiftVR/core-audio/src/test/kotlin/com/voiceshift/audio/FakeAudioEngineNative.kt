package com.voiceshift.audio

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Scriptable stand-in for the native engine. */
class FakeAudioEngineNative : AudioEngineNative {
    override var unavailableReason: String? = null
    val startResults = ArrayDeque<Int>()
    val startedWith = mutableListOf<EngineRequest>()
    val params = FloatArray(com.voiceshift.dsp.VoiceParameter.entries.size)
    val paramWrites = mutableListOf<Pair<Int, Float>>()
    var stopCount = 0
    var nativeState = NativeEngineState.STOPPED
    var errorText = ""
    var lastMode: EngineMode = EngineMode.DSP
    var lastBypass = false

    override fun start(request: EngineRequest): Int {
        startedWith += request
        val code = startResults.removeFirstOrNull() ?: 0
        nativeState = if (code == 0) NativeEngineState.RUNNING else NativeEngineState.ERROR
        return code
    }

    override fun stop() {
        stopCount++
        nativeState = NativeEngineState.STOPPED
    }

    override fun setParams(values: FloatArray) = values.forEachIndexed { i, v -> params[i] = v }
    override fun setParam(nativeId: Int, value: Float) {
        params[nativeId] = value
        paramWrites += nativeId to value
    }
    override fun setMode(mode: EngineMode) { lastMode = mode }
    override fun setBypass(bypass: Boolean) { lastBypass = bypass }
    override fun setMuted(muted: Boolean) = Unit
    override fun setTestSignal(signal: TestSignal) = Unit
    override fun setTapEnabled(enabled: Boolean) = Unit
    var lastMonitorGainDb = 0f
    override fun setMonitorGainDb(db: Float) { lastMonitorGainDb = db }

    override fun readStats(into: DoubleArray): Int {
        into.fill(0.0)
        into[NativeStats.STATE] = nativeState.toDouble()
        into[NativeStats.SAMPLE_RATE] = 48000.0
        into[NativeStats.INPUT_PEAK_DB] = -20.0
        return NativeStats.COUNT
    }

    override fun lastError(): String = errorText
    override fun aiAvailable(): Int = -2
    override fun aiRead(dst: FloatArray, maxFrames: Int, timestampOut: LongArray): Int = -2
    override fun aiWrite(src: FloatArray, frames: Int, timestamp: Long): Int = -2
    override fun tapRead(dst: FloatArray, maxFrames: Int): Int = 0
}

class FakeDeviceSource(initial: List<AudioDevice>) : AudioDeviceSource {
    val flow = MutableStateFlow(initial)
    var refreshCount = 0
    override val devices: StateFlow<List<AudioDevice>> = flow
    override fun refresh() { refreshCount++ }

    companion object {
        val MIC = AudioDevice(1, "", DeviceKind.BUILTIN_MIC, isInput = true, isOutput = false)
        val SPEAKER = AudioDevice(2, "", DeviceKind.BUILTIN_SPEAKER, isInput = false, isOutput = true)
        val USB_OUT = AudioDevice(30, "USB Audio", DeviceKind.USB_DEVICE, isInput = false, isOutput = true)
        val USB_IN = AudioDevice(31, "USB Audio", DeviceKind.USB_DEVICE, isInput = true, isOutput = false)
        val HEADPHONES = AudioDevice(40, "", DeviceKind.WIRED_HEADPHONES, isInput = false, isOutput = true)
    }
}
