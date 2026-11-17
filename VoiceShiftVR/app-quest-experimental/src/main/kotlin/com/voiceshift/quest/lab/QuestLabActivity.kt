package com.voiceshift.quest.lab

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.voiceshift.audio.EngineState
import com.voiceshift.dsp.VoiceSettings

private val Green = Color(0xFF5BD68A)
private val Amber = Color(0xFFFFC857)
private val Red = Color(0xFFFF5A6E)

class QuestLabActivity : ComponentActivity() {
    private val vm: QuestLabViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Color(0xFF4FD1C5), secondary = Color(0xFF8B7CFF))) {
                Surface(Modifier.fillMaxSize(), color = Color(0xFF0E0F14)) { QuestLab(vm) }
            }
        }
    }
}

@Composable
private fun QuestLab(vm: QuestLabViewModel) {
    val context = LocalContext.current
    var micGranted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { micGranted = it }
    val devices by vm.deviceSource.devices.collectAsStateWithLifecycle()
    val engineState by vm.engine.state.collectAsStateWithLifecycle()
    val stats by vm.engine.stats.collectAsStateWithLifecycle()
    val mode by vm.mode.collectAsStateWithLifecycle()
    val receiver by vm.receiver.collectAsStateWithLifecycle()
    var inputId by remember { mutableIntStateOf(0) }
    var port by remember { mutableStateOf("50555") }

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.widthIn(max = 900.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("VoiceShift Quest Lab", style = MaterialTheme.typography.headlineMedium)
            Text(
                "EXPERIMENTAL research tools. This app cannot create a microphone for Roblox or other apps; it measures " +
                    "what the headset receives. ${vm.deviceInfo}",
                style = MaterialTheme.typography.bodyMedium,
                color = Color(0xFFA3A8BC),
            )
            vm.nativeUnavailable?.let { Text("Native engine unavailable: $it", color = Red) }
            if (!micGranted) {
                Button(onClick = { launcher.launch(Manifest.permission.RECORD_AUDIO) }) { Text("Allow microphone access") }
            }

            LabCard("1 · Inputs Android reports on this headset") {
                val external = vm.externalInputs(devices)
                Text(
                    if (external.isEmpty()) "No USB/wired input device is listed. The Quest has not exposed an external microphone to apps."
                    else "External input(s) listed: ${external.joinToString { it.label }}. This is OS-level recognition only.",
                    color = if (external.isEmpty()) Amber else Green,
                )
                Option("System default microphone", inputId == 0) { inputId = 0 }
                devices.filter { it.isInput }.forEach { d ->
                    Option("${d.label} · #${d.id}${if (d.sampleRates.isNotEmpty()) " · ${d.sampleRates}" else ""}", inputId == d.id) { inputId = d.id }
                }
                OutlinedButton(onClick = { vm.deviceSource.refresh() }) { Text("Refresh") }
            }

            LabCard("2 · USB mic probe (tone detector)") {
                Text("On the phone, enable the 1 kHz test tone on the output that feeds the headset's USB input. Playback here stays muted.")
                if (mode == LabMode.USB_PROBE) {
                    Meter("Input level", stats.inputRmsDb)
                    val detected = stats.toneDb > -60f && stats.toneSnrDb > 10f
                    Text(
                        if (detected) "1 kHz tone DETECTED at %.1f dBFS (SNR %.0f dB). Signal reaches the headset.".format(stats.toneDb, stats.toneSnrDb)
                        else "No 1 kHz tone detected (tone %.0f dBFS, SNR %.0f dB).".format(stats.toneDb, stats.toneSnrDb),
                        color = if (detected) Green else Amber,
                    )
                    Text("Capturing from device #${stats.inputDeviceId} at ${stats.sampleRate} Hz", fontFamily = FontFamily.Monospace)
                    OutlinedButton(onClick = { vm.stopEngine() }) { Text("Stop probe") }
                } else {
                    Button(onClick = { vm.startUsbProbe(inputId) }, enabled = micGranted && mode == LabMode.IDLE) { Text("Start probe on selected input") }
                }
            }

            LabCard("3 · Native DSP on the headset (Route B feasibility)") {
                Text("Runs the phone app's voice engine on the Quest CPU with the Soft feminine settings. Use headphones to avoid feedback.")
                if (mode == LabMode.LOCAL_DSP) {
                    Meter("Input", stats.inputRmsDb)
                    Meter("Output", stats.outputRmsDb)
                    Text(
                        "Load %.0f%% avg / %.0f%% peak · xruns %d · DSP %.1f ms · out %.0f ms · in %.0f ms".format(
                            stats.callbackLoadAvgPct, stats.callbackLoadPeakPct, stats.xRunCount,
                            stats.dspLatencyMs, stats.outputLatencyMs, stats.inputLatencyMs,
                        ),
                        fontFamily = FontFamily.Monospace,
                    )
                    OutlinedButton(onClick = { vm.stopEngine() }) { Text("Stop") }
                } else {
                    Button(
                        onClick = {
                            vm.startLocalDsp(
                                inputId, 0,
                                VoiceSettings(pitchSemitones = 5f, formantSemitones = 2f, lowCutHz = 120f, bodyDb = -3f, presenceDb = 2f, airDb = 3f, compression = 0.3f),
                            )
                        },
                        enabled = micGranted && mode == LabMode.IDLE,
                    ) { Text("Start local voice engine") }
                }
                if (engineState is EngineState.Failed) Text((engineState as EngineState.Failed).message, color = Red)
            }

            LabCard("4 · Wi-Fi receiver (Route C)") {
                Text("Plays the phone's processed voice inside this app only. Enter this address on the phone: ${vm.localAddresses().joinToString().ifEmpty { "(no network)" }}")
                OutlinedTextField(port, { port = it.filter(Char::isDigit).take(5) }, label = { Text("UDP port") }, singleLine = true)
                if (receiver.running) {
                    val j = receiver.jitter
                    Text(
                        "From ${receiver.lastSender ?: "—"} · ${receiver.sampleRate} Hz\nreceived ${j.received} · played ${j.played} · lost ${j.lost} · late ${j.late} · buffer ${j.depthFrames} frames · rebuffers ${j.rebuffers}",
                        fontFamily = FontFamily.Monospace,
                    )
                    OutlinedButton(onClick = { vm.stopReceiver() }) { Text("Stop receiver") }
                } else {
                    Button(onClick = { vm.startReceiver(port.toIntOrNull() ?: 50555) }) { Text("Start receiver") }
                    receiver.error?.let { Text(it, color = Red) }
                }
            }
        }
    }
}

@Composable
private fun LabCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF171923)),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            content()
        }
    }
}

@Composable
private fun Option(label: String, selected: Boolean, onSelect: () -> Unit) {
    Row(Modifier.fillMaxWidth().selectable(selected, onClick = onSelect), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected = selected, onClick = onSelect)
        Text(label)
    }
}

@Composable
private fun Meter(label: String, db: Float) {
    Column {
        Text("$label: ${if (db <= -119f) "—" else "%.0f dBFS".format(db)}", fontFamily = FontFamily.Monospace)
        LinearProgressIndicator(progress = { ((db + 60f) / 60f).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
    }
}
