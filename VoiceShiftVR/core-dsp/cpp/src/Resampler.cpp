#include "voiceshift/dsp/Resampler.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

#include "voiceshift/dsp/Common.h"

namespace voiceshift::dsp {

Resampler::Resampler(double inputRate, double outputRate, int maxInputBlock, int zeroCrossings)
    : inRate_(inputRate), outRate_(outputRate) {
    if (inputRate <= 0.0 || outputRate <= 0.0) throw std::invalid_argument("Resampler: rates must be > 0");
    step_ = inRate_ / outRate_;
    // When decimating, lower the cutoff below the output Nyquist; leave a 5% transition band.
    cutoff_ = std::min(1.0, outRate_ / inRate_) * 0.95;
    halfTaps_ = static_cast<int>(std::ceil(zeroCrossings / cutoff_));
    phases_ = 256;

    const int tableSize = halfTaps_ * phases_ + 2;
    table_.resize(static_cast<size_t>(tableSize));
    for (int i = 0; i < tableSize; ++i) {
        const double x = static_cast<double>(i) / phases_;
        double v = 0.0;
        if (x < halfTaps_) {
            const double arg = kPiD * cutoff_ * x;
            const double sinc = x == 0.0 ? 1.0 : std::sin(arg) / arg;
            const double t = x / halfTaps_;  // 0..1
            const double window = 0.42 + 0.5 * std::cos(kPiD * t) + 0.08 * std::cos(2.0 * kPiD * t);
            v = cutoff_ * sinc * window;
        }
        table_[static_cast<size_t>(i)] = static_cast<float>(v);
    }

    buffer_.assign(static_cast<size_t>(maxInputBlock + 4 * halfTaps_ + 8), 0.0f);
    reset();
}

void Resampler::reset() {
    std::fill(buffer_.begin(), buffer_.end(), 0.0f);
    // Pre-roll of zeros so the first output can be centred on the first input sample.
    size_ = halfTaps_;
    pos_ = static_cast<double>(halfTaps_);
    dropped_ = 0;
}

float Resampler::kernel(double x) const {
    const double ax = std::fabs(x) * phases_;
    const int i = static_cast<int>(ax);
    if (i >= halfTaps_ * phases_) return 0.0f;
    const float frac = static_cast<float>(ax - i);
    const float a = table_[static_cast<size_t>(i)];
    const float b = table_[static_cast<size_t>(i + 1)];
    return a + frac * (b - a);
}

int Resampler::maxOutputFor(int inCount) const {
    return static_cast<int>(std::ceil((size_ + inCount) / step_)) + 2;
}

int Resampler::produce(float* out, int outCapacity) {
    int produced = 0;
    while (produced < outCapacity) {
        const int center = static_cast<int>(std::floor(pos_));
        if (center + halfTaps_ >= size_) break;  // need samples up to center + halfTaps_
        const double frac = pos_ - center;
        float acc = 0.0f;
        const int first = center - halfTaps_ + 1;
        for (int j = first; j <= center + halfTaps_; ++j) {
            acc += buffer_[static_cast<size_t>(j)] * kernel(static_cast<double>(j - center) - frac);
        }
        out[produced++] = acc;
        pos_ += step_;
    }
    return produced;
}

void Resampler::compact() {
    const int keepFrom = static_cast<int>(std::floor(pos_)) - halfTaps_ + 1;
    if (keepFrom <= 0) return;
    const int drop = std::min(keepFrom, size_);
    std::copy(buffer_.begin() + drop, buffer_.begin() + size_, buffer_.begin());
    size_ -= drop;
    pos_ -= drop;
}

int Resampler::process(const float* in, int inCount, float* out, int outCapacity) {
    int produced = 0;
    int consumed = 0;
    const int capacity = static_cast<int>(buffer_.size());
    while (consumed < inCount) {
        int space = capacity - size_;
        if (space <= 0) {
            // Output side is not draining: discard the oldest input to stay bounded.
            const int drop = std::min(size_, capacity / 4);
            std::copy(buffer_.begin() + drop, buffer_.begin() + size_, buffer_.begin());
            size_ -= drop;
            pos_ = std::max(static_cast<double>(halfTaps_), pos_ - drop);
            dropped_ += drop;
            space = capacity - size_;
        }
        const int n = std::min(space, inCount - consumed);
        std::copy(in + consumed, in + consumed + n, buffer_.begin() + size_);
        size_ += n;
        consumed += n;
        produced += produce(out + produced, outCapacity - produced);
        compact();
    }
    if (inCount == 0) {
        produced += produce(out + produced, outCapacity - produced);
        compact();
    }
    return produced;
}

}  // namespace voiceshift::dsp
