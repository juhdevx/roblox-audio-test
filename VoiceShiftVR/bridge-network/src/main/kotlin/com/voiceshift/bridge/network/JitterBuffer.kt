package com.voiceshift.bridge.network

/** A frame ready for playback. [concealed] frames were synthesised because a packet was lost. */
class PlayoutFrame(val sequence: Long, val samples: ShortArray, val concealed: Boolean)

data class JitterStats(
    val received: Long = 0,
    val played: Long = 0,
    val lost: Long = 0,
    val late: Long = 0,
    val duplicates: Long = 0,
    val overflowDrops: Long = 0,
    val rebuffers: Long = 0,
    val depthFrames: Int = 0,
)

/**
 * Reorders packets by sequence number and releases them at a steady pace.
 *
 * Playback starts once [targetFrames] are buffered. Missing packets are concealed by repeating the
 * previous frame at decreasing level (then silence). After [targetFrames] * 2 consecutive losses with
 * an empty buffer the stream re-buffers. Not thread-safe: guard with a lock when push and pop happen
 * on different threads.
 */
class JitterBuffer(
    private val targetFrames: Int = 4,
    private val maxFrames: Int = 50,
) {
    private val pending = sortedMapOf<Long, ShortArray>()
    private var started = false
    private var nextSequence = 0L
    private var lastSequenceSeen = -1L
    private var unwrapBase = 0L
    private var lastFrame: ShortArray? = null
    private var consecutiveLosses = 0
    var stats = JitterStats()
        private set

    /** Maps a wrapping uint32 sequence to a monotonically increasing value. */
    private fun unwrap(sequence: Long): Long {
        if (lastSequenceSeen >= 0) {
            val last = lastSequenceSeen and 0xFFFF_FFFFL
            val delta = sequence - last
            if (delta < -(1L shl 31)) unwrapBase += 1L shl 32
            if (delta > (1L shl 31)) return unwrapBase - (1L shl 32) + sequence
        }
        val value = unwrapBase + sequence
        if (value > lastSequenceSeen) lastSequenceSeen = value
        return value
    }

    fun push(packet: PcmPacket) {
        val seq = unwrap(packet.sequence)
        stats = stats.copy(received = stats.received + 1)
        when {
            started && seq < nextSequence -> stats = stats.copy(late = stats.late + 1)
            pending.containsKey(seq) -> stats = stats.copy(duplicates = stats.duplicates + 1)
            else -> {
                pending[seq] = packet.samples
                while (pending.size > maxFrames) {
                    val oldest = pending.firstKey()
                    pending.remove(oldest)
                    if (started && nextSequence <= oldest) nextSequence = oldest + 1
                    stats = stats.copy(overflowDrops = stats.overflowDrops + 1)
                }
            }
        }
        stats = stats.copy(depthFrames = pending.size)
    }

    /** Next frame to play, or null while (re)buffering. */
    fun pop(): PlayoutFrame? {
        if (!started) {
            if (pending.size < targetFrames) return null
            started = true
            nextSequence = pending.firstKey()
        }
        val seq = nextSequence++
        val samples = pending.remove(seq)
        val frame = if (samples != null) {
            consecutiveLosses = 0
            lastFrame = samples
            stats = stats.copy(played = stats.played + 1)
            PlayoutFrame(seq, samples, concealed = false)
        } else {
            consecutiveLosses++
            stats = stats.copy(lost = stats.lost + 1)
            val previous = lastFrame
            val concealment = if (previous != null && consecutiveLosses <= 3) {
                val gain = 1f / (1 shl consecutiveLosses)  // 0.5, 0.25, 0.125
                ShortArray(previous.size) { (previous[it] * gain).toInt().toShort() }
            } else {
                ShortArray(previous?.size ?: 0)
            }
            if (pending.isEmpty() && consecutiveLosses >= targetFrames * 2) {
                started = false
                consecutiveLosses = 0
                stats = stats.copy(rebuffers = stats.rebuffers + 1)
            }
            PlayoutFrame(seq, concealment, concealed = true)
        }
        stats = stats.copy(depthFrames = pending.size)
        return frame
    }

    fun reset() {
        pending.clear()
        started = false
        lastFrame = null
        consecutiveLosses = 0
        lastSequenceSeen = -1
        unwrapBase = 0
        stats = JitterStats()
    }
}
