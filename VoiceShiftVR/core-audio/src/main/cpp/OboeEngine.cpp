#include "OboeEngine.h"

#include <android/log.h>

#include <algorithm>
#include <chrono>
#include <cstring>

#define LOG_TAG "VoiceShiftEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace voiceshift::audio {

namespace {

constexpr int kMaxCallbackSlice = 2048;

oboe::InputPreset mapInputPreset(int preset) {
    switch (preset) {
        case 1: return oboe::InputPreset::VoiceRecognition;
        case 2: return oboe::InputPreset::VoiceCommunication;  // platform AEC/NS/AGC, higher latency
        case 3: return oboe::InputPreset::Unprocessed;
        case 4: return oboe::InputPreset::Generic;
        default: return oboe::InputPreset::VoicePerformance;   // low latency, no platform effects
    }
}

}  // namespace

OboeEngine::OboeEngine() {
    for (int i = 0; i < dsp::kParamCount; ++i) {
        params_[static_cast<size_t>(i)] = dsp::kParamSpecs[static_cast<size_t>(i)].defaultValue;
    }
}

OboeEngine::~OboeEngine() { stop(); }

void OboeEngine::setError(const std::string& message, int code) {
    LOGE("%s (code %d)", message.c_str(), code);
    {
        std::lock_guard<std::mutex> lock(errorMutex_);
        lastError_ = message;
    }
    lastErrorCode_.store(code);
}

std::string OboeEngine::lastError() {
    std::lock_guard<std::mutex> lock(errorMutex_);
    return lastError_;
}

