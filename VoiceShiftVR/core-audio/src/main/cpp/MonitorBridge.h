#pragma once

#include <atomic>
#include <cstdint>

#include "voiceshift/dsp/RingBuffer.h"

namespace voiceshift::audio {

// Carries the processed voice from the main output callback to a second, independent output
// stream (e.g. headphones for self-monitoring while the main output feeds the Quest cable).
//
// The two streams run on different hardware clocks, so the queue slowly fills or drains. The
// consumer keeps the fill near [targetFrames]: excess audio is skipped in one jump (counted as a
// drift correction) and an empty queue outputs silence until it is primed again (an underrun).
// Both sides are lock-free and allocation-free.
class MonitorBridge {
public:
    explicit MonitorBridge(float sampleRate);

    // Producer: main output callback.
    void push(const float* data, int n);

    // Consumer: monitor callback. Fills exactly n frames, applying gainLinear with a short ramp.
    void pull(float* out, int n, float gainLinear);

    void setTargetFrames(int frames) { targetFrames_.store(frames, std::memory_order_relaxed); }

    int64_t underruns() const { return underruns_.load(std::memory_order_relaxed); }
    int64_t driftCorrections() const { return driftCorrections_.load(std::memory_order_relaxed); }
    int64_t overflows() const { return overflows_.load(std::memory_order_relaxed); }
    int fillFrames() const { return static_cast<int>(ring_.availableToRead()); }

private:
    dsp::SpscRingBuffer<float> ring_;
    std::atomic<int> targetFrames_;
    bool primed_ = false;  // consumer-owned
    float gain_ = 0.0f;    // consumer-owned (ramped)
    float rampStep_;
    std::atomic<int64_t> underruns_{0};
    std::atomic<int64_t> driftCorrections_{0};
    std::atomic<int64_t> overflows_{0};
};

}  // namespace voiceshift::audio
