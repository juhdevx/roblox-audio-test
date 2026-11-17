#include <atomic>
#include <complex>
#include <thread>
#include <vector>

#include "TestHarness.h"
#include "TestSignals.h"
#include "voiceshift/dsp/Analysis.h"
#include "voiceshift/dsp/Biquad.h"
#include "voiceshift/dsp/Dynamics.h"
#include "voiceshift/dsp/Fft.h"
#include "voiceshift/dsp/Resampler.h"
#include "voiceshift/dsp/RingBuffer.h"

using namespace voiceshift::dsp;
using namespace vstest;

TEST_CASE(fft_matches_naive_dft) {
    const int n = 64;
    std::vector<float> x = noise(n, 1.0f, 7u);
    std::vector<std::complex<float>> data(n);
    for (int i = 0; i < n; ++i) data[i] = {x[i], 0.5f * x[(i * 7) % n]};
    std::vector<std::complex<float>> input = data;
    Fft fft(n);
    fft.forward(data.data());
    double maxErr = 0.0;
    for (int k = 0; k < n; ++k) {
        std::complex<double> acc = 0.0;
        for (int t = 0; t < n; ++t) {
            acc += std::complex<double>(input[t].real(), input[t].imag()) *
                   std::polar(1.0, -2.0 * kPiD * k * t / n);
        }
        maxErr = std::max(maxErr, std::abs(acc - std::complex<double>(data[k].real(), data[k].imag())));
    }
    CHECK_LT(maxErr, 1e-4);
}

TEST_CASE(fft_inverse_round_trip) {
    const int n = 1024;
    std::vector<float> x = noise(n, 1.0f, 99u);
    std::vector<std::complex<float>> data(n);
    for (int i = 0; i < n; ++i) data[i] = {x[i], 0.0f};
    Fft fft(n);
    fft.forward(data.data());
    fft.inverse(data.data());
    double maxErr = 0.0;
    for (int i = 0; i < n; ++i) maxErr = std::max(maxErr, static_cast<double>(std::abs(data[i] - std::complex<float>(x[i], 0.0f))));
    CHECK_LT(maxErr, 1e-5);
}

TEST_CASE(ring_buffer_wraps_and_bounds) {
    SpscRingBuffer<int> rb(5);  // rounds up to 8
    CHECK(rb.capacity() == 8);
    int in[10];
    for (int i = 0; i < 10; ++i) in[i] = i;
    CHECK(rb.write(in, 10) == 8);  // bounded
    CHECK(rb.availableToRead() == 8);
    int out[10] = {};
    CHECK(rb.read(out, 3) == 3);
    CHECK(out[0] == 0 && out[2] == 2);
    CHECK(rb.write(in, 3) == 3);  // wraps
    CHECK(rb.read(out, 10) == 8);
    CHECK(out[0] == 3 && out[4] == 7 && out[5] == 0 && out[7] == 2);
    CHECK(rb.framesRead() == 11);
    CHECK(rb.framesWritten() == 11);
    CHECK(rb.peek(out, 1) == 0);
}

TEST_CASE(ring_buffer_threaded_order) {
    SpscRingBuffer<uint32_t> rb(1024);
    const uint32_t total = 2'000'000;
    std::atomic<bool> ok{true};
    std::thread consumer([&] {
        uint32_t expected = 0;
        uint32_t buf[257];
        while (expected < total) {
            const size_t n = rb.read(buf, 257);
            for (size_t i = 0; i < n; ++i) {
                if (buf[i] != expected++) ok = false;
            }
        }
    });
    uint32_t next = 0;
    uint32_t chunk[100];
    while (next < total) {
        const uint32_t count = std::min<uint32_t>(100, total - next);
        for (uint32_t i = 0; i < count; ++i) chunk[i] = next + i;
        size_t done = 0;
        while (done < count) done += rb.write(chunk + done, count - done);
        next += count;
    }
    consumer.join();
    CHECK(ok.load());
}

