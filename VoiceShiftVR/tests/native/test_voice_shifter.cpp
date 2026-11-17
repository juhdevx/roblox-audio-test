#include <vector>

#include "TestHarness.h"
#include "TestSignals.h"
#include "voiceshift/dsp/SpectralVoiceShifter.h"
#include "voiceshift/dsp/VoiceChain.h"

using namespace voiceshift::dsp;
using namespace vstest;

namespace {

std::vector<float> runShifter(SpectralVoiceShifter& s, std::vector<float> x, int block = 192) {
    for (size_t off = 0; off < x.size(); off += static_cast<size_t>(block)) {
        const int n = static_cast<int>(std::min<size_t>(static_cast<size_t>(block), x.size() - off));
        s.process(x.data() + off, x.data() + off, n);
    }
    return x;
}

}  // namespace

TEST_CASE(shifter_identity_reconstructs_input) {
    const float sr = 48000.0f;
    SpectralVoiceShifter s(1024, sr);
    CHECK(s.latencySamples() == 1024);
    std::vector<float> x = sine(220.0f, 0.3f, 48000, sr);
    std::vector<float> extra = sine(1730.0f, 0.1f, 48000, sr, 0.3);
    std::vector<float> n = noise(48000, 0.02f, 77u);
    for (size_t i = 0; i < x.size(); ++i) x[i] += extra[i] + n[i];
    const std::vector<float> y = runShifter(s, x, 131);  // odd block size on purpose
    const int latency = s.latencySamples();
    double err = 0.0, sig = 0.0;
    for (size_t i = 4096; i < x.size(); ++i) {
        const double d = y[i] - x[i - static_cast<size_t>(latency)];
        err += d * d;
        sig += static_cast<double>(x[i]) * x[i];
    }
    const double snrDb = 10.0 * std::log10(sig / std::max(err, 1e-20));
    CHECK(snrDb > 60.0);
    if (!(snrDb > 60.0)) std::printf("    identity SNR = %.2f dB\n", snrDb);
}

TEST_CASE(shifter_moves_sine_to_expected_frequency) {
    const float sr = 48000.0f;
    const float semitones[] = {4.0f, 7.0f, -3.0f, 12.0f};
    for (float st : semitones) {
        SpectralVoiceShifter s(1024, sr);
        s.setPitchRatio(semitonesToRatio(st));
        s.snapParameters();
        const std::vector<float> y = runShifter(s, sine(220.0f, 0.4f, 96000, sr));
        const double expected = 220.0 * semitonesToRatio(st);
        const double measured = dominantFrequency(y.data() + 9600, 80000, sr, 80, 2000);
        CHECK_NEAR(measured, expected, expected * 0.01);
    }
}

static void checkVoiceShift(int fftSize, float f0) {
    const float sr = 48000.0f;
    const std::vector<float> vowel = syntheticVowel(f0, 700.0f, 1800.0f, 96000, sr);
    SpectralVoiceShifter s(fftSize, sr);
    s.setPitchRatio(semitonesToRatio(5.0f));
    s.snapParameters();
    const std::vector<float> y = runShifter(s, vowel);
    const double measuredF0 = autocorrPitch(y.data() + 24000, 24000, sr, 80, 500);
    CHECK_NEAR(measuredF0, f0 * semitonesToRatio(5.0f), f0 * 0.03);
    const double inFormant = envelopePeakHz(vowel.data() + 24000, 48000, sr, 300, 1300);
    const double outFormant = envelopePeakHz(y.data() + 24000, 48000, sr, 300, 1300);
    CHECK_NEAR(outFormant, inFormant, inFormant * 0.15);
}

TEST_CASE(shifter_quality_mode_low_male_voice) { checkVoiceShift(2048, 105.0f); }
TEST_CASE(shifter_quality_mode_mid_voice) { checkVoiceShift(2048, 140.0f); }
TEST_CASE(shifter_low_latency_mode_mid_voice) { checkVoiceShift(1024, 150.0f); }

TEST_CASE(shifter_formant_ratio_moves_envelope) {
    const float sr = 48000.0f;
    const std::vector<float> vowel = syntheticVowel(110.0f, 750.0f, 2200.0f, 96000, sr);
    SpectralVoiceShifter flat(2048, sr);
    const std::vector<float> ref = runShifter(flat, vowel);
    SpectralVoiceShifter up(2048, sr);
    up.setFormantRatio(semitonesToRatio(4.0f));
    up.snapParameters();
    const std::vector<float> y = runShifter(up, vowel);
    // Measured on F2: with f0 = 110 Hz the F1 peak can only land on a harmonic (110 Hz grid).
    const double before = envelopePeakHz(ref.data() + 24000, 48000, sr, 1600, 3500);
    const double after = envelopePeakHz(y.data() + 24000, 48000, sr, 1600, 3500);
    CHECK_NEAR(after / before, semitonesToRatio(4.0f), 0.08);
    CHECK(envelopePeakHz(y.data() + 24000, 48000, sr, 300, 1500) > envelopePeakHz(ref.data() + 24000, 48000, sr, 300, 1500));
    // Pitch must be unaffected by the formant control.
    CHECK_NEAR(autocorrPitch(y.data() + 24000, 24000, sr, 80, 400), 110.0, 3.0);
}

