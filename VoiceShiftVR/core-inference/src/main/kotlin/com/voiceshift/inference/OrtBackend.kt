package com.voiceshift.inference

import ai.onnxruntime.NodeInfo
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import com.voiceshift.models.Compatibility
import com.voiceshift.models.ModelFamily
import com.voiceshift.models.ModelValidator
import com.voiceshift.models.TensorDescription
import com.voiceshift.models.ValidationReport
import java.io.File
import java.nio.FloatBuffer

/** One forward pass over a window of audio. Implementations must be used from a single thread. */
interface InferenceSession : AutoCloseable {
    val spec: StreamingSpec
    fun run(window: FloatArray): FloatArray
}

/** Shared ONNX Runtime environment (ORT requires a single environment per process). */
object Ort {
    val environment: OrtEnvironment by lazy { OrtEnvironment.getEnvironment() }

    fun sessionOptions(threads: Int): OrtSession.SessionOptions = OrtSession.SessionOptions().apply {
        setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
        setIntraOpNumThreads(threads)
    }

    fun introspect(session: OrtSession): ModelIntrospection {
        fun describe(map: Map<String, NodeInfo>) = map.map { (name, node) ->
            val info = node.info
            if (info is TensorInfo) {
                TensorDescription(name, info.type.name, info.shape.toList())
            } else {
                TensorDescription(name, info.javaClass.simpleName, emptyList())
            }
        }
        val metadata = session.metadata
        return ModelIntrospection(
            inputs = describe(session.inputInfo),
            outputs = describe(session.outputInfo),
            customMetadata = metadata.customMetadata,
            producer = metadata.producerName.orEmpty(),
            graphName = metadata.graphName.orEmpty(),
            description = metadata.description.orEmpty(),
        )
    }
}

/** ONNX Runtime implementation of [InferenceSession] for stream-v1 models. */
class OrtInferenceSession private constructor(
    private val session: OrtSession,
    override val spec: StreamingSpec,
) : InferenceSession {

    private val shape = spec.inputShape()

    override fun run(window: FloatArray): FloatArray {
        require(window.size == spec.windowFrames) { "window must be ${spec.windowFrames} samples" }
        OnnxTensor.createTensor(Ort.environment, FloatBuffer.wrap(window), shape).use { tensor ->
            session.run(mapOf(spec.inputName to tensor)).use { result ->
                val value = result.get(0) as OnnxTensor
                val buffer = value.floatBuffer
                val out = FloatArray(buffer.remaining())
                buffer.get(out)
                return spec.selectChunk(out)
                    ?: throw IllegalStateException("Model returned ${out.size} samples; expected ${spec.chunkFrames} or ${spec.windowFrames}")
            }
        }
    }

    override fun close() = session.close()

    companion object {
        /** Opens [file]; fails with a readable message if it is not a compatible stream-v1 model. */
        fun open(file: File, threads: Int = 2): OrtInferenceSession {
            val session = Ort.environment.createSession(file.absolutePath, Ort.sessionOptions(threads))
            try {
                val analysis = CompatibilityAnalyzer.analyze(Ort.introspect(session))
                val spec = analysis.spec ?: throw IllegalArgumentException(analysis.report.summary)
                return OrtInferenceSession(session, spec)
            } catch (e: Exception) {
                session.close()
                throw e
            }
        }
    }
}

/**
 * [ModelValidator] backed by ONNX Runtime: parses the graph, applies [CompatibilityAnalyzer] and,
 * for compatible models, runs a smoke test (two inferences on silence) to prove the model actually
 * executes, returns finite samples of the right length, and to estimate its real-time factor.
 */
class OnnxModelValidator(private val threads: Int = 2) : ModelValidator {

    override fun validate(file: File): ValidationReport {
        val session = try {
            Ort.environment.createSession(file.absolutePath, Ort.sessionOptions(threads))
        } catch (e: Exception) {
            return ValidationReport(
                ModelFamily.UNKNOWN, Compatibility.INVALID,
                "Not a loadable ONNX model: ${e.message?.lineSequence()?.firstOrNull() ?: e.javaClass.simpleName}",
            )
        }
        session.use {
            val analysis = CompatibilityAnalyzer.analyze(Ort.introspect(session))
            val spec = analysis.spec ?: return analysis.report
            return try {
                val window = FloatArray(spec.windowFrames)
                val shape = spec.inputShape()
                var elapsedNs = 0L
                repeat(2) { iteration ->
                    val start = System.nanoTime()
                    val out = OnnxTensor.createTensor(Ort.environment, FloatBuffer.wrap(window), shape).use { tensor ->
                        session.run(mapOf(spec.inputName to tensor)).use { result ->
                            val buf = (result.get(0) as OnnxTensor).floatBuffer
                            FloatArray(buf.remaining()).also { buf.get(it) }
                        }
                    }
                    if (iteration == 1) elapsedNs = System.nanoTime() - start  // ignore warm-up
                    val chunk = spec.selectChunk(out)
                        ?: throw IllegalStateException("returned ${out.size} samples (expected ${spec.chunkFrames} or ${spec.windowFrames})")
                    if (chunk.any { !it.isFinite() }) throw IllegalStateException("returned NaN/Inf for silent input")
                }
                val rtf = elapsedNs / 1e6 / spec.chunkDurationMs
                val warnings = analysis.report.warnings.toMutableList()
                if (rtf > 0.8) warnings += "Smoke test: inference took ${"%.0f".format(rtf * 100)}% of real time; it may not keep up on this device."
                analysis.report.copy(smokeTestRealtimeFactor = rtf, warnings = warnings)
            } catch (e: Exception) {
                analysis.report.copy(
                    compatibility = Compatibility.UNSUPPORTED,
                    summary = "Model failed its smoke test: ${e.message}",
                    issues = analysis.report.issues + "Smoke test failed: ${e.message}",
                )
            }
        }
    }
}
