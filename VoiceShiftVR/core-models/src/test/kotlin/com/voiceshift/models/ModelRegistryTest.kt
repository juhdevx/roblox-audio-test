package com.voiceshift.models

import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelRegistryTest {

    private val root: File = Files.createTempDirectory("vs-models").toFile()
    private var ids = 0
    private var nextReport = compatibleReport()

    private val registry = ModelRegistry(
        root = root,
        validator = { nextReport },
        clock = { 1234L },
        newId = { "id${++ids}" },
        maxBytes = 1024,
    )

    private fun bytes(content: String) = ByteArrayInputStream(content.toByteArray())
    private val ownVoice = ConsentDeclaration(isCustomVoice = false, consentConfirmed = false)

    @Test
    fun importCopiesValidatesAndIndexes() = runTest {
        val result = registry.import(bytes("model-bytes"), "my_model.onnx", ownVoice) as ImportResult.Imported
        val record = result.record
        assertEquals("my_model", record.displayName)
        assertEquals(11L, record.sizeBytes)
        assertEquals(64, record.sha256.length)
        assertTrue(registry.fileFor(record).readText() == "model-bytes")
        assertEquals(listOf(record), registry.records.value)
        // Index survives a restart.
        val reopened = ModelRegistry(root, { nextReport })
        assertEquals(listOf(record), reopened.records.value)
        // No staging leftovers.
        assertTrue(root.listFiles()!!.none { it.name.endsWith(".tmp") })
    }

    @Test
    fun duplicateIsDetectedBySha() = runTest {
        val first = registry.import(bytes("same"), "a.onnx", ownVoice) as ImportResult.Imported
        val second = registry.import(bytes("same"), "b.onnx", ownVoice)
        assertEquals(ImportResult.Duplicate(first.record), second)
        assertEquals(1, registry.records.value.size)
    }

    @Test
    fun reimportingSameNameIncrementsRevision() = runTest {
        registry.import(bytes("v1"), "voice.onnx", ownVoice)
        val second = registry.import(bytes("v2"), "voice.onnx", ownVoice) as ImportResult.Imported
        assertEquals(2, second.record.revision)
    }

    @Test
    fun customVoiceWithoutConsentIsRejected() = runTest {
        val result = registry.import(bytes("x"), "someone.onnx", ConsentDeclaration(isCustomVoice = true, consentConfirmed = false))
        assertTrue(result is ImportResult.Rejected)
        assertTrue(registry.records.value.isEmpty())
    }

    @Test
    fun declaredVoiceOwnerRequiresConsent() = runTest {
        nextReport = compatibleReport().copy(declaredVoiceOwner = "A. Speaker")
        val rejected = registry.import(bytes("x"), "m.onnx", ownVoice)
        assertTrue(rejected is ImportResult.Rejected)
        val accepted = registry.import(bytes("x"), "m.onnx", ConsentDeclaration(true, true, "Signed release on file"))
        assertTrue(accepted is ImportResult.Imported)
    }

    @Test
    fun oversizedAndEmptyAndInvalidFilesAreRejected() = runTest {
        assertTrue(registry.import(bytes("x".repeat(2000)), "big.onnx", ownVoice) is ImportResult.Rejected)
        assertTrue(registry.import(bytes(""), "empty.onnx", ownVoice) is ImportResult.Rejected)
        nextReport = ValidationReport(ModelFamily.UNKNOWN, Compatibility.INVALID, "not onnx")
        val invalid = registry.import(bytes("garbage"), "g.onnx", ownVoice) as ImportResult.Rejected
        assertEquals("not onnx", invalid.reason)
        assertTrue(registry.records.value.isEmpty())
        assertTrue(root.listFiles()!!.none { it.name.endsWith(".tmp") })
    }

    @Test
    fun unsupportedModelsAreKeptButNotLoadable() = runTest {
        nextReport = ValidationReport(ModelFamily.RVC_GENERATOR, Compatibility.UNSUPPORTED, "RVC needs encoder")
        val record = (registry.import(bytes("rvc"), "rvc.onnx", ownVoice) as ImportResult.Imported).record
        val decision = LoadPlanner.check(record, budget(available = 8L shl 30))
        assertTrue(decision is LoadDecision.Denied)
    }

    @Test
    fun deleteRemovesFilesAndEntry() = runTest {
        val record = (registry.import(bytes("abc"), "d.onnx", ownVoice) as ImportResult.Imported).record
        assertTrue(registry.delete(record.id))
        assertFalse(File(root, record.id).exists())
        assertTrue(registry.records.value.isEmpty())
        assertFalse(registry.delete(record.id))
    }

    @Test
    fun loadPlannerRespectsMemory() {
        val record = ModelRecord(
            id = "m", displayName = "m", fileName = "model.onnx", sizeBytes = 100L shl 20, sha256 = "",
            importedAt = 0, report = compatibleReport(), consent = ownVoice,
        )
        assertEquals(LoadDecision.Allowed, LoadPlanner.check(record, budget(available = 2L shl 30)))
        assertTrue(LoadPlanner.check(record, budget(available = 300L shl 20)) is LoadDecision.Denied)
        assertTrue(LoadPlanner.check(record, budget(available = 2L shl 30, lowRam = true)) is LoadDecision.Denied)
    }

    private fun budget(available: Long, lowRam: Boolean = false) = object : MemoryBudget {
        override fun availableBytes() = available
        override fun isLowRamDevice() = lowRam
    }

    private fun compatibleReport() = ValidationReport(
        family = ModelFamily.STREAMING_V1,
        compatibility = Compatibility.COMPATIBLE,
        summary = "ok",
        sampleRate = 16000,
        chunkFrames = 1600,
        version = "1.0",
    )
}
