#pragma once

#include <complex>
#include <cstdint>
#include <vector>

namespace voiceshift::dsp {

// Iterative radix-2 complex FFT. Construction allocates; transforms do not.
class Fft {
public:
    explicit Fft(int size);

    int size() const { return n_; }

    // In-place forward transform: X[k] = sum x[n] e^{-2 pi i k n / N}.
    void forward(std::complex<float>* data) const;

    // In-place inverse transform, scaled by 1/N so inverse(forward(x)) == x.
    void inverse(std::complex<float>* data) const;

private:
    void transform(std::complex<float>* data, bool inverse) const;

    int n_;
    std::vector<uint32_t> bitReverse_;
    std::vector<std::complex<float>> twiddle_;  // e^{-2 pi i k / N}, k < N/2
};

}  // namespace voiceshift::dsp
