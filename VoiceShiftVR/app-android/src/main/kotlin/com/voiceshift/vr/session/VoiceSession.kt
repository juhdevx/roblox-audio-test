package com.voiceshift.vr.session

import android.content.Context
import android.net.Uri
import android.os.Build
import com.voiceshift.audio.AudioDeviceSource
import com.voiceshift.audio.AudioEngineNative
import com.voiceshift.audio.DeviceSelection
import com.voiceshift.audio.EngineMode
import com.voiceshift.audio.EngineRequest
import com.voiceshift.audio.EngineState
import com.voiceshift.audio.MicMode
import com.voiceshift.audio.NeuralPathConfig
import com.voiceshift.audio.TestSignal
import com.voiceshift.audio.VoiceEngineController
import com.voiceshift.bridge.network.LocalNetwork
import com.voiceshift.bridge.network.PcmSource
import com.voiceshift.bridge.network.SenderStats
import com.voiceshift.bridge.network.UdpPcmSender
import com.voiceshift.bridge.usb.RouteDiagnostics
import com.voiceshift.bridge.usb.RouteReport
import com.voiceshift.bridge.usb.UsbAudioInspector
import com.voiceshift.diagnostics.DiagnosticReport
import com.voiceshift.diagnostics.DiagnosticsLog
import com.voiceshift.diagnostics.PerfSnapshot
import com.voiceshift.diagnostics.PerformanceMonitor
import com.voiceshift.dsp.DspQuality
import com.voiceshift.dsp.VoiceParameter
import com.voiceshift.dsp.VoiceSettings
import com.voiceshift.inference.AudioStreamPort
import com.voiceshift.inference.OrtInferenceSession
import com.voiceshift.inference.StreamingInferenceWorker
import com.voiceshift.inference.StreamingSpec
import com.voiceshift.inference.WorkerState
import com.voiceshift.inference.WorkerStats
import com.voiceshift.models.AppSettings
import com.voiceshift.models.BuiltInPresets
import com.voiceshift.models.ConsentDeclaration
import com.voiceshift.models.ImportResult
import com.voiceshift.models.LoadDecision
import com.voiceshift.models.LoadPlanner
import com.voiceshift.models.MemoryBudget
import com.voiceshift.models.ModelRecord
import com.voiceshift.models.ModelRegistry
import com.voiceshift.models.PresetEngine
import com.voiceshift.models.PresetRepository
import com.voiceshift.models.SettingsRepository
import com.voiceshift.models.ValidationResult
import com.voiceshift.models.VoicePreset
import com.voiceshift.vr.BuildConfig
import com.voiceshift.vr.di.AppScope
import com.voiceshift.vr.di.IoDispatcher
import com.voiceshift.vr.service.VoiceEngineService
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** State of the neural engine (Engine B). */
data class NeuralStatus(
    val loadedModelId: String? = null,
    val loadedModelName: String? = null,
    val spec: StreamingSpec? = null,
    val worker: WorkerStats = WorkerStats(),
    val loading: Boolean = false,
)

data class NetworkStatus(
    val streaming: Boolean = false,
    val target: String = "",
    val sender: SenderStats = SenderStats(),
    val localAddresses: List<String> = emptyList(),
)

/**
 * Application-level orchestrator (domain layer) shared by every screen and the foreground service.
 * It owns the single native engine, applies user settings, manages the neural model/worker and the
 * experimental network stream, and persists everything through the repositories.
 */
