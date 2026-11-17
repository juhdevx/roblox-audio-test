package com.voiceshift.vr.ui.devices

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.voiceshift.audio.AudioDevice
import com.voiceshift.audio.DeviceSelection
import com.voiceshift.audio.EngineState
import com.voiceshift.audio.EngineStats
import com.voiceshift.audio.TestSignal
import com.voiceshift.bridge.usb.CheckStatus
import com.voiceshift.bridge.usb.QuestValidationProcedure
import com.voiceshift.bridge.usb.RouteReport
import com.voiceshift.models.AppSettings
import com.voiceshift.models.ValidationResult
import com.voiceshift.vr.session.NetworkStatus
import com.voiceshift.vr.session.VoiceSession
import com.voiceshift.vr.ui.components.Notice
import com.voiceshift.vr.ui.components.NoticeKind
import com.voiceshift.vr.ui.components.SectionCard
import com.voiceshift.vr.ui.components.StatRow
import com.voiceshift.vr.ui.components.StatusPill
import com.voiceshift.vr.ui.components.SwitchRow
import com.voiceshift.vr.ui.theme.VsColors
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class DevicesUiState(
    val devices: List<AudioDevice> = emptyList(),
    val settings: AppSettings = AppSettings(),
    val engine: EngineState = EngineState.Idle,
    val stats: EngineStats = EngineStats.EMPTY,
    val testSignal: TestSignal = TestSignal.None,
    val network: NetworkStatus = NetworkStatus(),
    val route: RouteReport? = null,
) {
    val running get() = engine is EngineState.Running
}

private data class Part1(val d: List<AudioDevice>, val s: AppSettings, val e: EngineState, val st: EngineStats, val t: TestSignal)

@HiltViewModel
class DevicesViewModel @Inject constructor(private val session: VoiceSession) : ViewModel() {
    private val route = MutableStateFlow<RouteReport?>(null)

    val state: StateFlow<DevicesUiState> = combine(
        combine(session.devices, session.settings, session.engineState, session.stats, session.testSignal, ::Part1),
        session.network,
        route,
    ) { a, n, r -> DevicesUiState(a.d, a.s, a.e, a.st, a.t, n, r) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), DevicesUiState())

    init {
        session.refreshLocalAddresses()
    }

    fun selectInput(id: Int) = viewModelScope.launch { session.selectInputDevice(id) }
    fun selectOutput(id: Int) = viewModelScope.launch { session.selectOutputDevice(id) }
    fun refresh() {
        session.refreshDevices()
        runChecks()
    }
    fun runChecks() {
        route.value = session.routeReport()
    }
    fun setTone(enabled: Boolean, frequency: Float, level: Float) {
        session.setTestSignal(if (enabled) TestSignal.Tone(frequency, level) else TestSignal.None)
        runChecks()
    }
    fun setProbe(enabled: Boolean) = session.setTestSignal(if (enabled) TestSignal.LatencyProbe else TestSignal.None)
    fun record(stepId: String, result: ValidationResult, note: String) = viewModelScope.launch { session.recordValidation(stepId, result, note) }
    fun startStream(host: String, port: Int) = viewModelScope.launch { session.startNetworkStream(host, port) }
    fun stopStream() = session.stopNetworkStream()
}

@Composable
fun DevicesScreen(vm: DevicesViewModel = hiltViewModel()) {
    val ui by vm.state.collectAsStateWithLifecycle()
    val inputs = ui.devices.filter { it.isInput }
    val outputs = ui.devices.filter { it.isOutput }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Devices & routing", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
                IconButton(onClick = vm::refresh) { Icon(Icons.Filled.Refresh, contentDescription = "Refresh devices") }
            }
            Text(
                "Changing a device restarts the engine (about half a second of silence).",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (DeviceSelection.feedbackRisk(ui.settings.inputDeviceId, ui.settings.outputDeviceId, ui.devices)) {
            item { Notice(NoticeKind.WARN, "Output is the phone speaker while recording from the phone microphone: expect howling feedback. Use headphones or a cable.") }
        }
        item {
            SectionCard("Input (microphone)") {
                DeviceOption("System default", ui.settings.inputDeviceId == 0) { vm.selectInput(0) }
                inputs.forEach { d -> DeviceOption(describe(d), ui.settings.inputDeviceId == d.id) { vm.selectInput(d.id) } }
            }
        }
        item {
            SectionCard("Output", subtitle = "Pick the USB interface or wired output that feeds the Quest (Route A).") {
                DeviceOption("System default", ui.settings.outputDeviceId == 0) { vm.selectOutput(0) }
                outputs.forEach { d -> DeviceOption(describe(d), ui.settings.outputDeviceId == d.id) { vm.selectOutput(d.id) } }
            }
        }
        item { RouteCard(ui, vm) }
        item { LatencyCard(ui, vm) }
        item {
            SectionCard(
                "Quest & Roblox validation",
                subtitle = "Record what you observed. These hardware steps are never marked passed automatically.",
            ) {
                QuestValidationProcedure.Stage.entries.forEach { stage ->
                    Text(stage.title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                    QuestValidationProcedure.steps.filter { it.stage == stage }.forEach { step ->
                        ValidationStepRow(step, ui.settings.validation.firstOrNull { it.stepId == step.id }, vm::record)
                    }
                }
            }
        }
        item { NetworkCard(ui, vm) }
    }
}

private fun describe(d: AudioDevice): String {
    val rates = if (d.sampleRates.isEmpty()) "" else " · ${d.sampleRates.joinToString("/") { "${it / 1000}k" }}"
    return "${d.label}$rates"
}