int OboeEngine::start(const EngineConfig& config) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    stopLocked();
    lastErrorCode_.store(0);
    {
        std::lock_guard<std::mutex> errLock(errorMutex_);
        lastError_.clear();
    }

    const oboe::SharingMode sharing = config.exclusive ? oboe::SharingMode::Exclusive : oboe::SharingMode::Shared;

    oboe::AudioStreamBuilder outBuilder;
    outBuilder.setDirection(oboe::Direction::Output)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(sharing)
        ->setFormat(oboe::AudioFormat::Float)
        ->setFormatConversionAllowed(true)
        ->setChannelCount(oboe::ChannelCount::Stereo)
        ->setChannelConversionAllowed(true)
        ->setSampleRate(config.sampleRate)
        ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
        ->setUsage(oboe::Usage::Media)
        ->setContentType(oboe::ContentType::Speech)
        ->setDeviceId(config.outputDeviceId)
        ->setDataCallback(this)
        ->setErrorCallback(this);
    oboe::Result result = outBuilder.openStream(output_);
    if (result != oboe::Result::OK) {
        setError(std::string("Could not open output stream: ") + oboe::convertToText(result), static_cast<int>(result));
        closeStreams();
        state_.store(static_cast<int>(EngineState::Error));
        return static_cast<int>(result);
    }

    const int sampleRate = output_->getSampleRate();
    outputChannels_ = std::max(1, output_->getChannelCount());
    const int burst = std::max(1, output_->getFramesPerBurst());
    output_->setBufferSizeInFrames(burst * 2);

    oboe::AudioStreamBuilder inBuilder;
    inBuilder.setDirection(oboe::Direction::Input)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(sharing)
        ->setFormat(oboe::AudioFormat::Float)
        ->setFormatConversionAllowed(true)
        ->setChannelCount(oboe::ChannelCount::Mono)
        ->setChannelConversionAllowed(true)
        ->setSampleRate(sampleRate)
        ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
        ->setInputPreset(mapInputPreset(config.inputPreset))
        ->setDeviceId(config.inputDeviceId)
        ->setErrorCallback(this);
    result = inBuilder.openStream(input_);
    if (result != oboe::Result::OK) {
        setError(std::string("Could not open microphone stream: ") + oboe::convertToText(result) +
                     " (is RECORD_AUDIO granted and the device free?)",
                 static_cast<int>(result));
        closeStreams();
        state_.store(static_cast<int>(EngineState::Error));
        return static_cast<int>(result);
    }
    inputChannels_ = std::max(1, input_->getChannelCount());
    inputBurst_ = std::max(1, input_->getFramesPerBurst());

    ProcessorConfig pc;
    pc.sampleRate = static_cast<float>(sampleRate);
    pc.fftSize = config.fftSize;
    pc.maxBlock = kMaxCallbackSlice;
    pc.aiModelRate = static_cast<float>(config.aiModelRate);
    pc.aiChunkFrames = config.aiChunkFrames;
    try {
        std::unique_ptr<DuplexProcessor> processor = std::make_unique<DuplexProcessor>(pc);
        for (int i = 0; i < dsp::kParamCount; ++i) processor->setParam(i, params_[static_cast<size_t>(i)]);
        processor->setMode(static_cast<EngineMode>(mode_));
        processor->setBypass(bypass_);
        processor->setMuted(muted_);
        processor->setTestSignal(static_cast<TestSignal>(testType_), testFrequency_, testLevelDb_);
        processor->setTapEnabled(tapEnabled_);
        std::lock_guard<std::mutex> workerLock(workerMutex_);
        processor_ = std::move(processor);
    } catch (const std::exception& e) {
        setError(std::string("Invalid processing configuration: ") + e.what(), -1);
        closeStreams();
        state_.store(static_cast<int>(EngineState::Error));
        return -1;
    }

    inputBuffer_.assign(static_cast<size_t>(kMaxCallbackSlice * inputChannels_), 0.0f);
    monoInput_.assign(static_cast<size_t>(kMaxCallbackSlice), 0.0f);
    monoBuffer_.assign(static_cast<size_t>(kMaxCallbackSlice), 0.0f);
    sampleRate_ = static_cast<float>(sampleRate);
    inputPrimed_ = false;
    warmupCallbacks_ = 0;
    callbackCount_.store(0);
    inputUnderflows_.store(0);
    inputDrains_.store(0);
    loadAvg_.store(0.0f);
    loadPeak_.store(0.0f);

    // The optional monitor is opened (not started) before any callback runs: callbacks read its pointer.
    if (config.monitorDeviceId != 0 && config.monitorDeviceId != output_->getDeviceId()) {
        openMonitor(config.monitorDeviceId, sampleRate);
    }

    // Start capture first so data is waiting when the first playback callback asks for it.
    result = input_->requestStart();
    if (result == oboe::Result::OK) result = output_->requestStart();
    if (result != oboe::Result::OK) {
        setError(std::string("Could not start streams: ") + oboe::convertToText(result), static_cast<int>(result));
        stopLocked();
        state_.store(static_cast<int>(EngineState::Error));
        return static_cast<int>(result);
    }

    if (monitor_) {
        if (monitor_->requestStart() == oboe::Result::OK) {
            monitorActive_.store(true);
        } else {
            LOGW("Monitor stream could not start");
        }
    }

    state_.store(static_cast<int>(EngineState::Running));
    LOGI("Started: %d Hz, out burst %d (%s, dev %d), in burst %d (%s, dev %d), fft %d, ai %d Hz",
         sampleRate, burst, output_->getSharingMode() == oboe::SharingMode::Exclusive ? "exclusive" : "shared",
         output_->getDeviceId(), inputBurst_,
         input_->getSharingMode() == oboe::SharingMode::Exclusive ? "exclusive" : "shared", input_->getDeviceId(),
         config.fftSize, config.aiModelRate);
    return 0;
}

