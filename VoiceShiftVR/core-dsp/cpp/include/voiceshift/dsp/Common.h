// VoiceShift VR — portable real-time DSP (C++17, no platform dependencies).
// Shared helpers. Everything in this library is allocation-free after construction and safe to call
// from a real-time audio callback unless a comment says otherwise.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace voiceshift::dsp {

constexpr double kPiD = 3.14159265358979323846;
constexpr float kPi = static_cast<float>(kPiD);
constexpr float kTwoPi = 2.0f * kPi;

inline float dbToGain(float db) { return std::pow(10.0f, db * 0.05f); }

inline float gainToDb(float gain, float floorDb = -120.0f) {
    return gain > 1.0e-6f ? 20.0f * std::log10(gain) : floorDb;
}

inline float powerToDb(float power, float floorDb = -120.0f) {
    return power > 1.0e-12f ? 10.0f * std::log10(power) : floorDb;
}

inline float semitonesToRatio(float semitones) { return std::exp2(semitones / 12.0f); }

inline float clampf(float v, float lo, float hi) { return std::min(std::max(v, lo), hi); }

// Coefficient c for y += (1 - c) * (x - y) so that y reaches ~63% of a step after timeMs.
inline float onePoleCoeff(float timeMs, float sampleRate) {
    if (timeMs <= 0.0f || sampleRate <= 0.0f) return 0.0f;
    return std::exp(-1000.0f / (timeMs * sampleRate));
}

// Wraps an angle into [-pi, pi].
inline float wrapPhase(float phase) {
    return phase - kTwoPi * std::round(phase / kTwoPi);
}

inline bool isPowerOfTwo(int n) { return n > 0 && (n & (n - 1)) == 0; }

}  // namespace voiceshift::dsp
