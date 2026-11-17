package com.voiceshift.inference

import com.voiceshift.models.Compatibility
import com.voiceshift.models.ModelFamily
import com.voiceshift.models.TensorDescription
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CompatibilityAnalyzerTest {

    private fun t(name: String, vararg shape: Long, type: String = "FLOAT") = TensorDescription(name, type, shape.toList())

    private val streamMeta = mapOf(
        "voiceshift.contract" to "stream-v1",
        "voiceshift.sample_rate" to "24000",
        "voiceshift.chunk_samples" to "2400",
    )

    @Test
    fun dynamicStreamingModelIsCompatible() {
        val a = CompatibilityAnalyzer.analyze(ModelIntrospection(listOf(t("x", 1, -1)), listOf(t("y", 1, -1)), streamMeta))
        assertEquals(Compatibility.COMPATIBLE, a.report.compatibility)
        val spec = a.spec!!
        assertEquals(24000, spec.sampleRate)
        assertEquals(2400, spec.chunkFrames)
        assertEquals(100.0, spec.chunkDurationMs, 1e-9)
        assertTrue(spec.inputShape().contentEquals(longArrayOf(1, 2400)))
    }

    @Test
    fun fixedLengthWithContextDerivesChunk() {
        val meta = mapOf("voiceshift.contract" to "stream-v1", "voiceshift.sample_rate" to "16000", "voiceshift.context_samples" to "400")
        val a = CompatibilityAnalyzer.analyze(ModelIntrospection(listOf(t("w", 1, 1, 2000)), listOf(t("o", 1, 1, 2000)), meta))
        assertEquals(Compatibility.COMPATIBLE, a.report.compatibility)
        val spec = requireNotNull(a.spec)
        assertEquals(1600, spec.chunkFrames)
        val out = FloatArray(2000) { it.toFloat() }
        assertEquals(400f, spec.selectChunk(out)!!.first(), 0f)
        assertNull(spec.selectChunk(FloatArray(10)))
    }

    @Test
    fun missingSampleRateIsUnsupported() {
        val a = CompatibilityAnalyzer.analyze(
            ModelIntrospection(listOf(t("x", 1, -1)), listOf(t("y", 1, -1)), mapOf("voiceshift.contract" to "stream-v1")),
        )
        assertEquals(Compatibility.UNSUPPORTED, a.report.compatibility)
        assertTrue(a.report.issues.any { it.contains("sample_rate") })
        assertNull(a.spec)
    }

    @Test
    fun noContractMetadataIsUnsupportedEvenIfShapesFit() {
        val a = CompatibilityAnalyzer.analyze(ModelIntrospection(listOf(t("x", 1, -1)), listOf(t("y", 1, -1))))
        assertEquals(Compatibility.UNSUPPORTED, a.report.compatibility)
        assertEquals(ModelFamily.UNKNOWN, a.report.family)
    }

    @Test
    fun rvcSignatureIsRecognisedAndRefused() {
        val inputs = listOf(
            t("phone", 1, -1, 768), t("phone_lengths", 1, type = "INT64"), t("pitch", 1, -1, type = "INT64"),
            t("pitchf", 1, -1), t("ds", 1, type = "INT64"), t("rnd", 1, 192, -1),
        )
        val a = CompatibilityAnalyzer.analyze(ModelIntrospection(inputs, listOf(t("audio", 1, 1, -1))))
        assertEquals(ModelFamily.RVC_GENERATOR, a.report.family)
        assertEquals(Compatibility.UNSUPPORTED, a.report.compatibility)
        assertTrue(a.report.summary.contains("RVC"))
    }

    @Test
    fun featureEncoderIsRecognised() {
        val a = CompatibilityAnalyzer.analyze(ModelIntrospection(listOf(t("source", 1, -1)), listOf(t("feats", 1, -1, 768))))
        assertEquals(ModelFamily.FEATURE_ENCODER, a.report.family)
    }

    @Test
    fun badShapesAndTypesAreExplained() {
        val a = CompatibilityAnalyzer.analyze(
            ModelIntrospection(listOf(t("x", 2, 1000, type = "INT16")), listOf(t("y", 1, 999)), streamMeta),
        )
        assertEquals(Compatibility.UNSUPPORTED, a.report.compatibility)
        val text = a.report.issues.joinToString()
        assertTrue(text, text.contains("float32"))
        assertTrue(text, text.contains("Leading input dimensions"))
    }

    @Test
    fun declaredOwnerWithoutConsentWarns() {
        val meta = streamMeta + ("voiceshift.voice_owner" to "Jane Example")
        val a = CompatibilityAnalyzer.analyze(ModelIntrospection(listOf(t("x", 1, -1)), listOf(t("y", 1, -1)), meta))
        assertEquals("Jane Example", a.report.declaredVoiceOwner)
        assertTrue(a.report.warnings.any { it.contains("permission") })
        val consented = CompatibilityAnalyzer.analyze(
            ModelIntrospection(listOf(t("x", 1, -1)), listOf(t("y", 1, -1)), meta + ("voiceshift.voice_owner_consent" to "documented")),
        )
        assertTrue(consented.report.declaredConsent)
        assertNotNull(consented.spec)
    }
}
