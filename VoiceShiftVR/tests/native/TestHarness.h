// Minimal dependency-free unit-test harness (no network access needed to build tests in CI).
#pragma once

#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace vstest {

struct TestCase {
    const char* name;
    std::function<void()> fn;
};

inline std::vector<TestCase>& registry() {
    static std::vector<TestCase> tests;
    return tests;
}

inline int& failures() {
    static int count = 0;
    return count;
}

struct Registrar {
    Registrar(const char* name, std::function<void()> fn) { registry().push_back({name, std::move(fn)}); }
};

inline void reportFailure(const char* file, int line, const std::string& message) {
    std::printf("    FAIL %s:%d: %s\n", file, line, message.c_str());
    ++failures();
}

}  // namespace vstest

#define VS_CONCAT_INNER(a, b) a##b
#define VS_CONCAT(a, b) VS_CONCAT_INNER(a, b)

#define TEST_CASE(name)                                                         \
    static void name();                                                         \
    static vstest::Registrar VS_CONCAT(registrar_, name)(#name, name);          \
    static void name()

#define CHECK(cond)                                                             \
    do {                                                                        \
        if (!(cond)) vstest::reportFailure(__FILE__, __LINE__, "CHECK(" #cond ")"); \
    } while (0)

#define CHECK_NEAR(actual, expected, tolerance)                                                     \
    do {                                                                                            \
        const double vs_a = static_cast<double>(actual);                                            \
        const double vs_e = static_cast<double>(expected);                                          \
        if (!(std::fabs(vs_a - vs_e) <= static_cast<double>(tolerance))) {                          \
            char vs_buf[256];                                                                       \
            std::snprintf(vs_buf, sizeof(vs_buf), "%s = %.6g, expected %.6g +/- %.3g", #actual, vs_a, \
                          vs_e, static_cast<double>(tolerance));                                    \
            vstest::reportFailure(__FILE__, __LINE__, vs_buf);                                      \
        }                                                                                           \
    } while (0)

#define CHECK_LT(a, b)                                                                              \
    do {                                                                                            \
        const double vs_a = static_cast<double>(a);                                                 \
        const double vs_b = static_cast<double>(b);                                                 \
        if (!(vs_a < vs_b)) {                                                                       \
            char vs_buf[256];                                                                       \
            std::snprintf(vs_buf, sizeof(vs_buf), "%s (%.6g) < %s (%.6g)", #a, vs_a, #b, vs_b);       \
            vstest::reportFailure(__FILE__, __LINE__, vs_buf);                                      \
        }                                                                                           \
    } while (0)
