package com.voiceshift.inference

import com.voiceshift.models.Compatibility
import com.voiceshift.models.ModelFamily
import com.voiceshift.models.TensorDescription
import com.voiceshift.models.ValidationReport

/** What ONNX Runtime tells us about a graph, decoupled from ORT types so the rules are unit-testable. */
data class ModelIntrospection(
    val inputs: List<TensorDescription>,
    val outputs: List<TensorDescription>,
    val customMetadata: Map<String, String> = emptyMap(),
    val producer: String = "",
    val graphName: String = "",
    val description: String = "",
)

/** How the streaming worker must feed and read a STREAMING_V1 model. */
data class StreamingSpec(
    val inputName: String,
    val inputRank: Int,
    val outputName: String,
    val sampleRate: Int,
    val chunkFrames: Int,
    val contextFrames: Int,
    /** Fixed input length, or null when the time dimension is dynamic. */
    val fixedInputLength: Int?,
) {
    val windowFrames: Int get() = contextFrames + chunkFrames
    val chunkDurationMs: Double get() = chunkFrames * 1000.0 / sampleRate

    /** Tensor shape for one window, e.g. [1, N] or [1, 1, N]. */
    fun inputShape(): LongArray = when (inputRank) {
        1 -> longArrayOf(windowFrames.toLong())
        2 -> longArrayOf(1, windowFrames.toLong())
        else -> longArrayOf(1, 1, windowFrames.toLong())
    }

    /** Selects the newest [chunkFrames] samples from a model output of any accepted length. */
    fun selectChunk(output: FloatArray): FloatArray? = when {
        output.size == chunkFrames -> output
        output.size == windowFrames -> output.copyOfRange(contextFrames, windowFrames)
        else -> null
    }
}

data class Analysis(val report: ValidationReport, val spec: StreamingSpec?)

/**
 * Rules that decide whether a model can run in the streaming engine. The contract ("stream-v1") is
 * documented in docs/MODELS.md:
 *
 *  * exactly one float32 input and one float32 output, shaped [N], [1, N] or [1, 1, N];
 *  * metadata `voiceshift.contract = stream-v1` and `voiceshift.sample_rate`;
 *  * optional `voiceshift.chunk_samples` / `voiceshift.context_samples`;
 *  * output length equal to the chunk or to context + chunk.
 *
 * Recognised-but-unsupported families (RVC synthesizers, feature encoders) are reported honestly
 * instead of being "loaded" and producing garbage.
 */
object CompatibilityAnalyzer {
    const val KEY_CONTRACT = "voiceshift.contract"
    const val KEY_SAMPLE_RATE = "voiceshift.sample_rate"
    const val KEY_CHUNK = "voiceshift.chunk_samples"
    const val KEY_CONTEXT = "voiceshift.context_samples"
    const val KEY_VERSION = "voiceshift.version"
    const val KEY_LICENSE = "voiceshift.license"
    const val KEY_VOICE_OWNER = "voiceshift.voice_owner"
    const val KEY_VOICE_CONSENT = "voiceshift.voice_owner_consent"
    const val CONTRACT_V1 = "stream-v1"

    private val RVC_MARKERS = setOf("phone", "phone_lengths", "pitch", "pitchf", "ds", "sid", "rnd")

