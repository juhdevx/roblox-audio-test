#include "voiceshift/dsp/Dynamics.h"

#include <cmath>

namespace voiceshift::dsp {

// ---------------------------------------------------------------- NoiseGate

void NoiseGate::prepare(float sampleRate) {
    sampleRate_ = sampleRate;
    envAttack_ = onePoleCoeff(1.0f, sampleRate);
    envRelease_ = onePoleCoeff(50.0f, sampleRate);
    gainOpenCoeff_ = onePoleCoeff(2.0f, sampleRate);
    gainCloseCoeff_ = onePoleCoeff(80.0f, sampleRate);
    holdSamples_ = static_cast<int>(0.060f * sampleRate);
    reset();
}

void NoiseGate::reset() {
    env_ = 0.0f;
    gain_ = 1.0f;
    holdCounter_ = 0;
    open_ = true;
}

void NoiseGate::process(float* data, int n) {
    const bool enabled = thresholdDb_ > -79.9f;
    const float openLevel = dbToGain(thresholdDb_);
    const float closeLevel = dbToGain(thresholdDb_ - 4.0f);  // 4 dB hysteresis
    for (int i = 0; i < n; ++i) {
        const float a = std::fabs(data[i]);
        const float c = a > env_ ? envAttack_ : envRelease_;
        env_ = c * env_ + (1.0f - c) * a;

        if (!enabled) {
            open_ = true;
        } else if (env_ > openLevel) {
            open_ = true;
            holdCounter_ = holdSamples_;
        } else if (env_ < closeLevel) {
            if (holdCounter_ > 0) {
                --holdCounter_;
            } else {
                open_ = false;
            }
        }

        const float target = open_ ? 1.0f : rangeGain_;
        const float gc = target > gain_ ? gainOpenCoeff_ : gainCloseCoeff_;
        gain_ = target + gc * (gain_ - target);
        data[i] *= gain_;
    }
}

// ---------------------------------------------------------------- AutomaticGainControl

void AutomaticGainControl::prepare(float sampleRate) {
    sampleRate_ = sampleRate;
    msCoeff_ = onePoleCoeff(300.0f, sampleRate);
    reset();
}

void AutomaticGainControl::reset() {
    meanSquare_ = 0.0f;
    gainDb_ = 0.0f;
    appliedGain_ = 1.0f;
}

void AutomaticGainControl::process(float* data, int n, bool speechPresent) {
    if (n <= 0) return;
    for (int i = 0; i < n; ++i) {
        meanSquare_ = msCoeff_ * meanSquare_ + (1.0f - msCoeff_) * data[i] * data[i];
    }

    if (enabled_) {
        const float levelDb = powerToDb(meanSquare_);
        if (speechPresent && levelDb > -65.0f) {
            const float desired = clampf(targetDb_ - levelDb, minGainDb_, maxGainDb_);
            const float blockSeconds = static_cast<float>(n) / sampleRate_;
            if (desired < gainDb_) {
                gainDb_ = std::max(desired, gainDb_ - 20.0f * blockSeconds);  // fast reduction
            } else {
                gainDb_ = std::min(desired, gainDb_ + 4.0f * blockSeconds);   // slow recovery
            }
        }
    } else {
        // Glide back to unity when disabled instead of jumping.
        const float blockSeconds = static_cast<float>(n) / sampleRate_;
        const float step = 20.0f * blockSeconds;
        gainDb_ = gainDb_ > 0.0f ? std::max(0.0f, gainDb_ - step) : std::min(0.0f, gainDb_ + step);
    }

    const float target = dbToGain(gainDb_);
    const float delta = (target - appliedGain_) / static_cast<float>(n);
    float g = appliedGain_;
    for (int i = 0; i < n; ++i) {
        g += delta;
        data[i] *= g;
    }
    appliedGain_ = target;
}

// ---------------------------------------------------------------- Compressor

void Compressor::prepare(float sampleRate) {
    sampleRate_ = sampleRate;
    attackCoeff_ = onePoleCoeff(5.0f, sampleRate);
    releaseCoeff_ = onePoleCoeff(120.0f, sampleRate);
    setAmount(amount_);
    reset();
}

void Compressor::reset() {
    env_ = 0.0f;
    lastReductionDb_ = 0.0f;
}

void Compressor::setAmount(float amount) {
    amount_ = clampf(amount, 0.0f, 1.0f);
    thresholdDb_ = -10.0f - 20.0f * amount_;
    ratio_ = 1.0f + 5.0f * amount_;
    makeupDb_ = -thresholdDb_ * (1.0f - 1.0f / ratio_) * 0.4f;
}

float Compressor::computeGainDb(float levelDb) const {
    if (ratio_ <= 1.0001f) return 0.0f;
    const float over = levelDb - thresholdDb_;
    const float slope = 1.0f / ratio_ - 1.0f;
    if (2.0f * over < -kneeDb_) return 0.0f;
    if (2.0f * std::fabs(over) <= kneeDb_) {
        const float x = over + kneeDb_ * 0.5f;
        return slope * x * x / (2.0f * kneeDb_);
    }
    return slope * over;
}

void Compressor::process(float* data, int n) {
    if (amount_ < 0.001f) {
        lastReductionDb_ = 0.0f;
        return;
    }
    float maxReduction = 0.0f;
    for (int i = 0; i < n; ++i) {
        const float a = std::fabs(data[i]);
        const float c = a > env_ ? attackCoeff_ : releaseCoeff_;
        env_ = c * env_ + (1.0f - c) * a;
        const float gr = computeGainDb(gainToDb(env_));
        maxReduction = std::min(maxReduction, gr);
        data[i] *= dbToGain(gr + makeupDb_);
    }
    lastReductionDb_ = maxReduction;
}

// ---------------------------------------------------------------- Limiter

void Limiter::prepare(float sampleRate) {
    releaseCoeff_ = onePoleCoeff(60.0f, sampleRate);
    reset();
}

void Limiter::reset() {
    sawNonFinite_ = false;
    env_ = 0.0f;
    lastReductionDb_ = 0.0f;
}

void Limiter::process(float* data, int n) {
    float minGain = 1.0f;
    for (int i = 0; i < n; ++i) {
        float x = data[i];
        if (!std::isfinite(x)) {
            x = 0.0f;
            sawNonFinite_ = true;
        }
        const float a = std::fabs(x);
        env_ = std::max(a, env_ * releaseCoeff_);
        const float g = env_ > ceiling_ ? ceiling_ / env_ : 1.0f;
        minGain = std::min(minGain, g);
        data[i] = x * g;
    }
    lastReductionDb_ = gainToDb(minGain);
}

}  // namespace voiceshift::dsp
