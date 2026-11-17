# Host (Linux/macOS) unit tests for the portable C++ audio code. No Android SDK required.
#   cmake -S tests/native -B tests/native/build -DCMAKE_BUILD_TYPE=Release
#   cmake --build tests/native/build -j
#   ctest --test-dir tests/native/build --output-on-failure
cmake_minimum_required(VERSION 3.18)
project(voiceshift_native_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(VS_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
add_subdirectory(${VS_ROOT}/core-dsp/cpp ${CMAKE_CURRENT_BINARY_DIR}/voiceshift_dsp)

find_package(Threads REQUIRED)

add_executable(voiceshift_native_tests
    main.cpp
    test_dsp_basics.cpp
    test_voice_shifter.cpp
    test_duplex_processor.cpp
    # Oboe-independent parts of the Android engine.
    ${VS_ROOT}/core-audio/src/main/cpp/AiBridge.cpp
    ${VS_ROOT}/core-audio/src/main/cpp/DuplexProcessor.cpp
    ${VS_ROOT}/core-audio/src/main/cpp/MonitorBridge.cpp
)
target_include_directories(voiceshift_native_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${VS_ROOT}/core-audio/src/main/cpp)
target_link_libraries(voiceshift_native_tests PRIVATE voiceshift_dsp Threads::Threads)
target_compile_options(voiceshift_native_tests PRIVATE -O2 -Wall -Wextra)

enable_testing()
add_test(NAME voiceshift_native_tests COMMAND voiceshift_native_tests)
