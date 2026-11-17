package com.voiceshift.bridge.network

import java.net.DatagramSocket
import java.util.concurrent.ConcurrentLinkedQueue
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkBridgeTest {

    private fun packet(seq: Long, value: Short = seq.toShort(), frames: Int = 4) =
        PcmPacket(seq, seq * frames, 48000, ShortArray(frames) { value })

    @Test
    fun packetRoundTrip() {
        val p = PcmPacket(0xFFFF_FFFEL, 123_456_789_012L, 48000, shortArrayOf(1, -2, 32767, -32768))
        val bytes = p.encode()
        assertEquals(PcmPacket.HEADER_SIZE + 8, bytes.size)
        assertEquals(p, PcmPacket.decode(bytes))
    }

    @Test
    fun malformedPacketsAreRejectedWithoutThrowing() {
        val good = packet(1).encode()
        assertNull(PcmPacket.decode(good.copyOf(10)))
        assertNull(PcmPacket.decode(good, good.size - 1))
        assertNull(PcmPacket.decode(good.copyOf().also { it[0] = 0 }))
        assertNull(PcmPacket.decode(good.copyOf().also { it[4] = 9 }))  // version
        assertNull(PcmPacket.decode(ByteArray(0)))
    }

    @Test
    fun pcmConversionClampsAndScales() {
        val pcm = PcmPacket.floatToPcm16(floatArrayOf(0f, 0.5f, 2f, -2f))
        assertArrayEquals(shortArrayOf(0, 16383, 32767, -32767), pcm)
        val back = FloatArray(4)
        PcmPacket.pcm16ToFloat(pcm, back)
        assertEquals(0.5f, back[1], 1e-3f)
    }

    @Test
    fun jitterBufferReordersAndWaitsForTarget() {
        val jb = JitterBuffer(targetFrames = 3)
        jb.push(packet(2))
        jb.push(packet(0))
        assertNull(jb.pop())  // still buffering
        jb.push(packet(1))
        assertEquals(0L, jb.pop()!!.sequence)
        assertEquals(1L, jb.pop()!!.sequence)
        assertEquals(2L, jb.pop()!!.sequence)
        assertEquals(3, jb.stats.played.toInt())
    }

    @Test
    fun jitterBufferConcealsLossDropsLateAndDuplicates() {
        val jb = JitterBuffer(targetFrames = 2)
        jb.push(packet(0, 1000))
        jb.push(packet(2, 2000))
        assertEquals(1000, jb.pop()!!.samples[0].toInt())
        val concealed = jb.pop()!!
        assertTrue(concealed.concealed)
        assertEquals(500, concealed.samples[0].toInt())  // previous frame at -6 dB
        assertEquals(2000, jb.pop()!!.samples[0].toInt())
        jb.push(packet(1))  // too late now
        jb.push(packet(3))
        jb.push(packet(3))
        val s = jb.stats
        assertEquals(1L, s.lost)
        assertEquals(1L, s.late)
        assertEquals(1L, s.duplicates)
    }

    @Test
    fun jitterBufferRebuffersAfterLongGap() {
        val jb = JitterBuffer(targetFrames = 2)
        jb.push(packet(0))
        jb.push(packet(1))
        jb.pop(); jb.pop()
        repeat(4) { assertNotNull(jb.pop()) }  // 4 concealed frames
        assertEquals(1L, jb.stats.rebuffers)
        assertNull(jb.pop())
    }

    @Test
    fun jitterBufferHandlesSequenceWrap() {
        val jb = JitterBuffer(targetFrames = 2)
        jb.push(packet(0xFFFF_FFFFL))
        jb.push(packet(0L))
        assertEquals(0xFFFF_FFFFL, jb.pop()!!.sequence)
        val next = jb.pop()!!
        assertTrue(!next.concealed)
    }

    @Test
    fun udpLoopbackEndToEnd() {
        val port = DatagramSocket(0).use { it.localPort }
        val received = ConcurrentLinkedQueue<Short>()
        val sink = PcmSink { samples, rate ->
            samples.forEach { received.add(it) }
            Thread.sleep((samples.size * 1000L / rate).coerceAtLeast(1))  // emulate a blocking audio device
        }
        val receiver = UdpPcmReceiver(port, sink, targetFrames = 2)
        receiver.start()

        var produced = 0
        val total = 4800 * 2  // 200 ms at 48 kHz
        val source = PcmSource { dst, max ->
            val n = minOf(max, total - produced)
            for (i in 0 until n) dst[i] = 0.25f
            produced += n
            if (n == 0) -1 else n
        }
        val sender = UdpPcmSender(source, "127.0.0.1", port, sampleRate = 48000)
        sender.start()
        val deadline = System.currentTimeMillis() + 5000
        while (received.size < total && System.currentTimeMillis() < deadline) Thread.sleep(10)
        sender.stop()
        receiver.stop()

        assertTrue("received ${received.size}", received.size >= total)
        assertEquals((0.25f * 32767).toInt().toShort(), received.first())
        assertEquals(20L, sender.stats.value.packetsSent)
        assertNull(sender.stats.value.error)
    }
}
