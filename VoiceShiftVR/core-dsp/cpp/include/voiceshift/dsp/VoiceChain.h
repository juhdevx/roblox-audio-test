#pragma once

#include <memory>

#include "voiceshift/dsp/Analysis.h"
#include "voiceshift/dsp/Biquad.h"
#include "voiceshift/dsp/Dynamics.h"
#include "voiceshift/dsp/SpectralVoiceShifter.h"
#include "voiceshift/dsp/VoiceParams.h"

namespace voiceshift::dsp {

// Engine A: the complete DSP voice chain, split into three stages so the neural engine can reuse the
// conditioning and output stages around its own transform.
//
//   input stage : low cut -> noise gate -> AGC
//   transform   : SpectralVoiceShifter (noise reduction, pitch, formant, breathiness)
//   output stage: body / presence / air EQ -> compressor -> output gain -> limiter (-1 dBFS)
class VoiceChain {
public:
    VoiceChain(float sampleRate, int fftSize);

    void reset();
    // Cheap; call once per audio block before processing.
    void setParams(const VoiceParams& params);

    void processInputStage(float* data, int n);
    void processTransform(float* data, int n);
    void processOutputStage(float* data, int n);

    void processAll(float* data, int n) {
        processInputStage(data, n);
        processTransform(data, n);
        processOutputStage(data, n);
    }

    int latencySamples() const { return shifter_.latencySamples(); }
    float sampleRate() const { return sampleRate_; }
    bool gateOpen() const { return gate_.isOpen(); }
    float agcGainDb() const { return agc_.currentGainDb(); }
    float compressorReductionDb() const { return compressor_.gainReductionDb(); }
    float limiterReductionDb() const { return limiter_.gainReductionDb(); }
    // True (once) when the chain produced NaN/Inf since the last call. The caller should reset().
    bool consumeFault() { return limiter_.consumeNonFinite(); }
    SpectralVoiceShifter& shifter() { return shifter_; }

private:
    void updateFilters(bool force);

    float sampleRate_;
    VoiceParams params_;
    VoiceParams appliedFilterParams_;
    bool filtersInitialised_ = false;

    Biquad lowCut_;
    NoiseGate gate_;
    AutomaticGainControl agc_;
    SpectralVoiceShifter shifter_;
    Biquad body_;
    Biquad presence_;
    Biquad air_;
    Compressor compressor_;
    Limiter limiter_;
    float outputGain_ = 1.0f;
    float appliedOutputGain_ = 1.0f;
};

}  // namespace voiceshift::dsp
