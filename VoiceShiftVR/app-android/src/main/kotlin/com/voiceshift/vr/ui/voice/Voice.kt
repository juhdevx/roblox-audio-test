package com.voiceshift.vr.ui.voice

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.FilterChip
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.voiceshift.audio.EngineState
import com.voiceshift.dsp.CalibrationResult
import com.voiceshift.dsp.PitchCalibration
import com.voiceshift.dsp.VoiceParameter
import com.voiceshift.dsp.VoiceSettings
import com.voiceshift.models.PresetEngine
import com.voiceshift.models.VoicePreset
import com.voiceshift.vr.session.VoiceSession
import com.voiceshift.vr.ui.components.ParameterSlider
import com.voiceshift.vr.ui.components.SectionCard
import com.voiceshift.vr.ui.components.SwitchRow
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class VoiceUiState(
    val voice: VoiceSettings = VoiceSettings(),
    val presets: List<VoicePreset> = emptyList(),
    val activePresetId: String = "",
    val engineRunning: Boolean = false,
    val calibration: CalibrationUi = CalibrationUi(),
)

data class CalibrationUi(
    val running: Boolean = false,
    val progress: Float = 0f,
    val voicedReadings: Int = 0,
    val targetHz: Float = PitchCalibration.DEFAULT_TARGET_HZ,
    val result: CalibrationResult? = null,
    val message: String? = null,
)

@HiltViewModel
class VoiceViewModel @Inject constructor(private val session: VoiceSession) : ViewModel() {
    private val calibration = MutableStateFlow(CalibrationUi())
    private val readings = mutableListOf<Pair<Float, Float>>()
    private var calibrationJob: Job? = null

    val state: StateFlow<VoiceUiState> = combine(
        session.voice, session.presets, session.settings, session.engineState, calibration,
    ) { v, p, s, e, c ->
        VoiceUiState(v, p, s.activePresetId, e is EngineState.Running, c)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), VoiceUiState())

    /** Listens to the live pitch tracker for 10 s while the user reads aloud. */
    fun startCalibration() {
        calibrationJob?.cancel()
        readings.clear()
        calibration.value = calibration.value.copy(running = true, progress = 0f, voicedReadings = 0, result = null, message = null)
        calibrationJob = viewModelScope.launch {
            val durationMs = 10_000L
            val stepMs = 50L
            var elapsed = 0L
            while (elapsed < durationMs) {
                val st = session.stats.value
                readings += st.inputPitchHz to st.pitchConfidence
                elapsed += stepMs
                val voiced = readings.count { (hz, conf) -> hz > 0f && conf >= PitchCalibration.MIN_CONFIDENCE }
                calibration.value = calibration.value.copy(progress = elapsed / durationMs.toFloat(), voicedReadings = voiced)
                delay(stepMs)
            }
            finishCalibration()
        }
    }

    fun cancelCalibration() {
        calibrationJob?.cancel()
        calibration.value = calibration.value.copy(running = false)
    }

    fun setCalibrationTarget(hz: Float) {
        calibration.value = calibration.value.copy(targetHz = hz)
        if (calibration.value.result != null) finishCalibration()
    }

    private fun finishCalibration() {
        val c = PitchCalibration(calibration.value.targetHz)
        readings.forEach { (hz, conf) -> c.add(hz, conf) }
        val result = c.result()
        calibration.value = calibration.value.copy(
            running = false,
            result = result,
            message = if (result == null) "Not enough voiced speech was heard. Read a sentence aloud at normal volume, closer to the microphone." else null,
        )
    }

    fun applyCalibration() {
        val r = calibration.value.result ?: return
        session.setVoiceParameter(VoiceParameter.PITCH_SEMITONES, r.suggestedPitchSemitones)
        session.setVoiceParameter(VoiceParameter.FORMANT_SEMITONES, r.suggestedFormantSemitones)
        session.message("Applied: %+.1f st pitch, %+.1f st formant".format(r.suggestedPitchSemitones, r.suggestedFormantSemitones))
    }

    fun set(p: VoiceParameter, value: Float) = session.setVoiceParameter(p, value)
    fun apply(p: VoicePreset) = session.applyPreset(p)
    fun resetToPreset() = session.resetToActivePreset()
    fun save(name: String) = viewModelScope.launch { session.saveCurrentAsPreset(name) }
    fun overwrite(id: String) = viewModelScope.launch { session.overwritePreset(id) }
    fun delete(id: String) = viewModelScope.launch { session.deletePreset(id) }
}