TEST_CASE(biquad_designs_have_expected_response) {
    const float sr = 48000.0f;
    const BiquadCoeffs hp = designBiquad(BiquadType::HighPass, sr, 100.0f, 0.707f);
    CHECK_NEAR(gainToDb(biquadMagnitude(hp, sr, 100.0f)), -3.01, 0.1);
    CHECK_LT(gainToDb(biquadMagnitude(hp, sr, 20.0f)), -25.0);
    CHECK_NEAR(gainToDb(biquadMagnitude(hp, sr, 2000.0f)), 0.0, 0.05);

    const BiquadCoeffs pk = designBiquad(BiquadType::Peaking, sr, 3000.0f, 0.9f, 6.0f);
    CHECK_NEAR(gainToDb(biquadMagnitude(pk, sr, 3000.0f)), 6.0, 0.05);
    CHECK_NEAR(gainToDb(biquadMagnitude(pk, sr, 100.0f)), 0.0, 0.2);

    const BiquadCoeffs hs = designBiquad(BiquadType::HighShelf, sr, 8000.0f, 0.707f, 4.0f);
    CHECK_NEAR(gainToDb(biquadMagnitude(hs, sr, 20000.0f)), 4.0, 0.3);
    CHECK_NEAR(gainToDb(biquadMagnitude(hs, sr, 200.0f)), 0.0, 0.1);

    // Time-domain processing agrees with the analytic magnitude.
    Biquad f;
    f.setCoeffs(pk);
    std::vector<float> x = sine(3000.0f, 0.1f, 48000, sr);
    f.process(x.data(), static_cast<int>(x.size()));
    CHECK_NEAR(rmsDb(x.data() + 24000, 24000) - (20 * std::log10(0.1 / std::sqrt(2.0))), 6.0, 0.1);
}

TEST_CASE(limiter_never_exceeds_ceiling) {
    Limiter lim;
    lim.prepare(48000.0f);
    lim.setCeilingDb(-1.0f);
    std::vector<float> x = sine(440.0f, 4.0f, 48000, 48000.0f);  // +12 dBFS
    std::vector<float> spikes = noise(48000, 8.0f, 3u);
    for (size_t i = 0; i < x.size(); i += 997) x[i] = spikes[i];
    lim.process(x.data(), static_cast<int>(x.size()));
    float peak = 0.0f;
    for (float v : x) peak = std::max(peak, std::fabs(v));
    CHECK(peak <= lim.ceiling() + 1e-6f);
    CHECK_LT(lim.gainReductionDb(), -5.0);
}

TEST_CASE(noise_gate_attenuates_quiet_passes_loud) {
    const float sr = 48000.0f;
    NoiseGate gate;
    gate.prepare(sr);
    gate.setThresholdDb(-45.0f);
    gate.setRangeDb(-30.0f);
    std::vector<float> quiet = noise(sr, 0.003f, 5u);  // about -55 dBFS RMS
    const double before = rmsDb(quiet.data() + 24000, 24000);
    gate.process(quiet.data(), static_cast<int>(quiet.size()));
    CHECK(!gate.isOpen());
    CHECK_LT(rmsDb(quiet.data() + 24000, 24000), before - 25.0);

    std::vector<float> loud = sine(200.0f, 0.3f, sr, sr);
    gate.process(loud.data(), static_cast<int>(loud.size()));
    CHECK(gate.isOpen());
    CHECK_NEAR(rmsDb(loud.data() + 24000, 24000), 20 * std::log10(0.3 / std::sqrt(2.0)), 0.2);
}

TEST_CASE(noise_gate_disabled_is_transparent) {
    NoiseGate gate;
    gate.prepare(48000.0f);
    gate.setThresholdDb(-80.0f);
    std::vector<float> x = noise(4800, 0.0005f, 9u);
    std::vector<float> y = x;
    gate.process(y.data(), static_cast<int>(y.size()));
    for (size_t i = 0; i < x.size(); ++i) CHECK_NEAR(y[i], x[i], 1e-9);
}

