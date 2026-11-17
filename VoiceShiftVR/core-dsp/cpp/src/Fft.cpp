#include "voiceshift/dsp/Fft.h"

#include <cmath>
#include <stdexcept>
#include <utility>

#include "voiceshift/dsp/Common.h"

namespace voiceshift::dsp {

Fft::Fft(int size) : n_(size) {
    if (!isPowerOfTwo(size) || size < 2) {
        throw std::invalid_argument("FFT size must be a power of two >= 2");
    }
    int bits = 0;
    while ((1 << bits) < n_) ++bits;

    bitReverse_.resize(static_cast<size_t>(n_));
    for (int i = 0; i < n_; ++i) {
        uint32_t r = 0;
        for (int b = 0; b < bits; ++b) {
            if (i & (1 << b)) r |= 1u << (bits - 1 - b);
        }
        bitReverse_[static_cast<size_t>(i)] = r;
    }

    twiddle_.resize(static_cast<size_t>(n_ / 2));
    for (int k = 0; k < n_ / 2; ++k) {
        const double angle = -2.0 * kPiD * static_cast<double>(k) / static_cast<double>(n_);
        twiddle_[static_cast<size_t>(k)] = {static_cast<float>(std::cos(angle)),
                                            static_cast<float>(std::sin(angle))};
    }
}

void Fft::forward(std::complex<float>* data) const { transform(data, false); }

void Fft::inverse(std::complex<float>* data) const { transform(data, true); }

void Fft::transform(std::complex<float>* data, bool inverse) const {
    for (int i = 0; i < n_; ++i) {
        const int j = static_cast<int>(bitReverse_[static_cast<size_t>(i)]);
        if (i < j) std::swap(data[i], data[j]);
    }

    const float sign = inverse ? -1.0f : 1.0f;
    for (int len = 2; len <= n_; len <<= 1) {
        const int half = len >> 1;
        const int step = n_ / len;
        for (int start = 0; start < n_; start += len) {
            for (int k = 0; k < half; ++k) {
                const std::complex<float>& w = twiddle_[static_cast<size_t>(k * step)];
                const float wr = w.real();
                const float wi = sign * w.imag();
                std::complex<float>& a = data[start + k];
                std::complex<float>& b = data[start + k + half];
                // Manual complex multiply: avoids the slow NaN-checking path of std::complex.
                const float vr = b.real() * wr - b.imag() * wi;
                const float vi = b.real() * wi + b.imag() * wr;
                const float ur = a.real();
                const float ui = a.imag();
                a = {ur + vr, ui + vi};
                b = {ur - vr, ui - vi};
            }
        }
    }

    if (inverse) {
        const float scale = 1.0f / static_cast<float>(n_);
        for (int i = 0; i < n_; ++i) data[i] *= scale;
    }
}

}  // namespace voiceshift::dsp
