#include <atomic>
#include <chrono>
#include <thread>
#include <vector>

#include "AiBridge.h"
#include "DuplexProcessor.h"
#include "TestHarness.h"
#include "TestSignals.h"

using namespace voiceshift::audio;
using namespace voiceshift::dsp;
using namespace vstest;

namespace {

ProcessorConfig config(float aiRate = 0.0f, int aiChunk = 0) {
    ProcessorConfig c;
    c.sampleRate = 48000.0f;
    c.fftSize = 1024;
    c.maxBlock = 1024;
    c.aiModelRate = aiRate;
    c.aiChunkFrames = aiChunk;
    return c;
}

void run(DuplexProcessor& p, const std::vector<float>& in, std::vector<float>& out, int block = 192) {
    out.assign(in.size(), 0.0f);
    for (size_t off = 0; off < in.size(); off += static_cast<size_t>(block)) {
        const int n = static_cast<int>(std::min<size_t>(static_cast<size_t>(block), in.size() - off));
        p.process(in.data() + off, out.data() + off, n);
    }
}

}  // namespace

TEST_CASE(duplex_bypass_passes_dry_signal) {
    DuplexProcessor p(config());
    p.setParam(kPitchSemitones, 7.0f);
    p.setBypass(true);
    const std::vector<float> in = sine(500.0f, 0.2f, 48000, 48000.0f);
    std::vector<float> out;
    run(p, in, out);
    double maxErr = 0.0;
    for (size_t i = 4800; i < in.size(); ++i) maxErr = std::max(maxErr, static_cast<double>(std::fabs(out[i] - in[i])));
    CHECK_LT(maxErr, 1e-5);
}

TEST_CASE(duplex_dsp_mode_shifts_pitch) {
    DuplexProcessor p(config());
    p.setParam(kPitchSemitones, 7.0f);
    const std::vector<float> in = sine(200.0f, 0.2f, 96000, 48000.0f);
    std::vector<float> out;
    run(p, in, out, 240);
    CHECK_NEAR(dominantFrequency(out.data() + 9600, 80000, 48000.0f, 80, 1000), 200.0 * semitonesToRatio(7.0f), 3.0);
    CHECK(p.stats().aiState.load() == static_cast<int>(AiState::Off));
}

TEST_CASE(duplex_nan_input_is_contained) {
    DuplexProcessor p(config());
    std::vector<float> in = sine(300.0f, 0.2f, 9600, 48000.0f);
    in[5000] = std::numeric_limits<float>::quiet_NaN();
    in[5001] = std::numeric_limits<float>::infinity();
    std::vector<float> out;
    run(p, in, out);
    for (float v : out) CHECK(std::isfinite(v));
    CHECK(p.stats().dspFaults.load() >= 1);
    // Recovers afterwards.
    const std::vector<float> clean = sine(300.0f, 0.2f, 48000, 48000.0f);
    run(p, clean, out);
    CHECK(rmsDb(out.data() + 24000, 24000) > -30.0);
}

TEST_CASE(duplex_mute_silences_output) {
    DuplexProcessor p(config());
    p.setMuted(true);
    const std::vector<float> in = sine(300.0f, 0.5f, 9600, 48000.0f);
    std::vector<float> out;
    run(p, in, out);
    for (size_t i = 2400; i < out.size(); ++i) CHECK(out[i] == 0.0f);
}

TEST_CASE(duplex_test_tone_level) {
    DuplexProcessor p(config());
    p.setTestSignal(TestSignal::Tone, 1000.0f, -18.0f);
    const std::vector<float> in(48000, 0.0f);
    std::vector<float> out;
    run(p, in, out);
    CHECK_NEAR(rmsDb(out.data() + 4800, 43200), -18.0 - 3.0103, 0.05);
    CHECK_NEAR(dominantFrequency(out.data(), 48000, 48000.0f, 200, 5000), 1000.0, 1.0);
}

TEST_CASE(duplex_tone_detector_sees_input_tone) {
    DuplexProcessor p(config());
    const std::vector<float> in = sine(1000.0f, dbToGain(-24.0f), 48000, 48000.0f);
    std::vector<float> out;
    run(p, in, out);
    CHECK_NEAR(p.stats().toneDb.load(), -24.0, 0.5);
    CHECK(p.stats().toneSnrDb.load() > 30.0f);
}

