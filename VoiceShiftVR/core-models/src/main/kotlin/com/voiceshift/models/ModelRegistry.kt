package com.voiceshift.models

import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** Broad model families recognised by the validator. */
@Serializable
enum class ModelFamily {
    /** Waveform-in / waveform-out ONNX following the VoiceShift streaming contract (docs/MODELS.md). */
    STREAMING_V1,
    /** RVC synthesizer graph (inputs phone/pitch/pitchf/...). Needs encoder + F0 stages not in the runtime. */
    RVC_GENERATOR,
    /** HuBERT/ContentVec-style feature encoder on its own. */
    FEATURE_ENCODER,
    UNKNOWN,
}

@Serializable
enum class Compatibility {
    /** Validated and runnable by the streaming worker. */
    COMPATIBLE,
    /** Recognised but cannot run in this version; the report says why. */
    UNSUPPORTED,
    /** Could not be parsed as an ONNX model at all. */
    INVALID,
}

@Serializable
data class TensorDescription(val name: String, val type: String, val shape: List<Long>) {
    override fun toString(): String = "$name: $type${shape.joinToString(prefix = "[", postfix = "]")}"
}

/** Result of inspecting a model file. Produced by a [ModelValidator] (ONNX Runtime in core-inference). */
@Serializable
data class ValidationReport(
    val family: ModelFamily,
    val compatibility: Compatibility,
    val summary: String,
    val issues: List<String> = emptyList(),
    val warnings: List<String> = emptyList(),
    val inputs: List<TensorDescription> = emptyList(),
    val outputs: List<TensorDescription> = emptyList(),
    val sampleRate: Int? = null,
    val chunkFrames: Int? = null,
    val contextFrames: Int = 0,
    val version: String? = null,
    val license: String? = null,
    val declaredVoiceOwner: String? = null,
    val declaredConsent: Boolean = false,
    /** Inference time of one chunk / chunk duration from the smoke test (< 1 means faster than real time). */
    val smokeTestRealtimeFactor: Double? = null,
)

fun interface ModelValidator {
    fun validate(file: File): ValidationReport
}

/** The user's declaration made at import time. */
@Serializable
data class ConsentDeclaration(
    /** The model reproduces a specific real person's voice (including the user's own). */
    val isCustomVoice: Boolean,
    /** The user confirms they own the voice or hold the speaker's documented permission. */
    val consentConfirmed: Boolean,
    val note: String = "",
)

@Serializable
data class ModelRecord(
    val id: String,
    val displayName: String,
    val fileName: String,
    val sizeBytes: Long,
    val sha256: String,
    val importedAt: Long,
    /** Version string from model metadata, if any. */
    val version: String? = null,
    /** Increments each time a model with the same display name is imported again. */
    val revision: Int = 1,
    val report: ValidationReport,
    val consent: ConsentDeclaration,
)

sealed interface ImportResult {
    data class Imported(val record: ModelRecord) : ImportResult
    data class Duplicate(val existing: ModelRecord) : ImportResult
    data class Rejected(val reason: String) : ImportResult
}

/** Decides whether loading a model is safe given current free memory. Pure; see [MemoryBudget]. */
interface MemoryBudget {
    fun availableBytes(): Long
    fun isLowRamDevice(): Boolean
}

sealed interface LoadDecision {
    data object Allowed : LoadDecision
    data class Denied(val reason: String) : LoadDecision
}

object LoadPlanner {
    private const val MB = 1024L * 1024L

    /**
     * ONNX Runtime typically needs the weights plus arena/workspace memory; budget 3x the file size
     * plus a fixed margin so the audio engine and UI are never starved.
     */
    fun check(record: ModelRecord, budget: MemoryBudget): LoadDecision {
        if (record.report.compatibility != Compatibility.COMPATIBLE) {
            return LoadDecision.Denied("Model is not compatible: ${record.report.summary}")
        }
        if (record.consent.isCustomVoice && !record.consent.consentConfirmed) {
            return LoadDecision.Denied("Custom voice without confirmed consent cannot be loaded.")
        }
        val needed = record.sizeBytes * 3 + 128 * MB
        val available = budget.availableBytes()
        if (budget.isLowRamDevice() && record.sizeBytes > 64 * MB) {
            return LoadDecision.Denied("Low-RAM device: models above 64 MB are not loaded.")
        }
        if (needed > available) {
            return LoadDecision.Denied(
                "Not enough free memory: needs ~${needed / MB} MB, ${available / MB} MB available. Close other apps and retry.",
            )
        }
        return LoadDecision.Allowed
    }
}

