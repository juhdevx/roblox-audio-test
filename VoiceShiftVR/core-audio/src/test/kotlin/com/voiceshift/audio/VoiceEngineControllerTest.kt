package com.voiceshift.audio

import com.voiceshift.audio.FakeDeviceSource.Companion.HEADPHONES
import com.voiceshift.audio.FakeDeviceSource.Companion.MIC
import com.voiceshift.audio.FakeDeviceSource.Companion.SPEAKER
import com.voiceshift.audio.FakeDeviceSource.Companion.USB_IN
import com.voiceshift.audio.FakeDeviceSource.Companion.USB_OUT
import com.voiceshift.dsp.VoiceParameter
import com.voiceshift.dsp.VoiceSettings
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class VoiceEngineControllerTest {

    private val native = FakeAudioEngineNative()
    private val devices = FakeDeviceSource(listOf(MIC, SPEAKER, USB_IN, USB_OUT, HEADPHONES))

    private fun TestScope.controller(maxAttempts: Int = 3) = VoiceEngineController(
        native = native,
        deviceSource = devices,
        scope = backgroundScope,
        ioDispatcher = StandardTestDispatcher(testScheduler),
        pollIntervalMs = 50,
        maxRecoveryAttempts = maxAttempts,
        recoveryBackoffMs = 100,
    )

    @Test
    fun startPushesParamsAndPublishesStats() = runTest {
        val c = controller()
        c.applySettings(VoiceSettings(pitchSemitones = 5f))
        assertNull(c.start(EngineRequest(inputDeviceId = MIC.id, outputDeviceId = HEADPHONES.id)))
        assertTrue(c.state.value is EngineState.Running)
        assertEquals(5f, native.params[VoiceParameter.PITCH_SEMITONES.nativeId], 0f)
        advanceTimeBy(120)
        runCurrent()
        assertEquals(48000, c.stats.value.sampleRate)
        assertEquals(-20f, c.stats.value.inputPeakDb, 0f)
    }

    @Test
    fun startFailureReportsNativeError() = runTest {
        val c = controller()
        native.startResults += -889
        native.errorText = "Could not open microphone stream: ErrorInternal"
        val error = c.start(EngineRequest())
        assertEquals("Could not open microphone stream: ErrorInternal", error)
        val state = c.state.value as EngineState.Failed
        assertEquals(-889, state.code)
    }

    @Test
    fun missingNativeLibraryFailsCleanly() = runTest {
        native.unavailableReason = "dlopen failed"
        val c = controller()
        assertNotNull(c.start(EngineRequest()))
        assertTrue(c.state.value is EngineState.Failed)
        assertTrue(native.startedWith.isEmpty())
    }

    @Test
    fun unpluggedUsbFallsBackToDefaultThenRestoresWhenReplugged() = runTest {
        val c = controller()
        c.start(EngineRequest(inputDeviceId = USB_IN.id, outputDeviceId = USB_OUT.id))
        assertEquals(USB_OUT.id, native.startedWith.last().outputDeviceId)

        // Interface removed: the stream reports a disconnect.
        devices.flow.value = listOf(MIC, SPEAKER)
        native.nativeState = NativeEngineState.DISCONNECTED
        advanceTimeBy(60)
        runCurrent()
        assertTrue(c.state.value is EngineState.Recovering)
        advanceTimeBy(200)
        runCurrent()
        val running = c.state.value as EngineState.Running
        assertEquals(0, running.request.inputDeviceId)
        assertEquals(0, running.request.outputDeviceId)
        assertTrue(devices.refreshCount >= 1)

        // Interface plugged back in: the user's original routing returns automatically.
        devices.flow.value = listOf(MIC, SPEAKER, USB_IN, USB_OUT)
        advanceTimeBy(60)
        runCurrent()
        val restored = c.state.value as EngineState.Running
        assertEquals(USB_OUT.id, restored.request.outputDeviceId)
        assertEquals(USB_IN.id, restored.request.inputDeviceId)
    }

    @Test
    fun recoveryGivesUpAfterMaxAttempts() = runTest {
        val c = controller(maxAttempts = 2)
        c.start(EngineRequest())
        native.startResults += listOf(-899, -899)
        native.errorText = "device busy"
        native.nativeState = NativeEngineState.ERROR
        advanceTimeBy(60 + 100 + 200 + 50)
        runCurrent()
        val failed = c.state.value as EngineState.Failed
        assertTrue(failed.message.contains("device busy"))
        assertEquals(3, native.startedWith.size)  // initial + 2 attempts
    }

    @Test
    fun applySettingsSendsOnlyChanges() = runTest {
        val c = controller()
        c.applySettings(VoiceSettings(pitchSemitones = 4f))
        native.paramWrites.clear()
        c.applySettings(VoiceSettings(pitchSemitones = 4f, airDb = 2f))
        assertEquals(listOf(VoiceParameter.AIR_DB.nativeId to 2f), native.paramWrites)
        c.applySettings(VoiceSettings(pitchSemitones = 40f, airDb = 2f))  // clamped
        assertEquals(12f, native.params[VoiceParameter.PITCH_SEMITONES.nativeId], 0f)
    }

    @Test
    fun stopReturnsToIdle() = runTest {
        val c = controller()
        c.start(EngineRequest())
        c.stop()
        assertEquals(EngineState.Idle, c.state.value)
        assertTrue(native.stopCount >= 1)
        assertEquals(EngineStats.EMPTY, c.stats.value)
    }

    @Test
    fun feedbackRiskOnlyForSpeakerPlusBuiltInMic() {
        val all = listOf(MIC, SPEAKER, HEADPHONES)
        assertTrue(DeviceSelection.feedbackRisk(MIC.id, SPEAKER.id, all))
        assertTrue(!DeviceSelection.feedbackRisk(MIC.id, HEADPHONES.id, all))
        // Default output with headphones attached routes to the headphones.
        assertTrue(!DeviceSelection.feedbackRisk(0, 0, all))
        assertTrue(DeviceSelection.feedbackRisk(0, 0, listOf(MIC, SPEAKER)))
    }
}
