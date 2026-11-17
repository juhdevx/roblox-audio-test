package com.voiceshift.vr.ui.settings

import android.content.Intent
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.voiceshift.audio.MicMode
import com.voiceshift.diagnostics.LogEntry
import com.voiceshift.diagnostics.LogLevel
import com.voiceshift.dsp.DspQuality
import com.voiceshift.models.AppSettings
import com.voiceshift.vr.BuildConfig
import com.voiceshift.vr.session.VoiceSession
import com.voiceshift.vr.ui.components.SectionCard
import com.voiceshift.vr.ui.components.SwitchRow
import com.voiceshift.vr.ui.theme.NumericStyle
import com.voiceshift.vr.ui.theme.VsColors
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class SettingsUiState(val settings: AppSettings = AppSettings(), val logs: List<LogEntry> = emptyList())

@HiltViewModel
class SettingsViewModel @Inject constructor(private val session: VoiceSession) : ViewModel() {
    val state: StateFlow<SettingsUiState> = combine(session.settings, session.log.entries) { s, l -> SettingsUiState(s, l) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), SettingsUiState())

    fun setQuality(q: DspQuality) = viewModelScope.launch { session.setQuality(q) }
    fun setMicMode(m: MicMode) = viewModelScope.launch { session.setMicMode(m) }
    fun setExclusive(e: Boolean) = viewModelScope.launch { session.setExclusive(e) }
    fun setKeepScreenOn(k: Boolean) = viewModelScope.launch { session.setKeepScreenOn(k) }
    fun clearLogs() = session.log.clear()
    fun report(): String = session.buildDiagnosticReport()
}

private val troubleshooting = listOf(
    "No sound / silence" to "Check Mute output, output gain and that the selected output device is connected. Try 'System default'.",
    "Howling feedback" to "You are monitoring through the phone speaker. Use headphones or a cable, or mute output.",
    "Crackles or dropouts" to "Switch DSP quality to Low latency, disable Exclusive audio, close other audio apps, keep the phone cool.",
    "Echo of your real voice" to "On Quest, make sure the built-in microphone is not also active; use the external input only.",
    "Robotic or metallic voice" to "Reduce pitch/formant shifts (stay within +7 st), lower noise reduction, use High quality mode.",
    "Engine stops in background" to "Allow notifications so the foreground service can run; disable battery optimisation for VoiceShift.",
    "USB interface not listed" to "Use a powered hub or a different OTG adapter; some interfaces need more power than a phone supplies.",
    "AI model too slow" to "The app falls back to DSP automatically. Use a smaller model or a larger chunk size.",
)

private val licenses = listOf(
    "Oboe (Google)" to "Apache-2.0",
    "ONNX Runtime Mobile (Microsoft)" to "MIT",
    "AndroidX, Jetpack Compose, Material 3" to "Apache-2.0",
    "Dagger / Hilt (Google)" to "Apache-2.0",
    "Kotlin, kotlinx.coroutines, kotlinx.serialization (JetBrains)" to "Apache-2.0",
    "VoiceShift VR DSP (this project)" to "Apache-2.0",
)

@Composable
fun SettingsScreen(vm: SettingsViewModel = hiltViewModel()) {
    val ui by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val s = ui.settings

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Text("Settings", style = MaterialTheme.typography.headlineSmall) }
        item {
            SectionCard("DSP quality", subtitle = "Frame length of the pitch/formant engine. Restarts audio if running.") {
                DspQuality.entries.forEach { q ->
                    Choice(q.label, if (q == DspQuality.QUALITY) "Resolves low voices cleanly. Recommended." else "Less delay; low male voices may sound rougher.", s.quality == q.name) { vm.setQuality(q) }
                }
            }
        }
        item {
            SectionCard("Microphone mode", subtitle = "Android input preset.") {
                MicMode.entries.forEach { m -> Choice(m.label, m.description, s.micMode == m.name) { vm.setMicMode(m) } }
            }
        }
        item {
            SectionCard("Audio") {
                SwitchRow("Exclusive audio", s.exclusiveAudio, vm::setExclusive, "Lowest latency when the device allows it. Disable if other apps lose sound.")
                SwitchRow("Keep screen on while live", s.keepScreenOn, vm::setKeepScreenOn)
            }
        }
        item {
            SectionCard("Diagnostics", subtitle = "Logs stay on this device. Sharing is manual.") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_SUBJECT, "VoiceShift VR diagnostic report")
                            putExtra(Intent.EXTRA_TEXT, vm.report())
                        }
                        context.startActivity(Intent.createChooser(send, "Share diagnostic report"))
                    }) {
                        Icon(Icons.Filled.Share, null)
                        Text(" Share report")
                    }
                    OutlinedButton(onClick = vm::clearLogs) { Text("Clear log") }
                }
                Text("Recent events", style = MaterialTheme.typography.titleSmall)
                if (ui.logs.isEmpty()) Text("No events yet.", style = MaterialTheme.typography.bodySmall)
            }
        }
        items(ui.logs.takeLast(80).reversed()) { e ->
            Text(
                e.format(),
                style = NumericStyle.copy(fontSize = NumericStyle.fontSize * 0.85f),
                color = when (e.level) {
                    LogLevel.ERROR -> VsColors.Red
                    LogLevel.WARN -> VsColors.Amber
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }
        item {
            SectionCard("Troubleshooting") {
                troubleshooting.forEach { (problem, fix) ->
                    Column {
                        Text(problem, style = MaterialTheme.typography.bodyMedium)
                        Text(fix, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        item {
            SectionCard("Privacy & licenses", subtitle = "VoiceShift VR ${BuildConfig.VERSION_NAME}") {
                Text(
                    "Works offline. No accounts, analytics or uploads. Audio is processed in memory and never recorded. " +
                        "Imported models stay in private app storage until you delete them.",
                    style = MaterialTheme.typography.bodySmall,
                )
                licenses.forEach { (name, license) ->
                    Row(Modifier.fillMaxWidth()) {
                        Text(name, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                        Text(license, style = NumericStyle)
                    }
                }
            }
        }
    }
}

@Composable
private fun Choice(title: String, subtitle: String, selected: Boolean, onSelect: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().selectable(selected = selected, onClick = onSelect).padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onSelect)
        Column {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
