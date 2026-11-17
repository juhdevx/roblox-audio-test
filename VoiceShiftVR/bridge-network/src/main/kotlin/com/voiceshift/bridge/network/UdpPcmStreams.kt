package com.voiceshift.bridge.network

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Where the sender gets processed audio (the engine's output tap). */
fun interface PcmSource {
    /** Copies up to [maxFrames] float samples into [dst]; returns the count, or < 0 if unavailable. */
    fun read(dst: FloatArray, maxFrames: Int): Int
}

/** Where the receiver delivers audio (AudioTrack on Android, a list in tests). Blocking writes pace playout. */
fun interface PcmSink {
    fun write(samples: ShortArray, sampleRate: Int)
}

data class SenderStats(val running: Boolean = false, val packetsSent: Long = 0, val bytesSent: Long = 0, val error: String? = null)

/**
 * EXPERIMENTAL Route C sender: streams the processed voice as 10 ms PCM packets to a receiver on the
 * local network. It does not create a microphone on the receiving device.
 */
class UdpPcmSender(
    private val source: PcmSource,
    private val host: String,
    private val port: Int,
    private val sampleRate: Int,
    private val frameMs: Int = 10,
) {
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null
    private val _stats = MutableStateFlow(SenderStats())
    val stats: StateFlow<SenderStats> = _stats.asStateFlow()

    fun start() {
        if (!running.compareAndSet(false, true)) return
        thread = Thread({ loop() }, "VoiceShift-UdpSender").apply { isDaemon = true; start() }
    }

    fun stop() {
        running.set(false)
        thread?.join(1000)
        thread = null
    }

    private fun loop() {
        val frames = (sampleRate * frameMs / 1000).coerceIn(32, PcmPacket.MAX_FRAMES)
        val buffer = FloatArray(frames)
        val scratch = FloatArray(frames)
        var filled = 0
        var sequence = 0L
        var timestamp = 0L
        try {
            DatagramSocket().use { socket ->
                val address = InetSocketAddress(InetAddress.getByName(host), port)
                _stats.value = SenderStats(running = true)
                while (running.get()) {
                    val n = source.read(scratch, frames - filled)
                    if (n > 0) {
                        System.arraycopy(scratch, 0, buffer, filled, n)
                        filled += n
                    } else {
                        Thread.sleep(2)
                    }
                    if (filled == frames) {
                        val bytes = PcmPacket(sequence, timestamp, sampleRate, PcmPacket.floatToPcm16(buffer)).encode()
                        socket.send(DatagramPacket(bytes, bytes.size, address))
                        sequence = (sequence + 1) and 0xFFFF_FFFFL
                        timestamp += frames
                        filled = 0
                        val s = _stats.value
                        _stats.value = s.copy(packetsSent = s.packetsSent + 1, bytesSent = s.bytesSent + bytes.size)
                    }
                }
                val end = PcmPacket(sequence, timestamp, sampleRate, ShortArray(0), endOfStream = true).encode()
                socket.send(DatagramPacket(end, end.size, address))
            }
            _stats.value = _stats.value.copy(running = false)
        } catch (e: Exception) {
            _stats.value = _stats.value.copy(running = false, error = e.message ?: e.javaClass.simpleName)
            running.set(false)
        }
    }
}

data class ReceiverStats(
    val running: Boolean = false,
    val sampleRate: Int = 0,
    val jitter: JitterStats = JitterStats(),
    val lastSender: String? = null,
    val error: String? = null,
)

/**
 * EXPERIMENTAL Route C receiver: UDP -> [JitterBuffer] -> [PcmSink]. Two threads: one receives
 * packets, one plays frames at the sink's pace.
 */
class UdpPcmReceiver(
    private val port: Int,
    private val sink: PcmSink,
    private val targetFrames: Int = 5,
) {
    private val running = AtomicBoolean(false)
    private val jitter = JitterBuffer(targetFrames = targetFrames)
    private val lock = Any()
    private var socket: DatagramSocket? = null
    private var receiveThread: Thread? = null
    private var playThread: Thread? = null
    @Volatile private var sampleRate = 0
    private val _stats = MutableStateFlow(ReceiverStats())
    val stats: StateFlow<ReceiverStats> = _stats.asStateFlow()

    fun start() {
        if (!running.compareAndSet(false, true)) return
        try {
            socket = DatagramSocket(port).apply { soTimeout = 200 }
        } catch (e: Exception) {
            running.set(false)
            _stats.value = ReceiverStats(error = "Cannot listen on UDP $port: ${e.message}")
            return
        }
        _stats.value = ReceiverStats(running = true)
        receiveThread = Thread({ receiveLoop() }, "VoiceShift-UdpReceive").apply { isDaemon = true; start() }
        playThread = Thread({ playLoop() }, "VoiceShift-UdpPlay").apply { isDaemon = true; start() }
    }

    fun stop() {
        running.set(false)
        socket?.close()
        receiveThread?.join(1000)
        playThread?.join(1000)
        receiveThread = null
        playThread = null
        synchronized(lock) { jitter.reset() }
        _stats.value = _stats.value.copy(running = false)
    }

    private fun receiveLoop() {
        val data = ByteArray(PcmPacket.HEADER_SIZE + PcmPacket.MAX_FRAMES * 2)
        val datagram = DatagramPacket(data, data.size)
        while (running.get()) {
            try {
                socket?.receive(datagram) ?: return
            } catch (_: SocketTimeoutException) {
                continue
            } catch (e: Exception) {
                if (running.get()) _stats.value = _stats.value.copy(error = e.message)
                return
            }
            val packet = PcmPacket.decode(data, datagram.length) ?: continue
            if (packet.endOfStream) {
                synchronized(lock) { jitter.reset() }
                continue
            }
            sampleRate = packet.sampleRate
            synchronized(lock) { jitter.push(packet) }
            _stats.value = _stats.value.copy(lastSender = datagram.address?.hostAddress, sampleRate = packet.sampleRate)
        }
    }

    private fun playLoop() {
        while (running.get()) {
            val frame = synchronized(lock) { jitter.pop() }
            val rate = sampleRate
            if (frame == null || rate == 0 || frame.samples.isEmpty()) {
                Thread.sleep(5)
            } else {
                sink.write(frame.samples, rate)  // blocking write paces playback
            }
            _stats.value = _stats.value.copy(jitter = synchronized(lock) { jitter.stats })
        }
    }
}

object LocalNetwork {
    /** Non-loopback IPv4 addresses, to show the user which address the sender should target. */
    fun ipv4Addresses(): List<String> = runCatching {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { it.inetAddresses.toList() }
            .filterIsInstance<Inet4Address>()
            .map { it.hostAddress.orEmpty() }
            .filter { it.isNotEmpty() }
    }.getOrDefault(emptyList())
}
