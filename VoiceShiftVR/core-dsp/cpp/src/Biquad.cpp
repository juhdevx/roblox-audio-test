#include "voiceshift/dsp/Biquad.h"

#include <cmath>
#include <complex>

#include "voiceshift/dsp/Common.h"

namespace voiceshift::dsp {

BiquadCoeffs designBiquad(BiquadType type, float sampleRate, float frequency, float q, float gainDb) {
    const float f = clampf(frequency, 1.0f, 0.49f * sampleRate);
    const float qq = std::max(q, 0.05f);
    const double w0 = 2.0 * kPiD * f / sampleRate;
    const double cosw = std::cos(w0);
    const double sinw = std::sin(w0);
    const double alpha = sinw / (2.0 * qq);
    const double A = std::pow(10.0, gainDb / 40.0);
    const double sqrtA2alpha = 2.0 * std::sqrt(A) * alpha;

    double b0 = 1, b1 = 0, b2 = 0, a0 = 1, a1 = 0, a2 = 0;
    switch (type) {
        case BiquadType::LowPass:
            b0 = (1 - cosw) / 2; b1 = 1 - cosw; b2 = (1 - cosw) / 2;
            a0 = 1 + alpha; a1 = -2 * cosw; a2 = 1 - alpha;
            break;
        case BiquadType::HighPass:
            b0 = (1 + cosw) / 2; b1 = -(1 + cosw); b2 = (1 + cosw) / 2;
            a0 = 1 + alpha; a1 = -2 * cosw; a2 = 1 - alpha;
            break;
        case BiquadType::BandPass:
            b0 = alpha; b1 = 0; b2 = -alpha;
            a0 = 1 + alpha; a1 = -2 * cosw; a2 = 1 - alpha;
            break;
        case BiquadType::Peaking:
            b0 = 1 + alpha * A; b1 = -2 * cosw; b2 = 1 - alpha * A;
            a0 = 1 + alpha / A; a1 = -2 * cosw; a2 = 1 - alpha / A;
            break;
        case BiquadType::LowShelf:
            b0 = A * ((A + 1) - (A - 1) * cosw + sqrtA2alpha);
            b1 = 2 * A * ((A - 1) - (A + 1) * cosw);
            b2 = A * ((A + 1) - (A - 1) * cosw - sqrtA2alpha);
            a0 = (A + 1) + (A - 1) * cosw + sqrtA2alpha;
            a1 = -2 * ((A - 1) + (A + 1) * cosw);
            a2 = (A + 1) + (A - 1) * cosw - sqrtA2alpha;
            break;
        case BiquadType::HighShelf:
            b0 = A * ((A + 1) + (A - 1) * cosw + sqrtA2alpha);
            b1 = -2 * A * ((A - 1) + (A + 1) * cosw);
            b2 = A * ((A + 1) + (A - 1) * cosw - sqrtA2alpha);
            a0 = (A + 1) - (A - 1) * cosw + sqrtA2alpha;
            a1 = 2 * ((A - 1) - (A + 1) * cosw);
            a2 = (A + 1) - (A - 1) * cosw - sqrtA2alpha;
            break;
    }

    BiquadCoeffs c;
    c.b0 = static_cast<float>(b0 / a0);
    c.b1 = static_cast<float>(b1 / a0);
    c.b2 = static_cast<float>(b2 / a0);
    c.a1 = static_cast<float>(a1 / a0);
    c.a2 = static_cast<float>(a2 / a0);
    return c;
}

float biquadMagnitude(const BiquadCoeffs& c, float sampleRate, float frequency) {
    const double w = 2.0 * kPiD * frequency / sampleRate;
    const std::complex<double> z1 = std::polar(1.0, -w);
    const std::complex<double> z2 = std::polar(1.0, -2.0 * w);
    const std::complex<double> num = static_cast<double>(c.b0) + static_cast<double>(c.b1) * z1 +
                                     static_cast<double>(c.b2) * z2;
    const std::complex<double> den = 1.0 + static_cast<double>(c.a1) * z1 + static_cast<double>(c.a2) * z2;
    return static_cast<float>(std::abs(num / den));
}

}  // namespace voiceshift::dsp
