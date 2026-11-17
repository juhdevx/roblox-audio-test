package com.voiceshift.models

import com.voiceshift.dsp.VoiceSettings
import java.io.File
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** Which engine a preset is designed for. */
@Serializable
enum class PresetEngine { DSP, NEURAL }

@Serializable
data class VoicePreset(
    val id: String,
    val name: String,
    val description: String = "",
    val settings: VoiceSettings = VoiceSettings(),
    val engine: PresetEngine = PresetEngine.DSP,
    /** Neural presets reference a registered model by id. */
    val modelId: String? = null,
    val builtIn: Boolean = false,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
)

/**
 * Built-in feminine presets for the DSP engine. They are generic parameter sets (pitch, formant,
 * EQ, dynamics); none of them imitates a real person.
 *
 * Starting points come from voice-feminisation practice: raise f0 by 4-7 semitones, raise formants
 * by roughly 10-20 % (2-3 semitones), thin the low-mid "chest" region and add presence/air. Smaller
 * shifts sound more natural, so the defaults stay conservative.
 */
object BuiltInPresets {
    val NATURAL = VoicePreset(
        id = "builtin.natural",
        name = "Natural (no change)",
        description = "Clean-up only: low cut and limiter. Use to compare with your own voice.",
        settings = VoiceSettings(lowCutHz = 80f),
        builtIn = true,
    )
    val SOFT = VoicePreset(
        id = "builtin.soft-feminine",
        name = "Soft feminine",
        description = "+5 st pitch, +2 st formants, gentle brightness. A balanced, natural starting point.",
        settings = VoiceSettings(
            pitchSemitones = 5f, formantSemitones = 2f, noiseReduction = 0.3f, gateThresholdDb = -60f,
            agcEnabled = true, agcTargetDb = -20f, lowCutHz = 120f, bodyDb = -3f, presenceDb = 2f, airDb = 3f,
            compression = 0.3f, breathiness = 0.15f,
        ),
        builtIn = true,
    )
    val BRIGHT = VoicePreset(
        id = "builtin.bright-feminine",
        name = "Bright feminine",
        description = "+7 st pitch, +3 st formants. Higher and lighter; works best with lower source voices.",
        settings = VoiceSettings(
            pitchSemitones = 7f, formantSemitones = 3f, noiseReduction = 0.3f, gateThresholdDb = -60f,
            agcEnabled = true, agcTargetDb = -20f, lowCutHz = 140f, bodyDb = -4f, presenceDb = 3f, airDb = 4f,
            compression = 0.35f, breathiness = 0.1f,
        ),
        builtIn = true,
    )
    val WARM = VoicePreset(
        id = "builtin.warm-feminine",
        name = "Warm feminine",
        description = "+4 st pitch, +1.5 st formants, more breath. Lower and warmer.",
        settings = VoiceSettings(
            pitchSemitones = 4f, formantSemitones = 1.5f, noiseReduction = 0.25f, gateThresholdDb = -60f,
            agcEnabled = true, agcTargetDb = -20f, lowCutHz = 100f, bodyDb = -1.5f, presenceDb = 1f, airDb = 2f,
            compression = 0.3f, breathiness = 0.2f,
        ),
        builtIn = true,
    )
    val ANDROGYNOUS = VoicePreset(
        id = "builtin.androgynous",
        name = "Subtle / androgynous",
        description = "+3 st pitch, +1 st formants. Minimal processing, maximum intelligibility.",
        settings = VoiceSettings(
            pitchSemitones = 3f, formantSemitones = 1f, noiseReduction = 0.2f, gateThresholdDb = -60f,
            agcEnabled = true, lowCutHz = 90f, bodyDb = -1f, presenceDb = 1f, airDb = 1f, compression = 0.25f,
        ),
        builtIn = true,
    )

    val ALL: List<VoicePreset> = listOf(SOFT, BRIGHT, WARM, ANDROGYNOUS, NATURAL)
    val DEFAULT: VoicePreset = SOFT
}

/** User presets persisted as JSON; built-ins are always listed first and cannot be modified. */
class PresetRepository(
    file: File,
    private val clock: () -> Long = System::currentTimeMillis,
    private val newId: () -> String = { "user." + UUID.randomUUID().toString() },
) {
    private val store = JsonFileStore(file, ListSerializer(VoicePreset.serializer()), emptyList(), clock)

    val presets: Flow<List<VoicePreset>> = store.value.map { BuiltInPresets.ALL + it.sortedBy { p -> p.name.lowercase() } }

    fun snapshot(): List<VoicePreset> = BuiltInPresets.ALL + store.value.value

    fun find(id: String): VoicePreset? = snapshot().firstOrNull { it.id == id }

    suspend fun save(
        name: String,
        settings: VoiceSettings,
        engine: PresetEngine = PresetEngine.DSP,
        modelId: String? = null,
        description: String = "",
    ): VoicePreset {
        val clean = name.trim()
        require(clean.isNotEmpty()) { "Preset name must not be empty" }
        require(clean.length <= 60) { "Preset name is too long" }
        val now = clock()
        val preset = VoicePreset(
            id = newId(), name = clean, description = description, settings = settings.clamped(),
            engine = engine, modelId = modelId, builtIn = false, createdAt = now, updatedAt = now,
        )
        store.update { it + preset }
        return preset
    }

    suspend fun update(id: String, settings: VoiceSettings): VoicePreset? {
        var updated: VoicePreset? = null
        store.update { list ->
            list.map { p ->
                if (p.id == id) p.copy(settings = settings.clamped(), updatedAt = clock()).also { updated = it } else p
            }
        }
        return updated
    }

    suspend fun rename(id: String, newName: String) {
        val clean = newName.trim()
        require(clean.isNotEmpty()) { "Preset name must not be empty" }
        store.update { list -> list.map { if (it.id == id) it.copy(name = clean, updatedAt = clock()) else it } }
    }

    /** Deletes a user preset. Built-ins are ignored. Returns true when something was removed. */
    suspend fun delete(id: String): Boolean {
        var removed = false
        store.update { list -> list.filterNot { (it.id == id).also { hit -> if (hit) removed = true } } }
        return removed
    }

    /** Presets that reference a model which is being deleted fall back to DSP. */
    suspend fun detachModel(modelId: String) {
        store.update { list ->
            list.map { if (it.modelId == modelId) it.copy(modelId = null, engine = PresetEngine.DSP) else it }
        }
    }
}