void OboeEngine::openMonitor(int deviceId, int sampleRate) {
    // A second, shared-mode output. Failure is not fatal: Android may refuse to drive two output
    // devices at once (e.g. a USB headset and wired headphones on the same codec).
    monitorBridge_ = std::make_unique<MonitorBridge>(static_cast<float>(sampleRate));
    monitorFeed_.assign(static_cast<size_t>(kMaxCallbackSlice), 0.0f);
    monitorPull_.assign(static_cast<size_t>(kMaxCallbackSlice), 0.0f);
    oboe::AudioStreamBuilder builder;
    builder.setDirection(oboe::Direction::Output)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(oboe::SharingMode::Shared)
        ->setFormat(oboe::AudioFormat::Float)
        ->setFormatConversionAllowed(true)
        ->setChannelCount(oboe::ChannelCount::Stereo)
        ->setChannelConversionAllowed(true)
        ->setSampleRate(sampleRate)
        ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
        ->setUsage(oboe::Usage::Media)
        ->setContentType(oboe::ContentType::Speech)
        ->setDeviceId(deviceId)
        ->setDataCallback(this)
        ->setErrorCallback(this);
    oboe::Result result = builder.openStream(monitor_);
    if (result == oboe::Result::OK) {
        monitorChannels_ = std::max(1, monitor_->getChannelCount());
        const int burst = std::max(1, monitor_->getFramesPerBurst());
        monitor_->setBufferSizeInFrames(burst * 2);
        monitorBridge_->setTargetFrames(burst * 2);
    }
    if (result != oboe::Result::OK) {
        LOGW("Monitor stream on device %d unavailable: %s", deviceId, oboe::convertToText(result));
        if (monitor_) {
            monitor_->close();
            monitor_.reset();
        }
        monitorBridge_.reset();
        return;
    }
    monitorPtr_.store(monitor_.get());
    LOGI("Monitor stream on device %d (%d Hz)", monitor_->getDeviceId(), monitor_->getSampleRate());
}

oboe::DataCallbackResult OboeEngine::renderMonitor(void* audioData, int32_t numFrames) {
    auto* out = static_cast<float*>(audioData);
    MonitorBridge* bridge = monitorBridge_.get();
    if (bridge == nullptr) {
        std::memset(out, 0, sizeof(float) * static_cast<size_t>(numFrames) * static_cast<size_t>(monitorChannels_));
        return oboe::DataCallbackResult::Continue;
    }
    const float gain = monitorGain_.load(std::memory_order_relaxed);
    int offset = 0;
    while (offset < numFrames) {
        const int chunk = std::min(numFrames - offset, kMaxCallbackSlice);
        bridge->pull(monitorPull_.data(), chunk, gain);
        float* dst = out + static_cast<size_t>(offset) * static_cast<size_t>(monitorChannels_);
        for (int i = 0; i < chunk; ++i) {
            for (int c = 0; c < monitorChannels_; ++c) dst[i * monitorChannels_ + c] = monitorPull_[static_cast<size_t>(i)];
        }
        offset += chunk;
    }
    return oboe::DataCallbackResult::Continue;
}

void OboeEngine::setMonitorGainDb(float db) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    monitorGainDb_ = db;
    monitorGain_.store(db <= -60.0f ? 0.0f : dsp::dbToGain(dsp::clampf(db, -60.0f, 12.0f)));
}

void OboeEngine::stop() {
    std::lock_guard<std::mutex> lock(controlMutex_);
    stopLocked();
}

void OboeEngine::stopLocked() {
    // stop() blocks until the data callback has returned, so the processor can be released after.
    if (monitor_) monitor_->stop();
    if (output_) output_->stop();
    if (input_) input_->stop();
    closeStreams();
    monitorBridge_.reset();
    {
        std::lock_guard<std::mutex> workerLock(workerMutex_);
        processor_.reset();
    }
    state_.store(static_cast<int>(EngineState::Stopped));
}

void OboeEngine::closeStreams() {
    monitorPtr_.store(nullptr);
    if (monitor_) {
        monitor_->close();
        monitor_.reset();
    }
    monitorActive_.store(false);
    if (output_) {
        output_->close();
        output_.reset();
    }
    if (input_) {
        input_->close();
        input_.reset();
    }
}

