package com.voiceshift.bridge.network

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack

/**
 * Plays received PCM with a low-latency [AudioTrack]. Blocking writes pace the receiver's playout
 * thread. Used by the Quest experimental receiver; the audio goes to the headset's speakers or
 * headphones — it is NOT injected into other apps' microphone input.
 */
class AudioTrackPcmSink : PcmSink, AutoCloseable {
    private var track: AudioTrack? = null
    private var trackRate = 0

    @Synchronized
    override fun write(samples: ShortArray, sampleRate: Int) {
        if (track == null || trackRate != sampleRate) open(sampleRate)
        track?.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING)
    }

    private fun open(sampleRate: Int) {
        close()
        val minBytes = AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(maxOf(minBytes, sampleRate / 50 * 2))  // >= 20 ms
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
            .also { it.play() }
        trackRate = sampleRate
    }

    @Synchronized
    override fun close() {
        track?.run {
            runCatching { stop() }
            release()
        }
        track = null
        trackRate = 0
    }
}
