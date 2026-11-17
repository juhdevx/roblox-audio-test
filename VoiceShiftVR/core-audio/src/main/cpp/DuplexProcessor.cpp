#include "DuplexProcessor.h"

#include <algorithm>
#include <cmath>

namespace voiceshift::audio {

using dsp::kParamCount;

DuplexProcessor::DuplexProcessor(const ProcessorConfig& config)
    : config_(config),
      chain_(config.sampleRate, config.fftSize),
      tap_(static_cast<size_t>(config.sampleRate)) {  // 1 s tap queue
    for (int i = 0; i < kParamCount; ++i) {
        paramValues_[static_cast<size_t>(i)].store(dsp::kParamSpecs[static_cast<size_t>(i)].defaultValue);
    }
    bypassLimiter_.prepare(config.sampleRate);
    bypassLimiter_.setCeilingDb(-1.0f);
    inputMeter_.prepare(config.sampleRate);
    outputMeter_.prepare(config.sampleRate);
    toneDetector_.prepare(config.sampleRate, 1000.0f, static_cast<int>(config.sampleRate / 20));  // 50 ms blocks
    toneGenerator_.prepare(config.sampleRate);
    pitchDetector_.prepare(config.sampleRate);
    probe_.prepare(config.sampleRate);
    if (config.aiModelRate > 0.0f && config.aiChunkFrames > 0) {
        ai_ = std::make_unique<AiBridge>(config.sampleRate, config.aiModelRate, config.maxBlock, config.aiChunkFrames);
    }
    const size_t block = static_cast<size_t>(config.maxBlock);
    dry_.assign(block, 0.0f);
    work_.assign(block, 0.0f);
    fallback_.assign(block, 0.0f);
    aiOut_.assign(block, 0.0f);
    bypassBuf_.assign(block, 0.0f);
    rampStep_ = 1.0f / (0.020f * config.sampleRate);
}

void DuplexProcessor::setParam(int id, float value) {
    if (id < 0 || id >= kParamCount) return;
    paramValues_[static_cast<size_t>(id)].store(dsp::clampParam(id, value), std::memory_order_relaxed);
    paramVersion_.fetch_add(1, std::memory_order_release);
}

void DuplexProcessor::setTestSignal(TestSignal type, float frequencyHz, float levelDb) {
    testFrequency_.store(dsp::clampf(frequencyHz, 20.0f, 20000.0f), std::memory_order_relaxed);
    testLevelDb_.store(dsp::clampf(levelDb, -60.0f, -3.0f), std::memory_order_relaxed);
    testSignal_.store(static_cast<int>(type), std::memory_order_release);
}

void DuplexProcessor::syncParams() {
    const uint32_t version = paramVersion_.load(std::memory_order_acquire);
    if (version == appliedParamVersion_) return;
    for (int i = 0; i < kParamCount; ++i) {
        params_.set(i, paramValues_[static_cast<size_t>(i)].load(std::memory_order_relaxed));
    }
    chain_.setParams(params_);
    appliedParamVersion_ = version;
}

void DuplexProcessor::process(const float* input, float* output, int n, float* preMuteOut) {
    int offset = 0;
    while (offset < n) {
        const int slice = std::min(config_.maxBlock, n - offset);
        processSlice(input + offset, output + offset, slice, preMuteOut != nullptr ? preMuteOut + offset : nullptr);
        offset += slice;
    }
}

void DuplexProcessor::processSlice(const float* input, float* output, int n, float* preMuteOut) {
    syncParams();

    inputMeter_.process(input, n);
    toneDetector_.process(input, n);

    const int testSignal = testSignal_.load(std::memory_order_acquire);
    if (testSignal != lastTestSignal_) {
        if (testSignal == static_cast<int>(TestSignal::LatencyProbe)) probe_.reset();
        lastTestSignal_ = testSignal;
    }
    if (testSignal == static_cast<int>(TestSignal::LatencyProbe)) {
        probe_.analyzeInput(input, n, frameIndex_);
    }

    // Sanitise the capture: a single NaN would otherwise poison every filter state downstream.
    bool inputFault = false;
    for (int i = 0; i < n; ++i) {
        const float x = input[i];
        const bool ok = std::isfinite(x);
        inputFault = inputFault || !ok;
        dry_[static_cast<size_t>(i)] = ok ? x : 0.0f;
    }
    if (inputFault) stats_.dspFaults.fetch_add(1, std::memory_order_relaxed);
    pitchDetector_.process(dry_.data(), n);
    std::copy(dry_.begin(), dry_.begin() + n, work_.begin());

    bool testActive = true;
    bool chainFault = false;
    if (testSignal == static_cast<int>(TestSignal::Tone)) {
        toneGenerator_.setFrequency(testFrequency_.load(std::memory_order_relaxed));
        toneGenerator_.setLevelDb(testLevelDb_.load(std::memory_order_relaxed));
        toneGenerator_.generate(work_.data(), n);
    } else if (testSignal == static_cast<int>(TestSignal::LatencyProbe)) {
        probe_.renderOutput(work_.data(), n, frameIndex_);
    } else {
        testActive = false;
        chain_.processInputStage(work_.data(), n);
        const bool neural = ai_ != nullptr && mode_.load(std::memory_order_relaxed) == static_cast<int>(EngineMode::Neural);
        if (neural) {
            ai_->pushInput(work_.data(), n);
            // The DSP transform keeps running as the instant fallback ("automatic safe bypass").
            std::copy(work_.begin(), work_.begin() + n, fallback_.begin());
            chain_.processTransform(fallback_.data(), n);
            const bool ok = ai_->pullOutput(aiOut_.data(), n);
            if (!ok) std::fill(aiOut_.begin(), aiOut_.begin() + n, 0.0f);
            const float target = ok ? 1.0f : 0.0f;
            const float step = ok ? rampStep_ : rampStep_ * 4.0f;  // fade out of AI quickly
            for (int i = 0; i < n; ++i) {
                aiMix_ = target > aiMix_ ? std::min(target, aiMix_ + step) : std::max(target, aiMix_ - step);
                work_[static_cast<size_t>(i)] = aiMix_ * aiOut_[static_cast<size_t>(i)] +
                                                (1.0f - aiMix_) * fallback_[static_cast<size_t>(i)];
            }
            const AiState state = ok ? AiState::Active : (ai_->priming() ? AiState::Priming : AiState::Fallback);
            stats_.aiState.store(static_cast<int>(state), std::memory_order_relaxed);
        } else {
            aiMix_ = 0.0f;
            chain_.processTransform(work_.data(), n);
            stats_.aiState.store(static_cast<int>(AiState::Off), std::memory_order_relaxed);
        }
        chain_.processOutputStage(work_.data(), n);
        if (chain_.consumeFault()) chainFault = true;
    }

    // Bypass crossfade: the dry path gets the same output gain and its own safety limiter.
    const float bypassTarget = (!testActive && bypass_.load(std::memory_order_relaxed)) ? 1.0f : 0.0f;
    if (bypassTarget > 0.0f || bypassMix_ > 0.0f) {
        const float gain = dsp::dbToGain(params_.get(dsp::kOutputGainDb));
        for (int i = 0; i < n; ++i) bypassBuf_[static_cast<size_t>(i)] = dry_[static_cast<size_t>(i)] * gain;
        bypassLimiter_.process(bypassBuf_.data(), n);
        for (int i = 0; i < n; ++i) {
            bypassMix_ = bypassTarget > bypassMix_ ? std::min(bypassTarget, bypassMix_ + rampStep_)
                                                   : std::max(bypassTarget, bypassMix_ - rampStep_);
            work_[static_cast<size_t>(i)] = bypassMix_ * bypassBuf_[static_cast<size_t>(i)] +
                                            (1.0f - bypassMix_) * work_[static_cast<size_t>(i)];
        }
    }

    // Numerical safety net: any NaN/Inf resets the chain and silences this block.
    bool finite = true;
    for (int i = 0; i < n; ++i) {
        if (!std::isfinite(work_[static_cast<size_t>(i)])) {
            finite = false;
            break;
        }
    }
    if (!finite || chainFault) {
        chain_.reset();
        bypassLimiter_.reset();
        std::fill(work_.begin(), work_.begin() + n, 0.0f);
        stats_.dspFaults.fetch_add(1, std::memory_order_relaxed);
    }

    if (preMuteOut != nullptr) std::copy(work_.begin(), work_.begin() + n, preMuteOut);

    const float muteTarget = muted_.load(std::memory_order_relaxed) ? 0.0f : 1.0f;
    for (int i = 0; i < n; ++i) {
        muteGain_ = muteTarget > muteGain_ ? std::min(muteTarget, muteGain_ + rampStep_)
                                           : std::max(muteTarget, muteGain_ - rampStep_);
        output[i] = work_[static_cast<size_t>(i)] * muteGain_;
    }

    outputMeter_.process(output, n);
    if (tapEnabled_.load(std::memory_order_relaxed)) {
        const size_t written = tap_.write(output, static_cast<size_t>(n));
        if (written < static_cast<size_t>(n)) {
            stats_.tapOverflows.fetch_add(n - static_cast<int64_t>(written), std::memory_order_relaxed);
        }
    }

    frameIndex_ += n;
    stats_.inputPeakDb.store(inputMeter_.peakDb(), std::memory_order_relaxed);
    stats_.inputRmsDb.store(inputMeter_.rmsDb(), std::memory_order_relaxed);
    stats_.outputPeakDb.store(outputMeter_.peakDb(), std::memory_order_relaxed);
    stats_.outputRmsDb.store(outputMeter_.rmsDb(), std::memory_order_relaxed);
    stats_.toneDb.store(toneDetector_.toneDb(), std::memory_order_relaxed);
    stats_.toneSnrDb.store(toneDetector_.snrDb(), std::memory_order_relaxed);
    stats_.agcGainDb.store(chain_.agcGainDb(), std::memory_order_relaxed);
    stats_.limiterReductionDb.store(chain_.limiterReductionDb(), std::memory_order_relaxed);
    stats_.compressorReductionDb.store(chain_.compressorReductionDb(), std::memory_order_relaxed);
    stats_.probeLatencyMs.store(probe_.latencyMs(), std::memory_order_relaxed);
    stats_.inputPitchHz.store(pitchDetector_.pitchHz(), std::memory_order_relaxed);
    stats_.pitchConfidence.store(pitchDetector_.confidence(), std::memory_order_relaxed);
    stats_.gateOpen.store(chain_.gateOpen() ? 1 : 0, std::memory_order_relaxed);
    stats_.framesProcessed.store(frameIndex_, std::memory_order_relaxed);
}

}  // namespace voiceshift::audio
