cmake_minimum_required(VERSION 3.22.1)
project(voiceshift_audio LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Portable DSP library shared with the host unit tests (tests/native).
set(VOICESHIFT_DSP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../core-dsp/cpp)
add_subdirectory(${VOICESHIFT_DSP_DIR} ${CMAKE_CURRENT_BINARY_DIR}/voiceshift_dsp)

# Oboe via prefab (com.google.oboe:oboe, Apache-2.0).
find_package(oboe REQUIRED CONFIG)

add_library(voiceshift_audio SHARED
    AiBridge.cpp
    DuplexProcessor.cpp
    OboeEngine.cpp
    jni_bridge.cpp
)

target_link_libraries(voiceshift_audio PRIVATE voiceshift_dsp oboe::oboe android log)
# Optimise even in debug builds: the debug APK is the artefact users install (see core-dsp/cpp).
target_compile_options(voiceshift_audio PRIVATE -O2 -Wall -Wextra)
