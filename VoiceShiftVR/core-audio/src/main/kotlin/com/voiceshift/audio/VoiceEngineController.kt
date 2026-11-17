package com.voiceshift.audio

import com.voiceshift.dsp.VoiceSettings
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Minimal logging hook so core-audio does not depend on the diagnostics module. */
fun interface EngineLog {
    enum class Level { DEBUG, INFO, WARN, ERROR }

    fun log(level: Level, message: String)

    companion object {
        val NONE = EngineLog { _, _ -> }
    }
}

/**
 * Owns the native duplex engine's lifecycle.
 *
 * * start/stop are serialised and run blocking native calls on [ioDispatcher].
 * * While running, stats are polled every [pollIntervalMs] and published on [stats].
 * * If the native side reports a disconnected or failed stream (unplugged USB interface, headset
 *   removed, audio server restart), the engine is reopened with back-off. A selected device that no
 *   longer exists falls back to the system default, and the original choice is restored automatically
 *   when that device comes back.
 */
class VoiceEngineController(
    private val native: AudioEngineNative,
    private val deviceSource: AudioDeviceSource,
    private val scope: CoroutineScope,
    private val ioDispatcher: CoroutineDispatcher,
    private val log: EngineLog = EngineLog.NONE,
    private val pollIntervalMs: Long = 50,
    private val maxRecoveryAttempts: Int = 5,
    private val recoveryBackoffMs: Long = 300,
) {
    private val _state = MutableStateFlow<EngineState>(EngineState.Idle)
    val state: StateFlow<EngineState> = _state.asStateFlow()

    private val _stats = MutableStateFlow(EngineStats.EMPTY)
    val stats: StateFlow<EngineStats> = _stats.asStateFlow()

    private val mutex = Mutex()
    private var monitorJob: Job? = null
    private var requested: EngineRequest? = null
    private var active: EngineRequest? = null
    private var settings: VoiceSettings = VoiceSettings.NEUTRAL
    private val statsBuffer = DoubleArray(NativeStats.COUNT)

    val isRunning: Boolean get() = _state.value is EngineState.Running

    /** Starts (or restarts) the engine. Returns null on success or a user-facing error message. */
    suspend fun start(request: EngineRequest): String? = mutex.withLock {
        monitorJob?.cancelAndJoin()
        monitorJob = null
        native.unavailableReason?.let { reason ->
            val message = "Native audio engine unavailable: $reason"
            _state.value = EngineState.Failed(message, -1)
            log.log(EngineLog.Level.ERROR, message)
            return@withLock message
        }
        _state.value = EngineState.Starting
        requested = request
        val resolved = resolve(request)
        native.setParams(settings.toNativeArray())
        val code = withContext(ioDispatcher) { native.start(resolved) }
        if (code != 0) {
            val message = native.lastError().ifBlank { "Audio engine failed to start (code $code)" }
            _state.value = EngineState.Failed(message, code)
            log.log(EngineLog.Level.ERROR, message)
            return@withLock message
        }
        active = resolved
        _state.value = EngineState.Running(resolved)
        log.log(EngineLog.Level.INFO, "Engine started: in=${resolved.inputDeviceId} out=${resolved.outputDeviceId} " +
            "fft=${resolved.quality.fftSize} mic=${resolved.micMode} neural=${resolved.neural}")
        monitorJob = scope.launch { monitor() }
        null
    }

    suspend fun stop() = mutex.withLock {
        monitorJob?.cancelAndJoin()
        monitorJob = null
        withContext(ioDispatcher) { native.stop() }
        if (_state.value !is EngineState.Idle) log.log(EngineLog.Level.INFO, "Engine stopped")
        _state.value = EngineState.Idle
        active = null
        _stats.value = EngineStats.EMPTY
    }

    /** Sends only the parameters that changed. Safe to call at slider rate. */
    fun applySettings(newSettings: VoiceSettings) {
        val next = newSettings.clamped()
        for (p in next.diff(settings)) native.setParam(p.nativeId, next[p])
        settings = next
    }

    fun currentSettings(): VoiceSettings = settings

    fun setMode(mode: EngineMode) = native.setMode(mode)
    fun setBypass(bypass: Boolean) = native.setBypass(bypass)
    fun setMuted(muted: Boolean) = native.setMuted(muted)
    fun setTestSignal(signal: TestSignal) = native.setTestSignal(signal)
    fun setTapEnabled(enabled: Boolean) = native.setTapEnabled(enabled)
    fun setMonitorGainDb(db: Float) = native.setMonitorGainDb(db)

    private fun resolve(request: EngineRequest): EngineRequest {
        val devices = deviceSource.devices.value
        val input = DeviceSelection.resolve(request.inputDeviceId, devices, wantInput = true)
        val output = DeviceSelection.resolve(request.outputDeviceId, devices, wantInput = false)
        if (input != request.inputDeviceId) {
            log.log(EngineLog.Level.WARN, "Input device ${request.inputDeviceId} not available; using system default")
        }
        if (output != request.outputDeviceId) {
            log.log(EngineLog.Level.WARN, "Output device ${request.outputDeviceId} not available; using system default")
        }
        // A missing monitor device simply disables monitoring (it is optional).
        val monitor = DeviceSelection.resolve(request.monitorDeviceId, devices, wantInput = false)
        if (monitor != request.monitorDeviceId) {
            log.log(EngineLog.Level.WARN, "Monitor device ${request.monitorDeviceId} not available; monitoring off")
        }
        return request.copy(inputDeviceId = input, outputDeviceId = output, monitorDeviceId = monitor)
    }

    private suspend fun monitor() {
        while (currentCoroutineContext().isActive) {
            delay(pollIntervalMs)
            val stats = withContext(ioDispatcher) {
                native.readStats(statsBuffer)
                NativeStats.parse(statsBuffer)
            }
            _stats.value = stats
            when (stats.nativeState) {
                NativeEngineState.DISCONNECTED -> if (!recover("Audio device disconnected")) return
                NativeEngineState.ERROR -> if (!recover("Audio stream error (code ${stats.lastErrorCode})")) return
                else -> restoreOriginalDevicesIfBack()
            }
        }
    }

    /** If we fell back to the default device and the user's device is present again, switch back. */
    private suspend fun restoreOriginalDevicesIfBack() {
        val want = requested ?: return
        val have = active ?: return
        if (want.inputDeviceId == have.inputDeviceId && want.outputDeviceId == have.outputDeviceId &&
            want.monitorDeviceId == have.monitorDeviceId
        ) {
            return
        }
        val devices = deviceSource.devices.value
        val inputBack = DeviceSelection.resolve(want.inputDeviceId, devices, true) == want.inputDeviceId
        val outputBack = DeviceSelection.resolve(want.outputDeviceId, devices, false) == want.outputDeviceId
        val monitorBack = DeviceSelection.resolve(want.monitorDeviceId, devices, false) == want.monitorDeviceId
        if (inputBack && outputBack && monitorBack) {
            log.log(EngineLog.Level.INFO, "Selected device reconnected; switching back")
            reopen(want)
        }
    }

    private suspend fun reopen(target: EngineRequest): Boolean {
        withContext(ioDispatcher) { native.stop() }
        val resolved = resolve(target)
        native.setParams(settings.toNativeArray())
        val code = withContext(ioDispatcher) { native.start(resolved) }
        if (code == 0) {
            active = resolved
            _state.value = EngineState.Running(resolved)
            return true
        }
        return false
    }

    private suspend fun recover(reason: String): Boolean {
        val target = requested ?: return false
        log.log(EngineLog.Level.WARN, "$reason; recovering")
        for (attempt in 1..maxRecoveryAttempts) {
            _state.value = EngineState.Recovering(attempt, reason)
            withContext(ioDispatcher) { native.stop() }
            delay(recoveryBackoffMs * attempt)
            deviceSource.refresh()
            if (reopen(target)) {
                log.log(EngineLog.Level.INFO, "Recovered on attempt $attempt")
                return true
            }
            log.log(EngineLog.Level.WARN, "Recovery attempt $attempt failed: ${native.lastError()}")
        }
        val message = "Could not reopen audio after $maxRecoveryAttempts attempts: ${native.lastError()}"
        _state.value = EngineState.Failed(message, -1)
        log.log(EngineLog.Level.ERROR, message)
        withContext(ioDispatcher) { native.stop() }
        return false
    }
}
