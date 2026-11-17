package com.voiceshift.models

import com.voiceshift.dsp.VoiceSettings
import java.io.File
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable

/**
 * Everything the user configures outside presets. Enum-like values are stored by name so this
 * module stays independent of the Android audio layer.
 */
@Serializable
data class AppSettings(
    val activePresetId: String = BuiltInPresets.DEFAULT.id,
    /** Live slider values (may differ from the active preset until saved). */
    val voice: VoiceSettings = BuiltInPresets.DEFAULT.settings,
    val engineMode: String = "DSP",
    val bypass: Boolean = false,
    val monitorMuted: Boolean = false,
    val inputDeviceId: Int = 0,
    val outputDeviceId: Int = 0,
    val quality: String = "QUALITY",
    val micMode: String = "PERFORMANCE",
    val exclusiveAudio: Boolean = true,
    val activeModelId: String? = null,
    val keepScreenOn: Boolean = true,
    val networkHost: String = "",
    val networkPort: Int = 50_555,
    val testToneLevelDb: Float = -18f,
    val testToneFrequencyHz: Float = 1000f,
    val onboardingComplete: Boolean = false,
    val validation: List<ValidationEntry> = emptyList(),
)

/**
 * A manual hardware check recorded by the user (Quest / Roblox procedure). Hardware results are
 * only ever set by a person who ran the test; the app never marks them passed on its own.
 */
@Serializable
data class ValidationEntry(
    val stepId: String,
    val result: ValidationResult,
    val note: String = "",
    val timestamp: Long = 0,
)

@Serializable
enum class ValidationResult { NOT_RUN, PASSED, FAILED, NOT_APPLICABLE }

class SettingsRepository(file: File, private val clock: () -> Long = System::currentTimeMillis) {
    private val store = JsonFileStore(file, AppSettings.serializer(), AppSettings(), clock)

    val settings: StateFlow<AppSettings> = store.value

    val recoveredFromCorruption: Boolean get() = store.recoveredFromCorruption

    suspend fun update(transform: (AppSettings) -> AppSettings): AppSettings =
        store.update { transform(it).let { s -> s.copy(voice = s.voice.clamped()) } }

    suspend fun recordValidation(stepId: String, result: ValidationResult, note: String = "") {
        update { s ->
            val others = s.validation.filterNot { it.stepId == stepId }
            s.copy(validation = others + ValidationEntry(stepId, result, note.take(500), clock()))
        }
    }
}
