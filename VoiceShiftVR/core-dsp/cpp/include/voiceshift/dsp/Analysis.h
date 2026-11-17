#pragma once

#include <array>
#include <cstdint>

#include "voiceshift/dsp/Common.h"

namespace voiceshift::dsp {

struct BlockLevels {
    float peak = 0.0f;
    float rms = 0.0f;
};

BlockLevels measureBlock(const float* data, int n);

// Peak/RMS meter with fast attack and ~300 ms release, reported in dBFS.
class LevelMeter {
public:
    void prepare(float sampleRate);
    void reset();
    void process(const float* data, int n);
    float peakDb() const { return gainToDb(peak_); }
    float rmsDb() const { return powerToDb(meanSquare_); }

private:
    float sampleRate_ = 48000.0f;
    float peak_ = 0.0f;
    float meanSquare_ = 0.0f;
};

// Sine test-tone generator (route verification, level calibration).
class ToneGenerator {
public:
    void prepare(float sampleRate) { sampleRate_ = sampleRate; phase_ = 0.0; }
    void setFrequency(float hz) { frequency_ = hz; }
    void setLevelDb(float db) { amplitude_ = dbToGain(db); }
    void generate(float* out, int n);

private:
    float sampleRate_ = 48000.0f;
    float frequency_ = 1000.0f;
    float amplitude_ = 0.125f;  // -18 dBFS
    double phase_ = 0.0;
};

// Goertzel detector for a single tone. Used on the receiving end of a route (e.g. the Quest probe
// listening for the phone's 1 kHz test tone) to separate "device recognised" from "signal arrives".
class ToneDetector {
public:
    void prepare(float sampleRate, float frequency, int blockSize = 2048);
    void reset();
    void process(const float* data, int n);
    // Amplitude of the tone in dBFS (sine peak), from the last completed block.
    float toneDb() const { return toneDb_; }
    // Tone energy relative to everything else in the block.
    float snrDb() const { return snrDb_; }
    bool detected(float minToneDb = -60.0f, float minSnrDb = 10.0f) const {
        return toneDb_ > minToneDb && snrDb_ > minSnrDb;
    }

private:
    float sampleRate_ = 48000.0f;
    float frequency_ = 1000.0f;
    int blockSize_ = 2048;
    float coeff_ = 0.0f;
    float s1_ = 0.0f, s2_ = 0.0f;
    double energy_ = 0.0;
    int count_ = 0;
    float toneDb_ = -120.0f;
    float snrDb_ = -120.0f;
};

// Loopback round-trip latency measurement. Emits a short 2 kHz burst once per period on the output
// and timestamps its arrival on the input. Requires a physical/electrical loopback (or the phone's
// speaker reaching its microphone). Frame indices must come from the same duplex clock.
class LatencyProbe {
public:
    void prepare(float sampleRate);
    void reset();
    // Writes the probe signal (adds nothing outside a burst). frameIndex is the index of out[0].
    void renderOutput(float* out, int n, int64_t frameIndex);
    // Analyses captured input. frameIndex is the index of in[0] in the same clock as renderOutput.
    void analyzeInput(const float* in, int n, int64_t frameIndex);
    // Median of the last measurements in milliseconds, or -1 when nothing was measured yet.
    float latencyMs() const;
    int measurementCount() const { return count_; }

private:
    float sampleRate_ = 48000.0f;
    int64_t period_ = 48000;
    int64_t burstLength_ = 96;
    int64_t nextEmission_ = 0;
    int64_t pendingEmission_ = -1;
    float noiseFloor_ = 0.001f;
    std::array<float, 5> history_{};
    int count_ = 0;
};

}  // namespace voiceshift::dsp
