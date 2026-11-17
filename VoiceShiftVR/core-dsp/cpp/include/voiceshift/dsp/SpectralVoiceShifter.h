#pragma once

#include <complex>
#include <cstdint>
#include <vector>

#include "voiceshift/dsp/Fft.h"

namespace voiceshift::dsp {

// Real-time pitch and formant shifter for a single voice.
//
// Algorithm (per STFT frame, Hann window, 75% overlap):
//   1. Analysis FFT.
//   2. Optional spectral noise suppression (minimum-tracking noise floor + smoothed Wiener-style gain).
//   3. Spectral envelope estimate by cepstral smoothing (the "vocal tract" / formants).
//   4. Excitation = spectrum / envelope.
//   5. Pitch shift of the excitation with a peak-locked phase vocoder (Laroche & Dolson 1999):
//      each spectral peak region is moved to ratio * f_peak and its phases are rotated coherently.
//   6. Multiply by the envelope resampled by 1/formantRatio (formant shift independent of pitch).
//   7. Optional breathiness: envelope-shaped random-phase noise above ~1 kHz.
//   8. Inverse FFT and weighted overlap-add.
//
// Algorithmic latency is fftSize samples (2048 = 42.7 ms at 48 kHz in quality mode, 1024 = 21.3 ms in
// low-latency mode). 2048 resolves the harmonics of low (~85-120 Hz) voices; 1024 trades accuracy for delay.
// With pitchRatio == formantRatio == 1 and the extras disabled the output reconstructs the input.
class SpectralVoiceShifter {
public:
    SpectralVoiceShifter(int fftSize, float sampleRate);

    void reset();

    void setPitchRatio(float ratio);      // clamped to [0.5, 2.0]
    void setFormantRatio(float ratio);    // clamped to [0.7, 1.5]
    void setNoiseReduction(float amount); // [0, 1]
    void setBreathiness(float amount);    // [0, 1]
    // Parameters glide to their targets with this time constant (default 30 ms).
    void setSmoothingMs(float ms);
    // Snap all smoothed parameters to their targets (used after reset and in tests).
    void snapParameters();

    // Processes n samples. in and out may alias.
    void process(const float* in, float* out, int n);

    int fftSize() const { return n_; }
    int hopSize() const { return hop_; }
    int latencySamples() const { return n_; }
    float sampleRate() const { return sampleRate_; }

private:
    void processFrame();
    void updateNoiseReduction();
    void computeEnvelope();
    void findPeaks(float maxMag);
    float envelopeAt(float bin) const;

    const int n_;
    const int half_;
    const int hop_;
    const float sampleRate_;
    Fft fft_;

    std::vector<float> window_;
    float olaGain_ = 1.0f;
    float phasePerBin_ = 0.0f;  // expected phase advance per hop for bin 1: 2*pi*hop/N

    std::vector<float> inFifo_;
    std::vector<float> outFifo_;
    std::vector<float> outAccum_;
    int rover_ = 0;

    std::vector<std::complex<float>> frame_;
    std::vector<std::complex<float>> cepstrum_;
    std::vector<std::complex<float>> shifted_;
    std::vector<float> mag_;
    std::vector<float> phase_;
    std::vector<float> prevPhase_;
    std::vector<float> synPhase_;
    std::vector<float> trueBin_;
    std::vector<float> envelope_;
    std::vector<float> lifter_;
    std::vector<float> smoothedPower_;
    std::vector<float> noiseFloor_;
    std::vector<float> nrGain_;
    std::vector<int> peaks_;
    std::vector<int> boundaries_;
    bool noiseInitialised_ = false;
    bool firstFrame_ = true;
    float noiseRisePerFrame_ = 1.0f;

    float targetPitch_ = 1.0f, pitch_ = 1.0f;
    float targetFormant_ = 1.0f, formant_ = 1.0f;
    float targetNr_ = 0.0f, nr_ = 0.0f;
    float targetBreath_ = 0.0f, breath_ = 0.0f;
    float paramSmoothing_ = 1.0f;  // per-frame interpolation factor
    uint32_t rng_ = 0x9E3779B9u;
};

}  // namespace voiceshift::dsp
