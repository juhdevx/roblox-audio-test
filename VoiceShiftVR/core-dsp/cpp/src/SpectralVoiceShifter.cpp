#include "voiceshift/dsp/SpectralVoiceShifter.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

#include "voiceshift/dsp/Common.h"

namespace voiceshift::dsp {

SpectralVoiceShifter::SpectralVoiceShifter(int fftSize, float sampleRate)
    : n_(fftSize),
      half_(fftSize / 2),
      hop_(fftSize / 4),
      sampleRate_(sampleRate),
      fft_(fftSize) {
    if (fftSize < 256 || !isPowerOfTwo(fftSize)) {
        throw std::invalid_argument("SpectralVoiceShifter: fftSize must be a power of two >= 256");
    }
    const size_t n = static_cast<size_t>(n_);
    const size_t bins = static_cast<size_t>(half_ + 1);

    window_.resize(n);
    double sumSquares = 0.0;
    for (int i = 0; i < n_; ++i) {
        const double w = 0.5 - 0.5 * std::cos(2.0 * kPiD * i / n_);  // periodic Hann
        window_[static_cast<size_t>(i)] = static_cast<float>(w);
        sumSquares += w * w;
    }
    // Analysis and synthesis both use the window, so overlap-add sums w^2 over hops.
    olaGain_ = static_cast<float>(hop_ / sumSquares);
    phasePerBin_ = static_cast<float>(2.0 * kPiD * hop_ / n_);

    inFifo_.assign(n, 0.0f);
    outFifo_.assign(n, 0.0f);
    outAccum_.assign(n, 0.0f);
    frame_.assign(n, {0.0f, 0.0f});
    cepstrum_.assign(n, {0.0f, 0.0f});
    shifted_.assign(bins, {0.0f, 0.0f});
    mag_.assign(bins, 0.0f);
    phase_.assign(bins, 0.0f);
    prevPhase_.assign(bins, 0.0f);
    synPhase_.assign(bins, 0.0f);
    trueBin_.assign(bins, 0.0f);
    envelope_.assign(bins, 1.0f);
    smoothedPower_.assign(bins, 0.0f);
    noiseFloor_.assign(bins, 0.0f);
    nrGain_.assign(bins, 1.0f);
    peaks_.reserve(bins);
    boundaries_.reserve(bins + 1);

    // Hann-shaped cepstral lifter reaching zero at 4 ms: keeps the formant structure and removes the
    // pitch harmonics of voices below ~250 Hz (quefrency 1/f0 >= 4 ms), i.e. typical source voices.
    const int L = std::clamp(static_cast<int>(std::lround(sampleRate_ * 0.004f)), 8, n_ / 4);
    lifter_.assign(n, 0.0f);
    for (int q = 0; q < n_; ++q) {
        const int qi = std::min(q, n_ - q);
        if (qi < L) {
            lifter_[static_cast<size_t>(q)] = 0.5f * (1.0f + std::cos(kPi * static_cast<float>(qi) / L));
        }
    }

    // Noise floor may rise by 4 dB per second (power domain).
    const float framesPerSecond = sampleRate_ / static_cast<float>(hop_);
    noiseRisePerFrame_ = std::pow(10.0f, 0.4f / framesPerSecond);

    setSmoothingMs(30.0f);
    reset();
}

void SpectralVoiceShifter::reset() {
    std::fill(inFifo_.begin(), inFifo_.end(), 0.0f);
    std::fill(outFifo_.begin(), outFifo_.end(), 0.0f);
    std::fill(outAccum_.begin(), outAccum_.end(), 0.0f);
    std::fill(prevPhase_.begin(), prevPhase_.end(), 0.0f);
    std::fill(synPhase_.begin(), synPhase_.end(), 0.0f);
    std::fill(nrGain_.begin(), nrGain_.end(), 1.0f);
    rover_ = n_ - hop_;
    firstFrame_ = true;
    noiseInitialised_ = false;
    snapParameters();
}

void SpectralVoiceShifter::setPitchRatio(float ratio) { targetPitch_ = clampf(ratio, 0.5f, 2.0f); }
void SpectralVoiceShifter::setFormantRatio(float ratio) { targetFormant_ = clampf(ratio, 0.7f, 1.5f); }
void SpectralVoiceShifter::setNoiseReduction(float amount) { targetNr_ = clampf(amount, 0.0f, 1.0f); }
void SpectralVoiceShifter::setBreathiness(float amount) { targetBreath_ = clampf(amount, 0.0f, 1.0f); }

void SpectralVoiceShifter::setSmoothingMs(float ms) {
    if (ms <= 0.0f) {
        paramSmoothing_ = 1.0f;
    } else {
        paramSmoothing_ = 1.0f - std::exp(-static_cast<float>(hop_) / (0.001f * ms * sampleRate_));
    }
}

void SpectralVoiceShifter::snapParameters() {
    pitch_ = targetPitch_;
    formant_ = targetFormant_;
    nr_ = targetNr_;
    breath_ = targetBreath_;
}

void SpectralVoiceShifter::process(const float* in, float* out, int n) {
    const int latency = n_ - hop_;  // FIFO offset; total input->output delay is n_ samples
    for (int i = 0; i < n; ++i) {
        const float x = in[i];
        inFifo_[static_cast<size_t>(rover_)] = x;
        out[i] = outFifo_[static_cast<size_t>(rover_ - latency)];
        ++rover_;
        if (rover_ >= n_) {
            rover_ = latency;
            processFrame();
        }
    }
}

float SpectralVoiceShifter::envelopeAt(float bin) const {
    if (bin <= 0.0f) return envelope_[0];
    if (bin >= static_cast<float>(half_)) return envelope_[static_cast<size_t>(half_)];
    const int i0 = static_cast<int>(bin);
    const float frac = bin - static_cast<float>(i0);
    const float a = envelope_[static_cast<size_t>(i0)];
    if (frac == 0.0f) return a;
    const float b = envelope_[static_cast<size_t>(i0 + 1)];
    return a + frac * (b - a);
}

void SpectralVoiceShifter::updateNoiseReduction() {
    for (int k = 0; k <= half_; ++k) {
        const size_t i = static_cast<size_t>(k);
        const float power = mag_[i] * mag_[i];
        if (!noiseInitialised_) {
            smoothedPower_[i] = power;
            noiseFloor_[i] = power;
        } else {
            smoothedPower_[i] = 0.7f * smoothedPower_[i] + 0.3f * power;
            if (smoothedPower_[i] < noiseFloor_[i]) {
                noiseFloor_[i] = 0.8f * noiseFloor_[i] + 0.2f * smoothedPower_[i];
            } else {
                noiseFloor_[i] *= noiseRisePerFrame_;
            }
        }
        noiseFloor_[i] = std::max(noiseFloor_[i], 1.0e-20f);
    }
    noiseInitialised_ = true;

    if (nr_ > 0.001f) {
        // A tracked minimum underestimates the mean noise power; kMinimumBias compensates (minimum
        // statistics), the rest is classic over-subtraction scaled by the user's amount.
        constexpr float kMinimumBias = 2.0f;
        const float overSubtraction = kMinimumBias * (1.0f + 1.5f * nr_);
        const float floorGain = dbToGain(-6.0f - 18.0f * nr_);
        for (int k = 0; k <= half_; ++k) {
            const size_t i = static_cast<size_t>(k);
            const float g = 1.0f - overSubtraction * noiseFloor_[i] / std::max(smoothedPower_[i], 1.0e-20f);
            const float gain = std::max(g > 0.0f ? std::sqrt(g) : 0.0f, floorGain);
            nrGain_[i] = 0.5f * nrGain_[i] + 0.5f * gain;  // temporal smoothing limits musical noise
        }
    } else {
        for (float& g : nrGain_) g = 0.5f * g + 0.5f;
    }

    for (int k = 0; k <= half_; ++k) {
        const size_t i = static_cast<size_t>(k);
        const float g = nrGain_[i];
        if (g != 1.0f) {
            mag_[i] *= g;
            frame_[i] *= g;
        }
    }
}

void SpectralVoiceShifter::computeEnvelope() {
    for (int k = 0; k <= half_; ++k) {
        cepstrum_[static_cast<size_t>(k)] = {std::log(std::max(mag_[static_cast<size_t>(k)], 1.0e-9f)), 0.0f};
    }
    for (int k = 1; k < half_; ++k) {
        cepstrum_[static_cast<size_t>(n_ - k)] = cepstrum_[static_cast<size_t>(k)];
    }
    fft_.inverse(cepstrum_.data());
    for (int q = 0; q < n_; ++q) {
        const size_t i = static_cast<size_t>(q);
        cepstrum_[i] = {cepstrum_[i].real() * lifter_[i], 0.0f};
    }
    fft_.forward(cepstrum_.data());

    float maxEnv = 0.0f;
    for (int k = 0; k <= half_; ++k) {
        const float e = std::exp(cepstrum_[static_cast<size_t>(k)].real());
        envelope_[static_cast<size_t>(k)] = e;
        maxEnv = std::max(maxEnv, e);
    }
    // Floor at -80 dB re. the strongest formant so excitation = spectrum / envelope stays bounded.
    const float floor = std::max(maxEnv * 1.0e-4f, 1.0e-12f);
    for (float& e : envelope_) e = std::max(e, floor);
}

void SpectralVoiceShifter::findPeaks(float maxMag) {
    peaks_.clear();
    boundaries_.clear();
    const float threshold = std::max(maxMag * 1.0e-4f, 1.0e-9f);
    for (int k = 1; k < half_; ++k) {
        const float m = mag_[static_cast<size_t>(k)];
        if (m <= threshold) continue;
        // Local maximum over +/-1 bin: closely spaced harmonics of low voices stay separate regions.
        if (m <= mag_[static_cast<size_t>(k - 1)] || m < mag_[static_cast<size_t>(k + 1)]) continue;
        peaks_.push_back(k);
    }
    if (peaks_.empty()) return;

    boundaries_.push_back(0);
    for (size_t i = 0; i + 1 < peaks_.size(); ++i) {
        int best = peaks_[i] + 1;
        float bestMag = mag_[static_cast<size_t>(best)];
        for (int k = peaks_[i] + 1; k < peaks_[i + 1]; ++k) {
            if (mag_[static_cast<size_t>(k)] < bestMag) {
                bestMag = mag_[static_cast<size_t>(k)];
                best = k;
            }
        }
        boundaries_.push_back(best);
    }
    boundaries_.push_back(half_ + 1);
}

void SpectralVoiceShifter::processFrame() {
    pitch_ += (targetPitch_ - pitch_) * paramSmoothing_;
    formant_ += (targetFormant_ - formant_) * paramSmoothing_;
    nr_ += (targetNr_ - nr_) * paramSmoothing_;
    breath_ += (targetBreath_ - breath_) * paramSmoothing_;

    // 1. Analysis.
    for (int k = 0; k < n_; ++k) {
        frame_[static_cast<size_t>(k)] = {inFifo_[static_cast<size_t>(k)] * window_[static_cast<size_t>(k)], 0.0f};
    }
    fft_.forward(frame_.data());
    float maxMag = 0.0f;
    for (int k = 0; k <= half_; ++k) {
        const size_t i = static_cast<size_t>(k);
        const float re = frame_[i].real();
        const float im = frame_[i].imag();
        mag_[i] = std::sqrt(re * re + im * im);
        phase_[i] = std::atan2(im, re);
        maxMag = std::max(maxMag, mag_[i]);
    }

    // 2. Noise suppression (also keeps the noise model warm while disabled).
    updateNoiseReduction();
    maxMag = 0.0f;
    for (int k = 0; k <= half_; ++k) maxMag = std::max(maxMag, mag_[static_cast<size_t>(k)]);

    // 3. Formant envelope.
    computeEnvelope();

    // 4. Instantaneous frequency of every bin, in bins.
    for (int k = 0; k <= half_; ++k) {
        const size_t i = static_cast<size_t>(k);
        if (firstFrame_) {
            trueBin_[i] = static_cast<float>(k);
        } else {
            const float delta = wrapPhase(phase_[i] - prevPhase_[i] - phasePerBin_ * static_cast<float>(k));
            trueBin_[i] = static_cast<float>(k) + delta / phasePerBin_;
        }
        prevPhase_[i] = phase_[i];
    }

    // 5. Peak-locked pitch shift of the excitation.
    std::fill(shifted_.begin(), shifted_.end(), std::complex<float>(0.0f, 0.0f));
    findPeaks(maxMag);
    const float ratio = pitch_;
    for (size_t r = 0; r < peaks_.size(); ++r) {
        const int p = peaks_[r];
        const float wp = trueBin_[static_cast<size_t>(p)];
        const float wShifted = wp * ratio;
        const int shift = static_cast<int>(std::lround(wShifted - wp));
        const int target = p + shift;
        if (target < 0 || target > half_) continue;

        const float theta = firstFrame_ ? phase_[static_cast<size_t>(p)]
                                        : synPhase_[static_cast<size_t>(target)] + phasePerBin_ * wShifted;
        const float rotation = theta - phase_[static_cast<size_t>(p)];
        const float cr = std::cos(rotation);
        const float si = std::sin(rotation);

        const int lo = boundaries_[r];
        const int hi = boundaries_[r + 1];
        for (int k = lo; k < hi; ++k) {
            const int dst = k + shift;
            if (dst < 0 || dst > half_) continue;
            const float inv = 1.0f / envelope_[static_cast<size_t>(k)];
            const float er = frame_[static_cast<size_t>(k)].real() * inv;
            const float ei = frame_[static_cast<size_t>(k)].imag() * inv;
            shifted_[static_cast<size_t>(dst)] += std::complex<float>(er * cr - ei * si, er * si + ei * cr);
        }
    }

    // Remember synthesis phases for the next frame (envelope gains are real, so they do not change phase).
    for (int k = 0; k <= half_; ++k) {
        const size_t i = static_cast<size_t>(k);
        const float re = shifted_[i].real();
        const float im = shifted_[i].imag();
        if (re * re + im * im > 1.0e-24f) {
            synPhase_[i] = std::atan2(im, re);
        } else {
            synPhase_[i] = wrapPhase(synPhase_[i] + phasePerBin_ * static_cast<float>(k));
        }
    }

    // 6. Re-apply the (optionally shifted) formant envelope.
    const float invFormant = 1.0f / formant_;
    for (int k = 0; k <= half_; ++k) {
        shifted_[static_cast<size_t>(k)] *= envelopeAt(static_cast<float>(k) * invFormant);
    }

    // 7. Breathiness: envelope-shaped noise, faded in from 1 kHz to 3.5 kHz.
    if (breath_ > 0.001f) {
        const float binHz = sampleRate_ / static_cast<float>(n_);
        const int k1 = std::max(1, static_cast<int>(1000.0f / binHz));
        const int k3 = std::max(k1 + 1, static_cast<int>(3500.0f / binHz));
        for (int k = k1; k < half_; ++k) {
            const float ramp = std::min(1.0f, static_cast<float>(k - k1) / static_cast<float>(k3 - k1));
            const float amp = breath_ * 0.5f * ramp * envelopeAt(static_cast<float>(k) * invFormant);
            rng_ ^= rng_ << 13;
            rng_ ^= rng_ >> 17;
            rng_ ^= rng_ << 5;
            const float angle = static_cast<float>(rng_) * (kTwoPi / 4294967296.0f);
            shifted_[static_cast<size_t>(k)] += std::complex<float>(amp * std::cos(angle), amp * std::sin(angle));
        }
    }

    // 8. Synthesis: Hermitian spectrum -> IFFT -> windowed overlap-add.
    frame_[0] = {shifted_[0].real(), 0.0f};
    frame_[static_cast<size_t>(half_)] = {shifted_[static_cast<size_t>(half_)].real(), 0.0f};
    for (int k = 1; k < half_; ++k) {
        frame_[static_cast<size_t>(k)] = shifted_[static_cast<size_t>(k)];
        frame_[static_cast<size_t>(n_ - k)] = std::conj(shifted_[static_cast<size_t>(k)]);
    }
    fft_.inverse(frame_.data());
    for (int k = 0; k < n_; ++k) {
        const size_t i = static_cast<size_t>(k);
        outAccum_[i] += frame_[i].real() * window_[i] * olaGain_;
    }

    std::copy(outAccum_.begin(), outAccum_.begin() + hop_, outFifo_.begin());
    std::copy(outAccum_.begin() + hop_, outAccum_.end(), outAccum_.begin());
    std::fill(outAccum_.end() - hop_, outAccum_.end(), 0.0f);
    std::copy(inFifo_.begin() + hop_, inFifo_.end(), inFifo_.begin());

    firstFrame_ = false;
}

}  // namespace voiceshift::dsp
