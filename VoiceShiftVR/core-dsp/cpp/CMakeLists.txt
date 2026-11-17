# Portable C++17 DSP library. Consumed by:
#   * core-audio/src/main/cpp/CMakeLists.txt (Android NDK build, linked into libvoiceshift_audio.so)
#   * tests/native/CMakeLists.txt             (host unit tests run in CI)
cmake_minimum_required(VERSION 3.18)
project(voiceshift_dsp LANGUAGES CXX)

add_library(voiceshift_dsp STATIC
    src/Analysis.cpp
    src/Biquad.cpp
    src/Dynamics.cpp
    src/Fft.cpp
    src/PitchDetector.cpp
    src/Resampler.cpp
    src/SpectralVoiceShifter.cpp
    src/VoiceChain.cpp
)

target_include_directories(voiceshift_dsp PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_features(voiceshift_dsp PUBLIC cxx_std_17)
set_target_properties(voiceshift_dsp PROPERTIES POSITION_INDEPENDENT_CODE ON)

# Real-time DSP must be optimised even in debug APKs (the only artefact CI publishes). The later -O2
# overrides the -O0 that Debug configurations add. -ffast-math is intentionally NOT used: the engine's
# NaN/Inf guard relies on std::isfinite.
target_compile_options(voiceshift_dsp PRIVATE -O2 -Wall -Wextra)
