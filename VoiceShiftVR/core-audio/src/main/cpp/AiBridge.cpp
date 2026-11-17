#include "AiBridge.h"

#include <algorithm>
#include <cmath>

namespace voiceshift::audio {

namespace {
constexpr int kMarginMs = 25;
}

AiBridge::AiBridge(float engineRate, float modelRate, int maxBlock, int chunkModelFrames)
    : engineRate_(engineRate),
      modelRate_(modelRate),
      chunkEngineFrames_(static_cast<int>(std::ceil(chunkModelFrames * engineRate / modelRate))),
      marginFrames_(static_cast<int>(engineRate * kMarginMs / 1000)),
      down_(engineRate, modelRate, maxBlock),
      up_(modelRate, engineRate, maxBlock),
      // Two seconds of queue in each direction: plenty for jitter, small enough to stay bounded.
      toWorker_(static_cast<size_t>(modelRate * 2)),
      fromWorker_(static_cast<size_t>(modelRate * 2)) {
    scratchModel_.assign(static_cast<size_t>(down_.maxOutputFor(maxBlock) + maxBlock + 64), 0.0f);
    // Engine-rate FIFO: holds a few chunks of converted model output plus the priming margin.
    fifo_.assign(static_cast<size_t>(chunkEngineFrames_ * 4 + marginFrames_ + maxBlock * 4 + 4096), 0.0f);
}

void AiBridge::pushInput(const float* data, int n) {
    const int produced = down_.process(data, n, scratchModel_.data(), static_cast<int>(scratchModel_.size()));
    const size_t written = toWorker_.write(scratchModel_.data(), static_cast<size_t>(produced));
    if (written < static_cast<size_t>(produced)) {
        inputOverflows_.fetch_add(static_cast<int64_t>(produced) - static_cast<int64_t>(written),
                                  std::memory_order_relaxed);
    }
}

void AiBridge::drainWorkerOutput() {
    const double upRatio = static_cast<double>(engineRate_) / modelRate_;
    while (true) {
        const size_t available = fromWorker_.availableToRead();
        if (available == 0) break;
        const int space = static_cast<int>(fifo_.size()) - fifoCount_;
        // Leave room for the resampler's rounding and its buffered tail.
        const int maxTake = static_cast<int>(std::floor((space - 8) / upRatio)) - 4;
        if (maxTake <= 0) break;
        const int take = std::min({static_cast<int>(available), maxTake, static_cast<int>(scratchModel_.size())});
        const size_t got = fromWorker_.read(scratchModel_.data(), static_cast<size_t>(take));
        const int produced = up_.process(scratchModel_.data(), static_cast<int>(got), fifo_.data() + fifoCount_, space);
        fifoCount_ += produced;
    }
}

bool AiBridge::pullOutput(float* out, int n) {
    drainWorkerOutput();

    // Latency estimate: newest input timestamp minus the timestamp currently being played.
    const double upRatio = static_cast<double>(engineRate_) / modelRate_;
    const double played = static_cast<double>(outputTimestampEnd_.load(std::memory_order_acquire)) -
                          static_cast<double>(fromWorker_.availableToRead()) - fifoCount_ / upRatio -
                          up_.latencyInputSamples();
    const double newest = static_cast<double>(toWorker_.framesWritten()) + down_.latencyInputSamples() / upRatio;
    latencyMs_.store(static_cast<float>(std::max(0.0, newest - played) * 1000.0 / modelRate_),
                     std::memory_order_relaxed);

    if (priming_) {
        if (fifoCount_ < std::max(n, std::min(chunkEngineFrames_, static_cast<int>(fifo_.size()) / 2))) {
            return false;
        }
        if (primeDelayRemaining_ <= 0) primeDelayRemaining_ = marginFrames_;
        primeDelayRemaining_ -= n;
        if (primeDelayRemaining_ > 0) return false;
        priming_ = false;
    }

    if (fifoCount_ < n) {
        underruns_.fetch_add(1, std::memory_order_relaxed);
        priming_ = true;
        primeDelayRemaining_ = 0;
        return false;
    }

    std::copy(fifo_.begin(), fifo_.begin() + n, out);
    std::copy(fifo_.begin() + n, fifo_.begin() + fifoCount_, fifo_.begin());
    fifoCount_ -= n;
    return true;
}

int AiBridge::workerAvailable() const { return static_cast<int>(toWorker_.availableToRead()); }

int AiBridge::workerRead(float* dst, int maxFrames, int64_t* timestamp) {
    if (timestamp != nullptr) *timestamp = toWorker_.framesRead();
    return static_cast<int>(toWorker_.read(dst, static_cast<size_t>(std::max(0, maxFrames))));
}

int AiBridge::workerWrite(const float* src, int frames, int64_t timestamp) {
    if (frames <= 0) return 0;
    if (expectedOutTimestamp_ >= 0 && timestamp != expectedOutTimestamp_) {
        discontinuities_.fetch_add(1, std::memory_order_relaxed);
    }
    expectedOutTimestamp_ = timestamp + frames;
    const size_t written = fromWorker_.write(src, static_cast<size_t>(frames));
    if (written < static_cast<size_t>(frames)) {
        outputOverflows_.fetch_add(frames - static_cast<int64_t>(written), std::memory_order_relaxed);
    }
    outputTimestampEnd_.store(timestamp + static_cast<int64_t>(written), std::memory_order_release);
    return static_cast<int>(written);
}

}  // namespace voiceshift::audio
