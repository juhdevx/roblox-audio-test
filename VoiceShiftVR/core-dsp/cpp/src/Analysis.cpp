#include "voiceshift/dsp/Analysis.h"

#include <algorithm>
#include <cmath>

namespace voiceshift::dsp {

BlockLevels measureBlock(const float* data, int n) {
    BlockLevels levels;
    if (n <= 0) return levels;
    double sum = 0.0;
    for (int i = 0; i < n; ++i) {
        const float a = std::fabs(data[i]);
        levels.peak = std::max(levels.peak, a);
        sum += static_cast<double>(data[i]) * data[i];
    }
    levels.rms = static_cast<float>(std::sqrt(sum / n));
    return levels;
}

// ---------------------------------------------------------------- LevelMeter

void LevelMeter::prepare(float sampleRate) {
    sampleRate_ = sampleRate;
    reset();
}

void LevelMeter::reset() {
    peak_ = 0.0f;
    meanSquare_ = 0.0f;
}

void LevelMeter::process(const float* data, int n) {
    if (n <= 0) return;
    const BlockLevels levels = measureBlock(data, n);
    const float blockSeconds = static_cast<float>(n) / sampleRate_;
    const float release = std::exp(-blockSeconds / 0.3f);
    peak_ = std::max(levels.peak, peak_ * release);
    const float ms = levels.rms * levels.rms;
    meanSquare_ = ms > meanSquare_ ? ms : meanSquare_ * release + ms * (1.0f - release);
}

// ---------------------------------------------------------------- ToneGenerator

void ToneGenerator::generate(float* out, int n) {
    const double increment = 2.0 * kPiD * frequency_ / sampleRate_;
    for (int i = 0; i < n; ++i) {
        out[i] = amplitude_ * static_cast<float>(std::sin(phase_));
        phase_ += increment;
        if (phase_ > 2.0 * kPiD) phase_ -= 2.0 * kPiD;
    }
}

// ---------------------------------------------------------------- ToneDetector

void ToneDetector::prepare(float sampleRate, float frequency, int blockSize) {
    sampleRate_ = sampleRate;
    frequency_ = frequency;
    blockSize_ = std::max(64, blockSize);
    coeff_ = 2.0f * std::cos(kTwoPi * frequency_ / sampleRate_);
    reset();
}

void ToneDetector::reset() {
    s1_ = s2_ = 0.0f;
    energy_ = 0.0;
    count_ = 0;
    toneDb_ = -120.0f;
    snrDb_ = -120.0f;
}

void ToneDetector::process(const float* data, int n) {
    for (int i = 0; i < n; ++i) {
        const float x = data[i];
        const float s0 = x + coeff_ * s1_ - s2_;
        s2_ = s1_;
        s1_ = s0;
        energy_ += static_cast<double>(x) * x;
        if (++count_ >= blockSize_) {
            const double power = static_cast<double>(s1_) * s1_ + static_cast<double>(s2_) * s2_ -
                                 static_cast<double>(coeff_) * s1_ * s2_;
            // |X(f)| = A * N / 2 for a sine of amplitude A centred on the analysis frequency.
            const double amplitude = 2.0 * std::sqrt(std::max(power, 0.0)) / blockSize_;
            toneDb_ = gainToDb(static_cast<float>(amplitude));
            const double toneEnergy = amplitude * amplitude * 0.5 * blockSize_;
            const double rest = std::max(energy_ - toneEnergy, 1.0e-12);
            snrDb_ = static_cast<float>(10.0 * std::log10(std::max(toneEnergy, 1.0e-12) / rest));
            s1_ = s2_ = 0.0f;
            energy_ = 0.0;
            count_ = 0;
        }
    }
}

// ---------------------------------------------------------------- LatencyProbe

void LatencyProbe::prepare(float sampleRate) {
    sampleRate_ = sampleRate;
    period_ = static_cast<int64_t>(sampleRate);           // one burst per second
    burstLength_ = static_cast<int64_t>(0.002f * sampleRate);  // 2 ms
    reset();
}

void LatencyProbe::reset() {
    nextEmission_ = static_cast<int64_t>(sampleRate_ * 0.25f);
    pendingEmission_ = -1;
    noiseFloor_ = 0.001f;
    history_.fill(0.0f);
    count_ = 0;
}

void LatencyProbe::renderOutput(float* out, int n, int64_t frameIndex) {
    for (int i = 0; i < n; ++i) {
        const int64_t t = frameIndex + i;
        if (t >= nextEmission_ && t < nextEmission_ + burstLength_) {
            if (t == nextEmission_) pendingEmission_ = nextEmission_;
            // Sharp onset (starts at full amplitude) so the arrival time is unambiguous; linear decay.
            const float local = static_cast<float>(t - nextEmission_);
            const float env = 1.0f - local / static_cast<float>(burstLength_);
            out[i] = 0.5f * env * std::cos(kTwoPi * 2000.0f * local / sampleRate_);
        } else {
            out[i] = 0.0f;
        }
        if (t == nextEmission_ + burstLength_ - 1) nextEmission_ += period_;
    }
}

void LatencyProbe::analyzeInput(const float* in, int n, int64_t frameIndex) {
    for (int i = 0; i < n; ++i) {
        const int64_t t = frameIndex + i;
        const float a = std::fabs(in[i]);
        if (pendingEmission_ < 0) {
            // Track the quiet noise floor between bursts.
            noiseFloor_ = 0.999f * noiseFloor_ + 0.001f * a;
            continue;
        }
        const int64_t elapsed = t - pendingEmission_;
        if (elapsed < 0) continue;
        const float threshold = std::max(0.02f, 8.0f * noiseFloor_);
        if (a > threshold) {
            const float ms = 1000.0f * static_cast<float>(elapsed) / sampleRate_;
            history_[static_cast<size_t>(count_ % static_cast<int>(history_.size()))] = ms;
            ++count_;
            pendingEmission_ = -1;
        } else if (elapsed > static_cast<int64_t>(0.8f * sampleRate_)) {
            pendingEmission_ = -1;  // lost: no loopback or too quiet
        }
    }
}

float LatencyProbe::latencyMs() const {
    if (count_ == 0) return -1.0f;
    const int n = std::min(count_, static_cast<int>(history_.size()));
    std::array<float, 5> sorted = history_;
    std::sort(sorted.begin(), sorted.begin() + n);
    return sorted[static_cast<size_t>(n / 2)];
}

}  // namespace voiceshift::dsp
