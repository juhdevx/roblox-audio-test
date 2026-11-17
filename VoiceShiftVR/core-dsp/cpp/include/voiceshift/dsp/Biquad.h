#pragma once

namespace voiceshift::dsp {

enum class BiquadType { LowPass, HighPass, BandPass, Peaking, LowShelf, HighShelf };

struct BiquadCoeffs {
    float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f, a1 = 0.0f, a2 = 0.0f;
};

// RBJ "Audio EQ Cookbook" designs. For shelves, q is the shelf Q (0.707 == slope S = 1).
BiquadCoeffs designBiquad(BiquadType type, float sampleRate, float frequency, float q, float gainDb = 0.0f);

// Magnitude response |H(e^{jw})| at the given frequency (used by tests and the UI).
float biquadMagnitude(const BiquadCoeffs& c, float sampleRate, float frequency);

// Transposed direct form II biquad.
class Biquad {
public:
    void setCoeffs(const BiquadCoeffs& c) { c_ = c; }
    const BiquadCoeffs& coeffs() const { return c_; }
    void reset() { z1_ = z2_ = 0.0f; }

    float process(float x) {
        const float y = c_.b0 * x + z1_;
        z1_ = c_.b1 * x - c_.a1 * y + z2_;
        z2_ = c_.b2 * x - c_.a2 * y;
        return y;
    }

    void process(float* data, int n) {
        for (int i = 0; i < n; ++i) data[i] = process(data[i]);
    }

private:
    BiquadCoeffs c_;
    float z1_ = 0.0f;
    float z2_ = 0.0f;
};

}  // namespace voiceshift::dsp
