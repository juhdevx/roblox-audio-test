package com.voiceshift.inference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** In-memory stand-in for the native AI queues. */
class FakePort(private val chunk: Int) : AudioStreamPort {
    private val pending = ArrayDeque<Float>()
    private var readPosition = 0L
    val written = mutableListOf<FloatArray>()
    val writtenTimestamps = mutableListOf<Long>()

    fun feed(samples: FloatArray) = samples.forEach { pending.addLast(it) }

    override fun available(): Int = pending.size
    override fun read(dst: FloatArray, maxFrames: Int, timestampOut: LongArray): Int {
        timestampOut[0] = readPosition
        val n = minOf(maxFrames, pending.size)
        for (i in 0 until n) dst[i] = pending.removeFirst()
        readPosition += n
        return n
    }

    override fun write(src: FloatArray, frames: Int, timestamp: Long): Int {
        written += src.copyOf(frames)
        writtenTimestamps += timestamp
        return frames
    }
}

private class ScriptedSession(
    override val spec: StreamingSpec,
    private val behaviour: (FloatArray) -> FloatArray,
) : InferenceSession {
    val windows = mutableListOf<FloatArray>()
    override fun run(window: FloatArray): FloatArray {
        windows += window.copyOf()
        return behaviour(window)
    }
    override fun close() = Unit
}

class StreamingInferenceWorkerTest {

    private fun spec(chunk: Int = 4, context: Int = 2) =
        StreamingSpec("x", 2, "y", sampleRate = 1000, chunkFrames = chunk, contextFrames = context, fixedInputLength = null)

    @Test
    fun contextCarriesOverBetweenChunks() {
        val session = ScriptedSession(spec()) { w -> w.copyOfRange(2, 6) }
        val port = FakePort(4).apply { feed(floatArrayOf(1f, 2f, 3f, 4f, 5f, 6f, 7f, 8f)) }
        val worker = StreamingInferenceWorker(session, port)
        assertTrue(worker.step())
        assertTrue(worker.step())
        assertTrue(session.windows[0].contentEquals(floatArrayOf(0f, 0f, 1f, 2f, 3f, 4f)))
        assertTrue(session.windows[1].contentEquals(floatArrayOf(3f, 4f, 5f, 6f, 7f, 8f)))
        assertTrue(port.written[1].contentEquals(floatArrayOf(5f, 6f, 7f, 8f)))
        assertEquals(listOf(0L, 4L), port.writtenTimestamps)
    }

    @Test
    fun modelErrorStopsWorker() {
        val session = ScriptedSession(spec()) { throw IllegalStateException("boom") }
        val port = FakePort(4).apply { feed(FloatArray(4)) }
        val worker = StreamingInferenceWorker(session, port)
        assertFalse(worker.step())
        assertEquals(WorkerState.STOPPED_ERROR, worker.stats.value.state)
        assertEquals("boom", worker.stats.value.lastError)
        assertTrue(port.written.isEmpty())
    }

    @Test
    fun persistentlySlowModelStops() {
        var now = 0L
        // Each run "takes" 10 ms for a 4 ms chunk (chunk 4 samples @ 1 kHz).
        val session = ScriptedSession(spec()) { w -> now += 10_000_000; w.copyOfRange(2, 6) }
        val port = FakePort(4).apply { feed(FloatArray(4 * 10)) }
        val worker = StreamingInferenceWorker(session, port, slowChunkLimit = 3, nanoTime = { now })
        assertTrue(worker.step())
        assertTrue(worker.step())
        assertFalse(worker.step())
        assertEquals(WorkerState.STOPPED_TOO_SLOW, worker.stats.value.state)
        assertEquals(2.5, worker.stats.value.realtimeFactor, 1e-9)
    }

    @Test
    fun threadedLoopDrainsPort() {
        val session = ScriptedSession(spec(chunk = 8, context = 0)) { it }
        val port = FakePort(8).apply { feed(FloatArray(80) { it.toFloat() }) }
        val worker = StreamingInferenceWorker(session, port)
        worker.start()
        val deadline = System.currentTimeMillis() + 5000
        while (port.written.size < 10 && System.currentTimeMillis() < deadline) Thread.sleep(5)
        worker.stop()
        assertEquals(10, port.written.size)
        assertEquals(79f, port.written.last().last(), 0f)
        assertFalse(worker.isRunning)
    }
}
