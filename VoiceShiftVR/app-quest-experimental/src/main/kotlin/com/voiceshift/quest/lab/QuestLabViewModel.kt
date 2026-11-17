package com.voiceshift.quest.lab

import android.app.Application
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.voiceshift.audio.AndroidAudioDeviceSource
import com.voiceshift.audio.AudioDevice
import com.voiceshift.audio.DeviceKind
import com.voiceshift.audio.EngineMode
import com.voiceshift.audio.EngineRequest
import com.voiceshift.audio.EngineState
import com.voiceshift.audio.MicMode
import com.voiceshift.audio.OboeAudioEngineNative
import com.voiceshift.audio.VoiceEngineController
import com.voiceshift.bridge.network.AudioTrackPcmSink
import com.voiceshift.bridge.network.LocalNetwork
import com.voiceshift.bridge.network.ReceiverStats
import com.voiceshift.bridge.network.UdpPcmReceiver
import com.voiceshift.dsp.DspQuality
import com.voiceshift.dsp.VoiceSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the lab is currently doing with the audio engine. */
enum class LabMode { IDLE, USB_PROBE, LOCAL_DSP }

/**
 * Research tools that run on the headset itself:
 *
 *  * USB mic probe (Route A, stage 3): capture from a chosen input and detect the phone's 1 kHz tone.
 *    Output is muted, so nothing is played back.
 *  * Local DSP (Route B feasibility): run the same native voice engine on the Quest's CPU and observe
 *    load and latency. Output goes to the headset speakers/headphones only.
 *  * Wi-Fi receiver (Route C): play the phone's streamed voice inside this app.
 */
class QuestLabViewModel(app: Application) : AndroidViewModel(app) {

    val deviceSource = AndroidAudioDeviceSource(app)
    private val native = OboeAudioEngineNative()
    val engine = VoiceEngineController(native, deviceSource, viewModelScope, Dispatchers.IO)

    private val _mode = MutableStateFlow(LabMode.IDLE)
    val mode: StateFlow<LabMode> = _mode.asStateFlow()

    private val _receiver = MutableStateFlow(ReceiverStats())
    val receiver: StateFlow<ReceiverStats> = _receiver.asStateFlow()
    private var udp: UdpPcmReceiver? = null
    private var sink: AudioTrackPcmSink? = null
    private var receiverWatch: Job? = null

    val nativeUnavailable: String? = native.unavailableReason
    val deviceInfo = "${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"

    fun localAddresses(): List<String> = LocalNetwork.ipv4Addresses()

    /** USB/wired inputs Android reports on this headset: the OS-level "recognition" evidence. */
    fun externalInputs(devices: List<AudioDevice>): List<AudioDevice> = devices.filter {
        it.isInput && it.kind in setOf(DeviceKind.USB_DEVICE, DeviceKind.USB_HEADSET, DeviceKind.WIRED_HEADSET, DeviceKind.USB_ACCESSORY)
    }

    fun startUsbProbe(inputDeviceId: Int) = viewModelScope.launch {
        native.setMuted(true)
        native.setBypass(true)
        native.setMode(EngineMode.DSP)
        val error = engine.start(EngineRequest(inputDeviceId = inputDeviceId, micMode = MicMode.UNPROCESSED, quality = DspQuality.LOW_LATENCY))
        _mode.value = if (error == null) LabMode.USB_PROBE else LabMode.IDLE
    }

    fun startLocalDsp(inputDeviceId: Int, outputDeviceId: Int, settings: VoiceSettings) = viewModelScope.launch {
        native.setMuted(false)
        native.setBypass(false)
        native.setMode(EngineMode.DSP)
        engine.applySettings(settings)
        val error = engine.start(EngineRequest(inputDeviceId = inputDeviceId, outputDeviceId = outputDeviceId))
        _mode.value = if (error == null) LabMode.LOCAL_DSP else LabMode.IDLE
    }

    fun stopEngine() = viewModelScope.launch {
        engine.stop()
        _mode.value = LabMode.IDLE
    }

    fun startReceiver(port: Int) {
        stopReceiver()
        val s = AudioTrackPcmSink()
        val r = UdpPcmReceiver(port, s)
        sink = s
        udp = r
        r.start()
        receiverWatch = viewModelScope.launch { r.stats.collect { _receiver.value = it } }
    }

    fun stopReceiver() {
        receiverWatch?.cancel()
        udp?.stop()
        sink?.close()
        udp = null
        sink = null
        _receiver.value = ReceiverStats()
    }

    val engineRunning: Boolean get() = engine.state.value is EngineState.Running

    override fun onCleared() {
        stopReceiver()
        native.stop()
    }
}
