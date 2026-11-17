#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <memory>
#include <vector>

#include "AiBridge.h"
#include "voiceshift/dsp/Analysis.h"
#include "voiceshift/dsp/Dynamics.h"
#include "voiceshift/dsp/RingBuffer.h"
#include "voiceshift/dsp/VoiceChain.h"
#include "voiceshift/dsp/VoiceParams.h"

namespace voiceshift::audio {

enum class EngineMode : int { Dsp = 0, Neural = 1 };
enum class TestSignal : int { None = 0, Tone = 1, LatencyProbe = 2 };
enum class AiState : int { Off = 0, Priming = 1, Active = 2, Fallback = 3 };

struct ProcessorConfig {
    float sampleRate = 48000.0f;
    int fftSize = 1024;
    int maxBlock = 2048;
    float aiModelRate = 0.0f;  // 0 = neural path not configured
    int aiChunkFrames = 0;     // model-rate frames per inference chunk
};

// Everything that happens to audio between "captured" and "played", independent of Oboe so it can
// be unit-tested on the host. All public setters are lock-free and may be called from any thread;
// process() must only be called from the audio thread.
class DuplexProcessor {
public:
    explicit DuplexProcessor(const ProcessorConfig& config);

    // ---- control (any thread)
    void setParam(int id, float value);
    void setMode(EngineMode mode) { mode_.store(static_cast<int>(mode), std::memory_order_relaxed); }
    void setBypass(bool bypass) { bypass_.store(bypass, std::memory_order_relaxed); }
    void setMuted(bool muted) { muted_.store(muted, std::memory_order_relaxed); }
    void setTestSignal(TestSignal type, float frequencyHz, float levelDb);
    void setTapEnabled(bool enabled) { tapEnabled_.store(enabled, std::memory_order_relaxed); }

    // ---- audio thread
    // input and output are mono; n may be any size (processed in maxBlock slices).
    void process(const float* input, float* output, int n);

    // ---- worker threads
    AiBridge* aiBridge() { return ai_.get(); }
    int tapRead(float* dst, int maxFrames) {
        return static_cast<int>(tap_.read(dst, static_cast<size_t>(std::max(0, maxFrames))));
    }

    // ---- diagnostics (any thread; values are snapshots)
    struct Stats {
        std::atomic<float> inputPeakDb{-120.0f};
        std::atomic<float> inputRmsDb{-120.0f};
        std::atomic<float> outputPeakDb{-120.0f};
        std::atomic<float> outputRmsDb{-120.0f};
        std::atomic<float> toneDb{-120.0f};
        std::atomic<float> toneSnrDb{-120.0f};
        std::atomic<float> agcGainDb{0.0f};
        std::atomic<float> limiterReductionDb{0.0f};
        std::atomic<float> compressorReductionDb{0.0f};
        std::atomic<float> probeLatencyMs{-1.0f};
        std::atomic<int> gateOpen{1};
        std::atomic<int> aiState{0};
        std::atomic<int64_t> dspFaults{0};
        std::atomic<int64_t> tapOverflows{0};
        std::atomic<int64_t> framesProcessed{0};
    };
    const Stats& stats() const { return stats_; }
    float sampleRate() const { return config_.sampleRate; }
    int dspLatencySamples() const { return chain_.latencySamples(); }
    EngineMode mode() const { return static_cast<EngineMode>(mode_.load(std::memory_order_relaxed)); }
    bool bypass() const { return bypass_.load(std::memory_order_relaxed); }

private:
    void processSlice(const float* input, float* output, int n);
    void syncParams();

    const ProcessorConfig config_;
    Stats stats_;
    dsp::VoiceChain chain_;
    dsp::Limiter bypassLimiter_;
    dsp::LevelMeter inputMeter_;
    dsp::LevelMeter outputMeter_;
    dsp::ToneDetector toneDetector_;
    dsp::ToneGenerator toneGenerator_;
    dsp::LatencyProbe probe_;
    std::unique_ptr<AiBridge> ai_;
    dsp::SpscRingBuffer<float> tap_;

    std::array<std::atomic<float>, dsp::kParamCount> paramValues_;
    std::atomic<uint32_t> paramVersion_{1};
    uint32_t appliedParamVersion_ = 0;
    dsp::VoiceParams params_;

    std::atomic<int> mode_{0};
    std::atomic<bool> bypass_{false};
    std::atomic<bool> muted_{false};
    std::atomic<bool> tapEnabled_{false};
    std::atomic<int> testSignal_{0};
    std::atomic<float> testFrequency_{1000.0f};
    std::atomic<float> testLevelDb_{-18.0f};
    int lastTestSignal_ = 0;

    std::vector<float> dry_, work_, fallback_, aiOut_, bypassBuf_;
    float bypassMix_ = 0.0f;
    float aiMix_ = 0.0f;
    float muteGain_ = 1.0f;
    float rampStep_ = 0.0f;  // per-sample increment for ~20 ms crossfades
    int64_t frameIndex_ = 0;
};

}  // namespace voiceshift::audio