@OptIn(FlowPreview::class)
@Singleton
class VoiceSession @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val controller: VoiceEngineController,
    private val native: AudioEngineNative,
    private val deviceSource: AudioDeviceSource,
    private val settingsRepo: SettingsRepository,
    private val presetRepo: PresetRepository,
    private val registry: ModelRegistry,
    private val memoryBudget: MemoryBudget,
    private val perfMonitor: PerformanceMonitor,
    private val usb: UsbAudioInspector,
    val log: DiagnosticsLog,
    @param:AppScope private val scope: CoroutineScope,
    @param:IoDispatcher private val io: CoroutineDispatcher,
) {
    val engineState: StateFlow<EngineState> = controller.state
    val stats = controller.stats
    val settings: StateFlow<AppSettings> = settingsRepo.settings
    val devices = deviceSource.devices
    val presets: StateFlow<List<VoicePreset>> =
        presetRepo.presets.stateIn(scope, SharingStarted.Eagerly, presetRepo.snapshot())
    val models: StateFlow<List<ModelRecord>> = registry.records

    private val _voice = MutableStateFlow(settingsRepo.settings.value.voice)
    val voice: StateFlow<VoiceSettings> = _voice.asStateFlow()

    private val _neural = MutableStateFlow(NeuralStatus())
    val neural: StateFlow<NeuralStatus> = _neural.asStateFlow()

    private val _perf = MutableStateFlow<PerfSnapshot?>(null)
    val perf: StateFlow<PerfSnapshot?> = _perf.asStateFlow()

    private val _network = MutableStateFlow(NetworkStatus())
    val network: StateFlow<NetworkStatus> = _network.asStateFlow()

    private val _testSignal = MutableStateFlow<TestSignal>(TestSignal.None)
    val testSignal: StateFlow<TestSignal> = _testSignal.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 16)
    val messages: SharedFlow<String> = _messages.asSharedFlow()

    val nativeUnavailableReason: String? get() = native.unavailableReason

    private val opMutex = Mutex()
    private var inference: OrtInferenceSession? = null
    private var worker: StreamingInferenceWorker? = null
    private var workerWatch: Job? = null
    private var sender: UdpPcmSender? = null
    private var senderWatch: Job? = null

    private val nativePort = object : AudioStreamPort {
        override fun available(): Int = native.aiAvailable()
        override fun read(dst: FloatArray, maxFrames: Int, timestampOut: LongArray): Int =
            native.aiRead(dst, maxFrames, timestampOut)
        override fun write(src: FloatArray, frames: Int, timestamp: Long): Int = native.aiWrite(src, frames, timestamp)
    }

    init {
        controller.applySettings(_voice.value)
        val s = settingsRepo.settings.value
        if (native.unavailableReason == null) {
            native.setBypass(s.bypass)
            native.setMuted(s.monitorMuted)
            native.setMode(EngineMode.DSP)
            native.setMonitorGainDb(s.monitorVolumeDb)
        }
        log.i("App", "VoiceShift ${BuildConfig.VERSION_NAME} on ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        if (settingsRepo.recoveredFromCorruption) message("Settings file was damaged and has been reset.")
        native.unavailableReason?.let { log.e("App", "Native engine unavailable: $it") }

        // Persist slider changes without writing the file on every drag step.
        scope.launch { _voice.drop(1).debounce(400).collect { v -> settingsRepo.update { it.copy(voice = v) } } }
        scope.launch {
            while (true) {
                _perf.value = runCatching { perfMonitor.sample() }.getOrNull()
                delay(1000)
            }
        }
        // Restore the last neural model in the background (it stays in DSP mode if this fails).
        s.activeModelId?.let { id -> scope.launch { loadModel(id, quiet = true) } }
    }

    fun message(text: String) {
        _messages.tryEmit(text)
    }

    // ------------------------------------------------------------------ engine lifecycle

    private fun buildRequest(s: AppSettings) = EngineRequest(
        inputDeviceId = s.inputDeviceId,
        outputDeviceId = s.outputDeviceId,
        sampleRate = 48000,
        quality = DspQuality.entries.firstOrNull { it.name == s.quality } ?: DspQuality.QUALITY,
        micMode = MicMode.entries.firstOrNull { it.name == s.micMode } ?: MicMode.PERFORMANCE,
        exclusive = s.exclusiveAudio,
        neural = inference?.spec?.let { NeuralPathConfig(it.sampleRate, it.chunkFrames) },
        monitorDeviceId = s.monitorDeviceId,
    )

    private fun effectiveMode(s: AppSettings): EngineMode =
        if (s.engineMode == EngineMode.NEURAL.name && inference != null) EngineMode.NEURAL else EngineMode.DSP

    suspend fun start(): String? = opMutex.withLock {
        _busy.value = true
        try {
            startLocked()
        } finally {
            _busy.value = false
        }
    }

    private suspend fun startLocked(): String? {
        val s = settings.value
        native.setBypass(s.bypass)
        native.setMuted(s.monitorMuted)
        native.setMode(effectiveMode(s))
        native.setTestSignal(_testSignal.value)
        val error = controller.start(buildRequest(s))
        if (error != null) {
            message(error)
            return error
        }
        if (DeviceSelection.feedbackRisk(s.inputDeviceId, s.outputDeviceId, devices.value) && !s.monitorMuted) {
            message("Feedback risk: the phone speaker is playing your processed voice. Use headphones or mute monitoring.")
        }
        VoiceEngineService.start(context)
        startWorkerIfNeeded()
        sender?.let { native.setTapEnabled(true) }
        return null
    }

    suspend fun stop() = opMutex.withLock {
        _busy.value = true
        try {
            stopWorker()
            stopNetworkInternal()
            controller.stop()
            VoiceEngineService.stop(context)
        } finally {
            _busy.value = false
        }
    }

    /** Re-opens the streams with the current settings (device / quality / model change). */
    private suspend fun restartIfRunning() = opMutex.withLock {
        if (!controller.isRunning) return@withLock
        stopWorker()
        startLocked()
    }

    // ------------------------------------------------------------------ voice parameters and presets

    fun setVoiceParameter(parameter: VoiceParameter, value: Float) {
        val next = _voice.value.with(parameter, value)
        _voice.value = next
        controller.applySettings(next)
    }

    fun applyPreset(preset: VoicePreset) {
        _voice.value = preset.settings
        controller.applySettings(preset.settings)
        scope.launch {
            settingsRepo.update { it.copy(activePresetId = preset.id, voice = preset.settings) }
            val modelId = preset.modelId
            if (preset.engine == PresetEngine.NEURAL && modelId != null) {
                if (loadModel(modelId) == null) setEngineMode(EngineMode.NEURAL)
            } else if (settings.value.engineMode == EngineMode.NEURAL.name && preset.engine == PresetEngine.DSP) {
                setEngineMode(EngineMode.DSP)
            }
        }
        log.i("Voice", "Applied preset '${preset.name}'")
    }

    fun resetToActivePreset() {
        val preset = presetRepo.find(settings.value.activePresetId) ?: BuiltInPresets.DEFAULT
        _voice.value = preset.settings
        controller.applySettings(preset.settings)
    }

    suspend fun saveCurrentAsPreset(name: String): VoicePreset? = runCatching {
        val s = settings.value
        val neural = s.engineMode == EngineMode.NEURAL.name && _neural.value.loadedModelId != null
        presetRepo.save(
            name = name,
            settings = _voice.value,
            engine = if (neural) PresetEngine.NEURAL else PresetEngine.DSP,
            modelId = if (neural) _neural.value.loadedModelId else null,
        ).also {
            settingsRepo.update { st -> st.copy(activePresetId = it.id) }
            message("Saved preset '${it.name}'")
        }
    }.onFailure { message(it.message ?: "Could not save preset") }.getOrNull()

    suspend fun overwritePreset(id: String) {
        presetRepo.update(id, _voice.value)?.let { message("Updated '${it.name}'") }
    }

    suspend fun deletePreset(id: String) {
        if (presetRepo.delete(id)) {
            if (settings.value.activePresetId == id) settingsRepo.update { it.copy(activePresetId = BuiltInPresets.DEFAULT.id) }
            message("Preset deleted")
        }
    }

    // ------------------------------------------------------------------ engine options

    suspend fun setEngineMode(mode: EngineMode) {
        if (mode == EngineMode.NEURAL && inference == null) {
            message("Load a compatible model in the Models tab to use the AI engine.")
            return
        }
        settingsRepo.update { it.copy(engineMode = mode.name) }
        native.setMode(mode)
        if (mode == EngineMode.NEURAL) {
            val running = controller.state.value as? EngineState.Running
            if (running != null && running.request.neural == null) restartIfRunning() else startWorkerIfNeeded()
        } else {
            stopWorker()
        }
        log.i("Engine", "Engine mode: $mode")
    }

    suspend fun setBypass(bypass: Boolean) {
        native.setBypass(bypass)
        settingsRepo.update { it.copy(bypass = bypass) }
    }

    suspend fun setMonitorMuted(muted: Boolean) {
        native.setMuted(muted)
        settingsRepo.update { it.copy(monitorMuted = muted) }
    }

    suspend fun selectInputDevice(id: Int) {
        settingsRepo.update { it.copy(inputDeviceId = id) }
        restartIfRunning()
    }

    suspend fun selectOutputDevice(id: Int) {
        settingsRepo.update { it.copy(outputDeviceId = id) }
        restartIfRunning()
    }

    suspend fun selectMonitorDevice(id: Int) {
        settingsRepo.update { it.copy(monitorDeviceId = id) }
        restartIfRunning()
    }

    fun setMonitorVolume(db: Float) {
        native.setMonitorGainDb(db)
        scope.launch { settingsRepo.update { it.copy(monitorVolumeDb = db) } }
    }

    suspend fun setQuality(quality: DspQuality) {
        settingsRepo.update { it.copy(quality = quality.name) }
        restartIfRunning()
    }

    suspend fun setMicMode(mode: MicMode) {
        settingsRepo.update { it.copy(micMode = mode.name) }
        restartIfRunning()
    }

    suspend fun setExclusive(exclusive: Boolean) {
        settingsRepo.update { it.copy(exclusiveAudio = exclusive) }
        restartIfRunning()
    }

    suspend fun setKeepScreenOn(keep: Boolean) = settingsRepo.update { it.copy(keepScreenOn = keep) }

    fun refreshDevices() = deviceSource.refresh()

    // ------------------------------------------------------------------ diagnostics signals

    fun setTestSignal(signal: TestSignal) {
        _testSignal.value = signal
        native.setTestSignal(signal)
        log.i("Route", "Test signal: $signal")
        if (signal is TestSignal.Tone) {
            scope.launch {
                settingsRepo.update { it.copy(testToneLevelDb = signal.levelDb, testToneFrequencyHz = signal.frequencyHz) }
            }
        }
    }

    fun routeReport(): RouteReport = RouteDiagnostics.evaluate(
        audioDevices = devices.value,
        usbDevices = runCatching { usb.attachedDevices() }.getOrDefault(emptyList()),
        usbHostSupported = usb.usbHostSupported,
        selectedOutputId = settings.value.outputDeviceId,
        stats = if (controller.isRunning) stats.value else null,
        testToneActive = _testSignal.value is TestSignal.Tone,
    )

    suspend fun recordValidation(stepId: String, result: ValidationResult, note: String) {
        settingsRepo.recordValidation(stepId, result, note)
        log.i("Validation", "$stepId -> $result ${note.take(80)}")
    }

    // ------------------------------------------------------------------ models (Engine B)

    suspend fun importModel(uri: Uri, displayName: String, consent: ConsentDeclaration): ImportResult {
        val result = withContext(io) {
            val stream = runCatching { context.contentResolver.openInputStream(uri) }.getOrNull()
                ?: return@withContext ImportResult.Rejected("Could not open the selected file.")
            registry.import(stream, displayName, consent)
        }
        when (result) {
            is ImportResult.Imported -> {
                log.i("Models", "Imported ${result.record.displayName}: ${result.record.report.compatibility} - ${result.record.report.summary}")
                message("Imported '${result.record.displayName}': ${result.record.report.compatibility.name.lowercase()}")
            }
            is ImportResult.Duplicate -> message("Already in your library as '${result.existing.displayName}'.")
            is ImportResult.Rejected -> {
                log.w("Models", "Import rejected: ${result.reason}")
                message(result.reason)
            }
        }
        return result
    }

    /** Loads a compatible model. Returns null on success or an error message. */
    suspend fun loadModel(id: String, quiet: Boolean = false): String? {
        val record = registry.find(id) ?: return "Model not found".also { if (!quiet) message(it) }
        val decision = LoadPlanner.check(record, memoryBudget)
        if (decision is LoadDecision.Denied) {
            if (!quiet) message(decision.reason)
            log.w("Models", "Not loading ${record.displayName}: ${decision.reason}")
            return decision.reason
        }
        _neural.value = _neural.value.copy(loading = true)
        stopWorker()
        closeInference()
        val opened = withContext(io) { runCatching { OrtInferenceSession.open(registry.fileFor(record)) } }
        val session = opened.getOrElse { e ->
            _neural.value = NeuralStatus()
            val msg = "Could not load '${record.displayName}': ${e.message}"
            if (!quiet) message(msg)
            log.e("Models", msg)
            return msg
        }
        inference = session
        _neural.value = NeuralStatus(loadedModelId = record.id, loadedModelName = record.displayName, spec = session.spec)
        settingsRepo.update { it.copy(activeModelId = record.id) }
        log.i("Models", "Loaded ${record.displayName} (${session.spec.sampleRate} Hz, chunk ${session.spec.chunkFrames})")
        restartIfRunning()  // the native AI queues are sized for this model at stream start
        if (!quiet) message("Loaded '${record.displayName}'. Switch the engine to AI to use it.")
        return null
    }

    suspend fun unloadModel() {
        stopWorker()
        closeInference()
        _neural.value = NeuralStatus()
        settingsRepo.update { it.copy(activeModelId = null, engineMode = EngineMode.DSP.name) }
        native.setMode(EngineMode.DSP)
        restartIfRunning()
    }

    suspend fun deleteModel(id: String) {
        if (_neural.value.loadedModelId == id) unloadModel()
        if (registry.delete(id)) {
            presetRepo.detachModel(id)
            message("Model deleted from this device")
        }
    }

    suspend fun revalidateModel(id: String) {
        val updated = withContext(io) { runCatching { registry.revalidate(id) }.getOrNull() }
        message(updated?.let { "Re-validated: ${it.report.compatibility.name.lowercase()}" } ?: "Re-validation failed")
    }

    private fun closeInference() {
        inference?.close()
        inference = null
    }

    private fun startWorkerIfNeeded() {
        val running = controller.state.value as? EngineState.Running ?: return
        val session = inference ?: return
        if (settings.value.engineMode != EngineMode.NEURAL.name || running.request.neural == null) return
        if (worker?.isRunning == true) return
        val w = StreamingInferenceWorker(session, nativePort)
        worker = w
        w.start()
        workerWatch?.cancel()
        workerWatch = scope.launch {
            w.stats.collect { st ->
                _neural.value = _neural.value.copy(worker = st)
                if (st.state == WorkerState.STOPPED_TOO_SLOW || st.state == WorkerState.STOPPED_ERROR) {
                    log.w("Neural", st.lastError ?: "worker stopped")
                    message(st.lastError ?: "AI engine stopped; using DSP")
                    native.setMode(EngineMode.DSP)
                    settingsRepo.update { it.copy(engineMode = EngineMode.DSP.name) }
                    workerWatch?.cancel()
                }
            }
        }
        log.i("Neural", "Inference worker started")
    }

    private fun stopWorker() {
        workerWatch?.cancel()
        workerWatch = null
        worker?.stop()
        worker = null
    }

    // ------------------------------------------------------------------ Route C (experimental)

    suspend fun startNetworkStream(host: String, port: Int): String? {
        val cleanHost = host.trim()
        if (!controller.isRunning) return "Start the engine first.".also(::message)
        if (cleanHost.isEmpty()) return "Enter the receiver's IP address.".also(::message)
        if (port !in 1024..65535) return "Port must be between 1024 and 65535.".also(::message)
        settingsRepo.update { it.copy(networkHost = cleanHost, networkPort = port) }
        stopNetworkInternal()
        native.setTapEnabled(true)
        val sampleRate = stats.value.sampleRate.takeIf { it > 0 } ?: 48000
        val s = UdpPcmSender(PcmSource { dst, max -> native.tapRead(dst, max) }, cleanHost, port, sampleRate)
        sender = s
        s.start()
        senderWatch = scope.launch {
            s.stats.collect { st ->
                _network.value = NetworkStatus(true, "$cleanHost:$port", st, LocalNetwork.ipv4Addresses())
                st.error?.let { message("Network stream: $it") }
            }
        }
        log.i("Network", "Streaming to $cleanHost:$port at $sampleRate Hz (experimental)")
        return null
    }

    fun stopNetworkStream() = stopNetworkInternal()

    private fun stopNetworkInternal() {
        senderWatch?.cancel()
        senderWatch = null
        sender?.stop()
        sender = null
        if (native.unavailableReason == null) native.setTapEnabled(false)
        _network.value = NetworkStatus(localAddresses = LocalNetwork.ipv4Addresses())
    }

    fun refreshLocalAddresses() {
        _network.value = _network.value.copy(localAddresses = LocalNetwork.ipv4Addresses())
    }

    // ------------------------------------------------------------------ reports

    fun buildDiagnosticReport(): String {
        val s = settings.value
        val st = stats.value
        val perf = _perf.value
        val n = _neural.value
        val route = routeReport()
        return DiagnosticReport.Builder()
            .section(
                "App and device",
                listOf(
                    "App" to "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                    "Device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "Android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                    "ABIs" to Build.SUPPORTED_ABIS.joinToString(),
                    "Native engine" to (native.unavailableReason ?: "loaded"),
                ),
            )
            .section(
                "Engine",
                listOf(
                    "State" to engineState.value.toString(),
                    "Sample rate" to "${st.sampleRate} Hz, burst ${st.framesPerBurst}, buffer ${st.bufferSizeFrames}",
                    "Exclusive" to "out=${st.outputExclusive} in=${st.inputExclusive}",
                    "Latency" to "in ${st.inputLatencyMs} ms, out ${st.outputLatencyMs} ms, DSP ${st.dspLatencyMs} ms, AI ${st.aiLatencyMs} ms, est. total ${st.estimatedEndToEndMs ?: "n/a"}",
                    "Callback load" to "avg ${"%.1f".format(st.callbackLoadAvgPct)} %, peak ${"%.1f".format(st.callbackLoadPeakPct)} %",
                    "Glitches" to "xruns ${st.xRunCount}, input underflows ${st.inputUnderflows}, drains ${st.inputDrains}, DSP faults ${st.dspFaults}",
                    "AI path" to "${st.aiState}, underruns ${st.aiUnderruns}, overflows ${st.aiOverflows}, gaps ${st.aiDiscontinuities}",
                    "Last probe" to if (st.probeLatencyMs >= 0) "${st.probeLatencyMs} ms" else "not measured",
                ),
            )
            .section(
                "Settings",
                listOf(
                    "Devices" to "in=${s.inputDeviceId} out=${s.outputDeviceId} monitor=${s.monitorDeviceId} (${if (st.monitorActive) "active" else "off"}, underruns ${st.monitorUnderruns}, drift ${st.monitorDriftCorrections})",
                    "Input pitch" to "%.0f Hz (confidence %.2f)".format(st.inputPitchHz, st.pitchConfidence),
                    "Quality / mic" to "${s.quality} / ${s.micMode}, exclusive=${s.exclusiveAudio}",
                    "Mode" to "${s.engineMode} bypass=${s.bypass} muted=${s.monitorMuted}",
                    "Voice" to _voice.value.toString(),
                ),
            )
            .section(
                "Neural engine",
                listOf(
                    "Model" to (n.loadedModelName ?: "none"),
                    "Spec" to (n.spec?.toString() ?: "-"),
                    "Worker" to n.worker.toString(),
                    "Library" to models.value.joinToString { "${it.displayName} r${it.revision} ${it.report.compatibility}" }.ifEmpty { "empty" },
                ),
            )
            .section("Audio devices", devices.value.map { "#${it.id}" to "${it.label} in=${it.isInput} out=${it.isOutput} rates=${it.sampleRates}" })
            .section("Route A checks", route.checks.map { it.status.name to "${it.title}: ${it.detail}" })
            .section("Hardware validation (entered by user)", s.validation.map { it.stepId to "${it.result} ${it.note}" })
            .section(
                "Performance",
                listOf(
                    "CPU" to (perf?.let { "${"%.1f".format(it.cpuPercentOfOneCore)} % of one core (${it.cores} cores)" } ?: "-"),
                    "Memory" to (perf?.let { "heap ${"%.0f".format(it.javaHeapUsedMb)} MB, native ${"%.0f".format(it.nativeHeapMb)} MB, free ${"%.0f".format(it.availableSystemMb)} MB" } ?: "-"),
                    "Thermal" to (perf?.let { "${it.thermal.label} headroom=${it.thermalHeadroom}" } ?: "-"),
                ),
            )
            .logs(log.entries.value)
            .build()
            .render()
    }
}
