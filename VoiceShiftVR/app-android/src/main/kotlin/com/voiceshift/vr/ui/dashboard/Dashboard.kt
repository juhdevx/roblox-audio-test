package com.voiceshift.vr.ui.dashboard

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.voiceshift.audio.AiPathState
import com.voiceshift.audio.AudioDevice
import com.voiceshift.audio.DeviceSelection
import com.voiceshift.audio.EngineMode
import com.voiceshift.audio.EngineState
import com.voiceshift.audio.EngineStats
import com.voiceshift.diagnostics.PerfSnapshot
import com.voiceshift.dsp.VoiceParameter
import com.voiceshift.dsp.VoiceSettings
import com.voiceshift.models.AppSettings
import com.voiceshift.models.VoicePreset
import com.voiceshift.vr.session.NeuralStatus
import com.voiceshift.vr.session.VoiceSession
import com.voiceshift.vr.ui.components.LevelMeter
import com.voiceshift.vr.ui.components.Notice
import com.voiceshift.vr.ui.components.NoticeKind
import com.voiceshift.vr.ui.components.ParameterSlider
import com.voiceshift.vr.ui.components.SectionCard
import com.voiceshift.vr.ui.components.StatRow
import com.voiceshift.vr.ui.components.StatusPill
import com.voiceshift.vr.ui.components.SwitchRow
import com.voiceshift.vr.ui.theme.VsColors
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class DashboardUiState(
    val engine: EngineState = EngineState.Idle,
    val stats: EngineStats = EngineStats.EMPTY,
    val settings: AppSettings = AppSettings(),
    val voice: VoiceSettings = VoiceSettings(),
    val presets: List<VoicePreset> = emptyList(),
    val neural: NeuralStatus = NeuralStatus(),
    val perf: PerfSnapshot? = null,
    val devices: List<AudioDevice> = emptyList(),
    val busy: Boolean = false,
) {
    val running: Boolean get() = engine is EngineState.Running
    val feedbackRisk: Boolean
        get() = running && !settings.monitorMuted &&
            DeviceSelection.feedbackRisk(settings.inputDeviceId, settings.outputDeviceId, devices)
    val activePresetName: String get() = presets.firstOrNull { it.id == settings.activePresetId }?.name ?: "Custom"
}

private data class EnginePart(val engine: EngineState, val stats: EngineStats, val settings: AppSettings, val voice: VoiceSettings, val presets: List<VoicePreset>)
private data class ExtraPart(val neural: NeuralStatus, val perf: PerfSnapshot?, val devices: List<AudioDevice>, val busy: Boolean)

@HiltViewModel
class DashboardViewModel @Inject constructor(private val session: VoiceSession) : ViewModel() {

    val nativeUnavailable: String? = session.nativeUnavailableReason

    val state: StateFlow<DashboardUiState> = combine(
        combine(session.engineState, session.stats, session.settings, session.voice, session.presets, ::EnginePart),
        combine(session.neural, session.perf, session.devices, session.busy, ::ExtraPart),
    ) { a, b ->
        DashboardUiState(a.engine, a.stats, a.settings, a.voice, a.presets, b.neural, b.perf, b.devices, b.busy)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), DashboardUiState())

    fun start() = viewModelScope.launch { session.start() }
    fun stop() = viewModelScope.launch { session.stop() }
    fun setMode(mode: EngineMode) = viewModelScope.launch { session.setEngineMode(mode) }
    fun setBypass(on: Boolean) = viewModelScope.launch { session.setBypass(on) }
    fun setMuted(on: Boolean) = viewModelScope.launch { session.setMonitorMuted(on) }
    fun setParameter(p: VoiceParameter, v: Float) = session.setVoiceParameter(p, v)
    fun applyPreset(p: VoicePreset) = session.applyPreset(p)
}

