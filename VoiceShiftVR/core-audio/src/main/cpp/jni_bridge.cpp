// JNI surface for com.voiceshift.audio.NativeAudioBridge. Every function takes the engine handle
// returned by nativeCreate(). Signatures must match the Kotlin `external` declarations exactly.
#include <jni.h>

#include <algorithm>

#include "OboeEngine.h"

using voiceshift::audio::EngineConfig;
using voiceshift::audio::OboeEngine;

namespace {
OboeEngine* engine(jlong handle) { return reinterpret_cast<OboeEngine*>(handle); }
}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeCreate(JNIEnv*, jclass) {
    return reinterpret_cast<jlong>(new OboeEngine());
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeDestroy(JNIEnv*, jclass, jlong handle) {
    delete engine(handle);
}

JNIEXPORT jint JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeStart(
    JNIEnv*, jclass, jlong handle, jint inputDeviceId, jint outputDeviceId, jint sampleRate, jint fftSize,
    jint inputPreset, jboolean exclusive, jint aiModelRate, jint aiChunkFrames, jint monitorDeviceId) {
    EngineConfig config;
    config.inputDeviceId = inputDeviceId;
    config.outputDeviceId = outputDeviceId;
    config.sampleRate = sampleRate;
    config.fftSize = fftSize;
    config.inputPreset = inputPreset;
    config.exclusive = exclusive == JNI_TRUE;
    config.aiModelRate = aiModelRate;
    config.aiChunkFrames = aiChunkFrames;
    config.monitorDeviceId = monitorDeviceId;
    return engine(handle)->start(config);
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeStop(JNIEnv*, jclass, jlong handle) {
    engine(handle)->stop();
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeSetParam(JNIEnv*, jclass, jlong handle,
                                                                                  jint id, jfloat value) {
    engine(handle)->setParam(id, value);
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeSetMode(JNIEnv*, jclass, jlong handle,
                                                                                 jint mode) {
    engine(handle)->setMode(mode);
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeSetBypass(JNIEnv*, jclass, jlong handle,
                                                                                   jboolean bypass) {
    engine(handle)->setBypass(bypass == JNI_TRUE);
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeSetMuted(JNIEnv*, jclass, jlong handle,
                                                                                  jboolean muted) {
    engine(handle)->setMuted(muted == JNI_TRUE);
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeSetTestSignal(JNIEnv*, jclass, jlong handle,
                                                                                       jint type, jfloat frequencyHz,
                                                                                       jfloat levelDb) {
    engine(handle)->setTestSignal(type, frequencyHz, levelDb);
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeSetTapEnabled(JNIEnv*, jclass, jlong handle,
                                                                                       jboolean enabled) {
    engine(handle)->setTapEnabled(enabled == JNI_TRUE);
}

JNIEXPORT void JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeSetMonitorGain(JNIEnv*, jclass, jlong handle,
                                                                                       jfloat db) {
    engine(handle)->setMonitorGainDb(db);
}

JNIEXPORT jint JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeGetStats(JNIEnv* env, jclass, jlong handle,
                                                                                  jdoubleArray out) {
    double buffer[voiceshift::audio::kStatCount];
    const int n = engine(handle)->fillStats(buffer, voiceshift::audio::kStatCount);
    const jsize length = std::min<jsize>(env->GetArrayLength(out), n);
    env->SetDoubleArrayRegion(out, 0, length, buffer);
    return n;
}

JNIEXPORT jstring JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeGetLastError(JNIEnv* env, jclass,
                                                                                         jlong handle) {
    return env->NewStringUTF(engine(handle)->lastError().c_str());
}

JNIEXPORT jint JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeAiAvailable(JNIEnv*, jclass, jlong handle) {
    return engine(handle)->aiAvailable();
}

JNIEXPORT jint JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeAiRead(JNIEnv* env, jclass, jlong handle,
                                                                                jfloatArray dst, jint maxFrames,
                                                                                jlongArray timestampOut) {
    const jint count = std::min<jint>(maxFrames, env->GetArrayLength(dst));
    jfloat* data = env->GetFloatArrayElements(dst, nullptr);
    if (data == nullptr) return -3;
    int64_t timestamp = 0;
    const int n = engine(handle)->aiRead(data, count, &timestamp);
    env->ReleaseFloatArrayElements(dst, data, 0);
    if (timestampOut != nullptr && env->GetArrayLength(timestampOut) > 0) {
        const jlong ts = static_cast<jlong>(timestamp);
        env->SetLongArrayRegion(timestampOut, 0, 1, &ts);
    }
    return n;
}

JNIEXPORT jint JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeAiWrite(JNIEnv* env, jclass, jlong handle,
                                                                                 jfloatArray src, jint frames,
                                                                                 jlong timestamp) {
    const jint count = std::min<jint>(frames, env->GetArrayLength(src));
    jfloat* data = env->GetFloatArrayElements(src, nullptr);
    if (data == nullptr) return -3;
    const int n = engine(handle)->aiWrite(data, count, timestamp);
    env->ReleaseFloatArrayElements(src, data, JNI_ABORT);
    return n;
}

JNIEXPORT jint JNICALL Java_com_voiceshift_audio_NativeAudioBridge_nativeTapRead(JNIEnv* env, jclass, jlong handle,
                                                                                 jfloatArray dst, jint maxFrames) {
    const jint count = std::min<jint>(maxFrames, env->GetArrayLength(dst));
    jfloat* data = env->GetFloatArrayElements(dst, nullptr);
    if (data == nullptr) return -3;
    const int n = engine(handle)->tapRead(data, count);
    env->ReleaseFloatArrayElements(dst, data, 0);
    return n;
}

}  // extern "C"
