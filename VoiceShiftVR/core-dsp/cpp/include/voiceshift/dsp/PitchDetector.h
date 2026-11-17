#pragma once

#include <array>
#include <vector>

#include "voiceshift/dsp/Biquad.h"

namespace voiceshift::dsp {

// Real-time fundamental-frequency tracker (YIN, de Cheveigné & Kawahara 2002) for diagnostics and
// voice calibration. The input is low-passed and decimated to ~12 kHz, so a full analysis costs
// ~80k multiply-adds every 16 ms (well under 1 % of a phone core). Allocation happens in prepare().
class PitchDetector {
public:
    void prepare(float sampleRate, float minHz = 60.0f, float maxHz = 600.0f);
    void reset();
    void process(const float* data, int n);

    // Median of the recent voiced estimates in Hz, or 0 when the last frames were unvoiced/silent.
    float pitchHz() const { return pitchHz_; }
    // 0..1, 1 = perfectly periodic (1 - YIN dip of the last voiced frame).
    float confidence() const { return confidence_; }

private:
    void analyse();

    float inputRate_ = 48000.0f;
    float rate_ = 12000.0f;  // decimated rate
    int decimation_ = 4;
    int phase_ = 0;
    int window_ = 384;
    int tauMin_ = 20;
    int tauMax_ = 200;
    int hop_ = 192;
    int sinceAnalysis_ = 0;
    Biquad antiAlias1_, antiAlias2_;
    std::vector<float> buffer_;  // circular, size window_ + tauMax_
    int writePos_ = 0;
    int filled_ = 0;
    std::vector<float> frame_;
    std::vector<float> diff_;
    std::array<float, 5> recent_{};
    int recentCount_ = 0;
    int unvoicedFrames_ = 0;
    float pitchHz_ = 0.0f;
    float confidence_ = 0.0f;
};

}  // namespace voiceshift::dsp