@Composable
fun DashboardScreen(
    onOpenModels: () -> Unit,
    onOpenDevices: () -> Unit,
    vm: DashboardViewModel = hiltViewModel(),
) {
    val ui by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    fun micGranted() = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    var granted by remember { mutableStateOf(micGranted()) }
    var deniedOnce by remember { mutableStateOf(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { granted = micGranted() }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        granted = result[Manifest.permission.RECORD_AUDIO] == true || micGranted()
        if (granted) vm.start() else deniedOnce = true
    }
    val requestAndStart = {
        if (granted) {
            vm.start()
        } else {
            val perms = buildList {
                add(Manifest.permission.RECORD_AUDIO)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
            }
            permissionLauncher.launch(perms.toTypedArray())
        }
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("VoiceShift VR", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
                EngineStatePill(ui.engine)
            }
            Text(
                "Preset: ${ui.activePresetName}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        vm.nativeUnavailable?.let { reason ->
            item { Notice(NoticeKind.ERROR, "The native audio engine could not be loaded on this device: $reason") }
        }

        if (!granted) {
            item {
                SectionCard("Microphone access", subtitle = "VoiceShift needs the microphone to process your voice. Audio never leaves this device unless you start the Wi-Fi bridge.") {
                    if (deniedOnce) {
                        Notice(NoticeKind.WARN, "Permission was denied. If Android no longer asks, enable Microphone in the app's settings.")
                        OutlinedButton(onClick = {
                            context.startActivity(
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
                            )
                        }) { Text("Open app settings") }
                    }
                }
            }
        }

        item {
            val starting = ui.busy || ui.engine is EngineState.Starting || ui.engine is EngineState.Recovering
            Button(
                onClick = { if (ui.running) vm.stop() else requestAndStart() },
                enabled = !ui.busy && vm.nativeUnavailable == null,
                modifier = Modifier.fillMaxWidth().height(64.dp),
                shape = RoundedCornerShape(20.dp),
                colors = if (ui.running) {
                    ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondaryContainer, contentColor = MaterialTheme.colorScheme.onSecondaryContainer)
                } else {
                    ButtonDefaults.buttonColors()
                },
            ) {
                if (starting) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                } else {
                    Icon(if (ui.running) Icons.Filled.Close else Icons.Filled.PlayArrow, contentDescription = null)
                }
                Spacer(Modifier.width(10.dp))
                Text(if (ui.running) "Stop voice" else "Start voice", style = MaterialTheme.typography.titleMedium)
            }
        }

        val notices = buildNotices(ui)
        items(notices) { (kind, text) -> Notice(kind, text) }

        item {
            SectionCard("Levels") {
                LevelMeter("Microphone", ui.stats.inputRmsDb, ui.stats.inputPeakDb)
                LevelMeter("Output", ui.stats.outputRmsDb, ui.stats.outputPeakDb)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatusPill(if (ui.stats.gateOpen) "Gate open" else "Gate closed", if (ui.stats.gateOpen) VsColors.Green else VsColors.TextSecondary)
                    if (ui.voice.agcEnabled) StatusPill("AGC %+.0f dB".format(ui.stats.agcGainDb), VsColors.Violet)
                    if (ui.stats.limiterReductionDb < -0.5f) StatusPill("Limit %.0f dB".format(ui.stats.limiterReductionDb), VsColors.Amber)
                }
            }
        }

        item {
            SectionCard("Engine", subtitle = engineSubtitle(ui)) {
                val neuralAvailable = ui.neural.loadedModelId != null
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    val mode = if (ui.settings.engineMode == EngineMode.NEURAL.name && neuralAvailable) EngineMode.NEURAL else EngineMode.DSP
                    SegmentedButton(
                        selected = mode == EngineMode.DSP,
                        onClick = { vm.setMode(EngineMode.DSP) },
                        shape = SegmentedButtonDefaults.itemShape(0, 2),
                    ) { Text("DSP") }
                    SegmentedButton(
                        selected = mode == EngineMode.NEURAL,
                        onClick = { if (neuralAvailable) vm.setMode(EngineMode.NEURAL) else onOpenModels() },
                        shape = SegmentedButtonDefaults.itemShape(1, 2),
                    ) { Text(if (neuralAvailable) "AI model" else "AI (no model)") }
                }
                SwitchRow("Bypass", ui.settings.bypass, vm::setBypass, "Hear your unmodified voice (crossfaded).")
                SwitchRow("Mute output", ui.settings.monitorMuted, vm::setMuted, "Silences monitoring and the routed output.")
            }
        }

        item {
            SectionCard("Quick voice") {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(ui.presets, key = { it.id }) { p ->
                        FilterChip(
                            selected = p.id == ui.settings.activePresetId,
                            onClick = { vm.applyPreset(p) },
                            label = { Text(p.name) },
                        )
                    }
                }
                ParameterSlider(VoiceParameter.PITCH_SEMITONES, ui.voice.pitchSemitones, { vm.setParameter(VoiceParameter.PITCH_SEMITONES, it) })
                ParameterSlider(VoiceParameter.FORMANT_SEMITONES, ui.voice.formantSemitones, { vm.setParameter(VoiceParameter.FORMANT_SEMITONES, it) })
            }
        }

        item { PerformanceCard(ui, onOpenDevices) }
    }
}

