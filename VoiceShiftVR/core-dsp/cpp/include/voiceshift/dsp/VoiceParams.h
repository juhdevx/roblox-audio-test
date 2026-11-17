#pragma once

#include <array>

namespace voiceshift::dsp {

// Parameter identifiers shared with Kotlin (com.voiceshift.dsp.VoiceParameter). The numeric values are
// part of the JNI contract: append new entries at the end, never renumber.
enum ParamId : int {
    kPitchSemitones = 0,
    kFormantSemitones = 1,
    kNoiseReduction = 2,
    kGateThresholdDb = 3,
    kAgcEnabled = 4,
    kAgcTargetDb = 5,
    kLowCutHz = 6,
    kBodyDb = 7,
    kPresenceDb = 8,
    kAirDb = 9,
    kCompression = 10,
    kBreathiness = 11,
    kOutputGainDb = 12,
    kParamCount = 13
};

struct ParamSpec {
    float minValue;
    float maxValue;
    float defaultValue;
};

// Ranges are deliberately conservative: intelligibility and naturalness over extreme effects.
inline constexpr std::array<ParamSpec, kParamCount> kParamSpecs = {{
    {-12.0f, 12.0f, 0.0f},    // pitch, semitones
    {-6.0f, 6.0f, 0.0f},      // formant shift, semitones (ratio 2^(x/12))
    {0.0f, 1.0f, 0.0f},       // spectral noise reduction amount
    {-80.0f, -20.0f, -80.0f}, // gate threshold dBFS (-80 = off)
    {0.0f, 1.0f, 0.0f},       // AGC enabled (0/1)
    {-30.0f, -10.0f, -20.0f}, // AGC target RMS dBFS
    {20.0f, 300.0f, 80.0f},   // input/output low cut, Hz
    {-12.0f, 6.0f, 0.0f},     // "body" peaking EQ at 220 Hz, dB
    {-6.0f, 9.0f, 0.0f},      // presence peaking EQ at 3 kHz, dB
    {-6.0f, 9.0f, 0.0f},      // air high shelf at 8 kHz, dB
    {0.0f, 1.0f, 0.0f},       // compression amount
    {0.0f, 1.0f, 0.0f},       // breathiness amount
    {-24.0f, 12.0f, 0.0f},    // output gain dB
}};

inline float clampParam(int id, float value) {
    if (id < 0 || id >= kParamCount) return value;
    const ParamSpec& s = kParamSpecs[static_cast<size_t>(id)];
    return value < s.minValue ? s.minValue : (value > s.maxValue ? s.maxValue : value);
}

struct VoiceParams {
    std::array<float, kParamCount> values{};

    VoiceParams() {
        for (int i = 0; i < kParamCount; ++i) values[static_cast<size_t>(i)] = kParamSpecs[static_cast<size_t>(i)].defaultValue;
    }

    float get(ParamId id) const { return values[static_cast<size_t>(id)]; }
    void set(int id, float v) {
        if (id >= 0 && id < kParamCount) values[static_cast<size_t>(id)] = clampParam(id, v);
    }
};

}  // namespace voiceshift::dsp