TEST_CASE(agc_converges_to_target) {
    const float sr = 48000.0f;
    AutomaticGainControl agc;
    agc.prepare(sr);
    agc.setEnabled(true);
    agc.setTargetDb(-20.0f);
    agc.setLimitsDb(-12.0f, 24.0f);
    std::vector<float> x = sine(300.0f, 0.02f, static_cast<int>(sr * 8), sr);  // ~ -37 dBFS RMS
    for (size_t off = 0; off < x.size(); off += 256) {
        agc.process(x.data() + off, 256, true);
    }
    CHECK_NEAR(rmsDb(x.data() + x.size() - 48000, 48000), -20.0, 1.5);
}

TEST_CASE(compressor_curve) {
    Compressor c;
    c.prepare(48000.0f);
    c.setAmount(0.0f);
    CHECK_NEAR(c.computeGainDb(0.0f), 0.0, 1e-6);
    c.setAmount(1.0f);
    CHECK_NEAR(c.thresholdDb(), -30.0, 1e-4);
    CHECK_NEAR(c.ratio(), 6.0, 1e-4);
    CHECK_NEAR(c.computeGainDb(-60.0f), 0.0, 1e-6);
    // 18 dB over threshold at 6:1 -> 15 dB of reduction.
    CHECK_NEAR(c.computeGainDb(-12.0f), -15.0, 1e-3);
    float prev = 1.0f;
    for (float l = -60.0f; l <= 0.0f; l += 0.5f) {
        const float out = l + c.computeGainDb(l);
        CHECK(out >= prev - 1e-4f || l == -60.0f);
        prev = out;
    }
}

TEST_CASE(resampler_down_and_up_preserve_tone) {
    const float hi = 48000.0f, lo = 16000.0f;
    std::vector<float> x = sine(1000.0f, 0.5f, 48000, hi);
    Resampler down(hi, lo, 512);
    std::vector<float> mid(20000);
    int produced = 0;
    for (size_t off = 0; off < x.size(); off += 480) {
        produced += down.process(x.data() + off, 480, mid.data() + produced, static_cast<int>(mid.size()) - produced);
    }
    CHECK_NEAR(produced, 16000, 40);
    CHECK_NEAR(dominantFrequency(mid.data() + 2000, 12000, lo, 500, 2000, 4096), 1000.0, 2.0);
    CHECK_NEAR(rmsDb(mid.data() + 2000, 12000), 20 * std::log10(0.5 / std::sqrt(2.0)), 0.2);

    Resampler up(lo, hi, 512);
    std::vector<float> back(60000);
    int backCount = 0;
    int fed = 0;
    for (int off = 0; off + 160 <= produced; off += 160) {
        backCount += up.process(mid.data() + off, 160, back.data() + backCount, static_cast<int>(back.size()) - backCount);
        fed += 160;
    }
    // Every fed sample yields 3 outputs, minus the kernel half-width still waiting for future input.
    CHECK_NEAR(backCount, fed * 3 - up.latencyInputSamples() * 3, 6);
    CHECK_NEAR(dominantFrequency(back.data() + 6000, 36000, hi, 500, 2000), 1000.0, 2.0);
    CHECK_NEAR(rmsDb(back.data() + 6000, 36000), 20 * std::log10(0.5 / std::sqrt(2.0)), 0.3);
    CHECK(down.droppedInputSamples() == 0);
}

TEST_CASE(resampler_rejects_aliasing) {
    std::vector<float> x = sine(12000.0f, 0.5f, 48000, 48000.0f);  // above the 8 kHz output Nyquist
    Resampler down(48000.0, 16000.0, 1024);
    std::vector<float> out(20000);
    int produced = 0;
    for (size_t off = 0; off < x.size(); off += 1000) {
        produced += down.process(x.data() + off, 1000, out.data() + produced, static_cast<int>(out.size()) - produced);
    }
    CHECK_LT(rmsDb(out.data() + 1000, produced - 1000), -60.0);
}

