package com.voiceshift.audio

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Live list of input and output devices from [AudioManager], updated by [AudioDeviceCallback]
 * whenever something is plugged in or removed (USB interfaces, headsets, Bluetooth).
 */
class AndroidAudioDeviceSource(context: Context) : AudioDeviceSource {

    private val audioManager = context.applicationContext.getSystemService(AudioManager::class.java)
    private val _devices = MutableStateFlow<List<AudioDevice>>(emptyList())
    override val devices: StateFlow<List<AudioDevice>> = _devices.asStateFlow()

    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) = refresh()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) = refresh()
    }

    init {
        refresh()
        audioManager.registerAudioDeviceCallback(callback, Handler(Looper.getMainLooper()))
    }

    override fun refresh() {
        val inputs = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).map { it.toModel(isInput = true) }
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { it.toModel(isInput = false) }
        _devices.value = (inputs + outputs).sortedWith(compareBy({ !it.isInput }, { it.kind.ordinal }, { it.id }))
    }

    private fun AudioDeviceInfo.toModel(isInput: Boolean) = AudioDevice(
        id = id,
        name = productName?.toString().orEmpty(),
        kind = DeviceKind.fromAndroidType(type),
        isInput = isInput && isSource,
        isOutput = !isInput && isSink,
        sampleRates = sampleRates.toList(),
        channelCounts = channelCounts.toList(),
        address = address.orEmpty(),
    )
}
