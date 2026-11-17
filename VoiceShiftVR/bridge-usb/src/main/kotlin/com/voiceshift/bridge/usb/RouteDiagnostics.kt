package com.voiceshift.bridge.usb

import com.voiceshift.audio.AudioDevice
import com.voiceshift.audio.DeviceKind
import com.voiceshift.audio.EngineStats

/** A USB device as seen by UsbManager (host mode). */
data class UsbDeviceSummary(
    val deviceName: String,
    val vendorId: Int,
    val productId: Int,
    val productName: String?,
    val manufacturerName: String?,
    val interfaceClasses: List<Int>,
    val audioStreamingInterfaces: Int,
) {
    val isAudioClass: Boolean get() = USB_CLASS_AUDIO in interfaceClasses
    val label: String
        get() = listOfNotNull(manufacturerName, productName).joinToString(" ").ifBlank {
            "USB %04x:%04x".format(vendorId, productId)
        }

    companion object {
        const val USB_CLASS_AUDIO = 1
        const val USB_SUBCLASS_AUDIOSTREAMING = 2
    }
}

enum class CheckStatus { PASS, WARN, FAIL, INFO }

data class RouteCheck(val id: String, val title: String, val status: CheckStatus, val detail: String)

data class RouteReport(val checks: List<RouteCheck>) {
    val worst: CheckStatus
        get() = when {
            checks.any { it.status == CheckStatus.FAIL } -> CheckStatus.FAIL
            checks.any { it.status == CheckStatus.WARN } -> CheckStatus.WARN
            else -> CheckStatus.PASS
        }
}

/**
 * Route A (phone -> cable/interface -> Quest USB microphone input) checks that can be answered on
 * the phone. They establish that the phone is sending a clean signal into an external path; they
 * cannot observe whether the Quest or Roblox receives it — those steps are verified on the headset
 * (app-quest-experimental probe) and in game by the user. See docs/QUEST_BRIDGE.md.
 */
object RouteDiagnostics {

    private val usbKinds = setOf(DeviceKind.USB_DEVICE, DeviceKind.USB_HEADSET, DeviceKind.USB_ACCESSORY)
    private val analogKinds = setOf(DeviceKind.WIRED_HEADSET, DeviceKind.WIRED_HEADPHONES, DeviceKind.LINE_ANALOG)

    fun evaluate(
        audioDevices: List<AudioDevice>,
        usbDevices: List<UsbDeviceSummary>,
        usbHostSupported: Boolean,
        selectedOutputId: Int,
        stats: EngineStats?,
        testToneActive: Boolean,
    ): RouteReport {
        val checks = mutableListOf<RouteCheck>()
        val outputs = audioDevices.filter { it.isOutput }
        val usbOutputs = outputs.filter { it.kind in usbKinds }
        val analogOutputs = outputs.filter { it.kind in analogKinds }
        val usbAudio = usbDevices.filter { it.isAudioClass }

        checks += RouteCheck(
            "not-a-microphone", "A USB-C cable alone is not a microphone", CheckStatus.INFO,
            "Plugging this phone straight into the Quest does not make it a USB microphone. The Quest needs a " +
                "USB audio *input* device; feed that device from this phone's output (see Quest bridge guide).",
        )

        checks += if (usbHostSupported) {
            RouteCheck("usb-host", "USB host mode", CheckStatus.PASS, "Phone advertises USB host (OTG) support.")
        } else {
            RouteCheck(
                "usb-host", "USB host mode", CheckStatus.WARN,
                "Phone does not advertise USB host support; USB audio interfaces may not work. A 3.5 mm or USB-C " +
                    "headphone output can be used instead.",
            )
        }

        checks += when {
            usbAudio.isNotEmpty() -> RouteCheck(
                "usb-audio-attached", "USB audio interface", CheckStatus.PASS,
                usbAudio.joinToString { "${it.label} (${it.audioStreamingInterfaces} streaming interfaces)" },
            )
            usbDevices.isNotEmpty() -> RouteCheck(
                "usb-audio-attached", "USB audio interface", CheckStatus.WARN,
                "USB device(s) attached but none is USB Audio Class: ${usbDevices.joinToString { it.label }}.",
            )
            else -> RouteCheck("usb-audio-attached", "USB audio interface", CheckStatus.INFO, "No USB device attached.")
        }

        checks += when {
            usbOutputs.isNotEmpty() -> RouteCheck(
                "usb-output-endpoint", "USB audio output", CheckStatus.PASS,
                "Android exposes: ${usbOutputs.joinToString { it.label }}.",
            )
            usbAudio.isNotEmpty() -> RouteCheck(
                "usb-output-endpoint", "USB audio output", CheckStatus.FAIL,
                "A USB audio interface is attached but Android lists no USB output for it. Try another cable/adapter, " +
                    "or check whether the interface needs external power.",
            )
            else -> RouteCheck("usb-output-endpoint", "USB audio output", CheckStatus.INFO, "No USB audio output present.")
        }

        if (analogOutputs.isNotEmpty()) {
            checks += RouteCheck(
                "analog-output", "Wired analog output", CheckStatus.PASS,
                "${analogOutputs.joinToString { it.label }} — usable as the send to an external input with an attenuator.",
            )
        }

        val selected = outputs.firstOrNull { it.id == selectedOutputId }
        val defaultRoutesExternally = selectedOutputId == 0 && (usbOutputs.isNotEmpty() || analogOutputs.isNotEmpty())
        checks += when {
            selected != null && selected.isExternalWired -> RouteCheck(
                "selected-output", "Engine output routed to cable", CheckStatus.PASS, "Output: ${selected.label}.",
            )
            defaultRoutesExternally -> RouteCheck(
                "selected-output", "Engine output routed to cable", CheckStatus.WARN,
                "Output is 'System default'. Android usually prefers the wired/USB device, but select it explicitly " +
                    "so routing cannot silently move to the speaker.",
            )
            else -> RouteCheck(
                "selected-output", "Engine output routed to cable", CheckStatus.FAIL,
                "The processed voice is playing on ${selected?.label ?: "the phone"}, not into an external cable.",
            )
        }

        if (selected != null && selected.sampleRates.isNotEmpty()) {
            checks += if (48000 in selected.sampleRates) {
                RouteCheck("sample-rate", "48 kHz support", CheckStatus.PASS, "${selected.label} supports 48 kHz.")
            } else {
                RouteCheck(
                    "sample-rate", "48 kHz support", CheckStatus.WARN,
                    "${selected.label} reports ${selected.sampleRates}; audio will be resampled (slightly more latency).",
                )
            }
        }

        if (stats != null && testToneActive) {
            checks += when {
                stats.outputRmsDb < -60f -> RouteCheck(
                    "signal-level", "Test tone leaving the phone", CheckStatus.FAIL,
                    "Output is silent (${"%.0f".format(stats.outputRmsDb)} dBFS). Check mute and output gain.",
                )
                stats.outputHot -> RouteCheck(
                    "signal-level", "Test tone leaving the phone", CheckStatus.WARN,
                    "Output is near full scale (${"%.1f".format(stats.outputPeakDb)} dBFS peak). Lower the tone level " +
                        "or output gain to avoid clipping a microphone input.",
                )
                else -> RouteCheck(
                    "signal-level", "Test tone leaving the phone", CheckStatus.PASS,
                    "Tone at ${"%.1f".format(stats.outputRmsDb)} dBFS RMS. Confirm it on the Quest probe.",
                )
            }
        }
        return RouteReport(checks)
    }
}
