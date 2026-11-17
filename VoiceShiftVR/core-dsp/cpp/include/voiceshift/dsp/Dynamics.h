#pragma once

#include "voiceshift/dsp/Common.h"

namespace voiceshift::dsp {

// Downward expander / noise gate with hysteresis and hold. Zero latency.
class NoiseGate {
public:
    void prepare(float sampleRate);
    void reset();
    // thresholdDb <= -80 disables the gate.
    void setThresholdDb(float db) { thresholdDb_ = db; }
    void setRangeDb(float db) { rangeGain_ = dbToGain(db); }
    void process(float* data, int n);
    bool isOpen() const { return open_; }
    float currentGain() const { return gain_; }

private:
    float sampleRate_ = 48000.0f;
    float thresholdDb_ = -80.0f;
    float rangeGain_ = 0.03f;  // -30 dB when closed
    float envAttack_ = 0.0f, envRelease_ = 0.0f;
    float gainOpenCoeff_ = 0.0f, gainCloseCoeff_ = 0.0f;
    float env_ = 0.0f;
    float gain_ = 1.0f;
    int holdSamples_ = 0;
    int holdCounter_ = 0;
    bool open_ = true;
};

// Slow automatic gain control. Only adapts while the gate reports speech, so it does not pump up
// background noise between phrases.
class AutomaticGainControl {
public:
    void prepare(float sampleRate);
    void reset();
    void setEnabled(bool enabled) { enabled_ = enabled; }
    void setTargetDb(float db) { targetDb_ = db; }
    void setLimitsDb(float minDb, float maxDb) { minGainDb_ = minDb; maxGainDb_ = maxDb; }
    void process(float* data, int n, bool speechPresent);
    float currentGainDb() const { return gainDb_; }

private:
    float sampleRate_ = 48000.0f;
    bool enabled_ = false;
    float targetDb_ = -20.0f;
    float minGainDb_ = -12.0f;
    float maxGainDb_ = 18.0f;
    float msCoeff_ = 0.0f;
    float meanSquare_ = 0.0f;
    float gainDb_ = 0.0f;
    float appliedGain_ = 1.0f;
};

// Feed-forward soft-knee compressor driven by a single "amount" control in [0, 1].
class Compressor {
public:
    void prepare(float sampleRate);
    void reset();
    void setAmount(float amount);
    void process(float* data, int n);
    float gainReductionDb() const { return lastReductionDb_; }
    float thresholdDb() const { return thresholdDb_; }
    float ratio() const { return ratio_; }
    // Static gain curve in dB (negative = reduction), exposed for tests.
    float computeGainDb(float levelDb) const;

private:
    float sampleRate_ = 48000.0f;
    float amount_ = 0.0f;
    float thresholdDb_ = 0.0f;
    float ratio_ = 1.0f;
    float kneeDb_ = 6.0f;
    float makeupDb_ = 0.0f;
    float attackCoeff_ = 0.0f, releaseCoeff_ = 0.0f;
    float env_ = 0.0f;
    float lastReductionDb_ = 0.0f;
};

// Peak limiter with instantaneous attack: |output| never exceeds the ceiling.
class Limiter {
public:
    void prepare(float sampleRate);
    void reset();
    void setCeilingDb(float db) { ceiling_ = dbToGain(db); }
    void process(float* data, int n);
    float gainReductionDb() const { return lastReductionDb_; }
    float ceiling() const { return ceiling_; }
    // True (once) if NaN/Inf reached the limiter since the last call; such samples are output as 0.
    bool consumeNonFinite() {
        const bool seen = sawNonFinite_;
        sawNonFinite_ = false;
        return seen;
    }

private:
    bool sawNonFinite_ = false;
    float ceiling_ = 0.891f;  // -1 dBFS
    float releaseCoeff_ = 0.0f;
    float env_ = 0.0f;
    float lastReductionDb_ = 0.0f;
};

}  // namespace voiceshift::dsp