TEST_CASE(tone_detector_measures_level) {
    const float sr = 48000.0f;
    ToneDetector det;
    det.prepare(sr, 1000.0f, 2400);
    std::vector<float> x = sine(1000.0f, dbToGain(-18.0f), 24000, sr);
    std::vector<float> n = noise(24000, 0.001f, 4u);
    for (size_t i = 0; i < x.size(); ++i) x[i] += n[i];
    det.process(x.data(), static_cast<int>(x.size()));
    CHECK_NEAR(det.toneDb(), -18.0, 0.5);
    CHECK(det.detected());

    ToneDetector silent;
    silent.prepare(sr, 1000.0f, 2400);
    std::vector<float> only = noise(24000, 0.05f, 8u);
    silent.process(only.data(), static_cast<int>(only.size()));
    CHECK(!silent.detected());
}

TEST_CASE(latency_probe_measures_loopback_delay) {
    const float sr = 48000.0f;
    const int delay = 2345;
    LatencyProbe probe;
    probe.prepare(sr);
    std::vector<float> line(static_cast<size_t>(delay), 0.0f);  // delay line
    std::vector<float> out(192), in(192);
    size_t pos = 0;
    int64_t frame = 0;
    for (int block = 0; block < 2000; ++block) {
        probe.renderOutput(out.data(), 192, frame);
        for (int i = 0; i < 192; ++i) {
            in[static_cast<size_t>(i)] = line[pos] * 0.3f;
            line[pos] = out[static_cast<size_t>(i)];
            pos = (pos + 1) % line.size();
        }
        probe.analyzeInput(in.data(), 192, frame);
        frame += 192;
    }
    CHECK(probe.measurementCount() >= 5);
    CHECK_NEAR(probe.latencyMs(), 1000.0 * delay / sr, 0.25);
}

#include "voiceshift/dsp/PitchDetector.h"

namespace {
float detect(const std::vector<float>& x, float sr = 48000.0f) {
    PitchDetector d;
    d.prepare(sr);
    for (size_t off = 0; off < x.size(); off += 240) {
        d.process(x.data() + off, static_cast<int>(std::min<size_t>(240, x.size() - off)));
    }
    return d.pitchHz();
}
}  // namespace

TEST_CASE(pitch_detector_tracks_sines) {
    for (float f : {85.0f, 110.0f, 196.0f, 330.0f, 520.0f}) {
        CHECK_NEAR(detect(sine(f, 0.3f, 24000, 48000.0f)), f, f * 0.01);
    }
}

TEST_CASE(pitch_detector_tracks_voice_like_signal) {
    CHECK_NEAR(detect(syntheticVowel(118.0f, 650.0f, 1900.0f, 48000, 48000.0f)), 118.0, 2.0);
    CHECK_NEAR(detect(syntheticVowel(205.0f, 800.0f, 2300.0f, 48000, 48000.0f)), 205.0, 3.0);
}

TEST_CASE(pitch_detector_reports_zero_for_noise_and_silence) {
    CHECK(detect(std::vector<float>(48000, 0.0f)) == 0.0f);
    CHECK(detect(noise(48000, 0.3f, 17u)) == 0.0f);
}

TEST_CASE(pitch_detector_holds_then_releases_after_speech) {
    PitchDetector d;
    d.prepare(48000.0f);
    std::vector<float> v = sine(150.0f, 0.3f, 24000, 48000.0f);
    d.process(v.data(), static_cast<int>(v.size()));
    CHECK_NEAR(d.pitchHz(), 150.0, 1.5);
    CHECK(d.confidence() > 0.8f);
    std::vector<float> gap(4800, 0.0f);  // 100 ms consonant-like gap: value held
    d.process(gap.data(), static_cast<int>(gap.size()));
    CHECK_NEAR(d.pitchHz(), 150.0, 1.5);
    std::vector<float> silence(48000, 0.0f);  // 1 s of silence: released
    d.process(silence.data(), static_cast<int>(silence.size()));
    CHECK(d.pitchHz() == 0.0f);
}
