package com.voiceshift.bridge.network

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Route C wire format (UDP, little-endian):
 *
 * | offset | size | field                                   |
 * |-------:|-----:|-----------------------------------------|
 * |      0 |    4 | magic "VSVR" (0x56 0x53 0x56 0x52)      |
 * |      4 |    1 | version (1)                             |
 * |      5 |    1 | flags (bit 0 = end of stream)           |
 * |      6 |    1 | channels (1)                            |
 * |      7 |    1 | reserved (0)                            |
 * |      8 |    4 | sequence number (uint32, wraps)         |
 * |     12 |    8 | timestamp: index of first frame (int64) |
 * |     20 |    4 | sample rate (Hz)                        |
 * |     24 |    2 | frame count                             |
 * |     26 |  2*n | PCM int16 samples                       |
 */
data class PcmPacket(
    val sequence: Long,
    val timestampFrames: Long,
    val sampleRate: Int,
    val samples: ShortArray,
    val channels: Int = 1,
    val endOfStream: Boolean = false,
) {
    init {
        require(sequence in 0..0xFFFF_FFFFL) { "sequence must fit in uint32" }
        require(channels == 1) { "only mono is supported" }
        require(samples.size <= MAX_FRAMES) { "too many frames: ${samples.size}" }
    }

    fun encode(): ByteArray {
        val buffer = ByteBuffer.allocate(HEADER_SIZE + samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put(MAGIC)
        buffer.put(VERSION.toByte())
        buffer.put(if (endOfStream) 1 else 0)
        buffer.put(channels.toByte())
        buffer.put(0)
        buffer.putInt(sequence.toInt())
        buffer.putLong(timestampFrames)
        buffer.putInt(sampleRate)
        buffer.putShort(samples.size.toShort())
        for (s in samples) buffer.putShort(s)
        return buffer.array()
    }

    override fun equals(other: Any?): Boolean = other is PcmPacket && sequence == other.sequence &&
        timestampFrames == other.timestampFrames && sampleRate == other.sampleRate &&
        samples.contentEquals(other.samples) && channels == other.channels && endOfStream == other.endOfStream

    override fun hashCode(): Int = (sequence * 31 + timestampFrames).hashCode() * 31 + samples.contentHashCode()

    companion object {
        const val HEADER_SIZE = 26
        const val VERSION = 1
        /** Keeps a packet inside a typical 1500-byte Ethernet/Wi-Fi MTU. */
        const val MAX_FRAMES = 720
        private val MAGIC = byteArrayOf(0x56, 0x53, 0x56, 0x52)

        /** Returns null for anything that is not a well-formed v1 packet (never throws on bad input). */
        fun decode(data: ByteArray, length: Int = data.size): PcmPacket? {
            if (length < HEADER_SIZE) return null
            val buffer = ByteBuffer.wrap(data, 0, length).order(ByteOrder.LITTLE_ENDIAN)
            for (b in MAGIC) if (buffer.get() != b) return null
            if (buffer.get().toInt() != VERSION) return null
            val flags = buffer.get().toInt()
            val channels = buffer.get().toInt()
            buffer.get()
            if (channels != 1) return null
            val sequence = buffer.int.toLong() and 0xFFFF_FFFFL
            val timestamp = buffer.long
            val sampleRate = buffer.int
            val frames = buffer.short.toInt() and 0xFFFF
            if (sampleRate !in 8000..192000 || frames > MAX_FRAMES || length != HEADER_SIZE + frames * 2) return null
            val samples = ShortArray(frames) { buffer.short }
            return PcmPacket(sequence, timestamp, sampleRate, samples, channels, endOfStream = flags and 1 != 0)
        }

        fun floatToPcm16(src: FloatArray, count: Int = src.size): ShortArray = ShortArray(count) {
            (src[it].coerceIn(-1f, 1f) * 32767f).toInt().toShort()
        }

        fun pcm16ToFloat(src: ShortArray, dst: FloatArray) {
            for (i in src.indices) dst[i] = src[i] / 32768f
        }
    }
}