/**
 * Local, private model library. Files live in app-private storage (`root/<id>/model.onnx`) with a
 * JSON index; nothing is ever uploaded.
 */
class ModelRegistry(
    private val root: File,
    private val validator: ModelValidator,
    private val clock: () -> Long = System::currentTimeMillis,
    private val newId: () -> String = { UUID.randomUUID().toString() },
    private val maxBytes: Long = 512L * 1024 * 1024,
) {
    private val store = JsonFileStore(File(root, "index.json"), ListSerializer(ModelRecord.serializer()), emptyList(), clock)

    val records: StateFlow<List<ModelRecord>> = store.value

    fun find(id: String): ModelRecord? = records.value.firstOrNull { it.id == id }

    fun fileFor(record: ModelRecord): File = File(File(root, record.id), record.fileName)

    /** Copies [source] into the library, validates it and records it. [source] is always closed. */
    suspend fun import(source: InputStream, suggestedName: String, consent: ConsentDeclaration): ImportResult {
        if (consent.isCustomVoice && !consent.consentConfirmed) {
            source.close()
            return ImportResult.Rejected(
                "Custom voices require your confirmation that you own the voice or have the speaker's permission.",
            )
        }
        root.mkdirs()
        val staging = File(root, "import-${newId()}.tmp")
        val sha: String
        val size: Long
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            source.use { input ->
                staging.outputStream().buffered().use { out ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        total += n
                        if (total > maxBytes) {
                            return ImportResult.Rejected("File is larger than ${maxBytes / (1024 * 1024)} MB.")
                        }
                        digest.update(buffer, 0, n)
                        out.write(buffer, 0, n)
                    }
                }
            }
            if (total == 0L) return ImportResult.Rejected("File is empty.")
            sha = digest.digest().joinToString("") { "%02x".format(it) }
            size = total

            records.value.firstOrNull { it.sha256 == sha }?.let { return ImportResult.Duplicate(it) }

            val report = try {
                validator.validate(staging)
            } catch (e: Exception) {
                ValidationReport(ModelFamily.UNKNOWN, Compatibility.INVALID, "Could not read model: ${e.message}")
            }
            if (report.compatibility == Compatibility.INVALID) {
                return ImportResult.Rejected(report.summary)
            }
            if (report.declaredVoiceOwner != null && !consent.consentConfirmed) {
                return ImportResult.Rejected(
                    "This model declares a voice owner (${report.declaredVoiceOwner}). Confirm you have their permission to import it.",
                )
            }

            val id = newId()
            val name = suggestedName.substringBeforeLast('.').trim().ifEmpty { "Model" }.take(60)
            val revision = records.value.count { it.displayName == name } + 1
            val dir = File(root, id).apply { mkdirs() }
            val target = File(dir, "model.onnx")
            if (!staging.renameTo(target)) {
                staging.copyTo(target, overwrite = true)
            }
            val record = ModelRecord(
                id = id, displayName = name, fileName = target.name, sizeBytes = size, sha256 = sha,
                importedAt = clock(), version = report.version, revision = revision, report = report, consent = consent,
            )
            store.update { it + record }
            return ImportResult.Imported(record)
        } finally {
            if (staging.exists()) staging.delete()
        }
    }

    suspend fun rename(id: String, newName: String) {
        val clean = newName.trim().take(60)
        require(clean.isNotEmpty()) { "Name must not be empty" }
        store.update { list -> list.map { if (it.id == id) it.copy(displayName = clean) else it } }
    }

    /** Re-runs validation (e.g. after an app update that supports more models). */
    suspend fun revalidate(id: String): ModelRecord? {
        val record = find(id) ?: return null
        val report = validator.validate(fileFor(record))
        val updated = record.copy(report = report, version = report.version)
        store.update { list -> list.map { if (it.id == id) updated else it } }
        return updated
    }

    /** Removes the files and the index entry. Returns true when the model existed. */
    suspend fun delete(id: String): Boolean {
        val record = find(id) ?: return false
        File(root, record.id).deleteRecursively()
        store.update { list -> list.filterNot { it.id == id } }
        return true
    }

    fun totalBytes(): Long = records.value.sumOf { it.sizeBytes }
}
