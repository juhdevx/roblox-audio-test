#include "voiceshift/dsp/VoiceChain.h"

#include <cmath>

namespace voiceshift::dsp {

VoiceChain::VoiceChain(float sampleRate, int fftSize)
    : sampleRate_(sampleRate), shifter_(fftSize, sampleRate) {
    gate_.prepare(sampleRate);
    gate_.setRangeDb(-30.0f);
    agc_.prepare(sampleRate);
    compressor_.prepare(sampleRate);
    limiter_.prepare(sampleRate);
    limiter_.setCeilingDb(-1.0f);
    setParams(params_);
    shifter_.snapParameters();
    updateFilters(true);
}

void VoiceChain::reset() {
    lowCut_.reset();
    gate_.reset();
    agc_.reset();
    shifter_.reset();
    body_.reset();
    presence_.reset();
    air_.reset();
    compressor_.reset();
    limiter_.reset();
    appliedOutputGain_ = outputGain_;
}

void VoiceChain::setParams(const VoiceParams& params) {
    params_ = params;
    gate_.setThresholdDb(params.get(kGateThresholdDb));
    agc_.setEnabled(params.get(kAgcEnabled) >= 0.5f);
    agc_.setTargetDb(params.get(kAgcTargetDb));
    shifter_.setPitchRatio(semitonesToRatio(params.get(kPitchSemitones)));
    shifter_.setFormantRatio(semitonesToRatio(params.get(kFormantSemitones)));
    shifter_.setNoiseReduction(params.get(kNoiseReduction));
    shifter_.setBreathiness(params.get(kBreathiness));
    compressor_.setAmount(params.get(kCompression));
    outputGain_ = dbToGain(params.get(kOutputGainDb));
    updateFilters(false);
}

void VoiceChain::updateFilters(bool force) {
    auto changed = [&](ParamId id) {
        return force || !filtersInitialised_ ||
               std::fabs(params_.get(id) - appliedFilterParams_.get(id)) > 1.0e-4f;
    };
    if (changed(kLowCutHz)) {
        lowCut_.setCoeffs(designBiquad(BiquadType::HighPass, sampleRate_, params_.get(kLowCutHz), 0.707f));
    }
    if (changed(kBodyDb)) {
        body_.setCoeffs(designBiquad(BiquadType::Peaking, sampleRate_, 220.0f, 1.0f, params_.get(kBodyDb)));
    }
    if (changed(kPresenceDb)) {
        presence_.setCoeffs(designBiquad(BiquadType::Peaking, sampleRate_, 3000.0f, 0.9f, params_.get(kPresenceDb)));
    }
    if (changed(kAirDb)) {
        air_.setCoeffs(designBiquad(BiquadType::HighShelf, sampleRate_, 8000.0f, 0.707f, params_.get(kAirDb)));
    }
    appliedFilterParams_ = params_;
    filtersInitialised_ = true;
}

void VoiceChain::processInputStage(float* data, int n) {
    lowCut_.process(data, n);
    gate_.process(data, n);
    agc_.process(data, n, gate_.isOpen());
}

void VoiceChain::processTransform(float* data, int n) { shifter_.process(data, data, n); }

void VoiceChain::processOutputStage(float* data, int n) {
    body_.process(data, n);
    presence_.process(data, n);
    air_.process(data, n);
    compressor_.process(data, n);
    if (n > 0) {
        const float delta = (outputGain_ - appliedOutputGain_) / static_cast<float>(n);
        float g = appliedOutputGain_;
        for (int i = 0; i < n; ++i) {
            g += delta;
            data[i] *= g;
        }
        appliedOutputGain_ = outputGain_;
    }
    limiter_.process(data, n);
}

}  // namespace voiceshift::dsp
