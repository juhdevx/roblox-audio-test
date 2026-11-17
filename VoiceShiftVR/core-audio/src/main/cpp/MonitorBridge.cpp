#include "MonitorBridge.h"

#include <algorithm>

namespace voiceshift::audio {

MonitorBridge::MonitorBridge(float sampleRate)
    : ring_(static_cast<size_t>(sampleRate / 4)),  // 250 ms of headroom
      targetFrames_(static_cast<int>(sampleRate * 0.010f)),
      rampStep_(1.0f / (0.010f * sampleRate)) {}

void MonitorBridge::push(const float* data, int n) {
    const size_t written = ring_.write(data, static_cast<size_t>(n));
    if (written < static_cast<size_t>(n)) {
        overflows_.fetch_add(n - static_cast<int64_t>(written), std::memory_order_relaxed);
    }
}

void MonitorBridge::pull(float* out, int n, float gainLinear) {
    const int target = targetFrames_.load(std::memory_order_relaxed);
    int available = static_cast<int>(ring_.availableToRead());

    if (!primed_) {
        if (available < target + n) {
            std::fill(out, out + n, 0.0f);
            return;
        }
        primed_ = true;
    }

    // Producer clock faster than ours: drop the excess so monitoring latency stays bounded.
    const int ceiling = 3 * target + 2 * n;
    if (available > ceiling) {
        ring_.skip(static_cast<size_t>(available - target - n));
        driftCorrections_.fetch_add(1, std::memory_order_relaxed);
        available = static_cast<int>(ring_.availableToRead());
    }

    const int got = static_cast<int>(ring_.read(out, static_cast<size_t>(n)));
    if (got < n) {
        // Our clock is faster (or the main stream stalled): pad and re-prime.
        std::fill(out + got, out + n, 0.0f);
        underruns_.fetch_add(1, std::memory_order_relaxed);
        primed_ = false;
    }

    for (int i = 0; i < n; ++i) {
        gain_ = gainLinear > gain_ ? std::min(gainLinear, gain_ + rampStep_) : std::max(gainLinear, gain_ - rampStep_);
        out[i] *= gain_;
    }
}

}  // namespace voiceshift::audio
