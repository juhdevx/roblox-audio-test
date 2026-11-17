// Signal generators and measurements shared by the native tests.
#pragma once

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdint>
#include <vector>

#include "voiceshift/dsp/Biquad.h"
#include "voiceshift/dsp/Common.h"
#include "voiceshift/dsp/Fft.h"

namespace vstest {

using voiceshift::dsp::kPiD;

inline std::vector<float> sine(float freq, float amplitude, int n, float sr, double phase = 0.0) {
    std::vector<float> out(static_cast<size_t>(n));
    for (int i = 0; i < n; ++i) {
        out[static_cast<size_t>(i)] = amplitude * static_cast<float>(std::sin(2.0 * kPiD * freq * i / sr + phase));
    }
    return out;
}

inline std::vector<float> noise(int n, float amplitude, uint32_t seed = 12345u) {
    std::vector<float> out(static_cast<size_t>(n));
    uint32_t s = seed;
    for (int i = 0; i < n; ++i) {
        s = s * 1664525u + 1013904223u;
        out[static_cast<size_t>(i)] = amplitude * (static_cast<float>(s >> 8) / 8388608.0f - 1.0f);
    }
    return out;
}

// Glottal-pulse-like train at f0 shaped by two formant resonators: a crude but deterministic voice.
inline std::vector<float> syntheticVowel(float f0, float formant1, float formant2, int n, float sr) {
    std::vector<float> src(static_cast<size_t>(n), 0.0f);
    double phase = 0.0;
    for (int i = 0; i < n; ++i) {
        phase += f0 / sr;
        if (phase >= 1.0) {
            phase -= 1.0;
            src[static_cast<size_t>(i)] = 1.0f;
        }
    }
    using namespace voiceshift::dsp;
    Biquad r1, r2, tilt;
    r1.setCoeffs(designBiquad(BiquadType::BandPass, sr, formant1, 6.0f));
    r2.setCoeffs(designBiquad(BiquadType::BandPass, sr, formant2, 8.0f));
    tilt.setCoeffs(designBiquad(BiquadType::LowPass, sr, 4000.0f, 0.707f));
    std::vector<float> out(static_cast<size_t>(n));
    for (int i = 0; i < n; ++i) {
        const float x = src[static_cast<size_t>(i)];
        out[static_cast<size_t>(i)] = tilt.process(r1.process(x) + 0.5f * r2.process(x));
    }
    float peak = 0.0f;
    for (float v : out) peak = std::max(peak, std::fabs(v));
    for (float& v : out) v *= 0.5f / std::max(peak, 1e-9f);
    return out;
}

inline double rms(const float* x, int n) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += static_cast<double>(x[i]) * x[i];
    return std::sqrt(s / std::max(n, 1));
}

inline double rmsDb(const float* x, int n) { return 20.0 * std::log10(std::max(rms(x, n), 1e-12)); }

// Averaged Hann-windowed magnitude spectrum (Welch), size/2+1 bins.
inline std::vector<double> averagedSpectrum(const float* x, int n, int size) {
    voiceshift::dsp::Fft fft(size);
    std::vector<double> acc(static_cast<size_t>(size / 2 + 1), 0.0);
    std::vector<std::complex<float>> buf(static_cast<size_t>(size));
    int frames = 0;
    for (int start = 0; start + size <= n; start += size / 2) {
        for (int i = 0; i < size; ++i) {
            const float w = 0.5f - 0.5f * static_cast<float>(std::cos(2.0 * kPiD * i / size));
            buf[static_cast<size_t>(i)] = {x[start + i] * w, 0.0f};
        }
        fft.forward(buf.data());
        for (int k = 0; k <= size / 2; ++k) acc[static_cast<size_t>(k)] += std::abs(buf[static_cast<size_t>(k)]);
        ++frames;
    }
    for (double& v : acc) v /= std::max(frames, 1);
    return acc;
}

// Frequency of the strongest spectral peak in [minHz, maxHz] with parabolic interpolation.
inline double dominantFrequency(const float* x, int n, float sr, double minHz, double maxHz, int size = 8192) {
    const std::vector<double> spec = averagedSpectrum(x, n, size);
    const double binHz = sr / size;
    int best = static_cast<int>(minHz / binHz);
    for (int k = static_cast<int>(minHz / binHz); k <= static_cast<int>(maxHz / binHz); ++k) {
        if (spec[static_cast<size_t>(k)] > spec[static_cast<size_t>(best)]) best = k;
    }
    const double a = std::log(spec[static_cast<size_t>(best - 1)] + 1e-12);
    const double b = std::log(spec[static_cast<size_t>(best)] + 1e-12);
    const double c = std::log(spec[static_cast<size_t>(best + 1)] + 1e-12);
    const double denom = a - 2 * b + c;
    const double offset = denom != 0.0 ? 0.5 * (a - c) / denom : 0.0;
    return (best + offset) * binHz;
}

// Fundamental via normalised autocorrelation within [minHz, maxHz].
inline double autocorrPitch(const float* x, int n, float sr, double minHz, double maxHz) {
    const int minLag = static_cast<int>(sr / maxHz);
    const int maxLag = static_cast<int>(sr / minHz);
    double bestR = -1.0;
    int bestLag = minLag;
    for (int lag = minLag; lag <= maxLag; ++lag) {
        double num = 0, e1 = 0, e2 = 0;
        for (int i = 0; i + lag < n; ++i) {
            num += static_cast<double>(x[i]) * x[i + lag];
            e1 += static_cast<double>(x[i]) * x[i];
            e2 += static_cast<double>(x[i + lag]) * x[i + lag];
        }
        const double r = num / std::sqrt(e1 * e2 + 1e-12);
        if (r > bestR) {
            bestR = r;
            bestLag = lag;
        }
    }
    return sr / bestLag;
}

// Peak of a heavily smoothed spectral envelope within [minHz, maxHz].
inline double envelopePeakHz(const float* x, int n, float sr, double minHz, double maxHz) {
    const int size = 4096;
    const std::vector<double> spec = averagedSpectrum(x, n, size);
    const double binHz = sr / size;
    // Smooth across ~250 Hz so individual harmonics disappear.
    const int radius = static_cast<int>(125.0 / binHz);
    double bestVal = -1.0;
    double bestHz = minHz;
    for (int k = static_cast<int>(minHz / binHz); k <= static_cast<int>(maxHz / binHz); ++k) {
        double s = 0.0;
        int count = 0;
        for (int j = std::max(0, k - radius); j <= std::min(size / 2, k + radius); ++j) {
            s += spec[static_cast<size_t>(j)];
            ++count;
        }
        s /= count;
        if (s > bestVal) {
            bestVal = s;
            bestHz = k * binHz;
        }
    }
    return bestHz;
}

}  // namespace vstest