oboe::DataCallbackResult OboeEngine::onAudioReady(oboe::AudioStream* stream, void* audioData, int32_t numFrames) {
    if (stream != nullptr && stream == monitorPtr_.load(std::memory_order_relaxed)) return renderMonitor(audioData, numFrames);
    auto* out = static_cast<float*>(audioData);
    DuplexProcessor* processor = processor_.get();
    if (processor == nullptr || !input_) {
        std::memset(out, 0, sizeof(float) * static_cast<size_t>(numFrames) * static_cast<size_t>(outputChannels_));
        return oboe::DataCallbackResult::Continue;
    }
    const auto started = std::chrono::steady_clock::now();

    if (!inputPrimed_) {
        // Drop whatever the microphone captured before playback began: it would only add latency.
        for (int guard = 0; guard < 16; ++guard) {
            const auto drained = input_->read(inputBuffer_.data(), kMaxCallbackSlice, 0);
            if (!drained || drained.value() <= 0) break;
        }
        inputPrimed_ = true;
    }

    int offset = 0;
    while (offset < numFrames) {
        const int chunk = std::min(numFrames - offset, kMaxCallbackSlice);
        int got = 0;
        const auto readResult = input_->read(inputBuffer_.data(), chunk, 0);
        if (readResult) {
            got = readResult.value();
        } else if (readResult.error() == oboe::Result::ErrorDisconnected) {
            state_.store(static_cast<int>(EngineState::Disconnected));
            lastErrorCode_.store(static_cast<int>(readResult.error()));
        }
        if (got < chunk) {
            std::fill(inputBuffer_.begin() + got * inputChannels_, inputBuffer_.begin() + chunk * inputChannels_, 0.0f);
            if (warmupCallbacks_ > 20) inputUnderflows_.fetch_add(1, std::memory_order_relaxed);
        }
        if (inputChannels_ == 1) {
            std::copy(inputBuffer_.begin(), inputBuffer_.begin() + chunk, monoInput_.begin());
        } else {
            const float scale = 1.0f / static_cast<float>(inputChannels_);
            for (int i = 0; i < chunk; ++i) {
                float sum = 0.0f;
                for (int c = 0; c < inputChannels_; ++c) sum += inputBuffer_[static_cast<size_t>(i * inputChannels_ + c)];
                monoInput_[static_cast<size_t>(i)] = sum * scale;
            }
        }

        MonitorBridge* monitor = monitorActive_.load(std::memory_order_relaxed) ? monitorBridge_.get() : nullptr;
        processor->process(monoInput_.data(), monoBuffer_.data(), chunk, monitor != nullptr ? monitorFeed_.data() : nullptr);
        if (monitor != nullptr) monitor->push(monitorFeed_.data(), chunk);

        float* dst = out + static_cast<size_t>(offset) * static_cast<size_t>(outputChannels_);
        for (int i = 0; i < chunk; ++i) {
            const float v = monoBuffer_[static_cast<size_t>(i)];
            for (int c = 0; c < outputChannels_; ++c) dst[i * outputChannels_ + c] = v;
        }
        offset += chunk;
    }

    // Clock drift between capture and playback slowly fills the input queue; keep it short.
    const auto available = input_->getAvailableFrames();
    if (available && available.value() > numFrames + 2 * inputBurst_) {
        int excess = available.value() - numFrames;
        while (excess > 0) {
            const int n = std::min(excess, kMaxCallbackSlice);
            const auto dropped = input_->read(inputBuffer_.data(), n, 0);
            if (!dropped || dropped.value() <= 0) break;
            excess -= dropped.value();
        }
        inputDrains_.fetch_add(1, std::memory_order_relaxed);
    }

    ++warmupCallbacks_;
    callbackCount_.fetch_add(1, std::memory_order_relaxed);
    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    const double budget = static_cast<double>(numFrames) / std::max(1.0f, sampleRate_);
    const float load = static_cast<float>(100.0 * elapsed / budget);
    loadAvg_.store(0.95f * loadAvg_.load(std::memory_order_relaxed) + 0.05f * load, std::memory_order_relaxed);
    if (load > loadPeak_.load(std::memory_order_relaxed)) loadPeak_.store(load, std::memory_order_relaxed);
    return oboe::DataCallbackResult::Continue;
}

