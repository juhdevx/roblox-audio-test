package com.voiceshift.vr.ui.models

import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.voiceshift.inference.WorkerState
import com.voiceshift.models.Compatibility
import com.voiceshift.models.ConsentDeclaration
import com.voiceshift.models.ModelFamily
import com.voiceshift.models.ModelRecord
import com.voiceshift.vr.session.NeuralStatus
import com.voiceshift.vr.session.VoiceSession
import com.voiceshift.vr.ui.components.Notice
import com.voiceshift.vr.ui.components.NoticeKind
import com.voiceshift.vr.ui.components.SectionCard
import com.voiceshift.vr.ui.components.StatRow
import com.voiceshift.vr.ui.components.StatusPill
import com.voiceshift.vr.ui.theme.VsColors
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ModelsUiState(
    val models: List<ModelRecord> = emptyList(),
    val neural: NeuralStatus = NeuralStatus(),
    val importing: Boolean = false,
)

@HiltViewModel
class ModelsViewModel @Inject constructor(private val session: VoiceSession) : ViewModel() {
    private val importing = MutableStateFlow(false)

    val state: StateFlow<ModelsUiState> = combine(session.models, session.neural, importing) { m, n, i ->
        ModelsUiState(m.sortedByDescending { it.importedAt }, n, i)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ModelsUiState())

    fun import(uri: Uri, name: String, consent: ConsentDeclaration) = viewModelScope.launch {
        importing.value = true
        try {
            session.importModel(uri, name, consent)
        } finally {
            importing.value = false
        }
    }

    fun load(id: String) = viewModelScope.launch { session.loadModel(id) }
    fun unload() = viewModelScope.launch { session.unloadModel() }
    fun delete(id: String) = viewModelScope.launch { session.deleteModel(id) }
    fun revalidate(id: String) = viewModelScope.launch { session.revalidateModel(id) }
}