@Composable
fun VoiceScreen(vm: VoiceViewModel = hiltViewModel()) {
    val ui by vm.state.collectAsStateWithLifecycle()
    var showSave by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<VoicePreset?>(null) }
    val v = ui.voice

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text("Voice", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Built-in presets are generic feminine settings, not anyone's real voice. Changes apply live.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { showSave = true }) {
                    Icon(Icons.Filled.Add, null)
                    Text(" Save as preset")
                }
                OutlinedButton(onClick = vm::resetToPreset) {
                    Icon(Icons.Filled.Refresh, null)
                    Text(" Revert")
                }
            }
        }
        item { CalibrationCard(ui, vm) }
        items(ui.presets, key = { it.id }) { preset ->
            PresetRow(
                preset = preset,
                active = preset.id == ui.activePresetId,
                onApply = { vm.apply(preset) },
                onOverwrite = { vm.overwrite(preset.id) },
                onDelete = { pendingDelete = preset },
            )
        }
        item {
            SectionCard("Voice character") {
                ParameterSlider(VoiceParameter.PITCH_SEMITONES, v.pitchSemitones, { vm.set(VoiceParameter.PITCH_SEMITONES, it) })
                ParameterSlider(VoiceParameter.FORMANT_SEMITONES, v.formantSemitones, { vm.set(VoiceParameter.FORMANT_SEMITONES, it) })
                ParameterSlider(VoiceParameter.BREATHINESS, v.breathiness, { vm.set(VoiceParameter.BREATHINESS, it) })
                Text(
                    "Tip: most natural results come from +4…+7 st pitch with +1…+3 st formants. Large shifts sound artificial.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        item {
            SectionCard("Clean-up") {
                ParameterSlider(VoiceParameter.NOISE_REDUCTION, v.noiseReduction, { vm.set(VoiceParameter.NOISE_REDUCTION, it) })
                ParameterSlider(VoiceParameter.GATE_THRESHOLD_DB, v.gateThresholdDb, { vm.set(VoiceParameter.GATE_THRESHOLD_DB, it) })
                ParameterSlider(VoiceParameter.LOW_CUT_HZ, v.lowCutHz, { vm.set(VoiceParameter.LOW_CUT_HZ, it) })
                SwitchRow("Automatic gain", v.agcEnabled, { vm.set(VoiceParameter.AGC_ENABLED, if (it) 1f else 0f) }, "Evens out loud and quiet speech.")
                ParameterSlider(VoiceParameter.AGC_TARGET_DB, v.agcTargetDb, { vm.set(VoiceParameter.AGC_TARGET_DB, it) }, enabled = v.agcEnabled)
            }
        }
        item {
            SectionCard("Tone") {
                ParameterSlider(VoiceParameter.BODY_DB, v.bodyDb, { vm.set(VoiceParameter.BODY_DB, it) })
                ParameterSlider(VoiceParameter.PRESENCE_DB, v.presenceDb, { vm.set(VoiceParameter.PRESENCE_DB, it) })
                ParameterSlider(VoiceParameter.AIR_DB, v.airDb, { vm.set(VoiceParameter.AIR_DB, it) })
            }
        }
        item {
            SectionCard("Dynamics & level") {
                ParameterSlider(VoiceParameter.COMPRESSION, v.compression, { vm.set(VoiceParameter.COMPRESSION, it) })
                ParameterSlider(VoiceParameter.OUTPUT_GAIN_DB, v.outputGainDb, { vm.set(VoiceParameter.OUTPUT_GAIN_DB, it) })
                Text(
                    "A peak limiter at -1 dBFS always protects the output from clipping.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }

    if (showSave) {
        var name by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showSave = false },
            title = { Text("Save preset") },
            text = {
                OutlinedTextField(name, { name = it.take(60) }, label = { Text("Name") }, singleLine = true)
            },
            confirmButton = {
                TextButton(enabled = name.isNotBlank(), onClick = { vm.save(name); showSave = false }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { showSave = false }) { Text("Cancel") } },
        )
    }

    pendingDelete?.let { preset ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("Delete preset?") },
            text = { Text("'${preset.name}' will be removed from this device.") },
            confirmButton = { TextButton(onClick = { vm.delete(preset.id); pendingDelete = null }) { Text("Delete") } },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun CalibrationCard(ui: VoiceUiState, vm: VoiceViewModel) {
    val c = ui.calibration
    SectionCard(
        "Calibrate to your voice",
        subtitle = "Measures your speaking pitch and suggests pitch and formant shifts to reach the target.",
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Target", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            PitchCalibration.TARGETS.forEach { (label, hz) ->
                FilterChip(
                    selected = c.targetHz == hz,
                    onClick = { vm.setCalibrationTarget(hz) },
                    label = { Text("${hz.toInt()} Hz") },
                    modifier = Modifier.semantics { contentDescription = "$label target ${hz.toInt()} hertz" },
                )
            }
        }
        when {
            !ui.engineRunning && !c.running -> Text(
                "Start the voice engine on Home, then read a sentence aloud for 10 seconds.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            c.running -> {
                Text("Read aloud at your normal speaking voice… (${c.voicedReadings} voiced readings)", style = MaterialTheme.typography.bodySmall)
                LinearProgressIndicator(progress = { c.progress }, modifier = Modifier.fillMaxWidth())
                OutlinedButton(onClick = vm::cancelCalibration) { Text("Cancel") }
            }
            else -> Button(onClick = vm::startCalibration) { Text(if (c.result == null) "Start 10 s calibration" else "Measure again") }
        }
        c.message?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
        c.result?.let { r ->
            Text(
                "Your speaking pitch: %.0f Hz (most speech %.0f–%.0f Hz).\nSuggested: %+.1f st pitch, %+.1f st formant → about %.0f Hz.".format(
                    r.medianHz, r.lowHz, r.highHz, r.suggestedPitchSemitones, r.suggestedFormantSemitones, r.expectedOutputHz,
                ),
                style = MaterialTheme.typography.bodyMedium,
            )
            if (r.suggestedPitchSemitones == 0f) {
                Text("Your voice is already at or above the target; consider only formant/EQ changes.", style = MaterialTheme.typography.bodySmall)
            }
            Button(onClick = vm::applyCalibration) { Text("Apply suggestion") }
        }
    }
}

@Composable
private fun PresetRow(
    preset: VoicePreset,
    active: Boolean,
    onApply: () -> Unit,
    onOverwrite: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onApply),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = if (active) BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null,
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    preset.name + if (preset.engine == PresetEngine.NEURAL) "  · AI" else "",
                    style = MaterialTheme.typography.titleSmall,
                )
                val detail = preset.description.ifBlank {
                    "%+.1f st pitch · %+.1f st formant".format(preset.settings.pitchSemitones, preset.settings.formantSemitones)
                }
                Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (!preset.builtIn) {
                IconButton(onClick = onOverwrite) { Icon(Icons.Filled.Edit, contentDescription = "Overwrite with current settings") }
                IconButton(onClick = onDelete) { Icon(Icons.Filled.Delete, contentDescription = "Delete preset") }
            }
            if (!active) TextButton(onClick = onApply) { Text("Apply") }
        }
    }
}