bool OboeEngine::onError(oboe::AudioStream* /*stream*/, oboe::Result /*error*/) {
    return false;  // let Oboe close the stream, then onErrorAfterClose reports it
}

void OboeEngine::onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) {
    if (stream != nullptr && stream == monitorPtr_.load()) {
        // Losing the optional monitor (e.g. headphones unplugged) must not stop the main path.
        LOGW("Monitor stream closed: %s", oboe::convertToText(error));
        monitorActive_.store(false);
        return;
    }
    const bool isOutput = stream != nullptr && stream->getDirection() == oboe::Direction::Output;
    LOGW("%s stream closed after error: %s", isOutput ? "Output" : "Input", oboe::convertToText(error));
    lastErrorCode_.store(static_cast<int>(error));
    state_.store(static_cast<int>(error == oboe::Result::ErrorDisconnected ? EngineState::Disconnected
                                                                             : EngineState::Error));
    std::lock_guard<std::mutex> lock(errorMutex_);
    lastError_ = std::string(isOutput ? "Output" : "Input") + " stream stopped: " + oboe::convertToText(error);
}

void OboeEngine::setParam(int id, float value) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    if (id < 0 || id >= dsp::kParamCount) return;
    params_[static_cast<size_t>(id)] = dsp::clampParam(id, value);
    if (processor_) processor_->setParam(id, value);
}

void OboeEngine::setMode(int mode) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    mode_ = mode;
    if (processor_) processor_->setMode(static_cast<EngineMode>(mode));
}

void OboeEngine::setBypass(bool bypass) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    bypass_ = bypass;
    if (processor_) processor_->setBypass(bypass);
}

void OboeEngine::setMuted(bool muted) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    muted_ = muted;
    if (processor_) processor_->setMuted(muted);
}

void OboeEngine::setTestSignal(int type, float frequencyHz, float levelDb) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    testType_ = type;
    testFrequency_ = frequencyHz;
    testLevelDb_ = levelDb;
    if (processor_) processor_->setTestSignal(static_cast<TestSignal>(type), frequencyHz, levelDb);
}

void OboeEngine::setTapEnabled(bool enabled) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    tapEnabled_ = enabled;
    if (processor_) processor_->setTapEnabled(enabled);
}

