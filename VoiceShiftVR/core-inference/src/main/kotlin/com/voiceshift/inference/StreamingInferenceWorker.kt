package com.voiceshift.inference

import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The worker's view of the native AI queues (AiBridge in core-audio). Negative return values mean
 * the engine is not running or has no neural path configured.
 */
interface AudioStreamPort {
    fun available(): Int
    fun read(dst: FloatArray, maxFrames: Int, timestampOut: LongArray): Int
    fun write(src: FloatArray, frames: Int, timestamp: Long): Int
}

enum class WorkerState { IDLE, RUNNING, STOPPED_TOO_SLOW, STOPPED_ERROR }

data class WorkerStats(
    val state: WorkerState = WorkerState.IDLE,
    val chunksProcessed: Long = 0,
    val lastInferenceMs: Double = 0.0,
    val averageInferenceMs: Double = 0.0,
    val maxInferenceMs: Double = 0.0,
    /** Average inference time divided by chunk duration; must stay below 1 for real time. */
    val realtimeFactor: Double = 0.0,
    val lastError: String? = null,
)

/**
 * Background inference loop for Engine B. It never touches the audio callback: it pulls model-rate
 * chunks from [port], keeps [StreamingSpec.contextFrames] of history, runs the model and pushes the
 * result back with the same timestamp.
 *
 * Safety: if the model throws, or stays slower than real time for [slowChunkLimit] consecutive
 * chunks, the worker stops. The native side then plays its DSP fallback automatically.
 */
class StreamingInferenceWorker(
    private val session: InferenceSession,
    private val port: AudioStreamPort,
    private val slowChunkLimit: Int = 20,
    private val idleSleepMs: Long = 2,
    private val nanoTime: () -> Long = System::nanoTime,
) {
    private val spec = session.spec
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null
    private val _stats = MutableStateFlow(WorkerStats())
    val stats: StateFlow<WorkerStats> = _stats.asStateFlow()

    private val window = FloatArray(spec.windowFrames)
    private val chunk = FloatArray(spec.chunkFrames)
    private val timestamp = LongArray(1)
    private var slowStreak = 0
    private var totalMs = 0.0

    fun start() {
        if (!running.compareAndSet(false, true)) return
        _stats.value = WorkerStats(state = WorkerState.RUNNING)
        thread = Thread({ loop() }, "VoiceShift-Inference").apply {
            priority = Thread.NORM_PRIORITY + 1
            isDaemon = true
            start()
        }
    }

    /** Stops the loop and waits for it; does not close the session (the owner does). */
    fun stop() {
        running.set(false)
        thread?.join(2000)
        thread = null
        if (_stats.value.state == WorkerState.RUNNING) _stats.value = _stats.value.copy(state = WorkerState.IDLE)
    }

    val isRunning: Boolean get() = running.get()

    private fun loop() {
        while (running.get()) {
            val available = port.available()
            if (available < spec.chunkFrames) {
                sleep(if (available < 0) 20 else idleSleepMs)
                continue
            }
            if (!step()) {
                running.set(false)
                return
            }
        }
    }

    /** Processes exactly one chunk. Returns false if the worker must stop. Visible for tests. */
    internal fun step(): Boolean {
        val got = port.read(chunk, spec.chunkFrames, timestamp)
        if (got != spec.chunkFrames) return true  // engine restarted between available() and read()
        System.arraycopy(window, spec.chunkFrames, window, 0, spec.contextFrames)
        System.arraycopy(chunk, 0, window, spec.contextFrames, spec.chunkFrames)

        val start = nanoTime()
        val output = try {
            session.run(window)
        } catch (e: Exception) {
            _stats.value = _stats.value.copy(state = WorkerState.STOPPED_ERROR, lastError = e.message ?: e.javaClass.simpleName)
            return false
        }
        val ms = (nanoTime() - start) / 1e6
        port.write(output, output.size, timestamp[0])

        val previous = _stats.value
        val count = previous.chunksProcessed + 1
        totalMs += ms
        val average = totalMs / count
        _stats.value = previous.copy(
            chunksProcessed = count,
            lastInferenceMs = ms,
            averageInferenceMs = average,
            maxInferenceMs = maxOf(previous.maxInferenceMs, ms),
            realtimeFactor = average / spec.chunkDurationMs,
        )
        slowStreak = if (ms > spec.chunkDurationMs) slowStreak + 1 else 0
        if (slowStreak >= slowChunkLimit) {
            _stats.value = _stats.value.copy(
                state = WorkerState.STOPPED_TOO_SLOW,
                lastError = "Model is slower than real time on this device (${"%.0f".format(ms)} ms per " +
                    "${"%.0f".format(spec.chunkDurationMs)} ms chunk). Using DSP instead.",
            )
            return false
        }
        return true
    }

    private fun sleep(ms: Long) {
        try {
            Thread.sleep(ms)
        } catch (_: InterruptedException) {
            running.set(false)
        }
    }
}
