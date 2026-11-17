#pragma once

#include <oboe/Oboe.h>

#include <array>
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "DuplexProcessor.h"
#include "voiceshift/dsp/VoiceParams.h"

namespace voiceshift::audio {

struct EngineConfig {
    int inputDeviceId = 0;   // 0 = system default (oboe::kUnspecified)
    int outputDeviceId = 0;
    int sampleRate = 48000;
    int fftSize = 2048;
    int inputPreset = 0;     // see mapInputPreset()
    bool exclusive = true;
    int aiModelRate = 0;     // 0 = no neural path
    int aiChunkFrames = 0;
};

enum class EngineState : int { Stopped = 0, Running = 1, Error = 2, Disconnected = 3 };

// Layout of the stats array exchanged with Kotlin (com.voiceshift.audio.NativeStats). Append only.
enum StatIndex : int {
    kStatState = 0,
    kStatSampleRate,
    kStatFramesPerBurst,
    kStatBufferSize,
    kStatInputPeakDb,
    kStatInputRmsDb,
    kStatOutputPeakDb,
    kStatOutputRmsDb,
    kStatOutputLatencyMs,
    kStatInputLatencyMs,
    kStatDspLatencyMs,
    kStatAiLatencyMs,
    kStatCallbackCount,
    kStatXRunCount,
    kStatInputUnderflows,
    kStatInputDrains,
    kStatLoadAvgPct,
    kStatLoadPeakPct,
    kStatDspFaults,
    kStatAiState,
    kStatAiUnderruns,
    kStatAiOverflows,
    kStatProbeLatencyMs,
    kStatToneDb,
    kStatToneSnrDb,
    kStatInputDeviceId,
    kStatOutputDeviceId,
    kStatOutputExclusive,
    kStatInputExclusive,
    kStatLastError,
    kStatGateOpen,
    kStatAgcGainDb,
    kStatLimiterReductionDb,
    kStatTapOverflows,
    kStatAiDiscontinuities,
    kStatOutputChannels,
    kStatCompressorReductionDb,
    kStatMode,
    kStatBypass,
    kStatFramesProcessed,
    kStatCount
};

// Full-duplex Oboe engine. The output stream is callback-driven (low-latency, exclusive when the
// device allows it); the input stream is read non-blocking from inside that callback, the same
// technique as oboe::FullDuplexStream, so capture and playback share one clock.
class OboeEngine : public oboe::AudioStreamDataCallback, public oboe::AudioStreamErrorCallback {
public:
    OboeEngine();
    ~OboeEngine() override;

    // Control thread. Returns 0 on success or a negative oboe::Result.
    int start(const EngineConfig& config);
    void stop();

    // Persisted across restarts; forwarded to the processor when running.
    void setParam(int id, float value);
    void setMode(int mode);
    void setBypass(bool bypass);
    void setMuted(bool muted);
    void setTestSignal(int type, float frequencyHz, float levelDb);
    void setTapEnabled(bool enabled);

    int fillStats(double* out, int capacity);
    std::string lastError();

    // Worker-thread entry points (inference worker, network sender).
    int aiAvailable();
    int aiRead(float* dst, int maxFrames, int64_t* timestamp);
    int aiWrite(const float* src, int frames, int64_t timestamp);
    int tapRead(float* dst, int maxFrames);

    // oboe callbacks
    oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream, void* audioData, int32_t numFrames) override;
    bool onError(oboe::AudioStream* stream, oboe::Result error) override;
    void onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) override;

private:
    void stopLocked();
    void closeStreams();
    void setError(const std::string& message, int code);

    std::mutex controlMutex_;  // start/stop/stats; never taken by the audio thread
    std::mutex workerMutex_;   // guards processor_ lifetime against worker threads
    std::shared_ptr<oboe::AudioStream> output_;
    std::shared_ptr<oboe::AudioStream> input_;
    std::unique_ptr<DuplexProcessor> processor_;

    std::vector<float> inputBuffer_;
    std::vector<float> monoInput_;
    std::vector<float> monoBuffer_;
    float sampleRate_ = 48000.0f;
    int inputChannels_ = 1;
    int outputChannels_ = 2;
    int inputBurst_ = 192;
    bool inputPrimed_ = false;
    int warmupCallbacks_ = 0;

    std::atomic<int> state_{static_cast<int>(EngineState::Stopped)};
    std::atomic<int> lastErrorCode_{0};
    std::atomic<int64_t> callbackCount_{0};
    std::atomic<int64_t> inputUnderflows_{0};
    std::atomic<int64_t> inputDrains_{0};
    std::atomic<float> loadAvg_{0.0f};
    std::atomic<float> loadPeak_{0.0f};

    std::array<float, dsp::kParamCount> params_{};
    int mode_ = 0;
    bool bypass_ = false;
    bool muted_ = false;
    int testType_ = 0;
    float testFrequency_ = 1000.0f;
    float testLevelDb_ = -18.0f;
    bool tapEnabled_ = false;

    std::mutex errorMutex_;
    std::string lastError_;
};

}  // namespace voiceshift::audio