int OboeEngine::fillStats(double* out, int capacity) {
    std::lock_guard<std::mutex> lock(controlMutex_);
    const int n = std::min(capacity, static_cast<int>(kStatCount));
    double s[kStatCount] = {};
    s[kStatState] = state_.load();
    s[kStatOutputLatencyMs] = -1.0;
    s[kStatInputLatencyMs] = -1.0;
    s[kStatProbeLatencyMs] = -1.0;
    if (output_) {
        s[kStatSampleRate] = output_->getSampleRate();
        s[kStatFramesPerBurst] = output_->getFramesPerBurst();
        s[kStatBufferSize] = output_->getBufferSizeInFrames();
        s[kStatOutputDeviceId] = output_->getDeviceId();
        s[kStatOutputExclusive] = output_->getSharingMode() == oboe::SharingMode::Exclusive ? 1.0 : 0.0;
        s[kStatOutputChannels] = output_->getChannelCount();
        const auto latency = output_->calculateLatencyMillis();
        if (latency) s[kStatOutputLatencyMs] = latency.value();
        const auto xruns = output_->getXRunCount();
        if (xruns) s[kStatXRunCount] = xruns.value();
    }
    if (input_) {
        s[kStatInputDeviceId] = input_->getDeviceId();
        s[kStatInputExclusive] = input_->getSharingMode() == oboe::SharingMode::Exclusive ? 1.0 : 0.0;
        const auto latency = input_->calculateLatencyMillis();
        if (latency) s[kStatInputLatencyMs] = latency.value();
    }
    s[kStatCallbackCount] = static_cast<double>(callbackCount_.load());
    s[kStatInputUnderflows] = static_cast<double>(inputUnderflows_.load());
    s[kStatInputDrains] = static_cast<double>(inputDrains_.load());
    s[kStatLoadAvgPct] = loadAvg_.load();
    s[kStatLoadPeakPct] = loadPeak_.exchange(0.0f);
    s[kStatLastError] = lastErrorCode_.load();
    s[kStatMode] = mode_;
    s[kStatBypass] = bypass_ ? 1.0 : 0.0;
    s[kStatMonitorActive] = monitorActive_.load() ? 1.0 : 0.0;
    if (monitor_) s[kStatMonitorDeviceId] = monitor_->getDeviceId();
    if (monitorBridge_) {
        s[kStatMonitorUnderruns] = static_cast<double>(monitorBridge_->underruns());
        s[kStatMonitorDriftCorrections] = static_cast<double>(monitorBridge_->driftCorrections());
    }
    if (processor_) {
        const DuplexProcessor::Stats& ps = processor_->stats();
        s[kStatInputPeakDb] = ps.inputPeakDb.load();
        s[kStatInputRmsDb] = ps.inputRmsDb.load();
        s[kStatOutputPeakDb] = ps.outputPeakDb.load();
        s[kStatOutputRmsDb] = ps.outputRmsDb.load();
        s[kStatDspLatencyMs] = 1000.0 * processor_->dspLatencySamples() / processor_->sampleRate();
        s[kStatDspFaults] = static_cast<double>(ps.dspFaults.load());
        s[kStatAiState] = ps.aiState.load();
        s[kStatProbeLatencyMs] = ps.probeLatencyMs.load();
        s[kStatToneDb] = ps.toneDb.load();
        s[kStatToneSnrDb] = ps.toneSnrDb.load();
        s[kStatGateOpen] = ps.gateOpen.load();
        s[kStatAgcGainDb] = ps.agcGainDb.load();
        s[kStatLimiterReductionDb] = ps.limiterReductionDb.load();
        s[kStatCompressorReductionDb] = ps.compressorReductionDb.load();
        s[kStatTapOverflows] = static_cast<double>(ps.tapOverflows.load());
        s[kStatFramesProcessed] = static_cast<double>(ps.framesProcessed.load());
        s[kStatInputPitchHz] = ps.inputPitchHz.load();
        s[kStatPitchConfidence] = ps.pitchConfidence.load();
        if (AiBridge* ai = processor_->aiBridge()) {
            s[kStatAiLatencyMs] = ai->latencyMs();
            s[kStatAiUnderruns] = static_cast<double>(ai->underruns());
            s[kStatAiOverflows] = static_cast<double>(ai->inputOverflows() + ai->outputOverflows());
            s[kStatAiDiscontinuities] = static_cast<double>(ai->discontinuities());
        }
    } else {
        s[kStatInputPeakDb] = s[kStatInputRmsDb] = s[kStatOutputPeakDb] = s[kStatOutputRmsDb] = -120.0;
    }
    std::copy(s, s + n, out);
    return n;
}

int OboeEngine::aiAvailable() {
    std::lock_guard<std::mutex> lock(workerMutex_);
    if (!processor_) return -1;
    AiBridge* ai = processor_->aiBridge();
    return ai != nullptr ? ai->workerAvailable() : -2;
}

int OboeEngine::aiRead(float* dst, int maxFrames, int64_t* timestamp) {
    std::lock_guard<std::mutex> lock(workerMutex_);
    if (!processor_) return -1;
    AiBridge* ai = processor_->aiBridge();
    return ai != nullptr ? ai->workerRead(dst, maxFrames, timestamp) : -2;
}

int OboeEngine::aiWrite(const float* src, int frames, int64_t timestamp) {
    std::lock_guard<std::mutex> lock(workerMutex_);
    if (!processor_) return -1;
    AiBridge* ai = processor_->aiBridge();
    return ai != nullptr ? ai->workerWrite(src, frames, timestamp) : -2;
}

int OboeEngine::tapRead(float* dst, int maxFrames) {
    std::lock_guard<std::mutex> lock(workerMutex_);
    if (!processor_) return -1;
    return processor_->tapRead(dst, maxFrames);
}

}  // namespace voiceshift::audio