TEST_CASE(shifter_noise_reduction_lowers_noise_between_syllables) {
    const float sr = 48000.0f;
    const int total = static_cast<int>(sr * 6);
    // "Syllables": 250 ms of vowel, 250 ms of pause, over constant background noise (~ -41 dBFS RMS).
    std::vector<float> speech = syntheticVowel(130.0f, 650.0f, 1900.0f, total, sr);
    for (int i = 0; i < total; ++i) {
        if ((i / 12000) % 2 == 1) speech[static_cast<size_t>(i)] = 0.0f;
    }
    const std::vector<float> bg = noise(total, 0.015f, 21u);
    std::vector<float> mix(static_cast<size_t>(total));
    for (int i = 0; i < total; ++i) mix[static_cast<size_t>(i)] = speech[static_cast<size_t>(i)] + bg[static_cast<size_t>(i)];

    SpectralVoiceShifter off(1024, sr);
    const std::vector<float> ref = runShifter(off, mix);
    SpectralVoiceShifter on(1024, sr);
    on.setNoiseReduction(1.0f);
    on.snapParameters();
    const std::vector<float> y = runShifter(on, mix);

    // Measure the last two seconds, aligned for the 1024-sample latency, avoiding segment edges.
    double gapIn = 0, gapOut = 0, voiceIn = 0, voiceOut = 0;
    int gapN = 0, voiceN = 0;
    for (int i = total - 96000; i < total; ++i) {
        const int src = i - 1024;
        const int pos = src % 12000;
        if (pos < 2000 || pos > 10000) continue;
        const double a = ref[static_cast<size_t>(i)], b = y[static_cast<size_t>(i)];
        if ((src / 12000) % 2 == 1) { gapIn += a * a; gapOut += b * b; ++gapN; }
        else { voiceIn += a * a; voiceOut += b * b; ++voiceN; }
    }
    const double gapReduction = 10 * std::log10(gapIn / std::max(gapOut, 1e-20));
    const double voiceChange = 10 * std::log10(voiceOut / std::max(voiceIn, 1e-20));
    std::printf("    noise reduction: gaps -%.1f dB, voiced %.1f dB\n", gapReduction, voiceChange);
    CHECK(gapReduction > 12.0);
    CHECK(voiceChange > -3.0);
}

TEST_CASE(shifter_stays_bounded_under_extreme_settings) {
    const float sr = 48000.0f;
    SpectralVoiceShifter s(1024, sr);
    std::vector<float> x = noise(96000, 0.9f, 5u);
    const std::vector<float> v = syntheticVowel(90.0f, 500.0f, 1500.0f, 96000, sr);
    for (size_t i = 0; i < x.size(); ++i) x[i] = 0.5f * x[i] + v[i];
    const float settings[][4] = {{2.0f, 1.5f, 1.0f, 1.0f}, {0.5f, 0.7f, 0.0f, 0.0f}, {1.6f, 1.2f, 0.5f, 0.3f}};
    for (const auto& p : settings) {
        s.setPitchRatio(p[0]);
        s.setFormantRatio(p[1]);
        s.setNoiseReduction(p[2]);
        s.setBreathiness(p[3]);
        const std::vector<float> y = runShifter(s, x, 240);
        float peak = 0.0f;
        bool finite = true;
        for (float f : y) {
            finite = finite && std::isfinite(f);
            peak = std::max(peak, std::fabs(f));
        }
        CHECK(finite);
        CHECK_LT(peak, 6.0);
    }
}

TEST_CASE(fft2048_quality_mode_identity) {
    const float sr = 48000.0f;
    SpectralVoiceShifter s(2048, sr);
    CHECK(s.latencySamples() == 2048);
    std::vector<float> x = syntheticVowel(140.0f, 800.0f, 2400.0f, 48000, sr);
    const std::vector<float> y = runShifter(s, x, 256);
    double err = 0.0, sig = 0.0;
    for (size_t i = 8192; i < x.size(); ++i) {
        const double d = y[i] - x[i - 2048];
        err += d * d;
        sig += static_cast<double>(x[i]) * x[i];
    }
    CHECK(10.0 * std::log10(sig / std::max(err, 1e-20)) > 60.0);
}

TEST_CASE(voice_chain_output_is_limited_and_finite) {
    const float sr = 48000.0f;
    VoiceChain chain(sr, 1024);
    VoiceParams p;
    p.set(kPitchSemitones, 5.0f);
    p.set(kFormantSemitones, 2.0f);
    p.set(kOutputGainDb, 12.0f);
    p.set(kAgcEnabled, 1.0f);
    p.set(kCompression, 0.5f);
    p.set(kPresenceDb, 6.0f);
    p.set(kAirDb, 6.0f);
    chain.setParams(p);
    std::vector<float> x = syntheticVowel(110.0f, 700.0f, 1900.0f, 96000, sr);
    for (float& v : x) v *= 1.8f;  // drive it hot
    for (size_t off = 0; off < x.size(); off += 256) chain.processAll(x.data() + off, 256);
    float peak = 0.0f;
    for (float v : x) {
        CHECK(std::isfinite(v));
        peak = std::max(peak, std::fabs(v));
    }
    CHECK(peak <= dbToGain(-1.0f) + 1e-5f);
    CHECK(chain.latencySamples() == 1024);
}

TEST_CASE(param_specs_clamp) {
    VoiceParams p;
    p.set(kPitchSemitones, 40.0f);
    CHECK_NEAR(p.get(kPitchSemitones), 12.0, 1e-6);
    p.set(kGateThresholdDb, -200.0f);
    CHECK_NEAR(p.get(kGateThresholdDb), -80.0, 1e-6);
    CHECK_NEAR(VoiceParams().get(kLowCutHz), 80.0, 1e-6);
}
