package com.voiceshift.models

import com.voiceshift.dsp.VoiceSettings
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StoresTest {

    private val dir: File = Files.createTempDirectory("vs-stores").toFile()

    @Test
    fun jsonStorePersistsAtomically() = runTest {
        val file = File(dir, "list.json")
        val store = JsonFileStore(file, ListSerializer(String.serializer()), emptyList())
        store.update { it + "a" }
        store.update { it + "b" }
        assertFalse(File(dir, "list.json.tmp").exists())
        val reopened = JsonFileStore(file, ListSerializer(String.serializer()), emptyList())
        assertEquals(listOf("a", "b"), reopened.value.value)
    }

    @Test
    fun corruptFileIsMovedAsideAndDefaultsUsed() {
        val file = File(dir, "settings.json")
        file.writeText("{ this is not json")
        val repo = SettingsRepository(file, clock = { 42L })
        assertTrue(repo.recoveredFromCorruption)
        assertEquals(AppSettings(), repo.settings.value)
        assertTrue(File(dir, "settings.json.corrupt-42").exists())
    }

    @Test
    fun settingsClampVoiceAndRecordValidation() = runTest {
        val repo = SettingsRepository(File(dir, "s.json"), clock = { 1000L })
        repo.update { it.copy(voice = VoiceSettings(pitchSemitones = 30f)) }
        assertEquals(12f, repo.settings.value.voice.pitchSemitones, 0f)
        repo.recordValidation("quest.recognized", ValidationResult.PASSED, "Shows as USB mic")
        repo.recordValidation("quest.recognized", ValidationResult.FAILED, "Retest")
        val entries = repo.settings.value.validation
        assertEquals(1, entries.size)
        assertEquals(ValidationResult.FAILED, entries.single().result)
        assertEquals(1000L, entries.single().timestamp)
        // Reload from disk.
        assertEquals(entries, SettingsRepository(File(dir, "s.json")).settings.value.validation)
    }

    @Test
    fun presetsCrud() = runTest {
        var n = 0
        val repo = PresetRepository(File(dir, "presets.json"), clock = { 5L }, newId = { "user.${++n}" })
        val initial = repo.presets.first()
        assertEquals(BuiltInPresets.ALL, initial)
        val saved = repo.save("  My voice ", VoiceSettings(pitchSemitones = 6f))
        assertEquals("My voice", saved.name)
        assertFalse(saved.builtIn)
        assertEquals(BuiltInPresets.ALL.size + 1, repo.presets.first().size)
        repo.update(saved.id, VoiceSettings(pitchSemitones = 99f))
        assertEquals(12f, repo.find(saved.id)!!.settings.pitchSemitones, 0f)
        repo.rename(saved.id, "Renamed")
        assertEquals("Renamed", repo.find(saved.id)!!.name)
        assertFalse(repo.delete(BuiltInPresets.SOFT.id))  // built-ins are immutable
        assertTrue(repo.delete(saved.id))
        assertNull(repo.find(saved.id))
    }

    @Test(expected = IllegalArgumentException::class)
    fun emptyPresetNameRejected() = runTest {
        PresetRepository(File(dir, "p.json")).save("   ", VoiceSettings())
    }

    @Test
    fun detachModelFallsBackToDsp() = runTest {
        val repo = PresetRepository(File(dir, "p2.json"))
        val p = repo.save("Neural", VoiceSettings(), PresetEngine.NEURAL, modelId = "m1")
        repo.detachModel("m1")
        val after = repo.find(p.id)!!
        assertEquals(PresetEngine.DSP, after.engine)
        assertNull(after.modelId)
    }

    @Test
    fun builtInPresetsAreValidAndFeminine() {
        for (p in BuiltInPresets.ALL) {
            assertEquals("${p.name} values must already be in range", p.settings, p.settings.clamped())
            assertTrue(p.builtIn)
        }
        for (p in BuiltInPresets.ALL - BuiltInPresets.NATURAL) {
            assertTrue("${p.name} raises pitch", p.settings.pitchSemitones in 3f..8f)
            assertTrue("${p.name} raises formants moderately", p.settings.formantSemitones in 0.5f..3.5f)
        }
        assertEquals(BuiltInPresets.ALL.size, BuiltInPresets.ALL.map { it.id }.toSet().size)
    }
}
