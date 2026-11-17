package com.voiceshift.audio

import kotlinx.coroutines.flow.StateFlow

/** Platform-independent description of an audio endpoint (mirrors android.media.AudioDeviceInfo). */
data class AudioDevice(
    val id: Int,
    val name: String,
    val kind: DeviceKind,
    val isInput: Boolean,
    val isOutput: Boolean,
    val sampleRates: List<Int> = emptyList(),
    val channelCounts: List<Int> = emptyList(),
    val address: String = "",
) {
    val label: String get() = if (name.isBlank() || name == kind.label) kind.label else "$name (${kind.label})"

    /** True for endpoints that can carry audio to another device over a cable. */
    val isExternalWired: Boolean
        get() = kind in setOf(
            DeviceKind.USB_DEVICE, DeviceKind.USB_HEADSET, DeviceKind.USB_ACCESSORY,
            DeviceKind.WIRED_HEADSET, DeviceKind.WIRED_HEADPHONES, DeviceKind.LINE_ANALOG, DeviceKind.LINE_DIGITAL,
        )
}

/** Device types we distinguish. [androidType] is the AudioDeviceInfo.TYPE_* constant. */
enum class DeviceKind(val androidType: Int, val label: String) {
    BUILTIN_MIC(15, "Built-in microphone"),
    BUILTIN_SPEAKER(2, "Phone speaker"),
    BUILTIN_EARPIECE(1, "Earpiece"),
    WIRED_HEADSET(3, "Wired headset"),
    WIRED_HEADPHONES(4, "Wired headphones"),
    LINE_ANALOG(5, "Analog line"),
    LINE_DIGITAL(6, "Digital line"),
    BLUETOOTH_SCO(7, "Bluetooth (call audio)"),
    BLUETOOTH_A2DP(8, "Bluetooth (media)"),
    HDMI(9, "HDMI"),
    USB_DEVICE(11, "USB audio device"),
    USB_ACCESSORY(12, "USB accessory"),
    TELEPHONY(18, "Telephony"),
    USB_HEADSET(22, "USB headset"),
    BLE_HEADSET(26, "Bluetooth LE headset"),
    BLE_SPEAKER(27, "Bluetooth LE speaker"),
    REMOTE_SUBMIX(25, "Remote submix"),
    OTHER(-1, "Other");

    companion object {
        fun fromAndroidType(type: Int): DeviceKind = entries.firstOrNull { it.androidType == type } ?: OTHER
    }
}

/** Source of the current device list; implemented with AudioManager on Android and by fakes in tests. */
interface AudioDeviceSource {
    val devices: StateFlow<List<AudioDevice>>
    fun refresh()
}

/** Pure selection rules shared by the controller and UI. */
object DeviceSelection {
    /** Keeps [requestedId] if that device is still present, otherwise falls back to system default (0). */
    fun resolve(requestedId: Int, available: List<AudioDevice>, wantInput: Boolean): Int {
        if (requestedId == 0) return 0
        val ok = available.any { it.id == requestedId && (if (wantInput) it.isInput else it.isOutput) }
        return if (ok) requestedId else 0
    }

    /**
     * Acoustic feedback risk: monitoring through the phone speaker while recording from the phone's own
     * microphone. [outputId]/[inputId] of 0 mean "system default", which is the speaker/mic when nothing
     * else is attached.
     */
    fun feedbackRisk(inputId: Int, outputId: Int, available: List<AudioDevice>): Boolean {
        val input = available.firstOrNull { it.id == inputId && it.isInput }
        val output = available.firstOrNull { it.id == outputId && it.isOutput }
        val wireless = setOf(DeviceKind.BLUETOOTH_A2DP, DeviceKind.BLUETOOTH_SCO, DeviceKind.BLE_HEADSET, DeviceKind.BLE_SPEAKER)
        val externalOutputPresent = available.any { it.isOutput && (it.isExternalWired || it.kind in wireless) }
        val outputIsSpeaker = output?.kind == DeviceKind.BUILTIN_SPEAKER || (output == null && !externalOutputPresent)
        val inputIsBuiltIn = input?.kind == DeviceKind.BUILTIN_MIC || input == null
        return outputIsSpeaker && inputIsBuiltIn
    }
}
