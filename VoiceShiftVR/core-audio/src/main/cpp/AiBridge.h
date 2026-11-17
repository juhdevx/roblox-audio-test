#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

#include "voiceshift/dsp/Resampler.h"
#include "voiceshift/dsp/RingBuffer.h"

namespace voiceshift::audio {

// Moves audio between the real-time callback (engine rate, e.g. 48 kHz) and the neural inference
// worker thread (model rate, e.g. 16/40 kHz) through bounded lock-free queues.
//
// Audio thread : pushInput() (downsample -> toWorker queue), pullOutput() (fromWorker -> upsample).
// Worker thread: workerRead() / workerWrite(). Samples carry 64-bit stream timestamps (model-rate
//                frame indices) so the worker can detect gaps and the engine can measure latency.
// pullOutput() returns false while priming or when the worker fell behind; the caller then plays its
// DSP fallback ("automatic safe bypass").
class AiBridge {
public:
    AiBridge(float engineRate, float modelRate, int maxBlock, int chunkModelFrames);

    // ---- audio thread
    void pushInput(const float* data, int n);
    bool pullOutput(float* out, int n);
    bool priming() const { return priming_; }

    // ---- worker thread
    int workerAvailable() const;
    int workerRead(float* dst, int maxFrames, int64_t* timestamp);
    int workerWrite(const float* src, int frames, int64_t timestamp);

    // ---- any thread (approximate diagnostics)
    float modelRate() const { return modelRate_; }
    int64_t inputOverflows() const { return inputOverflows_.load(std::memory_order_relaxed); }
    int64_t outputOverflows() const { return outputOverflows_.load(std::memory_order_relaxed); }
    int64_t underruns() const { return underruns_.load(std::memory_order_relaxed); }
    int64_t discontinuities() const { return discontinuities_.load(std::memory_order_relaxed); }
    float latencyMs() const { return latencyMs_.load(std::memory_order_relaxed); }

private:
    void drainWorkerOutput();

    const float engineRate_;
    const float modelRate_;
    const int chunkEngineFrames_;
    const int marginFrames_;

    dsp::Resampler down_;
    dsp::Resampler up_;
    dsp::SpscRingBuffer<float> toWorker_;
    dsp::SpscRingBuffer<float> fromWorker_;

    // Audio-thread-only scratch and FIFO (engine rate).
    std::vector<float> scratchModel_;
    std::vector<float> fifo_;
    int fifoCount_ = 0;
    bool priming_ = true;
    int primeDelayRemaining_ = 0;

    // Worker-thread-only.
    int64_t expectedOutTimestamp_ = -1;

    std::atomic<int64_t> outputTimestampEnd_{0};
    std::atomic<int64_t> inputOverflows_{0};
    std::atomic<int64_t> outputOverflows_{0};
    std::atomic<int64_t> underruns_{0};
    std::atomic<int64_t> discontinuities_{0};
    std::atomic<float> latencyMs_{0.0f};
};

}  // namespace voiceshift::audio