@Composable
fun ModelsScreen(vm: ModelsViewModel = hiltViewModel()) {
    val ui by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var pendingImport by remember { mutableStateOf<Pair<Uri, String>?>(null) }
    var pendingDelete by remember { mutableStateOf<ModelRecord?>(null) }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            } ?: "model.onnx"
            pendingImport = uri to name
        }
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text("Voice models", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Engine B runs ONNX models on-device. Models stay in private app storage and are never uploaded.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        item { NeuralStatusCard(ui.neural, onUnload = vm::unload) }
        item {
            Notice(
                NoticeKind.INFO,
                "No voice model is bundled. Supported: waveform-in/waveform-out ONNX models with VoiceShift " +
                    "'stream-v1' metadata (see docs/MODELS.md). RVC exports are detected but cannot run yet: they also need " +
                    "a content encoder and pitch extractor that this version does not include.",
            )
        }
        item {
            Button(onClick = { picker.launch(arrayOf("*/*")) }, enabled = !ui.importing, modifier = Modifier.fillMaxWidth()) {
                if (ui.importing) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Text("  Validating…")
                } else {
                    Icon(Icons.Filled.Add, null)
                    Text(" Import .onnx file")
                }
            }
        }
        if (ui.models.isEmpty()) {
            item {
                Text(
                    "Your library is empty. Tip: tools/onnx/make_test_models.py --diagnostic (or the CI artifact " +
                        "'diagnostic-onnx-models') produces pass-through test models to verify the AI pipeline end to end.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(ui.models, key = { it.id }) { record ->
            ModelCard(
                record = record,
                loaded = record.id == ui.neural.loadedModelId,
                onLoad = { vm.load(record.id) },
                onUnload = vm::unload,
                onRevalidate = { vm.revalidate(record.id) },
                onDelete = { pendingDelete = record },
            )
        }
    }

    pendingImport?.let { (uri, name) ->
        ConsentDialog(
            fileName = name,
            onDismiss = { pendingImport = null },
            onConfirm = { consent ->
                vm.import(uri, name, consent)
                pendingImport = null
            },
        )
    }

    pendingDelete?.let { record ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("Delete model?") },
            text = { Text("'${record.displayName}' (${record.sizeBytes / 1024} KB) will be erased from this device. Presets using it switch to DSP.") },
            confirmButton = { TextButton(onClick = { vm.delete(record.id); pendingDelete = null }) { Text("Delete") } },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun NeuralStatusCard(neural: NeuralStatus, onUnload: () -> Unit) {
    SectionCard("AI engine", subtitle = neural.loadedModelName?.let { "Loaded: $it" } ?: "No model loaded — DSP engine is used.") {
        val spec = neural.spec
        if (spec != null) {
            StatRow("Model audio", "${spec.sampleRate} Hz · ${"%.0f".format(spec.chunkDurationMs)} ms chunks")
            val w = neural.worker
            StatRow("Worker", w.state.name.lowercase().replace('_', ' '),
                when (w.state) {
                    WorkerState.RUNNING -> VsColors.Green
                    WorkerState.STOPPED_ERROR, WorkerState.STOPPED_TOO_SLOW -> VsColors.Red
                    else -> VsColors.TextSecondary
                })
            StatRow("Inference", "%.1f ms avg · %.1f ms max".format(w.averageInferenceMs, w.maxInferenceMs))
            StatRow("Real-time factor", "%.2f (must stay < 1)".format(w.realtimeFactor), if (w.realtimeFactor >= 1.0) VsColors.Red else VsColors.TextPrimary)
            StatRow("Chunks", w.chunksProcessed.toString())
            w.lastError?.let { Notice(NoticeKind.WARN, it) }
            OutlinedButton(onClick = onUnload) { Text("Unload model") }
        }
    }
}

@Composable
private fun ModelCard(
    record: ModelRecord,
    loaded: Boolean,
    onLoad: () -> Unit,
    onUnload: () -> Unit,
    onRevalidate: () -> Unit,
    onDelete: () -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val r = record.report
    Card(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = if (loaded) BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null,
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${record.displayName}  r${record.revision}", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "%.1f MB · %s%s".format(record.sizeBytes / 1_048_576.0, familyLabel(r.family), record.version?.let { " · v$it" } ?: ""),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                when (r.compatibility) {
                    Compatibility.COMPATIBLE -> StatusPill("Compatible", VsColors.Green)
                    Compatibility.UNSUPPORTED -> StatusPill("Unsupported", VsColors.Amber)
                    Compatibility.INVALID -> StatusPill("Invalid", VsColors.Red)
                }
            }
            Text(r.summary, style = MaterialTheme.typography.bodySmall)
            r.smokeTestRealtimeFactor?.let { StatRow("Smoke test speed", "%.2f × real time".format(it)) }
            if (record.consent.isCustomVoice) StatRow("Custom voice", if (record.consent.consentConfirmed) "consent confirmed" else "no consent")
            r.license?.let { StatRow("License", it) }
            if (expanded) {
                r.inputs.forEach { StatRow("Input", it.toString()) }
                r.outputs.forEach { StatRow("Output", it.toString()) }
                r.issues.forEach { Notice(NoticeKind.ERROR, it) }
                r.warnings.forEach { Notice(NoticeKind.WARN, it) }
                StatRow("SHA-256", record.sha256.take(16) + "…")
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (r.compatibility == Compatibility.COMPATIBLE) {
                    if (loaded) TextButton(onClick = onUnload) { Text("Unload") } else Button(onClick = onLoad) { Text("Load") }
                }
                TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "Less" else "Details") }
                TextButton(onClick = onRevalidate) { Text("Re-check") }
                TextButton(onClick = onDelete) { Text("Delete", color = VsColors.Red) }
            }
        }
    }
}

private fun familyLabel(f: ModelFamily) = when (f) {
    ModelFamily.STREAMING_V1 -> "stream-v1"
    ModelFamily.RVC_GENERATOR -> "RVC synthesizer"
    ModelFamily.FEATURE_ENCODER -> "feature encoder"
    ModelFamily.UNKNOWN -> "unknown"
}

@Composable
private fun ConsentDialog(fileName: String, onDismiss: () -> Unit, onConfirm: (ConsentDeclaration) -> Unit) {
    var custom by remember { mutableStateOf(false) }
    var confirmed by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Import $fileName") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Whose voice does this model produce?", style = MaterialTheme.typography.bodyMedium)
                ConsentOption("A generic / synthetic voice (not a real person)", !custom) { custom = false }
                ConsentOption("A real person's voice (mine, or someone who agreed)", custom) { custom = true }
                if (custom) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = confirmed, onCheckedChange = { confirmed = it })
                        Text(
                            "I own this voice or have the speaker's documented permission, and I will not use it to impersonate or deceive anyone.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    OutlinedTextField(note, { note = it.take(300) }, label = { Text("Consent note (optional)") }, singleLine = false)
                }
            }
        },
        confirmButton = {
            TextButton(enabled = !custom || confirmed, onClick = { onConfirm(ConsentDeclaration(custom, custom && confirmed, note)) }) {
                Text("Import")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ConsentOption(text: String, selected: Boolean, onSelect: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().selectable(selected = selected, onClick = onSelect),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onSelect)
        Text(text, style = MaterialTheme.typography.bodySmall)
    }
}
