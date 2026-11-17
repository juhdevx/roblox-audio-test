package com.voiceshift.bridge.usb

import com.voiceshift.audio.AudioDevice
import com.voiceshift.audio.DeviceKind
import com.voiceshift.audio.EngineStats
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteDiagnosticsTest {

    private val mic = AudioDevice(1, "", DeviceKind.BUILTIN_MIC, true, false)
    private val speaker = AudioDevice(2, "", DeviceKind.BUILTIN_SPEAKER, false, true)
    private val usbOut = AudioDevice(10, "UAC Dongle", DeviceKind.USB_DEVICE, false, true, sampleRates = listOf(44100, 48000))
    private val usbOut44 = usbOut.copy(id = 11, sampleRates = listOf(44100))
    private val usbAudio = UsbDeviceSummary("/dev/bus/usb/001/002", 0x1234, 0x5678, "Dongle", "Acme", listOf(1, 3), 2)
    private val usbHid = UsbDeviceSummary("/dev/bus/usb/001/003", 1, 2, "Keyboard", null, listOf(3), 0)

    private fun status(report: RouteReport, id: String) = report.checks.first { it.id == id }.status

    @Test
    fun fullyConfiguredUsbRoutePasses() {
        val stats = EngineStats(outputRmsDb = -21f, outputPeakDb = -18f)
        val r = RouteDiagnostics.evaluate(listOf(mic, speaker, usbOut), listOf(usbAudio), true, usbOut.id, stats, true)
        assertEquals(CheckStatus.PASS, status(r, "usb-output-endpoint"))
        assertEquals(CheckStatus.PASS, status(r, "selected-output"))
        assertEquals(CheckStatus.PASS, status(r, "sample-rate"))
        assertEquals(CheckStatus.PASS, status(r, "signal-level"))
        assertEquals(CheckStatus.INFO, status(r, "not-a-microphone"))
        assertEquals(CheckStatus.PASS, r.worst)
    }

    @Test
    fun speakerOutputFails() {
        val r = RouteDiagnostics.evaluate(listOf(mic, speaker), emptyList(), true, speaker.id, null, false)
        assertEquals(CheckStatus.FAIL, status(r, "selected-output"))
        assertEquals(CheckStatus.FAIL, r.worst)
    }

    @Test
    fun usbAudioWithoutAndroidEndpointFails() {
        val r = RouteDiagnostics.evaluate(listOf(mic, speaker), listOf(usbAudio), true, 0, null, false)
        assertEquals(CheckStatus.FAIL, status(r, "usb-output-endpoint"))
    }

    @Test
    fun nonAudioUsbDeviceWarns() {
        val r = RouteDiagnostics.evaluate(listOf(mic, speaker), listOf(usbHid), true, 0, null, false)
        assertEquals(CheckStatus.WARN, status(r, "usb-audio-attached"))
    }

    @Test
    fun defaultOutputWithExternalDeviceWarns() {
        val r = RouteDiagnostics.evaluate(listOf(mic, speaker, usbOut), listOf(usbAudio), true, 0, null, false)
        assertEquals(CheckStatus.WARN, status(r, "selected-output"))
    }

    @Test
    fun missing48kAndHotOrSilentSignalAreFlagged() {
        val hot = EngineStats(outputRmsDb = -3f, outputPeakDb = -0.5f)
        val r = RouteDiagnostics.evaluate(listOf(usbOut44), listOf(usbAudio), false, usbOut44.id, hot, true)
        assertEquals(CheckStatus.WARN, status(r, "sample-rate"))
        assertEquals(CheckStatus.WARN, status(r, "signal-level"))
        assertEquals(CheckStatus.WARN, status(r, "usb-host"))
        val silent = RouteDiagnostics.evaluate(listOf(usbOut), listOf(usbAudio), true, usbOut.id, EngineStats(), true)
        assertEquals(CheckStatus.FAIL, status(silent, "signal-level"))
    }

    @Test
    fun validationProcedureSeparatesStages() {
        val stages = QuestValidationProcedure.steps.map { it.stage }.toSet()
        assertEquals(QuestValidationProcedure.Stage.entries.toSet(), stages)
        assertEquals(QuestValidationProcedure.steps.size, QuestValidationProcedure.steps.map { it.id }.toSet().size)
        assertTrue(QuestValidationProcedure.steps.last().stage == QuestValidationProcedure.Stage.ROBLOX_IN_GAME)
    }
}