@Composable
private fun DeviceOption(label: String, selected: Boolean, onSelect: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().selectable(selected = selected, onClick = onSelect).padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onSelect)
        Text(label, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun RouteCard(ui: DevicesUiState, vm: DevicesViewModel) {
    val toneOn = ui.testSignal is TestSignal.Tone
    var level by remember { mutableStateOf(ui.settings.testToneLevelDb) }
    var frequency by remember { mutableStateOf(ui.settings.testToneFrequencyHz) }
    SectionCard("Route A · external microphone path", subtitle = "Phone output → audio interface/adapter → Quest USB microphone input.") {
        Notice(
            NoticeKind.INFO,
            "A plain USB-C cable between phone and Quest does not create a microphone. The Quest needs a USB audio input " +
                "device; this phone feeds that device's input. Full wiring options: docs/QUEST_BRIDGE.md.",
        )
        SwitchRow(
            "1 kHz test tone",
            toneOn,
            { vm.setTone(it, frequency, level) },
            subtitle = if (ui.running) "Replaces your voice on the output while on." else "Start the engine first.",
            enabled = ui.running,
        )
        Text("Tone level: %.0f dBFS".format(level), style = MaterialTheme.typography.bodySmall)
        Slider(
            value = level,
            onValueChange = { level = it },
            onValueChangeFinished = { if (toneOn) vm.setTone(true, frequency, level) },
            valueRange = -40f..-6f,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(440f, 1000f).forEach { f ->
                FilterChip(
                    selected = frequency == f,
                    onClick = { frequency = f; if (toneOn) vm.setTone(true, f, level) },
                    label = { Text("${f.toInt()} Hz") },
                )
            }
        }
        Button(onClick = vm::runChecks) { Text("Run route checks") }
        ui.route?.checks?.forEach { c ->
            Row(verticalAlignment = Alignment.Top, modifier = Modifier.padding(vertical = 2.dp)) {
                val color = when (c.status) {
                    CheckStatus.PASS -> VsColors.Green
                    CheckStatus.WARN -> VsColors.Amber
                    CheckStatus.FAIL -> VsColors.Red
                    CheckStatus.INFO -> VsColors.Violet
                }
                StatusPill(c.status.name, color)
                Column(Modifier.padding(start = 8.dp)) {
                    Text(c.title, style = MaterialTheme.typography.bodyMedium)
                    Text(c.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun LatencyCard(ui: DevicesUiState, vm: DevicesViewModel) {
    val probing = ui.testSignal is TestSignal.LatencyProbe
    SectionCard("Round-trip latency probe", subtitle = "Plays a click once per second and times its return on the input.") {
        Text(
            "Connect the selected output to the selected input (loopback cable on a USB interface), or hold the phone " +
                "speaker near its microphone at moderate volume. Your voice is replaced by clicks while probing.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        StatRow(
            "Measured round trip",
            if (ui.stats.probeLatencyMs >= 0) "%.1f ms".format(ui.stats.probeLatencyMs) else if (probing) "listening…" else "not measured",
        )
        if (probing) {
            OutlinedButton(onClick = { vm.setProbe(false) }) { Text("Stop probe") }
        } else {
            Button(onClick = { vm.setProbe(true) }, enabled = ui.running) { Text("Start probe") }
        }
    }
}

@Composable
private fun ValidationStepRow(
    step: QuestValidationProcedure.Step,
    entry: com.voiceshift.models.ValidationEntry?,
    onRecord: (String, ValidationResult, String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    var note by remember(entry) { mutableStateOf(entry?.note.orEmpty()) }
    val result = entry?.result ?: ValidationResult.NOT_RUN
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(step.title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            StatusPill(
                result.name.replace('_', ' ').lowercase(),
                when (result) {
                    ValidationResult.PASSED -> VsColors.Green
                    ValidationResult.FAILED -> VsColors.Red
                    else -> VsColors.TextSecondary
                },
            )
            TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "Hide" else "Record") }
        }
        if (expanded) {
            Text(step.instructions, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(note, { note = it.take(500) }, label = { Text("Observation / OS version") }, modifier = Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(ValidationResult.PASSED, ValidationResult.FAILED, ValidationResult.NOT_APPLICABLE).forEach { r ->
                    FilterChip(selected = result == r, onClick = { onRecord(step.id, r, note) }, label = { Text(r.name.replace('_', ' ').lowercase()) })
                }
            }
        }
    }
}

@Composable
private fun NetworkCard(ui: DevicesUiState, vm: DevicesViewModel) {
    var host by remember { mutableStateOf(ui.settings.networkHost) }
    var port by remember { mutableStateOf(ui.settings.networkPort.toString()) }
    SectionCard("Route C · Wi-Fi bridge (experimental)", subtitle = "Streams the processed voice to VoiceShift Quest Lab on your LAN.") {
        Notice(
            NoticeKind.WARN,
            "This plays audio inside the receiver app only. It does NOT create a microphone for Roblox or any other app.",
        )
        OutlinedTextField(host, { host = it.trim() }, label = { Text("Receiver IP (shown in Quest Lab)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(
            port, { port = it.filter(Char::isDigit).take(5) }, label = { Text("UDP port") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
        if (ui.network.streaming) {
            StatRow("Target", ui.network.target)
            StatRow("Packets sent", ui.network.sender.packetsSent.toString())
            StatRow("Data", "%.1f KB".format(ui.network.sender.bytesSent / 1024.0))
            OutlinedButton(onClick = vm::stopStream) { Text("Stop streaming") }
        } else {
            Button(onClick = { vm.startStream(host, port.toIntOrNull() ?: 0) }, enabled = ui.running) { Text("Start streaming") }
        }
        if (ui.network.localAddresses.isNotEmpty()) {
            StatRow("This phone", ui.network.localAddresses.joinToString())
        }
    }
}