TEST_CASE(duplex_latency_probe_with_simulated_loopback) {
    DuplexProcessor p(config());
    p.setTestSignal(TestSignal::LatencyProbe, 1000.0f, -18.0f);
    const int delay = 3000;  // 62.5 ms round trip
    std::vector<float> line(static_cast<size_t>(delay), 0.0f);
    size_t pos = 0;
    std::vector<float> in(256), out(256);
    for (int block = 0; block < 1500; ++block) {
        for (int i = 0; i < 256; ++i) {
            in[static_cast<size_t>(i)] = line[pos];
            pos = (pos + 1) % line.size();
        }
        // Output written now enters the delay line at the same positions we just read.
        p.process(in.data(), out.data(), 256);
        size_t wpos = (pos + line.size() - 256) % line.size();
        for (int i = 0; i < 256; ++i) {
            line[wpos] = out[static_cast<size_t>(i)] * 0.5f;
            wpos = (wpos + 1) % line.size();
        }
    }
    CHECK_NEAR(p.stats().probeLatencyMs.load(), 1000.0 * delay / 48000.0, 0.1);
}

TEST_CASE(duplex_tap_receives_output) {
    DuplexProcessor p(config());
    p.setTapEnabled(true);
    const std::vector<float> in = sine(300.0f, 0.2f, 4800, 48000.0f);
    std::vector<float> out;
    run(p, in, out);
    std::vector<float> tap(10000);
    const int got = p.tapRead(tap.data(), 10000);
    CHECK(got == 4800);
    for (int i = 0; i < got; ++i) CHECK(tap[static_cast<size_t>(i)] == out[static_cast<size_t>(i)]);
}

TEST_CASE(ai_bridge_timestamps_and_discontinuities) {
    AiBridge bridge(48000.0f, 16000.0f, 1024, 1600);
    std::vector<float> in = sine(440.0f, 0.3f, 4800, 48000.0f);
    bridge.pushInput(in.data(), 4800);
    std::vector<float> buf(4000);
    int64_t ts = -1;
    const int got = bridge.workerRead(buf.data(), 800, &ts);
    CHECK(ts == 0);
    CHECK(got == 800);
    int64_t ts2 = -1;
    bridge.workerRead(buf.data(), 100, &ts2);
    CHECK(ts2 == 800);
    CHECK(bridge.workerWrite(buf.data(), 800, 0) == 800);
    CHECK(bridge.discontinuities() == 0);
    bridge.workerWrite(buf.data(), 100, 5000);  // gap
    CHECK(bridge.discontinuities() == 1);
}

// End-to-end neural path with a simulated inference worker thread (phase inversion "model").
TEST_CASE(duplex_neural_path_uses_worker_then_falls_back) {
    DuplexProcessor p(config(16000.0f, 1600));  // 100 ms chunks
    p.setMode(EngineMode::Neural);
    AiBridge* ai = p.aiBridge();
    CHECK(ai != nullptr);

    std::atomic<bool> workerRunning{true};
    std::thread worker([&] {
        std::vector<float> chunk(1600);
        while (workerRunning.load()) {
            if (ai->workerAvailable() >= 1600) {
                int64_t ts = 0;
                const int got = ai->workerRead(chunk.data(), 1600, &ts);
                for (int i = 0; i < got; ++i) chunk[static_cast<size_t>(i)] = 0.0f;  // "model" outputs silence
                std::this_thread::sleep_for(std::chrono::milliseconds(5));          // inference time
                ai->workerWrite(chunk.data(), got, ts);
            } else {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
        }
    });

    // Feed audio in real time-ish so the worker can keep up.
    const std::vector<float> in = sine(250.0f, 0.3f, 48000 * 3, 48000.0f);
    std::vector<float> out(in.size());
    for (size_t off = 0; off < in.size(); off += 480) {
        p.process(in.data() + off, out.data() + off, 480);
        std::this_thread::sleep_for(std::chrono::microseconds(2500));  // 4x faster than real time
    }
    // After priming the worker's silent output is what we hear.
    CHECK(p.stats().aiState.load() == static_cast<int>(AiState::Active));
    CHECK_LT(rmsDb(out.data() + out.size() - 24000, 24000), -60.0);
    CHECK(ai->latencyMs() > 100.0f);

    // Worker stalls -> automatic fallback to the DSP transform (audible again).
    workerRunning = false;
    worker.join();
    std::vector<float> after(48000);
    const std::vector<float> in2 = sine(250.0f, 0.3f, 48000, 48000.0f);
    for (size_t off = 0; off < in2.size(); off += 480) p.process(in2.data() + off, after.data() + off, 480);
    CHECK(p.stats().aiState.load() != static_cast<int>(AiState::Active));
    CHECK(ai->underruns() >= 1);
    CHECK(rmsDb(after.data() + 24000, 24000) > -20.0);
}
