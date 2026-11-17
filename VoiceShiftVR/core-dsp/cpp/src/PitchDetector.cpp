#include "voiceshift/dsp/PitchDetector.h"

#include <algorithm>
#include <cmath>

#include "voiceshift/dsp/Common.h"

namespace voiceshift::dsp {

namespace {
constexpr float kYinThreshold = 0.15f;
constexpr float kMinRms = 0.003f;  // about -50 dBFS: quieter frames count as unvoiced
}  // namespace

void PitchDetector::prepare(float sampleRate, float minHz, float maxHz) {
    inputRate_ = sampleRate;
    decimation_ = std::max(1, static_cast<int>(std::lround(sampleRate / 12000.0f)));
    rate_ = sampleRate / static_cast<float>(decimation_);
    tauMin_ = std::max(2, static_cast<int>(rate_ / maxHz));
    tauMax_ = std::max(tauMin_ + 2, static_cast<int>(std::ceil(rate_ / minHz)));
    window_ = std::max(2 * tauMax_, static_cast<int>(0.032f * rate_));
    hop_ = std::max(16, static_cast<int>(0.016f * rate_));
    // Two cascaded 2nd-order low-passes at 0.2 x the decimated rate (2.4 kHz for 12 kHz) prevent
    // aliasing; voice fundamentals and their first harmonics stay well inside the passband.
    const BiquadCoeffs lp = designBiquad(BiquadType::LowPass, sampleRate, 0.2f * rate_, 0.707f);
    antiAlias1_.setCoeffs(lp);
    antiAlias2_.setCoeffs(lp);
    buffer_.assign(static_cast<size_t>(window_ + tauMax_), 0.0f);
    frame_.assign(buffer_.size(), 0.0f);
    diff_.assign(static_cast<size_t>(tauMax_ + 1), 0.0f);
    reset();
}

void PitchDetector::reset() {
    antiAlias1_.reset();
    antiAlias2_.reset();
    std::fill(buffer_.begin(), buffer_.end(), 0.0f);
    writePos_ = 0;
    filled_ = 0;
    phase_ = 0;
    sinceAnalysis_ = 0;
    recentCount_ = 0;
    unvoicedFrames_ = 0;
    pitchHz_ = 0.0f;
    confidence_ = 0.0f;
}

void PitchDetector::process(const float* data, int n) {
    const int size = static_cast<int>(buffer_.size());
    for (int i = 0; i < n; ++i) {
        const float y = antiAlias2_.process(antiAlias1_.process(data[i]));
        if (++phase_ < decimation_) continue;
        phase_ = 0;
        buffer_[static_cast<size_t>(writePos_)] = y;
        writePos_ = (writePos_ + 1) % size;
        filled_ = std::min(filled_ + 1, size);
        if (++sinceAnalysis_ >= hop_ && filled_ == size) {
            sinceAnalysis_ = 0;
            analyse();
        }
    }
}

void PitchDetector::analyse() {
    const int size = static_cast<int>(buffer_.size());
    // Unroll the circular buffer, oldest sample first.
    for (int i = 0; i < size; ++i) frame_[static_cast<size_t>(i)] = buffer_[static_cast<size_t>((writePos_ + i) % size)];

    double energy = 0.0;
    for (int j = 0; j < window_; ++j) energy += static_cast<double>(frame_[static_cast<size_t>(j)]) * frame_[static_cast<size_t>(j)];
    const bool loudEnough = std::sqrt(energy / window_) > kMinRms;

    float bestTau = -1.0f;
    float dip = 1.0f;
    if (loudEnough) {
        // Difference function d(tau) and its cumulative-mean-normalised form d'(tau).
        diff_[0] = 1.0f;
        double running = 0.0;
        for (int tau = 1; tau <= tauMax_; ++tau) {
            double d = 0.0;
            for (int j = 0; j < window_; ++j) {
                const double delta = static_cast<double>(frame_[static_cast<size_t>(j)]) - frame_[static_cast<size_t>(j + tau)];
                d += delta * delta;
            }
            running += d;
            diff_[static_cast<size_t>(tau)] = running > 0.0 ? static_cast<float>(d * tau / running) : 1.0f;
        }
        // First dip below the threshold, then walk to its local minimum.
        for (int tau = tauMin_; tau < tauMax_; ++tau) {
            if (diff_[static_cast<size_t>(tau)] < kYinThreshold) {
                while (tau + 1 < tauMax_ && diff_[static_cast<size_t>(tau + 1)] < diff_[static_cast<size_t>(tau)]) ++tau;
                const float a = diff_[static_cast<size_t>(tau - 1)];
                const float b = diff_[static_cast<size_t>(tau)];
                const float c = diff_[static_cast<size_t>(tau + 1)];
                const float denom = a - 2.0f * b + c;
                const float offset = std::fabs(denom) > 1e-9f ? 0.5f * (a - c) / denom : 0.0f;
                bestTau = static_cast<float>(tau) + clampf(offset, -0.5f, 0.5f);
                dip = b;
                break;
            }
        }
    }

    if (bestTau <= 0.0f) {
        // Hold the last value briefly across short unvoiced gaps (consonants), then report silence.
        if (++unvoicedFrames_ > 12) {
            pitchHz_ = 0.0f;
            confidence_ = 0.0f;
            recentCount_ = 0;
        }
        return;
    }
    unvoicedFrames_ = 0;
    const float hz = rate_ / bestTau;
    recent_[static_cast<size_t>(recentCount_ % static_cast<int>(recent_.size()))] = hz;
    ++recentCount_;
    const int count = std::min(recentCount_, static_cast<int>(recent_.size()));
    // Median of up to 5 values (insertion sort; avoids a GCC -Warray-bounds false positive in std::sort).
    std::array<float, 5> sorted = recent_;
    for (int i = 1; i < count; ++i) {
        const float v = sorted[static_cast<size_t>(i)];
        int j = i - 1;
        while (j >= 0 && sorted[static_cast<size_t>(j)] > v) {
            sorted[static_cast<size_t>(j + 1)] = sorted[static_cast<size_t>(j)];
            --j;
        }
        sorted[static_cast<size_t>(j + 1)] = v;
    }
    pitchHz_ = sorted[static_cast<size_t>(count / 2)];
    confidence_ = clampf(1.0f - dip, 0.0f, 1.0f);
}

}  // namespace voiceshift::dsp