@Composable
private fun EngineStatePill(state: EngineState) {
    when (state) {
        EngineState.Idle -> StatusPill("Stopped", VsColors.TextSecondary)
        EngineState.Starting -> StatusPill("Starting", VsColors.Violet)
        is EngineState.Running -> StatusPill("Live", VsColors.Green)
        is EngineState.Recovering -> StatusPill("Reconnecting", VsColors.Amber)
        is EngineState.Failed -> StatusPill("Error", VsColors.Red)
    }
}

private fun engineSubtitle(ui: DashboardUiState): String = when {
    ui.settings.engineMode == EngineMode.NEURAL.name && ui.neural.loadedModelName != null ->
        "AI: ${ui.neural.loadedModelName} — DSP stays ready as automatic fallback."
    else -> "DSP: real-time pitch and formant shifting, no model required."
}

private fun buildNotices(ui: DashboardUiState): List<Pair<NoticeKind, String>> = buildList {
    when (val e = ui.engine) {
        is EngineState.Failed -> add(NoticeKind.ERROR to e.message)
        is EngineState.Recovering -> add(NoticeKind.WARN to "${e.reason}. Reopening audio (attempt ${e.attempt})…")
        else -> Unit
    }
    if (ui.feedbackRisk) add(NoticeKind.WARN to "Feedback risk: output is the phone speaker next to the microphone. Use headphones or mute output.")
    if (ui.running && ui.settings.bypass) add(NoticeKind.INFO to "Bypass is on: you are hearing your unprocessed voice.")
    if (ui.running && ui.settings.engineMode == EngineMode.NEURAL.name) {
        when (ui.stats.aiState) {
            AiPathState.PRIMING -> add(NoticeKind.INFO to "AI engine warming up; DSP covers until the model's first chunks arrive.")
            AiPathState.FALLBACK -> add(NoticeKind.WARN to "AI engine fell behind; playing the DSP voice until it catches up.")
            else -> Unit
        }
    }
    if (ui.stats.dspFaults > 0) add(NoticeKind.WARN to "${ui.stats.dspFaults} invalid audio block(s) were silenced and the DSP reset.")
    ui.perf?.let { if (it.thermal.throttlingLikely) add(NoticeKind.WARN to "Device is hot (${it.thermal.label}). Expect throttling; consider the low-latency DSP mode.") }
}

@Composable
private fun PerformanceCard(ui: DashboardUiState, onOpenDevices: () -> Unit) {
    val s = ui.stats
    SectionCard("Latency & performance", subtitle = "Targets: below 100 ms ideal, 200 ms acceptable. Measured values only.") {
        val total = s.estimatedEndToEndMs
        StatRow(
            "Estimated mic → output",
            total?.let { "%.0f ms".format(it) } ?: if (ui.running) "device does not report" else "—",
            when {
                total == null -> Color.Unspecified
                total < 100f -> VsColors.Green
                total < 200f -> VsColors.Amber
                else -> VsColors.Red
            },
        )
        StatRow("Voice transform", if (ui.running) "%.1f ms".format(if (s.aiState == AiPathState.ACTIVE) s.aiLatencyMs else s.dspLatencyMs) else "—")
        StatRow("Platform in / out", if (s.inputLatencyMs >= 0) "%.0f / %.0f ms".format(s.inputLatencyMs, s.outputLatencyMs) else "—")
        StatRow("Measured round trip", if (s.probeLatencyMs >= 0) "%.1f ms".format(s.probeLatencyMs) else "run probe in Devices")
        StatRow("Audio thread load", "%.0f %% avg / %.0f %% peak".format(s.callbackLoadAvgPct, s.callbackLoadPeakPct),
            if (s.callbackLoadAvgPct > 70) VsColors.Amber else Color.Unspecified)
        StatRow("Stream", if (ui.running) "${s.sampleRate} Hz · burst ${s.framesPerBurst} · ${if (s.outputExclusive) "exclusive" else "shared"}" else "—")
        StatRow("Glitches (xrun / underflow)", "${s.xRunCount} / ${s.inputUnderflows}", if (s.xRunCount + s.inputUnderflows > 0) VsColors.Amber else Color.Unspecified)
        ui.perf?.let { p ->
            StatRow("App CPU", "%.0f %% of one core".format(p.cpuPercentOfOneCore))
            StatRow("Memory", "%.0f MB heap · %.0f MB native".format(p.javaHeapUsedMb, p.nativeHeapMb))
            StatRow("Thermal", p.thermal.label, if (p.thermal.throttlingLikely) VsColors.Amber else Color.Unspecified)
        }
        if (s.probeLatencyMs < 0) {
            OutlinedButton(onClick = onOpenDevices, modifier = Modifier.padding(top = 4.dp)) { Text("Measure latency") }
        }
    }
}
