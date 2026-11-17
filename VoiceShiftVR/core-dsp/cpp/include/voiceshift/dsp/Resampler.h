#pragma once

#include <vector>

namespace voiceshift::dsp {

// Streaming band-limited resampler (Blackman-windowed sinc, table-interpolated kernel) for arbitrary
// rate pairs, e.g. 48 kHz engine audio <-> 16/24/40 kHz neural-model audio.
//
// process() appends input to an internal fixed-size buffer and emits every output sample whose
// kernel support is fully available. Construction allocates; process() does not.
class Resampler {
public:
    Resampler(double inputRate, double outputRate, int maxInputBlock = 4096, int zeroCrossings = 16);

    void reset();

    // Returns the number of output samples written (<= outCapacity). Input that cannot be consumed
    // yet stays buffered; if the internal buffer would overflow, the oldest samples are dropped and
    // counted in droppedInputSamples().
    int process(const float* in, int inCount, float* out, int outCapacity);

    double inputRate() const { return inRate_; }
    double outputRate() const { return outRate_; }
    // Group delay in input samples.
    int latencyInputSamples() const { return halfTaps_; }
    long long droppedInputSamples() const { return dropped_; }
    // Upper bound on the outputs produced by feeding inCount more samples.
    int maxOutputFor(int inCount) const;

private:
    float kernel(double x) const;
    int produce(float* out, int outCapacity);
    void compact();

    double inRate_;
    double outRate_;
    double step_;     // input samples advanced per output sample
    double cutoff_;   // normalised to the input Nyquist (<= 1)
    int halfTaps_;    // kernel half-width in input samples
    int phases_;
    std::vector<float> table_;  // kernel sampled at x = i / phases_, i in [0, halfTaps_ * phases_ + 1]
    std::vector<float> buffer_;
    int size_ = 0;
    double pos_ = 0.0;  // fractional index (in buffer_) of the next output's centre
    long long dropped_ = 0;
};

}  // namespace voiceshift::dsp