    fun analyze(model: ModelIntrospection): Analysis {
        val meta = model.customMetadata
        val version = meta[KEY_VERSION]
        val license = meta[KEY_LICENSE]
        val owner = meta[KEY_VOICE_OWNER]?.takeIf { it.isNotBlank() }
        val consent = meta[KEY_VOICE_CONSENT]?.trim()?.lowercase() in setOf("true", "yes", "documented")
        fun report(
            family: ModelFamily,
            compatibility: Compatibility,
            summary: String,
            issues: List<String> = emptyList(),
            warnings: List<String> = emptyList(),
            sampleRate: Int? = null,
            chunk: Int? = null,
            context: Int = 0,
        ) = ValidationReport(
            family = family, compatibility = compatibility, summary = summary, issues = issues, warnings = warnings,
            inputs = model.inputs, outputs = model.outputs, sampleRate = sampleRate, chunkFrames = chunk,
            contextFrames = context, version = version, license = license, declaredVoiceOwner = owner,
            declaredConsent = consent,
        )

        val inputNames = model.inputs.map { it.name.lowercase() }.toSet()
        if (inputNames.contains("phone") && (inputNames.contains("pitch") || inputNames.contains("pitchf")) ||
            inputNames.count { it in RVC_MARKERS } >= 3
        ) {
            return Analysis(
                report(
                    ModelFamily.RVC_GENERATOR, Compatibility.UNSUPPORTED,
                    "RVC synthesizer graph detected. It needs HuBERT/ContentVec features and an F0 track " +
                        "(RMVPE/CREPE) as inputs; that pipeline is not part of this version's mobile runtime.",
                    issues = listOf(
                        "Inputs ${model.inputs.joinToString { it.name }} are RVC features, not audio.",
                        "Convert to a waveform-in/waveform-out stream-v1 model (docs/MODELS.md) to use it here.",
                    ),
                ),
                null,
            )
        }

        if (model.inputs.size == 1 && model.outputs.size == 1) {
            val out = model.outputs.single()
            if (out.shape.size == 3 && out.shape.last() in setOf(256L, 512L, 768L, 1024L)) {
                return Analysis(
                    report(
                        ModelFamily.FEATURE_ENCODER, Compatibility.UNSUPPORTED,
                        "Speech feature encoder (outputs ${out.shape.last()}-dim features). It does not produce audio by itself.",
                    ),
                    null,
                )
            }
        }

        val issues = mutableListOf<String>()
        val warnings = mutableListOf<String>()
        if (model.inputs.size != 1) issues += "Expected exactly 1 input, found ${model.inputs.size}."
        if (model.outputs.size != 1) issues += "Expected exactly 1 output, found ${model.outputs.size}."
        if (issues.isNotEmpty()) {
            return Analysis(
                report(ModelFamily.UNKNOWN, Compatibility.UNSUPPORTED, "Unrecognised model signature.", issues), null,
            )
        }
        val input = model.inputs.single()
        val output = model.outputs.single()
        if (input.type != "FLOAT") issues += "Input must be float32, is ${input.type}."
        if (output.type != "FLOAT") issues += "Output must be float32, is ${output.type}."
        if (input.shape.size !in 1..3) issues += "Input rank must be 1-3 ([N], [1,N] or [1,1,N]), is ${input.shape.size}."
        if (output.shape.size !in 1..3) issues += "Output rank must be 1-3, is ${output.shape.size}."
        if (input.shape.dropLast(1).any { it != 1L && it != -1L }) {
            issues += "Leading input dimensions must be 1 (batch/channel), found ${input.shape}."
        }

        val contract = meta[KEY_CONTRACT]
        if (contract != CONTRACT_V1) {
            issues += if (contract == null) "Missing metadata $KEY_CONTRACT=$CONTRACT_V1." else "Unsupported contract '$contract'."
        }
        val sampleRate = meta[KEY_SAMPLE_RATE]?.toIntOrNull()
        when {
            sampleRate == null -> issues += "Missing metadata $KEY_SAMPLE_RATE (the model's audio rate)."
            sampleRate !in 8000..96000 -> issues += "Sample rate $sampleRate is outside 8-96 kHz."
        }

        val fixedLength = input.shape.lastOrNull()?.takeIf { it > 0 }?.toInt()
        val context = meta[KEY_CONTEXT]?.toIntOrNull() ?: 0
        if (context < 0) issues += "Context must be >= 0."
        var chunk = meta[KEY_CHUNK]?.toIntOrNull()
        if (chunk == null) {
            chunk = when {
                fixedLength != null -> fixedLength - context
                sampleRate != null -> (sampleRate / 10).also {
                    warnings += "No $KEY_CHUNK; defaulting to 100 ms ($it samples)."
                }
                else -> null
            }
        }
        if (chunk != null && chunk <= 0) issues += "Chunk must be positive."
        if (fixedLength != null && chunk != null && fixedLength != chunk + context) {
            issues += "Fixed input length $fixedLength must equal context ($context) + chunk ($chunk)."
        }
        val outLength = output.shape.lastOrNull()?.takeIf { it > 0 }?.toInt()
        if (outLength != null && chunk != null && outLength != chunk && outLength != chunk + context) {
            issues += "Output length $outLength must equal chunk ($chunk) or context + chunk (${chunk + context})."
        }
        if (sampleRate != null && chunk != null && chunk > 0) {
            val ms = chunk * 1000.0 / sampleRate
            if (ms > 500) warnings += "Chunk is ${"%.0f".format(ms)} ms: expect at least that much extra latency."
            if (ms < 10) warnings += "Chunk is ${"%.1f".format(ms)} ms: per-call overhead may exceed real time."
        }
        if (owner != null && !consent) {
            warnings += "Model declares voice owner '$owner' without $KEY_VOICE_CONSENT; you must confirm permission."
        }

        if (issues.isNotEmpty() || sampleRate == null || chunk == null) {
            return Analysis(
                report(
                    if (contract == CONTRACT_V1) ModelFamily.STREAMING_V1 else ModelFamily.UNKNOWN,
                    Compatibility.UNSUPPORTED,
                    "Not a valid stream-v1 model: ${issues.firstOrNull() ?: "incomplete metadata"}",
                    issues, warnings, sampleRate, chunk, context,
                ),
                null,
            )
        }
        val spec = StreamingSpec(
            inputName = input.name, inputRank = input.shape.size, outputName = output.name,
            sampleRate = sampleRate, chunkFrames = chunk, contextFrames = context, fixedInputLength = fixedLength,
        )
        return Analysis(
            report(
                ModelFamily.STREAMING_V1, Compatibility.COMPATIBLE,
                "Streaming model, ${sampleRate / 1000.0} kHz, ${"%.0f".format(spec.chunkDurationMs)} ms chunks" +
                    if (context > 0) " + ${context * 1000 / sampleRate} ms context." else ".",
                emptyList(), warnings, sampleRate, chunk, context,
            ),
            spec,
        )
    }
}
