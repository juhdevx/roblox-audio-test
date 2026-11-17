#include <chrono>
#include <cstdio>
#include <cstring>

#include "TestHarness.h"

int main(int argc, char** argv) {
    const char* filter = argc > 1 ? argv[1] : nullptr;
    int run = 0;
    for (const auto& test : vstest::registry()) {
        if (filter != nullptr && std::strstr(test.name, filter) == nullptr) continue;
        const int before = vstest::failures();
        const auto start = std::chrono::steady_clock::now();
        test.fn();
        const double ms =
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
        std::printf("[%s] %s (%.1f ms)\n", vstest::failures() == before ? " OK " : "FAIL", test.name, ms);
        ++run;
    }
    std::printf("\n%d tests, %d failed checks\n", run, vstest::failures());
    return vstest::failures() == 0 && run > 0 ? 0 : 1;
}
